"""Gera `resources/dialogues/*.tres` — uma árvore de conversa por diálogo.

O critério de aceite da fase é literal: **acrescentar conversa nova não pode exigir tocar
em código**. Isto é o que torna isso verdade — uma entrada nova em `params.DIALOGUES` vira
um `.tres`, um arquétipo aponta para ele em `DIALOGUE_BY_ARCHETYPE`, e o runner carrega
pelo nome. Nenhum `match` em lugar nenhum, nenhum registro para atualizar.

Como `resources/gaits/` e `resources/schedules/`, isto é **versionado**: é dado de design,
e o diff de uma fala é exatamente o tipo de mudança que se quer ver numa revisão.

O gerador reprova o que só apareceria em runtime: escolha apontando para um nó que não
existe, mais escolhas que o teto, nó órfão, tipo de condição inventado. Um `goto` errado
num `.tres` fecha a conversa em silêncio no meio de uma frase — e ninguém liga isso à
linha que errou.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT_DIR = Path(P.DIALOGUE_DIR)
SCRIPT_PATH = "res://scripts/gameplay/dialogue_tree.gd"
SCRIPT_ID = "1_dialogue_tree"

# Contrato com `DialogueTree`. Um tipo fora daqui compila, carrega e falha em silêncio.
CONDITION_TYPES = ("flag", "reputacao", "raca")
EFFECT_TYPES = ("flag", "reputacao")
COMPARES = ("==", "!=", ">=", "<=", ">", "<")


def _literal(value) -> str:
    """Valor Python como literal GDScript."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return f'&"{value}"' if value.islower() and " " not in value else f'"{value}"'
    if isinstance(value, float):
        return P.num(value)
    return str(value)


def _condition(entry: dict) -> str:
    compare = entry.get("compare", "==")
    return (
        f'{{"type": &"{entry["type"]}", "key": &"{entry["key"]}", '
        f'"compare": "{compare}", "value": {_literal(entry["value"])}}}'
    )


def _effect(entry: dict) -> str:
    return (
        f'{{"type": &"{entry["type"]}", "key": &"{entry["key"]}", '
        f'"value": {_literal(entry["value"])}}}'
    )


def _rules(entry: dict, key: str, render) -> str:
    items = entry.get(key, ())
    if not items:
        return ""
    joined = ", ".join(render(item) for item in items)
    return f', "{key}": [{joined}]'


def _choice(entry: dict) -> str:
    return (
        f'{{"text": "{entry["text"]}", "goto": &"{entry.get("goto", "")}"'
        + _rules(entry, "conditions", _condition)
        + _rules(entry, "effects", _effect)
        + "}"
    )


def _node(entry: dict) -> str:
    choices = ", ".join(_choice(choice) for choice in entry.get("choices", ()))
    return (
        f'\t{{"id": &"{entry["id"]}", "text": "{entry["text"]}"'
        + _rules(entry, "conditions", _condition)
        + _rules(entry, "effects", _effect)
        + f', "choices": [{choices}]}},'
    )


def _tree_resource(name: str, tree: dict) -> str:
    body = "\n".join(_node(node) for node in tree["nodes"])
    return f"""{GENERATED_HEADER('tools/gen_dialogues.py', 'tools/params.py', ';')}
[gd_resource type="Resource" script_class="DialogueTree" load_steps=2 format=3]

[ext_resource type="Script" path="{SCRIPT_PATH}" id="{SCRIPT_ID}"]

[resource]
script = ExtResource("{SCRIPT_ID}")
id = &"{name}"
speaker = "{tree["speaker"]}"
start = &"{tree["start"]}"
nodes = Array[Dictionary]([
{body}
])
"""


def _audit(name: str, tree: dict) -> None:
    """Cobra o que um `.tres` quebrado só mostraria no meio de uma conversa."""
    ids = {node["id"] for node in tree["nodes"]}
    if tree["start"] not in ids:
        raise SystemExit(
            f"Diálogo {name!r}: o nó inicial {tree['start']!r} não existe."
        )

    reached = {tree["start"]}
    for node in tree["nodes"]:
        _audit_rules(name, node["id"], node)
        choices = node.get("choices", ())
        if len(choices) > P.DIALOGUE_MAX_CHOICES:
            raise SystemExit(
                f"Diálogo {name!r}, nó {node['id']!r}: {len(choices)} escolhas, acima do "
                f"teto de {P.DIALOGUE_MAX_CHOICES}."
            )
        if not choices:
            raise SystemExit(
                f"Diálogo {name!r}, nó {node['id']!r}: sem escolhas. Um nó sem saída "
                f"trava a conversa aberta e o jogador fica sem como sair."
            )
        for choice in choices:
            _audit_rules(name, f"{node['id']}/{choice['text']}", choice)
            goto = choice.get("goto", "")
            if goto and goto not in ids:
                raise SystemExit(
                    f"Diálogo {name!r}, nó {node['id']!r}: a escolha {choice['text']!r} "
                    f"aponta para {goto!r}, que não existe. Em runtime isso fecha a "
                    f"conversa no meio, sem erro."
                )
            if goto:
                reached.add(goto)

    orphans = sorted(ids - reached)
    if orphans:
        raise SystemExit(
            f"Diálogo {name!r}: o(s) nó(s) {orphans} não são alcançáveis de lugar nenhum."
        )


def _audit_rules(name: str, where: str, entry: dict) -> None:
    for condition in entry.get("conditions", ()):
        if condition["type"] not in CONDITION_TYPES:
            raise SystemExit(
                f"Diálogo {name!r}, {where}: condição de tipo {condition['type']!r}. "
                f"Válidos: {', '.join(CONDITION_TYPES)}."
            )
        compare = condition.get("compare", "==")
        if compare not in COMPARES:
            raise SystemExit(
                f"Diálogo {name!r}, {where}: comparação {compare!r}. "
                f"Válidas: {', '.join(COMPARES)}."
            )
    for effect in entry.get("effects", ()):
        if effect["type"] not in EFFECT_TYPES:
            raise SystemExit(
                f"Diálogo {name!r}, {where}: efeito de tipo {effect['type']!r}. "
                f"Válidos: {', '.join(EFFECT_TYPES)}."
            )
        if effect["type"] == "reputacao" and effect["key"] not in P.FACTIONS:
            raise SystemExit(
                f"Diálogo {name!r}, {where}: reputação com a facção {effect['key']!r}, "
                f"que não está em FACTIONS."
            )


def main() -> list[Path]:
    missing = sorted(set(P.DIALOGUE_BY_ARCHETYPE.values()) - set(P.DIALOGUES))
    if missing:
        raise SystemExit(
            f"tools/params.py: os arquétipos apontam para a árvore {missing} e DIALOGUES "
            f"não a define."
        )

    written: list[Path] = []
    changes = 0
    for name, tree in P.DIALOGUES.items():
        _audit(name, tree)
        written += write_if_changed(OUTPUT_DIR / f"{name}.tres", _tree_resource(name, tree))
        changes += sum(
            1
            for node in tree["nodes"]
            for choice in node.get("choices", ())
            if choice.get("effects")
        ) + sum(1 for node in tree["nodes"] if node.get("effects"))

    total = sum(len(tree["nodes"]) for tree in P.DIALOGUES.values())
    print(
        f"  diálogos: {len(P.DIALOGUES)} árvores, {total} nós, {changes} efeitos em "
        f"{OUTPUT_DIR}/"
    )
    return written


if __name__ == "__main__":
    main()
