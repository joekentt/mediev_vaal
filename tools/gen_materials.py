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


def _emissive_resource(name: str, glow_key: str, energy: float, albedo_key: str) -> str:
    """Material que emite luz própria.

    Nasce **apagado** (`emission_energy_multiplier = 0`), e não aceso: quem acende é
    `DayNightCycle`, que multiplica a energia pela escuridão da hora. Um material que
    nascesse aceso deixaria toda janela da cidade brilhando ao meio-dia até o primeiro
    quadro do ciclo rodar — e nas provas sem ciclo, para sempre.

    `emission_operator = 1` é ADD: o brilho soma ao albedo em vez de o substituir, que é o
    que faz a janela acesa continuar tendo a cor da madeira em volta do vão.
    """
    return f"""{GENERATED_HEADER('tools/gen_materials.py', 'tools/params.py', ';')}
[gd_resource type="StandardMaterial3D" format=3]

[resource]
resource_name = "{name}"
albedo_color = {P.color_literal(P.PALETTE[albedo_key])}
metallic = 0.0
roughness = 1.0
vertex_color_use_as_albedo = true
emission_enabled = true
emission = {P.color_literal(P.PALETTE[glow_key])}
emission_energy_multiplier = 0.0
emission_operator = 1
"""


def main() -> list[Path]:
    written: list[Path] = []
    for name, (color_key, roughness, metallic) in P.MATERIALS.items():
        if color_key not in P.PALETTE:
            raise KeyError(f"Material {name!r} referencia cor inexistente: {color_key!r}")
        target = OUTPUT_DIR / f"{name}.tres"
        written += write_if_changed(target, _material_resource(name, color_key, roughness, metallic))

    for name, (glow_key, energy, albedo_key) in P.EMISSIVE_MATERIALS.items():
        for key in (glow_key, albedo_key):
            if key not in P.PALETTE:
                raise KeyError(f"Material {name!r} referencia cor inexistente: {key!r}")
        target = OUTPUT_DIR / f"{name}.tres"
        written += write_if_changed(target, _emissive_resource(name, glow_key, energy, albedo_key))

    unique_materials = len(P.MATERIALS) + len(P.EMISSIVE_MATERIALS)
    ceiling = P.BUDGET["unique_materials"]
    if unique_materials > ceiling:
        raise SystemExit(
            f"Biblioteca de materiais estourou o orçamento: "
            f"{unique_materials} materiais para um teto de {ceiling}."
        )
    print(
        f"  materiais: {unique_materials}/{ceiling} do orçamento de materiais únicos "
        f"({len(P.EMISSIVE_MATERIALS)} emissivos)"
    )
    return written


if __name__ == "__main__":
    main()
