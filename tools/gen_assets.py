"""`make assets` — fábrica de peças do kit em Blender headless.

Gera as 34 peças paramétricas de `kit_architecture`, `kit_props` e `kit_nature`, confere
cada uma contra as restrições duras do projeto, exporta `.glb` para `assets/generated/kit/`
e escreve o `manifest.json` que a fase 6 vai ler para montar prédios.

**Dois pontos de entrada, de propósito:**

    blender --background --python tools/gen_assets.py -- [nomes...]
    python -m tools.gen_assets [nomes...]

O primeiro é o caminho canônico. O segundo procura o `blender` no PATH e reexecuta o
primeiro; se não achar, cai para o módulo `bpy` do PyPI, que é o mesmo Blender sem a
casca de aplicativo. Máquina de desenvolvedor costuma ter o binário; CI costuma achar
mais fácil `pip install bpy`. Os dois produzem o mesmo `.glb`.

**Restrições que reprovam a peça** (não avisam — reprovam):

- teto de triângulos por categoria (`params.KIT_TRI_BUDGET`);
- normais consistentes, e para fora quando a malha é fechada;
- nenhuma camada de UV, nenhuma textura;
- toda face pintada com uma chave de `params.PALETTE`;
- origem no canto inferior mínimo, alinhada ao grid nas peças que declaram encaixe.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import params as P  # noqa: E402

KIT_DIR = ROOT / P.KIT_DIR
MANIFEST = KIT_DIR / "manifest.json"
MATERIAL_NAME = "kit_flat"
ARG_SEPARATOR = "--"

# Precisão do manifesto. Mais casas só acrescentariam ruído de ponto flutuante ao diff.
_ROUND = 4


def _is_inside_blender() -> bool:
    try:
        import bpy  # noqa: F401
    except ImportError:
        return False
    return True


# ---------------------------------------------------------------------------
# Catálogo
# ---------------------------------------------------------------------------


def build_catalog() -> list[dict]:
    """Todas as peças, com a categoria que define o orçamento de triângulos.

    A categoria `tree` existe só para dar às árvores o teto maior de `KIT_TRI_BUDGET`;
    no manifesto elas continuam sendo natureza, e é por `group` que a fase 3 as procura.
    """
    from tools import kit_architecture as A
    from tools import kit_nature as N
    from tools import kit_props as R

    # `grid_axes` diz *quais* eixos horizontais precisam medir um múltiplo do grid.
    # Não é o mesmo que "a peça é modular": uma parede vence uma célula em X e tem
    # 25 cm de espessura em Y — exigir 2 m nos dois eixos seria exigir uma parede cúbica.
    # Telhado declara nenhum eixo porque o beiral ultrapassa a célula de propósito.
    architecture = [
        (A.wall, ("x",)),
        (A.wall_window, ("x",)),
        (A.wall_door, ("x",)),
        (A.roof_gable, ()),
        (A.roof_hip, ()),
        (A.beam, ("x",)),
        (A.pillar, ()),
        (A.stairs, ("x", "y")),
        (A.floor_tile, ("x", "y")),
        (A.wall_gate, ("x",)),
        (A.tower, ()),
        (A.bridge, ("x", "y")),
        (A.fence, ("x",)),
        (A.sign, ()),
    ]
    props = [
        R.barrel, R.crate, R.well, R.market_stall, R.lantern_post, R.cart,
        R.anvil, R.bench, R.pot, R.sack, R.rope, R.banner,
    ]
    nature = [
        N.rock, N.tree_broadleaf, N.tree_conifer, N.bush, N.grass_tuft,
        N.log, N.stump, N.boulder,
    ]

    catalog: list[dict] = []
    for function, axes in architecture:
        catalog.append(_entry(function, "architecture", "architecture", axes))
    for function in props:
        catalog.append(_entry(function, "props", "props", ()))
    for function in nature:
        # Árvore custa o dobro do teto normal; o resto da natureza não.
        budget = "tree" if function.__name__.startswith("tree_") else "nature"
        catalog.append(_entry(function, "nature", budget, ()))
    return catalog


def _entry(function, group: str, budget_key: str, grid_axes: tuple[str, ...]) -> dict:
    from tools import meshlib as M

    return {
        "name": function.__name__,
        "function": function,
        "group": group,
        "budget_key": budget_key,
        "grid_axes": grid_axes,
        "seed": M.part_seed(function.__name__),
    }


# ---------------------------------------------------------------------------
# Produção de uma peça
# ---------------------------------------------------------------------------


def build_part(spec: dict) -> dict:
    """Constrói, confere e exporta uma peça. Devolve a entrada do manifesto.

    Levanta `AssetError` na primeira restrição violada — a fábrica não entrega peça
    torta com um aviso no log.
    """
    import bpy

    from tools import meshlib as M

    M.clear_scene()
    bm = spec["function"](spec["seed"])

    M.recalc_normals(bm)
    M.triangulate(bm)
    M.recalc_normals(bm)

    placement = M.snap_origin_to_grid(bm, grid_axes=spec["grid_axes"])
    triangles = M.triangle_count(bm)
    normals = M.inspect_normals(bm)
    (min_corner, max_corner) = M.bounds(bm)

    _enforce(spec, triangles, normals, placement)

    # Só depois de conferir a topologia: a canonicalização separa vértices por face e a
    # malha deixaria de parecer fechada para `inspect_normals`.
    bm = M.canonicalize(bm)

    material = M.flat_material(MATERIAL_NAME)
    obj = M.to_object(bm, spec["name"], material)
    bm.free()

    _assert_no_uv(obj)
    path = KIT_DIR / f"{spec['name']}.glb"
    _export_glb(obj, path)

    return {
        "name": spec["name"],
        "category": spec["group"],
        "file": path.name,
        "tris": triangles,
        "budget": P.KIT_TRI_BUDGET[spec["budget_key"]],
        "seed": spec["seed"],
        "grid_axes": list(spec["grid_axes"]),
        "cells": placement["cells"],
        "closed": normals["closed"],
        "bbox_min": [round(value, _ROUND) for value in min_corner],
        "bbox_max": [round(value, _ROUND) for value in max_corner],
        "size": [round(value, _ROUND) for value in placement["footprint"]],
    }


class AssetError(RuntimeError):
    """Uma peça violou uma restrição dura. O build inteiro para."""


def _enforce(spec: dict, triangles: int, normals: dict, placement: dict) -> None:
    name = spec["name"]
    ceiling = P.KIT_TRI_BUDGET[spec["budget_key"]]
    if triangles > ceiling:
        raise AssetError(
            f"{name}: {triangles} triângulos para um teto de {ceiling} "
            f"({spec['budget_key']}). Simplifique a peça ou renegocie o teto em params.py."
        )
    if not normals["consistent"]:
        raise AssetError(
            f"{name}: {normals['inconsistent_edges']} arestas com faces em sentidos "
            f"opostos — há face invertida na malha."
        )
    if not normals["outward"]:
        raise AssetError(
            f"{name}: malha fechada com volume negativo ({normals['signed_volume']:.4f}) "
            f"— as normais apontam para dentro."
        )
    for axis in placement["misaligned"]:
        measured = placement["footprint"]["xyz".index(axis)]
        raise AssetError(
            f"{name}: mede {measured:.4f} m no eixo {axis.upper()}, que precisa ser "
            f"múltiplo do grid de {P.GRID_SIZE} m para a peça encaixar na célula."
        )


def _assert_no_uv(obj) -> None:
    if obj.data.uv_layers:
        raise AssetError(
            f"{obj.name}: tem camada de UV. O projeto não usa uma única textura — "
            f"cor vem de vertex color."
        )


def _export_glb(obj, path: Path) -> None:
    import bpy

    path.parent.mkdir(parents=True, exist_ok=True)
    for other in bpy.data.objects:
        other.select_set(other is obj)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format=P.KIT_EXPORT_FORMAT,
        use_selection=True,
        export_apply=True,
        export_yup=True,                 # Godot é Y-up; Blender é Z-up
        export_texcoords=False,          # não há UV para exportar
        export_normals=True,
        export_materials="EXPORT",
        # `MATERIAL` exporta o atributo de cor ativo como COLOR_0 — que é exatamente o
        # que a malha carrega. `export_all_vertex_colors` exportaria camadas extras que
        # não existem aqui e só engordariam o arquivo.
        export_vertex_color="MATERIAL",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_extras=False,
    )


# ---------------------------------------------------------------------------
# Manifesto
# ---------------------------------------------------------------------------


def write_manifest(entries: list[dict]) -> None:
    payload = {
        "_generated_by": "tools/gen_assets.py",
        "_source": "tools/params.py",
        "_warning": "ARQUIVO GERADO — NÃO EDITE À MÃO. Regenerar: make assets",
        "kit_seed": P.KIT_SEED,
        "grid_size": P.GRID_SIZE,
        "material": MATERIAL_NAME,
        "tri_budget": P.KIT_TRI_BUDGET,
        "palette": {key: P.PALETTE[key] for key in P.PALETTE_KEYS},
        "part_count": len(entries),
        "total_tris": sum(entry["tris"] for entry in entries),
        "parts": sorted(entries, key=lambda entry: (entry["category"], entry["name"])),
    }
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Execução dentro do Blender
# ---------------------------------------------------------------------------


def run_in_blender(selected: list[str]) -> int:
    from tools import meshlib as M

    catalog = build_catalog()
    if selected:
        unknown = sorted(set(selected) - {spec["name"] for spec in catalog})
        if unknown:
            print(f"ERRO: peça desconhecida: {', '.join(unknown)}", file=sys.stderr)
            return 1
        catalog = [spec for spec in catalog if spec["name"] in selected]

    KIT_DIR.mkdir(parents=True, exist_ok=True)
    entries: list[dict] = []
    failures: list[str] = []

    for spec in catalog:
        try:
            entry = build_part(spec)
        except AssetError as error:
            failures.append(str(error))
            continue
        entries.append(entry)
        headroom = entry["budget"] - entry["tris"]
        print(f"  {entry['name']:<16} {entry['tris']:>4} tris  (folga {headroom:>4})  {entry['category']}")

    if failures:
        print(f"\n  {len(failures)} peça(s) reprovada(s):", file=sys.stderr)
        for failure in failures:
            print(f"    - {failure}", file=sys.stderr)
        return 1

    if not selected:
        write_manifest(entries)
        print(f"\n  {len(entries)} peças, {sum(e['tris'] for e in entries)} triângulos no total")
        print(f"  manifesto: {MANIFEST.relative_to(ROOT)}")
    return 0


# ---------------------------------------------------------------------------
# Execução fora do Blender
# ---------------------------------------------------------------------------


class BlenderMissing(RuntimeError):
    """Nem o binário do Blender nem o módulo `bpy` estão disponíveis."""


def find_blender() -> str | None:
    """Binário do Blender: $BLENDER primeiro, depois nomes comuns no PATH."""
    from_env = os.environ.get("BLENDER", "").strip()
    if from_env:
        if shutil.which(from_env) or Path(from_env).is_file():
            return from_env
        raise BlenderMissing(f"$BLENDER aponta para algo que não existe: {from_env}")
    for name in ("blender", "blender4", "Blender"):
        found = shutil.which(name)
        if found:
            return found
    return None


def dispatch(script: Path, in_blender, selected: list[str]) -> int:
    """Roda `in_blender` dentro do Blender, seja qual for o caminho disponível.

    Três cenários, e o chamador não precisa saber em qual está:
    já estamos dentro do Blender (executa direto), existe um binário (reexecuta o script
    com `--background`), ou existe só o módulo `bpy` (que é o mesmo Blender, e aí já
    estamos "dentro"). Compartilhado por `gen_assets` e `preview_assets` para que os dois
    tenham exatamente o mesmo comportamento e a mesma mensagem de erro.
    """
    if _is_inside_blender():
        return in_blender(selected)
    try:
        binary = find_blender()
    except BlenderMissing as error:
        print(f"ERRO: {error}", file=sys.stderr)
        return 1
    if binary is not None:
        return run_via_subprocess(binary, selected, script)
    print(BLENDER_HELP, file=sys.stderr)
    return 1


BLENDER_HELP = (
    "ERRO: Blender não encontrado — esta etapa precisa dele.\n"
    "  Escolha um caminho:\n"
    "    - deixe `blender` no PATH;\n"
    "    - aponte a variável BLENDER para o executável (BLENDER=/opt/blender/blender make assets);\n"
    "    - ou instale o módulo equivalente com `pip install bpy` no Python que roda o make.\n"
    "  As três produzem exatamente os mesmos arquivos."
)


def run_via_subprocess(binary: str, selected: list[str], script: Path | None = None) -> int:
    script = Path(__file__).resolve() if script is None else script.resolve()
    command = [binary, "--background", "--python", str(script)]
    if selected:
        command += [ARG_SEPARATOR, *selected]
    print(f"  $ {' '.join(command)}")
    process = subprocess.run(command, capture_output=True, text=True)
    # O Blender fala muito; só interessa o que a fábrica imprimiu e o que deu errado.
    for line in process.stdout.splitlines():
        if line.startswith("  ") or line.startswith("ERRO"):
            print(line)
    if process.returncode != 0:
        print(process.stderr, file=sys.stderr)
    return process.returncode


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    selected = [arg for arg in argv if not arg.startswith("-")]
    return dispatch(Path(__file__), run_in_blender, selected)


def script_args() -> list[str]:
    """Argumentos da etapa, venha ela do Blender ou do Python.

    `blender --background --python x.py -- a b` põe os argumentos depois de `--`;
    `python -m tools.x a b` põe em `sys.argv[1:]`. Ler só o primeiro caso fazia o filtro
    de peças ser silenciosamente ignorado quando se roda pelo módulo `bpy`.
    """
    if ARG_SEPARATOR in sys.argv:
        return sys.argv[sys.argv.index(ARG_SEPARATOR) + 1:]
    return [arg for arg in sys.argv[1:] if not arg.startswith("-")]


if __name__ == "__main__":
    if _is_inside_blender():
        raise SystemExit(run_in_blender(script_args()))
    raise SystemExit(main())
