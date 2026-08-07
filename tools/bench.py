"""`make bench` — mede contra o orçamento e falha se estourar.

Mesmo caminho de `make preview`, com duas diferenças: não salva captura e o código de
saída é o veredito. É o alvo para pendurar em CI ou rodar antes de fechar uma fase.
"""

from __future__ import annotations

import sys

from . import preview
from .util import GodotMissing, GodotTimeout, ROOT, fail, run_godot

OUTPUT = ROOT / "assets/generated/bench/bench.json"


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    budget_key = argv[0] if argv else preview.DEFAULT_BUDGET_KEY

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    try:
        process = run_godot(["--", "--bench", "--out", str(OUTPUT), "--budget", budget_key])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    summary = preview._extract_result(process.stdout)
    if summary is None:
        print(process.stdout)
        print(process.stderr, file=sys.stderr)
        fail("O projeto não reportou métricas.")
        return 1

    within_budget = preview.report(summary, budget_key)
    print(f"  resumo: {OUTPUT.relative_to(ROOT)}")
    if not within_budget:
        print("  bench REPROVADO: a cena está fora do orçamento.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
