"""Guarda-costas da regra inegociável: nada é criado manualmente.

Cobre quatro coisas, e reprova o build em qualquer uma:

1. **Deriva** — todo arquivo gerado na árvore é idêntico ao que os geradores produziriam
   agora. Se alguém editou `project.godot` pelo editor do Godot ou mexeu no `params.gd`
   à mão, aparece aqui.
2. **Números mágicos** — nenhum literal numérico com significado fora de `tools/params.py`.
   Literais só são aceitos em declarações `const` (constante estrutural, nomeada) e num
   punhado de valores triviais.
3. **Tipagem** — todo `var`, parâmetro e retorno de função em GDScript é tipado.
4. **Integridade** — materiais apontam para cores que existem, os artefatos gerados estão
   no lugar, e `assets/generated` está de fato ignorado pelo git.
5. **Kit** — se o manifesto do Blender existe, toda peça cabe nos tetos *atuais* de
   `params.py`. Baixar um teto sem rodar `make assets` reprova aqui.

Não precisa do Godot instalado: é tudo análise de texto.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from . import gen_audio, gen_materials, gen_params, gen_project, gen_world
from . import params as P
from .util import ROOT

# Literais aceitos fora de uma declaração `const`: identidade, vizinhança e metade.
ALLOWED_LITERALS = {"0", "1", "2", "-1", "0.0", "1.0", "2.0", "0.5", "-1.0"}

# Diretórios varridos pelos linters de GDScript.
GDSCRIPT_DIRS = ("scripts", "generators")

# `params.gd` é o espelho gerado da fonte de verdade: é o único .gd cheio de números.
MAGIC_NUMBER_EXEMPT = {Path("scripts/core/params.gd")}

_STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
_NUMBER_RE = re.compile(r"(?<![\w.])-?\d+(?:_\d+)*(?:\.\d+)?(?![\w.])")
_CONST_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)?const\s")
_ENUM_RE = re.compile(r"^\s*enum\s")
_VAR_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)?(?:static\s+)?var\s+(\w+)\s*(:|=|$)")
_FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(")

_failures: list[str] = []
_kit_failures_at_entry: list[int] = [0]


def _fail(message: str) -> None:
    _failures.append(message)


# ---------------------------------------------------------------------------
# 1. Deriva entre a árvore e os geradores
# ---------------------------------------------------------------------------


def check_drift() -> None:
    """Reprova qualquer arquivo gerado que tenha sido editado à mão."""
    expected: dict[Path, str] = {
        gen_params.OUTPUT: gen_params.render(),
        gen_project.OUTPUT: gen_project.render(),
        gen_world.MAIN_SCENE_OUTPUT: gen_world._main_scene(),
        gen_world.MANIFEST_OUTPUT: gen_world._manifest(),
    }
    for name, (color_key, roughness, metallic) in P.MATERIALS.items():
        target = gen_materials.OUTPUT_DIR / f"{name}.tres"
        expected[target] = gen_materials._material_resource(name, color_key, roughness, metallic)
    expected[gen_audio.BUS_LAYOUT_OUTPUT] = gen_audio._bus_layout()

    for relative, content in expected.items():
        path = ROOT / relative
        if not path.exists():
            _fail(f"{relative}: arquivo gerado ausente. Rode `make all`.")
        elif path.read_text(encoding="utf-8") != content:
            _fail(
                f"{relative}: divergente do gerador. Alguém editou o arquivo gerado à mão "
                f"(ou o editor do Godot o reescreveu). Mude tools/params.py e rode `make all`."
            )


# ---------------------------------------------------------------------------
# 2. Números mágicos
# ---------------------------------------------------------------------------


def _strip_noise(line: str) -> str:
    """Remove strings e comentários — número dentro deles não é número mágico."""
    line = _STRING_RE.sub('""', line)
    hash_index = line.find("#")
    return line[:hash_index] if hash_index >= 0 else line


def check_magic_numbers() -> None:
    for path in _gdscript_files():
        if path.relative_to(ROOT) in MAGIC_NUMBER_EXEMPT:
            continue
        for number, line_no, line in _iter_numbers(path):
            if number in ALLOWED_LITERALS:
                continue
            _fail(
                f"{path.relative_to(ROOT)}:{line_no}: número mágico {number!r} "
                f"fora de tools/params.py — {line.strip()}"
            )


def _iter_numbers(path: Path):
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        code = _strip_noise(raw)
        if not code.strip() or _CONST_RE.match(code) or _ENUM_RE.match(code):
            continue
        for match in _NUMBER_RE.finditer(code):
            yield match.group(0), line_no, raw


# ---------------------------------------------------------------------------
# 3. Tipagem obrigatória
# ---------------------------------------------------------------------------


def check_typing() -> None:
    for path in _gdscript_files():
        relative = path.relative_to(ROOT)
        lines = path.read_text(encoding="utf-8").splitlines()

        for line_no, raw in enumerate(lines, start=1):
            code = _strip_noise(raw)
            var_match = _VAR_RE.match(code)
            if var_match and var_match.group(2) != ":":
                _fail(f"{relative}:{line_no}: `var {var_match.group(1)}` sem tipo — {raw.strip()}")

        # Assinaturas podem ocupar várias linhas; junte até fechar os parênteses antes
        # de cobrar o `->`, senão uma `func` multilinha sem tipo passaria batido.
        for line_no, name, signature in _iter_signatures(lines):
            if "->" not in signature:
                _fail(
                    f"{relative}:{line_no}: `func {name}` sem tipo de retorno "
                    f"— {signature.strip()}"
                )


def _iter_signatures(lines: list[str]):
    """Produz (linha, nome, assinatura completa) para cada `func` do arquivo."""
    index = 0
    while index < len(lines):
        code = _strip_noise(lines[index])
        match = _FUNC_RE.match(code)
        if not match:
            index += 1
            continue

        start = index
        signature = code
        depth = signature.count("(") - signature.count(")")
        while depth > 0 and index + 1 < len(lines):
            index += 1
            piece = _strip_noise(lines[index])
            signature += " " + piece.strip()
            depth += piece.count("(") - piece.count(")")

        yield start + 1, match.group(1), signature
        index += 1


# ---------------------------------------------------------------------------
# 4. Integridade dos parâmetros e do repositório
# ---------------------------------------------------------------------------


def check_params_integrity() -> None:
    for name, (color_key, _roughness, _metallic) in P.MATERIALS.items():
        if color_key not in P.PALETTE:
            _fail(f"tools/params.py: material {name!r} usa cor inexistente {color_key!r}.")

    if len(P.MATERIALS) > P.BUDGET["unique_materials"]:
        _fail(
            f"tools/params.py: {len(P.MATERIALS)} materiais para um teto de "
            f"{P.BUDGET['unique_materials']}."
        )

    if len(P.PHYSICS_LAYERS) != len(set(P.PHYSICS_LAYERS)):
        _fail("tools/params.py: nomes de camada de física repetidos.")

    bus_names = [name for name, _, _ in P.AUDIO_BUSES]
    if bus_names[0] != "Master":
        _fail("tools/params.py: o barramento 0 tem de ser 'Master'.")
    for name, _volume, send in P.AUDIO_BUSES[1:]:
        if send not in bus_names:
            _fail(f"tools/params.py: barramento {name!r} envia para {send!r}, que não existe.")

    for action, spec in P.INPUT_MAP.items():
        for key_name in spec.get("keys", []):
            if key_name not in P.KEY:
                _fail(f"tools/params.py: ação {action!r} usa tecla desconhecida {key_name!r}.")

    stage_tris = P.STAGE_GROUND_CELLS * P.STAGE_GROUND_CELLS * 2
    if stage_tris > P.TRI_BUDGET["stage_ground"]:
        _fail(f"tools/params.py: chão do estágio com {stage_tris} tris estoura o teto.")


def check_kit_manifest() -> None:
    """Confere o manifesto do kit contra os tetos atuais, sem precisar do Blender.

    O kit é derivado e mora em `assets/generated/`, então numa árvore recém-clonada ele
    simplesmente não existe — e isso não é erro. O que *é* erro é ele existir e estar
    fora do que `params.py` manda agora: baixar um teto e esquecer de rodar `make assets`
    deixaria peças fora do orçamento passando despercebidas.
    """
    _kit_failures_at_entry[0] = len(_failures)
    manifest_path = ROOT / P.KIT_DIR / "manifest.json"
    if not manifest_path.exists():
        print("  kit: ausente (derivado — rode `make assets`)")
        return

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    parts = manifest.get("parts", [])
    if manifest.get("kit_seed") != P.KIT_SEED:
        _fail(
            f"{P.KIT_DIR}/manifest.json: gerado com a semente {manifest.get('kit_seed')}, "
            f"mas params.py diz {P.KIT_SEED}. Rode `make assets`."
        )
    if manifest.get("grid_size") != P.GRID_SIZE:
        _fail(
            f"{P.KIT_DIR}/manifest.json: grid de {manifest.get('grid_size')} m contra "
            f"{P.GRID_SIZE} m em params.py. Rode `make assets`."
        )

    for part in parts:
        budget = P.KIT_TRI_BUDGET.get(_budget_key(part))
        if budget is None:
            _fail(f"kit: peça {part['name']!r} tem categoria desconhecida {part['category']!r}.")
        elif part["tris"] > budget:
            _fail(
                f"kit: {part['name']} com {part['tris']} triângulos estoura o teto atual "
                f"de {budget}. Rode `make assets`."
            )
        missing = ROOT / P.KIT_DIR / part["file"]
        if not missing.exists():
            _fail(f"kit: {part['name']} está no manifesto mas {part['file']} não existe.")

    for key in manifest.get("palette", {}):
        if key not in P.PALETTE:
            _fail(f"kit: manifesto cita a cor {key!r}, que não existe mais na paleta.")

    before = len(_failures)
    if before == _kit_failures_at_entry[0]:
        print(f"  kit: {len(parts)} peças dentro do orçamento")


def _budget_key(part: dict) -> str:
    """Árvore tem teto próprio; o resto usa o teto da categoria."""
    if part["name"].startswith("tree_"):
        return "tree"
    return part["category"]


def check_repository() -> None:
    gitignore = ROOT / ".gitignore"
    if not gitignore.exists():
        _fail(".gitignore ausente.")
        return
    body = gitignore.read_text(encoding="utf-8")
    if "/assets/generated/" not in body:
        _fail(".gitignore: /assets/generated/ tem de ser ignorado — é derivado.")

    for required in ("tools/params.py", "Makefile", "CLAUDE.md", "scripts/core/params.gd"):
        if not (ROOT / required).exists():
            _fail(f"{required}: ausente.")


# ---------------------------------------------------------------------------


def _gdscript_files() -> list[Path]:
    files: list[Path] = []
    for directory in GDSCRIPT_DIRS:
        files += sorted((ROOT / directory).rglob("*.gd"))
    return files


def main() -> list[Path]:
    _failures.clear()
    check_drift()
    check_magic_numbers()
    check_typing()
    check_params_integrity()
    check_kit_manifest()
    check_repository()

    scanned = len(_gdscript_files())
    if _failures:
        print(f"  {len(_failures)} problema(s) em {scanned} arquivos GDScript:")
        for failure in _failures:
            print(f"    - {failure}")
        raise SystemExit(1)

    print(f"  {scanned} arquivos GDScript: tipagem ok, sem número mágico")
    print("  arquivos gerados: em dia com os geradores")
    return []


if __name__ == "__main__":
    main()
