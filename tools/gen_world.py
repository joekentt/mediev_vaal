"""Gera as cenas e o manifesto do mundo.

O manifesto é o caminho pelo qual a seed alcança o jogo. `make world SEED=123` escreve
`123` ali, e `WorldGenerator.current_seed()` lê — sem recompilar nada, sem tocar em
`params.py`, e sem que a seed precise virar constante do projeto. Uma seed em `params.py`
teria de passar por `make params`, e trocar de vale deixaria de ser uma linha de comando
para virar uma edição de fonte.

`scenes/world/main.tscn` é deliberadamente quase vazia: um `Node3D` e um script. Nada
de nó posicionado à mão. Céu, sol, chão e câmera nascem em `generators/world_generator.gd`
quando a cena roda — é o que garante que o mundo seja regenerável e diffável.

O manifesto (`assets/generated/world/world_manifest.json`) carrega a topologia derivada
dos parâmetros: seed, tamanho de chunk, lista de chunks. Os geradores de runtime leem
daqui em vez de recalcular, para que Python e GDScript nunca discordem sobre o mundo.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, ROOT, write_if_changed

MAIN_SCENE_OUTPUT = Path("scenes/world/main.tscn")
MANIFEST_OUTPUT = Path("assets/generated/world/world_manifest.json")


def _main_scene() -> str:
    return f"""{GENERATED_HEADER('tools/gen_world.py', 'tools/params.py', ';')}
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/core/main.gd" id="1_main"]

[node name="Main" type="Node3D"]
script = ExtResource("1_main")
"""


def _chunk_coords() -> list[list[int]]:
    """Chunks dentro do raio do mundo, em disco (não em quadrado)."""
    radius = P.WORLD_RADIUS_CHUNKS
    coords = []
    for z in range(-radius, radius + 1):
        for x in range(-radius, radius + 1):
            if x * x + z * z <= radius * radius:
                coords.append([x, z])
    return coords


def _manifest(seed: int | None = None) -> str:
    chunks = _chunk_coords()
    data = {
        "_generated_by": "tools/gen_world.py",
        "_source": "tools/params.py",
        "_warning": "ARQUIVO GERADO — NÃO EDITE À MÃO. Regenerar: make world",
        "seed": P.WORLD_SEED if seed is None else seed,
        "grid_size": P.GRID_SIZE,
        "chunk_cells": P.CHUNK_CELLS,
        "chunk_size": P.CHUNK_SIZE,
        "world_radius_chunks": P.WORLD_RADIUS_CHUNKS,
        "chunk_count": len(chunks),
        "world_diameter_m": P.CHUNK_SIZE * (2 * P.WORLD_RADIUS_CHUNKS + 1),
        "chunks": chunks,
        "stage": {
            "ground_size": P.STAGE_GROUND_SIZE,
            "ground_cells": P.STAGE_GROUND_CELLS,
            "ground_tris": P.STAGE_GROUND_CELLS * P.STAGE_GROUND_CELLS * 2,
        },
        "valley": {
            "size_m": P.TERRAIN_SIZE,
            "cell_m": P.TERRAIN_CELL,
            "chunk_cells": P.TERRAIN_CHUNK_CELLS,
            "chunks": _terrain_chunks(),
            "chunk_tris": P.TERRAIN_CHUNK_CELLS * P.TERRAIN_CHUNK_CELLS * 2,
            "height_m": P.TERRAIN_HEIGHT,
            "scatter_tile_m": P.SCATTER_TILE,
            "scatter_types": [spec["part"] for spec in P.SCATTER_TYPES],
            "road_max_slope": P.ROAD_MAX_SLOPE,
        },
    }
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def _terrain_chunks() -> int:
    """Pedaços de malha por lado do vale, ao quadrado."""
    per_side = math.ceil((P.TERRAIN_SIZE / P.TERRAIN_CELL) / P.TERRAIN_CHUNK_CELLS)
    return per_side * per_side


def current_seed() -> int:
    """Seed gravada no manifesto, ou a de fábrica quando ele ainda não existe.

    `make verify` usa isto: com uma seed customizada na árvore, comparar o manifesto
    contra o que `P.WORLD_SEED` produziria acusaria deriva onde só houve `make world
    SEED=123` — e a checagem de deriva perderia a credibilidade justamente por ser
    barulhenta.
    """
    path = ROOT / MANIFEST_OUTPUT
    if not path.exists():
        return P.WORLD_SEED
    try:
        return int(json.loads(path.read_text(encoding="utf-8"))["seed"])
    except (ValueError, KeyError, TypeError):
        return P.WORLD_SEED


def main(argv: list[str] | None = None) -> list[Path]:
    argv = sys.argv[1:] if argv is None else argv
    seed = int(argv[0]) if argv and argv[0].strip() else None

    written = write_if_changed(MAIN_SCENE_OUTPUT, _main_scene())
    written += write_if_changed(MANIFEST_OUTPUT, _manifest(seed))

    stage_tris = P.STAGE_GROUND_CELLS * P.STAGE_GROUND_CELLS * 2
    ceiling = P.TRI_BUDGET["stage_ground"]
    if stage_tris > ceiling:
        raise SystemExit(
            f"Chão do estágio estourou o orçamento: {stage_tris} tris para um teto de {ceiling}."
        )

    chunk_tris = P.TERRAIN_CHUNK_CELLS * P.TERRAIN_CHUNK_CELLS * 2
    chunk_ceiling = P.TRI_BUDGET["terrain_chunk"]
    if chunk_tris > chunk_ceiling:
        raise SystemExit(
            f"Pedaço de terreno com {chunk_tris} tris estoura o teto de {chunk_ceiling}. "
            f"Baixe TERRAIN_CHUNK_CELLS ou renegocie o teto."
        )

    used = P.WORLD_SEED if seed is None else seed
    print(
        f"  vale: {P.num(P.TERRAIN_SIZE)} m, {_terrain_chunks()} pedaços de "
        f"{chunk_tris}/{chunk_ceiling} tris (seed {used})"
    )
    print(f"  estágio plano: chão de {stage_tris}/{ceiling} tris")
    return written


if __name__ == "__main__":
    main()
