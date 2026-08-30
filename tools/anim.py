"""`make anim` — roda `tools/anim_preview.gd` e traduz o que ele mediu.

O trabalho é do GDScript: só ele tem esqueleto, física e renderizador. Este módulo acha o
Godot, garante o projeto importado, e transforma "o pé deslizou 3 cm" numa falha de build
em vez de num PNG que ninguém abriu.

Precisa de display, pela mesma razão de `make preview`: sem renderizador o viewport
devolve preto, e uma tira preta parece um bug de animação em vez de um bug de ambiente.
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

ANIM_SCRIPT = "res://tools/anim_preview.gd"
RESULT_PREFIX = "MEDIEV_ANIM "
NO_DISPLAY_MARKER = "Sem display"


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _check_gait_spread(gaits: list[dict]) -> list[str]:
    """Cobra o critério de aceite: posturas diferentes têm de produzir marchas diferentes.

    Compara os parâmetros que de fato chegaram ao corpo, e não os de `params.py`. A
    diferença importa: um perfil que não é carregado deixa os três andando igual com o
    arquivo na árvore inteiramente correto.
    """
    problems: list[str] = []
    if len(gaits) < 2:
        return problems

    for field in ("stride_scale", "cadence_scale", "foot_lift", "arm_swing_deg"):
        values = {entry["posture"]: entry[field] for entry in gaits}
        if len(set(values.values())) < len(values):
            problems.append(
                f"as marchas comparadas têm o mesmo {field} ({values}) — o perfil não "
                f"está chegando ao corpo, e as três silhuetas andariam igual."
            )
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        process = run_godot(["--script", ANIM_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    output = process.stdout + process.stderr
    if NO_DISPLAY_MARKER in output:
        fail(
            "A tira de quadros precisa de display: sem renderizador o viewport devolve\n"
            "preto, e uma tira preta parece defeito de animação. Em CI:\n"
            "  xvfb-run -a -s '-screen 0 1920x1080x24' make anim"
        )
        return 1

    for line in process.stdout.splitlines():
        if line.startswith("  "):
            print(line)

    report = _extract(process.stdout)
    if report is None:
        fail(f"o Godot terminou com código {process.returncode} sem reportar medição.")
        return 1

    problems: list[str] = []
    limit = report["slide_limit"]
    for take, slide in report["slide"].items():
        if slide > limit:
            problems.append(
                f"{take}: o pé apoiado andou {slide:.4f} m, acima do limite de "
                f"{limit:g} m. A passada deixou de ser função da velocidade — confira "
                f"`frequency_scale` e o cálculo de cadência."
            )
    problems += _check_gait_spread(report["gaits"])

    if problems:
        print()
        for problem in problems:
            print(f"  ESTOUROU: {problem}", file=sys.stderr)
        print(f"\n  tiras: {P.ANIM_DIR}")
        return 1

    worst = max(report["slide"].values()) if report["slide"] else 0.0
    print(f"\n  pé apoiado: no máximo {worst:.4f} m de desvio (limite {limit:g} m)")
    costs = report.get("physics_ms", {})
    if costs:
        peak = max(costs.values())
        # O orçamento de NPCs ativos é o que este número decide: se posar um corpo custa
        # X ms, `active_npcs` corpos custam X vezes isso, e o frame inteiro tem 16,6 ms.
        total = peak * P.BUDGET["active_npcs"]
        print(
            f"  pose de um corpo: {peak:.3f} ms/frame  "
            f"(x{P.BUDGET['active_npcs']} NPCs = {total:.2f} ms de "
            f"{P.FRAME_BUDGET_MS:g} ms de frame)"
        )
    print(f"  tiras: {P.ANIM_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
