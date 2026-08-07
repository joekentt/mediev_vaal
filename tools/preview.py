"""`make preview` — os olhos do projeto, numa passada.

Três etapas, nesta ordem, porque cada uma alimenta a seguinte:

1. `preview_assets.py` renderiza um contato de cada peça do kit (Blender);
2. `contact_sheet.py` monta `docs/assets.html` com esses renders e os números do
   manifesto (Python puro);
3. `godot_shot.gd` captura a cena de verdade dos pontos de câmera nomeados (Godot).

As etapas 1 e 3 precisam de ferramentas externas e a 3 precisa de display. Quando uma
falta, o alvo **não** finge sucesso: diz qual etapa não rodou e por quê, e continua as
que consegue — meia visão é melhor que nenhuma, desde que fique claro qual metade falta.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import contact_sheet, params as P, preview_assets  # noqa: E402
from tools.util import GodotMissing, GodotTimeout, ensure_imported, run_godot  # noqa: E402

SHOT_SCRIPT = "res://tools/godot_shot.gd"
NO_DISPLAY_MARKER = "Sem display"


def _step(title: str) -> None:
    print(f"  --- {title} ---")


def run_shots() -> tuple[bool, str]:
    """Capturas da cena no Godot. Devolve (rodou, motivo de não ter rodado)."""
    try:
        ensure_imported()
        process = run_godot(["--script", SHOT_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        return False, str(error)

    output = process.stdout + process.stderr
    if NO_DISPLAY_MARKER in output:
        return False, (
            "o Godot rodou sem display, e sem renderizador não há imagem.\n"
            "    Em CI: xvfb-run -a -s '-screen 0 1920x1080x24' make preview"
        )
    if process.returncode != 0:
        return False, f"o Godot terminou com código {process.returncode}."
    for line in output.splitlines():
        if line.startswith("  ") and "->" in line:
            print(line)
    return True, ""


def main(argv: list[str] | None = None) -> int:
    del argv
    skipped: list[str] = []

    _step("renderizando o kit (Blender)")
    if preview_assets.main([]) != 0:
        skipped.append("renders do kit")

    _step("montando o catálogo")
    if contact_sheet.main([]) != 0:
        skipped.append("catálogo")

    _step("capturando a cena (Godot)")
    ran, reason = run_shots()
    if not ran:
        skipped.append("capturas da cena")
        print(f"  PULADO: {reason}")

    print()
    print(f"  catálogo: {P.PREVIEW_SHEET}")
    print(f"  capturas: {P.SHOTS_DIR}")
    if skipped:
        print(f"  NÃO rodou: {', '.join(skipped)}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
