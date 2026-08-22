"""`make audit` — de que a cena é feita em cada estação do bench.

O bench responde "quanto custa". Este responde "de quê", que é a pergunta que se faz
antes de otimizar. A tabela sai por ramo do estágio, porque ramo é gerador: se a conta
estoura na vegetação, quem se mexe é `scatter_gen.gd`, e não o traçado da cidade.

Roda sem renderizador: a contagem é geométrica (tronco de visão e caixa envolvente), e por
isso é um **teto** — o driver desenha isto ou menos, já que oclusão não se simula aqui.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import params as P  # noqa: E402
from tools.util import GodotMissing, GodotTimeout, ensure_imported, fail, run_godot  # noqa: E402

AUDIT_SCRIPT = "res://tools/audit.gd"
RESULT_PREFIX = "MEDIEV_AUDIT "
# Ramos na ordem em que se otimiza, e não na ordem alfabética: primeiro o que se agrupa,
# depois o que se instancia, depois o que se corta por distância.
BRANCH_ORDER = ("City", "Terrain", "Scatter", "Ambient", "Navigation")


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _branch_names(stations: list[dict]) -> list[str]:
    seen: list[str] = []
    for station in stations:
        for name in station["branches"]:
            if name not in seen:
                seen.append(name)
    ordered = [name for name in BRANCH_ORDER if name in seen]
    return ordered + [name for name in seen if name not in ordered]


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        process = run_godot(["--headless", "--script", AUDIT_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    report = _extract(process.stdout)
    if report is None:
        fail(f"o Godot terminou com código {process.returncode} sem reportar a auditoria.")
        for line in (process.stdout + process.stderr).splitlines():
            if line.startswith("SCRIPT ERROR") or line.startswith("ERROR"):
                print(f"  {line}", file=sys.stderr)
        return 1

    stations = report["stations"]
    branches = _branch_names(stations)
    header = "  ramo         " + "".join(f"{station['name']:>12s}" for station in stations)
    print(header)
    for branch in branches:
        row = f"  {branch:<12s}"
        for station in stations:
            entry = station["branches"].get(branch)
            row += f"{entry['nodes'] if entry else 0:>12d}"
        print(row)
    print("  " + "-" * (len(header) - 2))
    total = "  nós          "
    for station in stations:
        total += f"{station['nodes']:>12d}"
    print(total)
    instances = "  instâncias   "
    for station in stations:
        instances += f"{station['instances']:>12d}"
    print(instances)

    census = report["materials"]
    listed = ", ".join(
        f"{name} {count}" for name, count in sorted(census.items(), key=lambda item: -item[1])
    )
    ceiling = P.BUDGET["unique_materials"]
    print(f"  materiais:   {len(census)}/{ceiling} distintos — {listed}")

    if len(census) > ceiling:
        # O teto de materiais únicos existe desde a fase 1 e nada o cobrava: `Metrics` conta
        # o cache do `MaterialLibrary`, que não enxerga os materiais que vêm dentro dos
        # `.glb`. Medido aqui, ele passa a ser um teto de verdade.
        print()
        print(
            f"  ESTOUROU: {len(census)} materiais distintos em cena, teto de {ceiling}. "
            f"Material repetido é agrupamento perdido: ver MATERIALS['kit'] em params.py.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
