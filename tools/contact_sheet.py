"""Monta `docs/assets.html`: o catálogo visual do kit, numa página só.

Junta o que a fábrica sabe (nome, triângulos, dimensões, orçamento, semente) com o que
`preview_assets.py` renderizou, numa grade por categoria. É a página que responde
"como está o kit hoje?" sem abrir o Blender nem o Godot.

Python puro, sem dependência: só lê o manifesto e escreve HTML. Se um PNG faltar, a peça
aparece assim mesmo, marcada — um buraco visível é mais útil que uma peça omitida.
"""

from __future__ import annotations

import html
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import params as P  # noqa: E402

MANIFEST = ROOT / P.KIT_DIR / "manifest.json"
IMAGE_DIR = ROOT / P.PREVIEW_IMAGE_DIR
OUTPUT = ROOT / P.PREVIEW_SHEET

CATEGORY_LABELS = {
    "architecture": "Arquitetura",
    "props": "Props",
    "nature": "Natureza",
}

# Acima disto a peça aparece marcada como apertada no orçamento — ainda passa, mas é
# onde vale olhar antes de acrescentar detalhe.
_TIGHT_RATIO = 0.75

_STYLE = """
:root {
  --bg: #16151a; --panel: #201f26; --line: #35333d;
  --ink: #e8e4dc; --dim: #9d978c; --accent: #c9a253; --warn: #d08b52;
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2rem 1.5rem 4rem; background: var(--bg); color: var(--ink);
  font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
}
header { max-width: 76rem; margin: 0 auto 2rem; }
h1 { margin: 0 0 .35rem; font-size: 1.6rem; letter-spacing: .01em; }
.sub { color: var(--dim); font-size: .92rem; }
.totals { display: flex; flex-wrap: wrap; gap: 1.4rem; margin-top: 1rem; }
.total { background: var(--panel); border: 1px solid var(--line); border-radius: 8px;
         padding: .55rem .9rem; }
.total b { display: block; font-size: 1.25rem; font-variant-numeric: tabular-nums; }
.total span { color: var(--dim); font-size: .78rem; text-transform: uppercase;
              letter-spacing: .06em; }
main { max-width: 76rem; margin: 0 auto; }
details { border: 1px solid var(--line); border-radius: 10px; margin-bottom: 1.1rem;
          background: var(--panel); overflow: hidden; }
summary { cursor: pointer; padding: .85rem 1.1rem; font-weight: 600; list-style: none;
          display: flex; align-items: baseline; gap: .7rem; }
summary::-webkit-details-marker { display: none; }
summary::before { content: "▸"; color: var(--accent); transition: transform .15s; }
details[open] summary::before { transform: rotate(90deg); }
summary .count { color: var(--dim); font-weight: 400; font-size: .88rem; }
.grid { display: grid; gap: 1rem; padding: 0 1.1rem 1.2rem;
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr)); }
figure { margin: 0; background: #191820; border: 1px solid var(--line);
         border-radius: 8px; overflow: hidden; }
figure img { display: block; width: 100%; height: auto; background: #5a5a5a; }
figcaption { padding: .6rem .75rem .7rem; }
.name { font-weight: 600; letter-spacing: .01em; }
.meta { color: var(--dim); font-size: .8rem; margin-top: .25rem;
        font-variant-numeric: tabular-nums; }
.bar { height: 3px; background: #2c2a33; border-radius: 2px; margin-top: .5rem;
       overflow: hidden; }
.bar i { display: block; height: 100%; background: var(--accent); }
.bar.tight i { background: var(--warn); }
.missing { padding: 3rem .75rem; text-align: center; color: var(--warn);
           font-size: .85rem; }
footer { max-width: 76rem; margin: 2.5rem auto 0; color: var(--dim); font-size: .8rem;
         border-top: 1px solid var(--line); padding-top: 1rem; }
code { background: #2a2831; padding: .1rem .35rem; border-radius: 4px; font-size: .85em; }
"""


