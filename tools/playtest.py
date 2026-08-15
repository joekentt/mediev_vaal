"""`make playtest` — roda `tools/playtest.gd` e cobra os critérios de aceite do controle.

O GDScript dirige e mede; este módulo traduz medida em aprovação ou reprovação. Os três
critérios da fase viram três checagens executáveis:

- **andar/correr fluidos**: a velocidade estabilizada bate com `params.py` dentro da
  tolerância, e o tempo até 90% dela é reportado — é a sensação de peso em segundos;
- **pular fluido**: a altura do salto bate com `PLAYER_JUMP_HEIGHT`, e o coyote time
  aceita um pulo apertado *depois* da beirada;
- **a câmera nunca atravessa parede**: a menor folga da lente ao longo de uma órbita
  completa encostado num muro é positiva.

"Nenhum valor mágico" é o terceiro critério e não passa por aqui: quem cobra isso é
`make verify`, em cima do código-fonte.
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

PLAYTEST_SCRIPT = "res://tools/playtest.gd"
RESULT_PREFIX = "MEDIEV_PLAYTEST "
NO_DISPLAY_MARKER = "Sem display"


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _check_speed(label: str, measured: float, target: float, tolerance: float) -> list[str]:
    drift = abs(measured - target) / target if target else 0.0
    if drift <= tolerance:
        return []
    return [
        f"{label}: estabilizou em {measured:.2f} m/s contra o alvo de {target:.2f} m/s "
        f"({drift:.0%} de desvio, limite {tolerance:.0%}). O corpo não está chegando à "
        f"velocidade que params.py manda."
    ]


def _audit(report: dict) -> list[str]:
    tolerance = report["tolerance"]
    problems: list[str] = []
    problems += _check_speed("caminhada", report["walk"]["speed"], report["walk_target"], tolerance)
    problems += _check_speed("corrida", report["run"]["speed"], report["run_target"], tolerance)

    jump = report["jump"]
    drift = abs(jump["height"] - jump["target"]) / jump["target"]
    if drift > tolerance:
        problems.append(
            f"salto: subiu {jump['height']:.2f} m contra o alvo de {jump['target']:.2f} m "
            f"({drift:.0%} de desvio). Confira gravidade e `v = sqrt(2·g·h)`."
        )

    coyote = report["coyote"]
    if not coyote["jumped"]:
        problems.append(
            f"coyote time: o pulo apertado {coyote['waited']:.3f} s depois de sair da "
            f"beirada não aconteceu, e a janela é de {P.PLAYER_COYOTE_TIME:g} s. Sem isto "
            f"todo pulo na quina falha e o jogador culpa o controle — corretamente."
        )

    clearance = report["camera_clearance"]
    if clearance <= 0.0:
        problems.append(
            f"câmera: a lente entrou {abs(clearance):.3f} m na geometria. O braço de mola "
            f"não está encurtando — confira `collision_mask` e `margin` do SpringArm3D."
        )
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        process = run_godot(["--script", PLAYTEST_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    output = process.stdout + process.stderr
    if NO_DISPLAY_MARKER in output:
        fail(
            "A prova do controle precisa de display: sem renderizador não há captura e o\n"
            "braço de câmera não tem o que varrer. Em CI:\n"
            "  xvfb-run -a -s '-screen 0 1920x1080x24' make playtest"
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

    print(
        f"\n  controle: {report['walk']['speed']:.2f} / {report['run']['speed']:.2f} m/s, "
        f"salto de {report['jump']['height']:.2f} m, coyote ok"
    )
    print(f"  câmera: folga mínima de {report['camera_clearance']:.3f} m em toda a órbita")
    print(f"  tira: {P.PLAYTEST_DIR}/controle.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
