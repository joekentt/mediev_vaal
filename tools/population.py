"""`make population` — roda `tools/population.gd` e cobra os critérios de aceite da fase.

Os três critérios da fase viram checagens executáveis, e um deles não é cobrado aqui:

- **"3 minutos parado na praça mostram movimento contínuo e não repetitivo"**: em toda
  janela da prova, uma fração mínima dos habitantes tem de ter saído do lugar, e a
  dispersão dos rastros tem de passar de `POPULATION_MIN_VARIETY`. As duas juntas, porque
  cada uma sozinha aprova o defeito da outra: vinte NPCs andando em círculos de dois metros
  passam no primeiro teste, e vinte NPCs que atravessam a cidade uma vez e param passam no
  segundo.
- **"ninguém entala em porta nem atravessa parede"**: zero destravamentos e zero amostras
  com o centro do habitante dentro de uma caixa de prédio.
- **"60 FPS com 20 NPCs à vista"** é do `make bench`, que tem contador de draw call e a
  cidade inteira em cena. Cobrar frame time aqui mediria o llvmpipe deste contêiner, e a
  prova roda sem renderizador exatamente para não gastar meia hora respondendo à pergunta
  errada.
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

POPULATION_SCRIPT = "res://tools/population.gd"
RESULT_PREFIX = "MEDIEV_POPULATION "

# Estados que três minutos de cidade têm de exercitar. Uma população que nunca sai de IDLE
# passa em movimento e em dispersão e continua sendo uma população que não faz nada.
EXPECTED_STATES = ("WALK_TO",)


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _audit(report: dict) -> list[str]:
    problems: list[str] = []

    if report["npcs"] < report["expected"]:
        problems.append(
            f"a cidade tem {report['npcs']} habitantes, e {report['expected']} foram "
            f"pedidos. Falta corpo, agenda ou marcador."
        )
    if report["worst_window_movers"] < report["min_movers"]:
        problems.append(
            f"na pior janela de {P.POPULATION_WINDOW:g}s só {report['worst_window_movers']:.0%} "
            f"dos habitantes saíram do lugar, abaixo do mínimo de "
            f"{report['min_movers']:.0%}. A praça para de ter movimento em algum momento "
            f"dos três minutos."
        )
    if report["novelty"] < report["min_novelty"]:
        problems.append(
            f"a novidade dos rastros é {report['novelty']:.2f}, abaixo do mínimo de "
            f"{report['min_novelty']:.2f}. Há movimento, mas ele se repete: os habitantes "
            f"voltam a pisar onde já pisaram em vez de cobrir terreno novo."
        )
    if report["stuck"] > report["max_stuck"]:
        problems.append(
            f"{report['stuck']} destravamento(s) em {P.POPULATION_SECONDS:g}s. Alguém "
            f"ficou preso numa quina de porta e precisou ser recolocado no navmesh."
        )
    if report["clipping"] > report["max_clipping"]:
        problems.append(
            f"{report['clipping']} amostra(s) com um habitante dentro da caixa de colisão "
            f"de um prédio. Isso é atravessar parede."
        )
    if report["active_peak"] > report["active_ceiling"]:
        problems.append(
            f"pico de {report['active_peak']} NPCs com física ativa, acima do teto de "
            f"{report['active_ceiling']}."
        )
    missing = [state for state in EXPECTED_STATES if state not in report["states_seen"]]
    if missing:
        problems.append(
            f"nenhum habitante entrou no estado {missing} durante a prova. A agenda não "
            f"está movendo ninguém."
        )
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        # Sem renderizador: a prova é de física e de rotina. Ver o cabeçalho de population.gd.
        process = run_godot(["--headless", "--script", POPULATION_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    report = _extract(process.stdout)
    if report is None:
        fail(f"o Godot terminou com código {process.returncode} sem reportar medição.")
        for line in (process.stdout + process.stderr).splitlines():
            if line.startswith("SCRIPT ERROR") or line.startswith("ERROR"):
                print(f"  {line}", file=sys.stderr)
        return 1

    kinds = ", ".join(f"{name} {count}" for name, count in sorted(report["archetypes"].items()))
    print(f"  habitantes: {report['npcs']} ({kinds})")
    print(
        f"  movimento:  pior janela {report['worst_window_movers']:.0%} de "
        f"{report['windows']} janelas (mínimo {report['min_movers']:.0%})"
    )
    print(
        f"  novidade:   {report['novelty']:.2f} das amostras em terreno novo "
        f"(mínimo {report['min_novelty']:.2f})"
    )
    print(
        f"  integridade: {report['stuck']} entalos, {report['clipping']} amostras dentro "
        f"de parede"
    )
    print(
        f"  orçamento:  pico de {report['active_peak']}/{report['active_ceiling']} NPCs "
        f"com física"
    )
    print(
        f"  ambiente:   {report['smoke']} chaminés, {report['birds']} pássaros, "
        f"{report['leaves']} folhas"
    )
    print(f"  estados:    {', '.join(sorted(report['states_seen']))}")

    problems = _audit(report)
    if problems:
        print()
        for problem in problems:
            print(f"  ESTOUROU: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
