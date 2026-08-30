"""`make city` — roda `tools/city.gd` e cobra os critérios de aceite da fase.

O GDScript gera as cidades e mede; este módulo decide se passaram. Os três critérios da
fase viram checagens executáveis, e um deles não vira:

- **"nenhuma quebrada"**: em cada seed, nenhum problema de traçado (sobreposição de
  prédio, marcador obrigatório ausente, beco sem saída) e nenhuma porta fora do alcance da
  malha de navegação.
- **"três seeds, três cidades plausíveis"**: as três geram, e cada uma passa do mínimo de
  prédios. Plausível é o que sobra depois de "não quebrada" — cidade que valida mas tem
  seis casas não é cidade.
- **"60 FPS na praça"**: cobrado em draw calls e triângulos, que são o que o orçamento
  controla e o que não depende de GPU. Frame time é reportado e **não** reprova aqui: sem
  GPU o número mede o llvmpipe, não a cidade. Quem cobra frame time é `make bench`, e lá
  a limitação já está documentada.
- **"lê como habitável"** não vira número. É o que as seis capturas em `docs/shots/city/`
  existem para responder, e nenhuma delas é lida por este arquivo.

`make city SEED=123` gera só aquela seed e é a que deixa as capturas na árvore.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import gen_world, params as P  # noqa: E402
from tools.util import GodotMissing, GodotTimeout, ensure_imported, fail, run_godot  # noqa: E402

CITY_SCRIPT = "res://tools/city.gd"
RESULT_PREFIX = "MEDIEV_CITY "
NO_DISPLAY_MARKER = "Sem display"
SEEDS_ENV = "MEDIEV_CITY_SEEDS"


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _audit(report: dict) -> list[str]:
    problems: list[str] = []
    for city in report["cities"]:
        label = f"seed {city['seed']}"

        if city["layout_problems"] > 0:
            problems.append(
                f"{label}: {city['layout_problems']} problema(s) de traçado. O Godot os "
                f"imprimiu como ERROR — sobreposição de prédio, marcador ausente ou beco "
                f"sem saída."
            )
        if city["doors_unreachable"] > 0:
            problems.append(
                f"{label}: {city['doors_unreachable']} de {city['doors_total']} portas "
                f"sem caminho pela malha de navegação a partir da praça (a pior fica a "
                f"{city['doors_worst_gap_m']:.1f} m de qualquer polígono, limite "
                f"{P.CITY_DOOR_REACH:g} m). Uma porta que o navmesh não alcança é uma "
                f"porta que NPC nenhum vai atravessar."
            )
        if city["buildings"] < report["min_buildings"]:
            problems.append(
                f"{label}: {city['buildings']} prédios, abaixo do mínimo de "
                f"{report['min_buildings']}."
            )
        if city["house_markers"] < 1:
            problems.append(f"{label}: nenhum marcador de casa foi gerado.")
        if city["plaza_draw_calls"] > report["draw_call_ceiling"]:
            problems.append(
                f"{label}: {city['plaza_draw_calls']} draw calls na praça, acima do teto "
                f"de {report['draw_call_ceiling']}. A praça é o pior ângulo da cidade e é "
                f"onde o orçamento tem de fechar."
            )
        if city["plaza_triangles"] > report["triangle_ceiling"]:
            problems.append(
                f"{label}: {city['plaza_triangles']} triângulos na praça, acima do teto "
                f"de {report['triangle_ceiling']}."
            )
    return problems


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    seeds = [int(argv[0])] if argv and argv[0].strip() else list(P.CITY_SEEDS)

    environment = dict(os.environ)
    environment[SEEDS_ENV] = ",".join(str(seed) for seed in seeds)

    try:
        return _measure(environment, seeds)
    finally:
        # A cidade que fica na árvore é a da última seed medida, escrita pelo gerador em
        # Python — o GDScript troca a seed durante a execução e o `JSON.stringify` dele
        # não bate byte a byte com o `json.dumps` daqui. Ver `tools/valley.py`.
        gen_world.main([str(seeds[-1])])


def _measure(environment: dict, seeds: list[int]) -> int:
    try:
        ensure_imported()
        process = run_godot(["--script", CITY_SCRIPT], environment=environment)
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    output = process.stdout + process.stderr
    if NO_DISPLAY_MARKER in output:
        fail(
            "A prova da cidade precisa de display: sem renderizador as capturas saem\n"
            "pretas e o contador de draw call devolve zero. Em CI:\n"
            "  xvfb-run -a -s '-screen 0 1920x1080x24' make city"
        )
        return 1

    for line in process.stdout.splitlines():
        if line.startswith("  "):
            print(line)

    report = _extract(process.stdout)
    if report is None:
        fail(
            f"o Godot terminou com código {process.returncode} sem reportar medição "
            f"para as seeds {seeds}."
        )
        for line in output.splitlines():
            if line.startswith("SCRIPT ERROR") or line.startswith("ERROR"):
                print(f"  {line}", file=sys.stderr)
        return 1

    problems = _audit(report)
    if problems:
        print()
        for problem in problems:
            print(f"  ESTOUROU: {problem}", file=sys.stderr)
        return 1

    print()
    for city in report["cities"]:
        print(
            f"  seed {city['seed']}: {city['buildings']} prédios em {city['lots']} lotes, "
            f"{city['instances']} peças em {city['draw_nodes']} nós, "
            f"{city['occluders']} occluders"
        )
        print(
            f"    praça: {city['plaza_draw_calls']}/{report['draw_call_ceiling']} draw calls, "
            f"{city['plaza_triangles']}/{report['triangle_ceiling']} triângulos, "
            f"{city['plaza_frame_ms']:.1f} ms de passo idle"
        )
        print(
            f"    sítio: inclinação {city['site_slope']:.3f}, corte de terraplenagem "
            f"{city['terrace_cut_m']:.1f} m, portão a {city['gate_road_distance_m']:.1f} m "
            f"da estrada"
        )
        print(
            f"    {city['doors_total']} portas, todas no navmesh (pior folga "
            f"{city['doors_worst_gap_m']:.2f} m); {city['dead_ends']} becos sem saída"
        )
    print(f"  capturas: {P.CITY_DIR} (seed {report['cities'][0]['seed']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
