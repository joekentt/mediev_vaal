"""`make preview` — roda o projeto, mede e reporta os números do orçamento.

É o gesto de fim de fase: gerar, rodar, medir, reportar. O CLAUDE.md manda rodar isto ao
terminar qualquer fase e colar os números no relatório.

Salva também um PNG do que a câmera vê, em `assets/generated/preview/`, para dar para
olhar o resultado sem abrir o editor.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from . import params as P
from .util import (
    MAX_DIAGNOSTIC_LINES,
    GodotMissing,
    GodotTimeout,
    ROOT,
    ensure_imported,
    fail,
    run_godot,
)

RESULT_PREFIX = "MEDIEV_RESULT "
OUTPUT_DIR = ROOT / "assets/generated/preview"
DEFAULT_BUDGET_KEY = "draw_calls_wilderness"


NO_DISPLAY_MARKER = "Unable to create DisplayServer"


def _extract_result(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def explain_missing_result(process) -> str:
    """Traduz um fim de execução sem métricas na causa provável."""
    output = process.stdout + process.stderr
    if NO_DISPLAY_MARKER in output:
        return (
            "O Godot não conseguiu abrir uma janela, então não há o que medir.\n"
            "Medir sem renderizar não diz nada sobre draw calls nem frame time, por isso\n"
            "este alvo não roda em headless. Numa sessão gráfica ele funciona direto; em\n"
            "CI, envolva com um display virtual:\n"
            "  xvfb-run -a -s '-screen 0 1920x1080x24' make bench"
        )
    diagnostics = [
        line for line in output.splitlines()
        if line.startswith("SCRIPT ERROR") or line.startswith("ERROR")
    ]
    if diagnostics:
        joined = "\n    ".join(dict.fromkeys(diagnostics[:MAX_DIAGNOSTIC_LINES]))
        return f"O projeto não reportou métricas. O Godot reclamou:\n    {joined}"
    return "O projeto não reportou métricas. SessionProbe chegou a rodar?"


def _row(label: str, value: str, ceiling: str = "", ok: bool | None = None) -> str:
    mark = "" if ok is None else ("  ok" if ok else "  ESTOUROU")
    return f"  {label:<26} {value:>12}{ceiling:>16}{mark}"


def report(summary: dict, budget_key: str) -> bool:
    draw_ceiling = P.BUDGET[budget_key]
    tri_ceiling = P.BUDGET["visible_tris"]
    material_ceiling = P.BUDGET["unique_materials"]

    draw_calls = int(summary["draw_calls"])
    triangles = int(summary["triangles"])
    materials = int(summary["materials_loaded"])
    frame_avg = float(summary["frame_ms_avg"])
    frame_max = float(summary["frame_ms_max"])
    fps_avg = float(summary["fps_avg"])
    headless = bool(summary.get("headless", False))

    print()
    print(f"  {'métrica':<26} {'medido':>12} {'teto':>16}")
    print(f"  {'-' * 60}")
    print(_row("draw calls (pico)", str(draw_calls), str(draw_ceiling), draw_calls <= draw_ceiling))
    print(_row("triângulos (pico)", str(triangles), str(tri_ceiling), triangles <= tri_ceiling))
    print(_row("materiais únicos", str(materials), str(material_ceiling), materials <= material_ceiling))
    print(_row("frame time médio", f"{frame_avg:.2f} ms", f"{P.FRAME_BUDGET_MS} ms", frame_avg <= P.FRAME_BUDGET_MS))
    print(_row("frame time pior", f"{frame_max:.2f} ms"))
    print(_row("fps médio", f"{fps_avg:.1f}", str(P.TARGET_FPS), fps_avg >= P.TARGET_FPS))
    print(_row("objetos desenhados", str(int(summary["objects"]))))
    print(_row("memória estática", f"{float(summary['memory_mb']):.1f} MB"))
    print(_row("amostras", str(int(summary["samples"]))))
    print()

    if headless:
        print("  NOTA: rodou sem display (headless). Draw calls e frame time não são")
        print("        representativos — use uma sessão com janela para medir de verdade.")
        print()

    violations = summary.get("violations", [])
    if violations:
        print("  Fora do orçamento:")
        for violation in violations:
            print(f"    - {violation}")
        print()
        return False

    print("  Dentro do orçamento.")
    print()
    return True


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    budget_key = argv[0] if argv else DEFAULT_BUDGET_KEY
    if budget_key not in P.BUDGET:
        fail(f"Orçamento desconhecido: {budget_key!r}. Escolhas: {', '.join(P.BUDGET)}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    screenshot = OUTPUT_DIR / "preview.png"
    summary_path = OUTPUT_DIR / "preview.json"

    try:
        ensure_imported()
        process = run_godot([
            "--",
            "--bench",
            "--screenshot", str(screenshot),
            "--out", str(summary_path),
            "--budget", budget_key,
        ])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    if process.returncode != 0:
        print(process.stdout)
        print(process.stderr, file=sys.stderr)
        fail(f"Godot terminou com código {process.returncode}.")

    summary = _extract_result(process.stdout)
    if summary is None:
        fail(explain_missing_result(process))
        return 1

    within_budget = report(summary, budget_key)
    print(f"  captura: {screenshot.relative_to(ROOT)}")
    print(f"  resumo:  {summary_path.relative_to(ROOT)}")
    return 0 if within_budget else 1


if __name__ == "__main__":
    raise SystemExit(main())
