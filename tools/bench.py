"""`make bench` — roda `tools/bench.gd` e mostra o que ele mediu.

O trabalho é todo do GDScript, que é quem tem acesso aos contadores do renderizador.
Este módulo só acha o Godot, garante que o projeto está importado, e traduz uma falha de
ambiente em mensagem útil em vez de traceback.

O artefato que interessa é `docs/bench_history.csv`, que ganha uma linha por execução.
`docs/bench.json` é a corrida de agora, para quem quiser o detalhe.
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

BENCH_SCRIPT = "res://tools/bench.gd"
RESULT_PREFIX = "MEDIEV_BENCH "
NO_DISPLAY_MARKER = "Sem display"


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        process = run_godot(["--script", BENCH_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    output = process.stdout + process.stderr
    if NO_DISPLAY_MARKER in output:
        fail(
            "O benchmark precisa de display: draw calls e frame time medidos sem\n"
            "renderizador seriam zero e infinito, e entrariam no histórico como se\n"
            "fossem medição. Em CI:\n"
            "  xvfb-run -a -s '-screen 0 1920x1080x24' make bench"
        )
        return 1

    for line in process.stdout.splitlines():
        if line.startswith("  "):
            print(line)

    report = _extract(process.stdout)
    if report is None:
        print(output[-2000:], file=sys.stderr)
        fail("O benchmark não reportou métricas.")
        return 1

    print()
    print(f"  detalhe:   {P.BENCH_JSON}")
    print(f"  histórico: {P.BENCH_HISTORY}")

    violations = report.get("violations", [])
    if violations:
        print(f"  bench REPROVADO: {len(violations)} teto(s) estourado(s).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
