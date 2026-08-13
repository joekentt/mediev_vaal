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
CHARACTER_MANIFEST = ROOT / P.CHARACTER_DIR / "manifest.json"
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
.grid.wide { grid-template-columns: repeat(auto-fill, minmax(24rem, 1fr)); }
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
.poses { display: grid; grid-template-columns: 1fr 1fr; gap: 1px; background: var(--line); }
.pose { position: relative; }
.pose span { position: absolute; left: .35rem; top: .35rem; background: #000a;
             color: var(--ink); font-size: .68rem; padding: .05rem .3rem;
             border-radius: 3px; letter-spacing: .04em; }
.tags { color: var(--dim); font-size: .75rem; margin-top: .2rem; }
.ok { color: var(--accent); }
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


def _image(name: str, label: str) -> str:
    """Uma imagem do catálogo, ou o buraco visível que diz que ela falta."""
    if not (IMAGE_DIR / f"{name}.png").exists():
        return f'<div class="missing">sem render de {html.escape(label)}</div>'
    relative = Path(P.PREVIEW_IMAGE_DIR).name + "/" + f"{name}.png"
    return (
        f'<div class="pose"><img src="{relative}" alt="{html.escape(name)}" loading="lazy">'
        f'<span>{html.escape(label)}</span></div>'
    )


def _character_figure(entry: dict, suffix: str, limit: float) -> str:
    """Um personagem: T-pose à esquerda, pose de teste à direita.

    As duas imagens lado a lado são o argumento inteiro. A da esquerda diz que a
    silhueta saiu certa; só a da direita diz que o skinning aguenta — em T-pose todo rig
    parece impecável, porque nenhum osso girou ainda.
    """
    name = html.escape(entry["name"])
    width, depth, height = entry["size"]
    ratio = entry["tris"] / entry["budget"] if entry["budget"] else 0.0
    tight = " tight" if ratio > _TIGHT_RATIO else ""
    stretch = entry["max_edge_stretch"]
    verdict = "ok" if stretch <= limit else "warn"

    tags = " &middot; ".join(html.escape(str(entry[key])) for key in
                             ("posture", "clothing", "hair", "ears"))
    return f"""      <figure>
        <div class="poses">
{_image(entry['name'], 'T-pose')}
{_image(entry['name'] + suffix, 'pose de teste')}
        </div>
        <figcaption>
          <div class="name">{name}</div>
          <div class="meta">{entry['tris']} / {entry['budget']} tris &middot;
            {entry['bones']} ossos &middot; {entry['height']:g} m &middot;
            ombro {entry['shoulder_span']:g} m</div>
          <div class="meta">envergadura {width:g} &times; {depth:g} &times; {height:g} m
            &middot; até {entry['influences_max']} ossos por vértice &middot;
            <span class="{verdict}">estica {stretch:g}x</span> (limite {limit:g}x)</div>
          <div class="tags">{tags}{' &middot; barba' if entry['beard'] else ''}</div>
          <div class="bar{tight}"><i style="width:{min(100.0, ratio * 100.0):.0f}%"></i></div>
        </figcaption>
      </figure>"""


def _character_section(manifest: dict) -> str:
    entries = manifest["characters"]
    total = sum(entry["tris"] for entry in entries)
    figures = "\n".join(
        _character_figure(entry, manifest["pose_suffix"], manifest["max_edge_stretch"])
        for entry in entries
    )
    return f"""    <details open>
      <summary>Personagens <span class="count">{len(entries)} corpos &middot; {total} tris
        &middot; teto de {manifest['tri_budget']} tris cada</span></summary>
      <div class="grid wide">
{figures}
      </div>
    </details>"""


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


def render(manifest: dict, characters: dict | None = None) -> str:
    parts = manifest["parts"]
    by_category: dict[str, list[dict]] = {}
    for entry in parts:
        by_category.setdefault(entry["category"], []).append(entry)

    order = [key for key in CATEGORY_LABELS if key in by_category]
    order += [key for key in by_category if key not in CATEGORY_LABELS]
    sections = "\n".join(_section(key, by_category[key]) for key in order)
    if characters is not None:
        sections = _character_section(characters) + "\n" + sections

    people = 0 if characters is None else len(characters["characters"])
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
    <div class="total"><b>{people}</b><span>personagens</span></div>
    <div class="total"><b>{manifest['total_tris']}</b><span>triângulos do kit</span></div>
    <div class="total"><b>{rendered}/{len(parts)}</b><span>peças renderizadas</span></div>
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
    characters = (
        json.loads(CHARACTER_MANIFEST.read_text(encoding="utf-8"))
        if CHARACTER_MANIFEST.exists() else None
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(manifest, characters), encoding="utf-8")

    parts = manifest["parts"]
    missing = [entry["name"] for entry in parts
               if not (IMAGE_DIR / f"{entry['name']}.png").exists()]
    people = 0 if characters is None else len(characters["characters"])
    print(f"  catálogo: {OUTPUT.relative_to(ROOT)} ({len(parts)} peças, {people} personagens)")
    if missing:
        print(f"  sem render: {', '.join(missing)} — rode `make preview`")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
