"""`make valley` — roda `tools/valley.gd` e cobra os critérios de aceite da fase.

O GDScript gera os dois vales e mede; este módulo decide se passaram. Os dois critérios
da fase viram checagens executáveis:

- **"duas seeds produzem vales reconhecivelmente diferentes"**: a diferença média de
  altura entre os dois relevos, como fração da amplitude, tem de passar de
  `VALLEY_MIN_DIFFERENCE` — e a mesma seed gerada duas vezes tem de dar exatamente zero.
  Comparar capturas não serviria — dois ângulos do mesmo vale também parecem diferentes; e
  um mínimo sem o caso nulo seria um número sem piso, que uma medição barulhenta passaria
  sozinha.
- **"ambos jogáveis"**: em cada vale, a estrada respeita `ROAD_MAX_SLOPE`, a malha de
  navegação cobre pelo menos `VALLEY_MIN_WALKABLE` do mapa, e o ponto de nascimento está
  apoiado no chão.

O terceiro critério da fase — 60 FPS e draw calls abaixo do teto — é de `make bench`, que
percorre a rota fixa com os contadores do renderizador na mão.

A seed fica gravada no manifesto ao fim da execução, então rodar isto **troca o vale** da
árvore. É de propósito: um comando que gera vales sem deixar nenhum para trás não teria
como ser inspecionado depois.

Quem escreve esse manifesto final é o gerador em Python, e não o GDScript que trocou a
seed durante a execução. O `JSON.stringify` do Godot e o `json.dumps` do Python separam
chaves e valores de formas diferentes, então um manifesto escrito de dentro do jogo é
byte a byte distinto do que `tools/gen_world.py` produz — e `make verify` acusaria deriva
num arquivo que ninguém editou à mão. A regeneração final acontece mesmo quando a prova
reprova: deixar a árvore num estado que o verificador rejeita transformaria uma falha de
critério em duas.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import gen_world, params as P  # noqa: E402
from tools.util import GodotMissing, GodotTimeout, ensure_imported, fail, run_godot  # noqa: E402

VALLEY_SCRIPT = "res://tools/valley.gd"
RESULT_PREFIX = "MEDIEV_VALLEY "
NO_DISPLAY_MARKER = "Sem display"


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _audit(report: dict) -> list[str]:
    problems: list[str] = []

    difference = report["difference"]
    if difference < report["min_difference"]:
        problems.append(
            f"as duas seeds diferem em média {difference:.1%} da amplitude do relevo, "
            f"abaixo do mínimo de {report['min_difference']:.0%}. A seed não está "
            f"chegando ao terreno — os dois vales são o mesmo vale."
        )

    null_difference = report["null_difference"]
    if null_difference != 0.0:
        problems.append(
            f"a mesma seed, gerada duas vezes, deu vales que diferem em "
            f"{null_difference:.2%}. A geração não é determinística, e a diferença de "
            f"{difference:.1%} entre seeds distintas não prova nada — pode ser esse mesmo "
            f"ruído."
        )

    for valley in report["valleys"]:
        label = f"seed {valley['seed']}"
        if valley["road_slope"] > report["slope_limit"]:
            problems.append(
                f"{label}: a estrada chega a {valley['road_slope']:.3f} de inclinação, "
                f"acima do limite de {report['slope_limit']:g}. O nivelamento da curva "
                f"não sobreviveu ao corte do terreno."
            )
        if valley["walkable"] < report["min_walkable"]:
            problems.append(
                f"{label}: a navegação cobre {valley['walkable']:.1%} do vale, abaixo do "
                f"mínimo de {report['min_walkable']:.0%}. Um vale sem malha de navegação "
                f"não é jogável, por mais bonito que fique na captura."
            )
        spawn = valley["spawn"]
        if spawn["clearance"] < 0.0:
            problems.append(
                f"{label}: o jogador nasce {abs(spawn['clearance']):.2f} m **dentro** do "
                f"chão. A planície não está onde o ponto de nascimento pensa que está."
            )
        if valley["scatter_instances"] <= 0:
            problems.append(f"{label}: nenhuma vegetação foi plantada.")
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        return _measure()
    finally:
        # O vale que fica na árvore é o da última seed da prova, escrito pelo gerador.
        gen_world.main([str(P.VALLEY_SEEDS[-1])])


def _measure() -> int:
    try:
        ensure_imported()
        process = run_godot(["--script", VALLEY_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    output = process.stdout + process.stderr
    if NO_DISPLAY_MARKER in output:
        fail(
            "A prova do vale precisa de display: sem renderizador as duas capturas saem\n"
            "pretas e a comparação visual some. Em CI:\n"
            "  xvfb-run -a -s '-screen 0 1920x1080x24' make valley"
        )
        return 1

    for line in process.stdout.splitlines():
        if line.startswith("  "):
            print(line)

    report = _extract(process.stdout)
    if report is None:
        fail(f"o Godot terminou com código {process.returncode} sem reportar medição.")
        return 1

    problems = _audit(report)
    if problems:
        print()
        for problem in problems:
            print(f"  ESTOUROU: {problem}", file=sys.stderr)
        return 1

    seeds = ", ".join(str(valley["seed"]) for valley in report["valleys"])
    print(
        f"\n  seeds {seeds}: relevo difere {report['difference']:.1%} em média "
        f"(mínimo {report['min_difference']:.0%}); a mesma seed duas vezes difere "
        f"{report['null_difference']:.0%}"
    )
    for valley in report["valleys"]:
        print(
            f"  seed {valley['seed']}: {valley['walkable']:.0%} navegável, estrada a "
            f"{valley['road_slope']:.3f}, {valley['scatter_instances']} plantas em "
            f"{valley['scatter_nodes']} nós, gerado em {valley['build_ms']:.0f} ms"
        )
    print(f"  tira: {P.VALLEY_DIR}/seeds.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