def _figure(entry: dict) -> str:
    name = html.escape(entry["name"])
    image = IMAGE_DIR / f"{entry['name']}.png"
    relative = Path(P.PREVIEW_IMAGE_DIR).name + "/" + image.name

    if image.exists():
        media = f'<img src="{relative}" alt="{name}" loading="lazy">'
    else:
        media = '<div class="missing">sem render — rode <code>make preview</code></div>'

    width, depth, height = entry["size"]
    ratio = entry["tris"] / entry["budget"] if entry["budget"] else 0.0
    tight = " tight" if ratio > _TIGHT_RATIO else ""
    percent = min(100.0, ratio * 100.0)

    return f"""      <figure>
        {media}
        <figcaption>
          <div class="name">{name}</div>
          <div class="meta">{entry['tris']} / {entry['budget']} tris &middot;
            {width:g} &times; {depth:g} &times; {height:g} m</div>
          <div class="bar{tight}"><i style="width:{percent:.0f}%"></i></div>
        </figcaption>
      </figure>"""


def _section(category: str, entries: list[dict]) -> str:
    label = CATEGORY_LABELS.get(category, category)
    total = sum(entry["tris"] for entry in entries)
    figures = "\n".join(_figure(entry) for entry in entries)
    return f"""    <details open>
      <summary>{label} <span class="count">{len(entries)} peças &middot; {total} tris</span></summary>
      <div class="grid">
{figures}
      </div>
    </details>"""


def render(manifest: dict) -> str:
    parts = manifest["parts"]
    by_category: dict[str, list[dict]] = {}
    for entry in parts:
        by_category.setdefault(entry["category"], []).append(entry)

    order = [key for key in CATEGORY_LABELS if key in by_category]
    order += [key for key in by_category if key not in CATEGORY_LABELS]
    sections = "\n".join(_section(key, by_category[key]) for key in order)

    rendered = sum(1 for entry in parts if (IMAGE_DIR / f"{entry['name']}.png").exists())
    angles = ", ".join(label for label, _ in P.PREVIEW_ANGLES)

    return f"""<!DOCTYPE html>
<meta charset="utf-8">
<title>Mediev Vaal — catálogo do kit</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<!-- ARQUIVO GERADO — NÃO EDITE À MÃO. Gerado por tools/contact_sheet.py. -->
<style>{_STYLE}</style>
<header>
  <h1>Catálogo do kit</h1>
  <div class="sub">
    {angles} &middot; figura de escala de {P.PREVIEW_FIGURE_HEIGHT:g} m &middot;
    semente {manifest['kit_seed']} &middot; grid de {manifest['grid_size']:g} m
  </div>
  <div class="totals">
    <div class="total"><b>{len(parts)}</b><span>peças</span></div>
    <div class="total"><b>{manifest['total_tris']}</b><span>triângulos</span></div>
    <div class="total"><b>{rendered}/{len(parts)}</b><span>renderizadas</span></div>
    <div class="total"><b>{len(manifest['palette'])}</b><span>cores na paleta</span></div>
  </div>
</header>
<main>
{sections}
</main>
<footer>
  Gerado por <code>make preview</code>. As imagens saem de <code>tools/preview_assets.py</code>
  (Blender headless) e os números do manifesto de <code>tools/gen_assets.py</code> — nenhum
  dos dois é editável à mão. A barra sob cada peça é o consumo do orçamento de triângulos
  da categoria; ela fica âmbar acima de {_TIGHT_RATIO:.0%}.
</footer>
"""


def main(argv: list[str] | None = None) -> int:
    del argv
    if not MANIFEST.exists():
        print(f"ERRO: {MANIFEST.relative_to(ROOT)} não existe. Rode `make assets`.", file=sys.stderr)
        return 1

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(manifest), encoding="utf-8")

    parts = manifest["parts"]
    missing = [entry["name"] for entry in parts
               if not (IMAGE_DIR / f"{entry['name']}.png").exists()]
    print(f"  catálogo: {OUTPUT.relative_to(ROOT)} ({len(parts)} peças)")
    if missing:
        print(f"  sem render: {', '.join(missing)} — rode `make preview`")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
