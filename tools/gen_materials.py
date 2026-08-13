"""Gera a biblioteca de materiais em `assets/generated/materials/`.

Cada material de `params.MATERIALS` vira um `StandardMaterial3D` de cor flat com
`vertex_color_use_as_albedo` ligado — a variação de tom vem do vertex color da malha,
não de textura nem de material novo. Materiais compartilhados são a base do orçamento
de draw calls: quanto menos materiais distintos, melhor o renderer agrupa.

`assets/generated/` é derivado e está no .gitignore. Rode `make materials` após clonar.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT_DIR = Path("assets/generated/materials")


def _material_resource(name: str, color_key: str, roughness: float, metallic: float) -> str:
    return f"""{GENERATED_HEADER('tools/gen_materials.py', 'tools/params.py', ';')}
[gd_resource type="StandardMaterial3D" format=3]

[resource]
resource_name = "{name}"
albedo_color = {P.color_literal(P.PALETTE[color_key])}
metallic = {P.num(metallic)}
roughness = {P.num(roughness)}
vertex_color_use_as_albedo = true
"""


def main() -> list[Path]:
    written: list[Path] = []
    for name, (color_key, roughness, metallic) in P.MATERIALS.items():
        if color_key not in P.PALETTE:
            raise KeyError(f"Material {name!r} referencia cor inexistente: {color_key!r}")
        target = OUTPUT_DIR / f"{name}.tres"
        written += write_if_changed(target, _material_resource(name, color_key, roughness, metallic))

    unique_materials = len(P.MATERIALS)
    ceiling = P.BUDGET["unique_materials"]
    if unique_materials > ceiling:
        raise SystemExit(
            f"Biblioteca de materiais estourou o orçamento: "
            f"{unique_materials} materiais para um teto de {ceiling}."
        )
    print(f"  materiais: {unique_materials}/{ceiling} do orçamento de materiais únicos")
    return written


if __name__ == "__main__":
    main()
