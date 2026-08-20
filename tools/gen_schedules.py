"""Gera `resources/schedules/*.tres` — uma agenda diária por arquétipo.

São estes `.tres` que fazem vinte habitantes funcionarem com três rotinas. O controlador
de NPC não conhece comerciante nem criança: ele lê blocos `{hora, marcador, estado}` e
obedece. Trocar a vida da cidade é trocar um arquivo de dados.

As agendas referenciam **nomes de marcador**, e por isso funcionam em qualquer seed: a
fase 8 gera `praca`, `poco`, `taverna`, `portao`, `mercado_01..05` e `casa_01..15` onde
quer que a cidade tenha caído, e `casa`/`trabalho` são resolvidos por NPC na hora de
povoar. Nenhuma coordenada aparece aqui nem poderia.

Como `resources/gaits/`, isto é **versionado**: é dado de design, não derivado de malha, e
o diff de uma rotina é exatamente o tipo de mudança que se quer ver numa revisão. Continua
gerado, e `make verify` reprova se alguém editar à mão.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT_DIR = Path(P.NPC_DIR)
SCRIPT_PATH = "res://scripts/gameplay/npc_schedule.gd"
SCRIPT_ID = "1_npc_schedule"

# Estados que um bloco de agenda pode pedir. É contrato com `NPCController.State`: um
# nome fora desta lista compila e falha em silêncio no jogo, com o NPC parado para sempre.
VALID_STATES = ("IDLE", "WALK_TO", "WORK", "SOCIALIZE", "SLEEP", "REACT")

# Marcadores resolvidos por NPC, e não pelo nome literal. Ver `population_gen.gd`.
PER_NPC_MARKERS = ("casa", "trabalho")

HOURS_PER_DAY = float(P.HOURS_PER_DAY)


def _blocks_literal(blocks: tuple[tuple[float, float, str, str], ...]) -> str:
    entries = []
    for start, end, marker, state in blocks:
        entries.append(
            f'{{"start": {float(start)!r}, "end": {float(end)!r}, '
            f'"marker": &"{marker}", "state": &"{state}"}}'
        )
    return "[" + ", ".join(entries) + "]"


def _schedule_resource(name: str, blocks) -> str:
    return f"""{GENERATED_HEADER('tools/gen_schedules.py', 'tools/params.py', ';')}
[gd_resource type="Resource" script_class="NPCSchedule" load_steps=2 format=3]

[ext_resource type="Script" path="{SCRIPT_PATH}" id="{SCRIPT_ID}"]

[resource]
script = ExtResource("{SCRIPT_ID}")
archetype = &"{name}"
blocks = Array[Dictionary]({_blocks_literal(blocks)})
"""


def _audit(name: str, blocks) -> None:
    """Cobra o que uma agenda quebrada só mostraria depois de horas de jogo."""
    covered = []
    for start, end, marker, state in blocks:
        if state not in VALID_STATES:
            raise SystemExit(
                f"Agenda {name!r}: estado {state!r} não existe. Válidos: "
                f"{', '.join(VALID_STATES)}."
            )
        if end <= start:
            raise SystemExit(
                f"Agenda {name!r}: bloco {marker!r} termina ({end}) antes de começar "
                f"({start})."
            )
        covered.append((start, end))

    covered.sort()
    # As 24 horas têm de estar cobertas sem buraco. Um buraco deixa o NPC sem ordem, e ele
    # congela no lugar — na madrugada, quando ninguém está olhando.
    reach = covered[0][0]
    if reach > 0.0 and covered[-1][1] - HOURS_PER_DAY < reach:
        raise SystemExit(
            f"Agenda {name!r}: o dia começa descoberto até as {reach:g}h, e o último bloco "
            f"só chega às {covered[-1][1] - HOURS_PER_DAY:g}h do dia seguinte."
        )
    for (_start, end), (next_start, _next_end) in zip(covered, covered[1:]):
        if next_start > end:
            raise SystemExit(
                f"Agenda {name!r}: buraco entre {end:g}h e {next_start:g}h. Um NPC sem "
                f"bloco fica parado até a hora seguinte."
            )


def main() -> list[Path]:
    wanted = {spec["schedule"] for spec in P.NPC_ARCHETYPES}
    missing = sorted(wanted - set(P.NPC_SCHEDULES))
    if missing:
        raise SystemExit(
            f"tools/params.py: os arquétipos pedem a agenda {missing} e NPC_SCHEDULES não "
            f"a define. Um arquétipo sem agenda vira um habitante parado."
        )

    written: list[Path] = []
    for name, blocks in P.NPC_SCHEDULES.items():
        _audit(name, blocks)
        written += write_if_changed(OUTPUT_DIR / f"{name}.tres", _schedule_resource(name, blocks))

    total = sum(len(blocks) for blocks in P.NPC_SCHEDULES.values())
    print(f"  rotinas: {len(P.NPC_SCHEDULES)} agendas, {total} blocos em {OUTPUT_DIR}/")
    return written


if __name__ == "__main__":
    main()
