"""Gera as cenas e o manifesto do mundo.

`scenes/world/main.tscn` é deliberadamente quase vazia: um `Node3D` e um script. Nada
de nó posicionado à mão. Céu, sol, chão e câmera nascem em `generators/world_generator.gd`
quando a cena roda — é o que garante que o mundo seja regenerável e diffável.

O manifesto (`assets/generated/world/world_manifest.json`) carrega a topologia derivada
dos parâmetros: seed, tamanho de chunk, lista de chunks. Os geradores de runtime leem
daqui em vez de recalcular, para que Python e GDScript nunca discordem sobre o mundo.
"""

from __future__ import annotations

import json
from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

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


def _manifest() -> str:
    chunks = _chunk_coords()
    data = {
        "_generated_by": "tools/gen_world.py",
        "_source": "tools/params.py",
        "_warning": "ARQUIVO GERADO — NÃO EDITE À MÃO. Regenerar: make world",
        "seed": P.WORLD_SEED,
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
    }
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def main() -> list[Path]:
    written = write_if_changed(MAIN_SCENE_OUTPUT, _main_scene())
    written += write_if_changed(MANIFEST_OUTPUT, _manifest())

    chunks = _chunk_coords()
    stage_tris = P.STAGE_GROUND_CELLS * P.STAGE_GROUND_CELLS * 2
    ceiling = P.TRI_BUDGET["stage_ground"]
    if stage_tris > ceiling:
        raise SystemExit(
            f"Chão do estágio estourou o orçamento: {stage_tris} tris para um teto de {ceiling}."
        )
    print(f"  mundo: {len(chunks)} chunks de {P.num(P.CHUNK_SIZE)} m (seed {P.WORLD_SEED})")
    print(f"  estágio: chão de {stage_tris}/{ceiling} tris")
    return written


if __name__ == "__main__":
    main()
