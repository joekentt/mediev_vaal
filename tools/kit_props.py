"""Props: o mobiliário urbano que faz a cidade parecer habitada.

Mesma convenção de `kit_architecture`: `seed` primeiro, proporções depois, devolve
`BMesh` pintado. Props não precisam medir múltiplo do grid — um barril de 2 m seria um
barril errado. O que eles precisam é assentar no chão com a origem no canto inferior,
e disso o driver cuida.

Aqui a semente costuma ser usada de verdade: é o que faz dois barris lado a lado não
parecerem clonados.
"""

from __future__ import annotations

import math

import bmesh
from mathutils import Matrix

from tools import meshlib as M
from tools import params as P

_BARREL_SIDES = 8
_BARREL_HEIGHT = 0.85
_BARREL_RADIUS = 0.32
_BARREL_BULGE = 1.15           # quanto o bojo passa do raio das tampas
_CRATE_SIZE = 0.6
_WELL_SIDES = 8
_WELL_RADIUS = 0.7
_WELL_WALL = 0.75
_STALL_WIDTH = 2.0
_STALL_DEPTH = 1.2
_STALL_HEIGHT = 2.1
_LANTERN_HEIGHT = 2.6
_CART_LENGTH = 1.9
_CART_WIDTH = 1.0
_WHEEL_SIDES = 8
_ANVIL_HEIGHT = 0.75
_BENCH_LENGTH = 1.6
_POT_SIDES = 7
_SACK_SIDES = 6
_ROPE_COILS = 3
_BANNER_SIZE = (0.7, 0.02, 1.6)
_POST = 0.09


def barrel(seed: int, height: float = _BARREL_HEIGHT, radius: float = _BARREL_RADIUS,
           sides: int = _BARREL_SIDES) -> bmesh.types.BMesh:
    """Barril de aduelas com dois arcos de ferro.

    seed   gira o barril em torno de Z, para a fileira de barris não ficar espelhada
    height altura
    radius raio das tampas (o bojo é maior)
    sides  aduelas
    """
    bm = M.new_bmesh()
    bulge = radius * _BARREL_BULGE
    # Três anéis: tampa, bojo, tampa. Dois troncos de cone empilhados custam menos que
    # um perfil revolucionado e dão a mesma silhueta a esta escala.
    M.add_prism(bm, (0.0, 0.0, 0.0), radius, height * 0.5, sides, "wood", top_radius=bulge)
    M.add_prism(bm, (0.0, 0.0, height * 0.5), bulge, height * 0.5, sides, "wood", top_radius=radius)
    for band_z in (height * 0.22, height * 0.72):
        M.add_prism(bm, (0.0, 0.0, band_z), bulge * 1.03, height * 0.07, sides, "iron_dark")
    M.transform(bm, Matrix.Rotation(M.value_noise(seed, 0.0, 0.0, 0.0) * math.pi, 4, "Z"))
    return bm


def crate(seed: int, size: float = _CRATE_SIZE) -> bmesh.types.BMesh:
    """Caixote de ripas, com travessas nas faces laterais.

    seed escolhe o tom da madeira entre claro e escuro
    size aresta do cubo
    """
    bm = M.new_bmesh()
    light = M.value_noise(seed, 0.0, 0.0, 0.0) > 0.0
    M.add_box(bm, (0.0, 0.0, 0.0), (size, size, size), "wood" if light else "wood_dark")
    slat = size * 0.09
    for offset in (size * 0.2, size * 0.7):
        M.add_box(bm, (-slat * 0.3, -slat * 0.3, offset), (size + slat * 0.6, slat, slat), "wood_dark" if light else "wood")
        M.add_box(bm, (-slat * 0.3, size - slat * 0.7, offset), (size + slat * 0.6, slat, slat), "wood_dark" if light else "wood")
    return bm


def well(seed: int, radius: float = _WELL_RADIUS, wall_height: float = _WELL_WALL,
         sides: int = _WELL_SIDES) -> bmesh.types.BMesh:
    """Poço: mureta poligonal, dois montantes e a trave do balde.

    seed        ignorado
    radius      raio da mureta
    wall_height altura da mureta
    sides       lados
    """
    del seed
    bm = M.new_bmesh()
    M.add_prism(bm, (0.0, 0.0, 0.0), radius, wall_height, sides, "stone")
    M.add_prism(bm, (0.0, 0.0, wall_height), radius * 1.08, wall_height * 0.12, sides, "stone_light")
    post_height = wall_height * 2.2
    for side in (-1.0, 1.0):
        M.add_box(
            bm, (side * radius * 0.8 - _POST, -_POST, wall_height),
            (_POST * 2.0, _POST * 2.0, post_height), "wood_dark",
        )
    M.add_box(
        bm, (-radius * 0.9, -_POST, wall_height + post_height),
        (radius * 1.8, _POST * 2.0, _POST * 1.6), "wood",
    )
    return bm


def market_stall(seed: int, width: float = _STALL_WIDTH, depth: float = _STALL_DEPTH,
                 height: float = _STALL_HEIGHT) -> bmesh.types.BMesh:
    """Barraca de feira: bancada, quatro pés e toldo de duas águas.

    seed   escolhe a cor do toldo entre os tecidos da paleta
    width  largura da bancada
    depth  profundidade
    height altura do toldo
    """
    bm = M.new_bmesh()
    cloths = ("cloth_red", "cloth_blue", "cloth_green")
    pick = int((M.value_noise(seed, 0.0, 0.0, 0.0) * 0.5 + 0.5) * len(cloths)) % len(cloths)

    bench_z = height * 0.42
    M.add_box(bm, (0.0, 0.0, bench_z), (width, depth, _POST * 1.2), "wood")
    for corner_x in (0.0, width - _POST * 2.0):
        for corner_y in (0.0, depth - _POST * 2.0):
            M.add_box(bm, (corner_x, corner_y, 0.0), (_POST * 2.0, _POST * 2.0, height), "wood_dark")
    M.add_wedge(
        bm, (-_POST, -_POST, height), (width + _POST * 2.0, depth + _POST * 2.0, height * 0.22),
        cloths[pick],
    )
    return bm


def lantern_post(seed: int, height: float = _LANTERN_HEIGHT) -> bmesh.types.BMesh:
    """Poste de lampião: fuste de ferro e lanterna de vidro âmbar.

    seed   ignorado
    height altura do poste
    """
    del seed
    bm = M.new_bmesh()
    M.add_prism(bm, (0.0, 0.0, 0.0), _POST * 1.6, _POST * 1.4, 6, "stone")
    M.add_prism(bm, (0.0, 0.0, _POST * 1.4), _POST * 0.8, height, 6, "iron_dark")
    lamp = _POST * 2.4
    M.add_box(bm, (-lamp * 0.5, -lamp * 0.5, height), (lamp, lamp, lamp * 1.3), "gold")
    M.add_cone(bm, (0.0, 0.0, height + lamp * 1.3), lamp * 0.8, lamp * 0.7, 4, "iron_dark")
    return bm


def cart(seed: int, length: float = _CART_LENGTH, width: float = _CART_WIDTH) -> bmesh.types.BMesh:
    """Carroça de duas rodas com varais.

    seed   gira as rodas, para duas carroças não terem os raios alinhados
    length comprimento do caixote
    width  largura
    """
    bm = M.new_bmesh()
    wheel_radius = width * 0.42
    bed_z = wheel_radius * 1.1
    M.add_box(bm, (0.0, 0.0, bed_z), (width, length, _POST * 1.4), "wood")
    for side_x in (0.0, width - _POST):
        M.add_box(bm, (side_x, 0.0, bed_z), (_POST, length, width * 0.3), "wood_dark")
    spin = M.value_noise(seed, 0.0, 0.0, 0.0) * math.pi
    for wheel_x in (-_POST, width):
        wheel = M.new_bmesh()
        M.add_prism(wheel, (0.0, 0.0, 0.0), wheel_radius, _POST, _WHEEL_SIDES, "wood_dark", rotation=spin)
        M.transform(wheel, Matrix.Rotation(math.radians(90.0), 4, "Y"))
        M.merge_into(bm, wheel, (wheel_x, length * 0.5, wheel_radius))
    # Varais para a tração.
    for shaft_x in (width * 0.2, width * 0.8):
        M.add_box(bm, (shaft_x, length, bed_z), (_POST, length * 0.5, _POST), "wood")
    return bm


def anvil(seed: int, height: float = _ANVIL_HEIGHT) -> bmesh.types.BMesh:
    """Bigorna sobre cepo de madeira.

    seed   ignorado
    height altura total, cepo incluído
    """
    del seed
    bm = M.new_bmesh()
    stump_height = height * 0.55
    M.add_prism(bm, (0.0, 0.0, 0.0), height * 0.28, stump_height, 6, "bark")
    body = height * 0.2
    M.add_box(bm, (-body, -body * 0.6, stump_height), (body * 2.0, body * 1.2, body * 0.5), "iron_dark")
    M.add_box(bm, (-body * 0.6, -body * 0.45, stump_height + body * 0.5), (body * 1.2, body * 0.9, body * 0.7), "iron_dark")
    M.add_box(bm, (-body * 1.4, -body * 0.55, stump_height + body * 1.2), (body * 2.8, body * 1.1, body * 0.55), "iron")
    return bm


def bench(seed: int, length: float = _BENCH_LENGTH) -> bmesh.types.BMesh:
    """Banco de praça: assento, encosto e dois pés.

    seed   ignorado
    length comprimento
    """
    del seed
    bm = M.new_bmesh()
    seat_z = 0.45
    depth = 0.4
    M.add_box(bm, (0.0, 0.0, seat_z), (length, depth, _POST), "wood")
    M.add_box(bm, (0.0, depth - _POST, seat_z + _POST), (length, _POST, seat_z * 0.9), "wood")
    for leg_x in (_POST, length - _POST * 2.0):
        M.add_box(bm, (leg_x, 0.0, 0.0), (_POST, depth, seat_z), "wood_dark")
    return bm


def pot(seed: int, height: float = 0.45, sides: int = _POT_SIDES) -> bmesh.types.BMesh:
    """Pote de cerâmica bojudo com boca estreita.

    seed   varia a altura em ±10%, para um conjunto de potes não parecer estampado
    height altura nominal
    sides  lados
    """
    bm = M.new_bmesh()
    scaled = height * (1.0 + M.value_noise(seed, 0.0, 0.0, 0.0) * 0.1)
    radius = scaled * 0.55
    M.add_prism(bm, (0.0, 0.0, 0.0), radius * 0.6, scaled * 0.55, sides, "clay", top_radius=radius)
    M.add_prism(bm, (0.0, 0.0, scaled * 0.55), radius, scaled * 0.35, sides, "clay", top_radius=radius * 0.55)
    M.add_prism(bm, (0.0, 0.0, scaled * 0.9), radius * 0.62, scaled * 0.12, sides, "earth_dark")
    return bm


def sack(seed: int, height: float = 0.55, sides: int = _SACK_SIDES) -> bmesh.types.BMesh:
    """Saco de grão amarrado no pescoço, deformado por ruído.

    seed   define as bossas do pano — dois sacos nunca ficam iguais
    height altura
    sides  lados do corpo
    """
    bm = M.new_bmesh()
    radius = height * 0.42
    M.add_prism(bm, (0.0, 0.0, 0.0), radius * 0.85, height * 0.78, sides, "cloth_cream", top_radius=radius * 0.42)
    M.add_prism(bm, (0.0, 0.0, height * 0.78), radius * 0.3, height * 0.22, sides, "cloth_cream", top_radius=radius * 0.5)
    M.deform_by_noise(bm, seed, amount=radius * 0.16, scale=2.5, axis_weights=(1.0, 1.0, 0.2))
    return bm


def rope(seed: int, coils: int = _ROPE_COILS, radius: float = 0.28) -> bmesh.types.BMesh:
    """Rolo de corda: anéis empilhados de raio decrescente.

    seed   gira cada anel, quebrando o alinhamento das faces
    coils  número de voltas visíveis
    radius raio externo do rolo
    """
    bm = M.new_bmesh()
    thickness = radius * 0.22
    for index in range(coils):
        spin = M.value_noise(seed, float(index), 0.0, 0.0) * math.pi
        ring_radius = radius * (1.0 - index * 0.08)
        M.add_prism(
            bm, (0.0, 0.0, index * thickness), ring_radius, thickness, 6, "thatch",
            top_radius=ring_radius * 0.94, rotation=spin,
        )
    return bm


def banner(seed: int, size: tuple[float, float, float] = _BANNER_SIZE,
           pole_height: float = 2.4) -> bmesh.types.BMesh:
    """Estandarte pendurado num mastro, com a ponta inferior em bico.

    seed        escolhe a cor do pano
    size        dimensões do pano (x, y, z)
    pole_height altura do mastro
    """
    bm = M.new_bmesh()
    cloths = ("cloth_red", "cloth_blue", "cloth_green")
    pick = int((M.value_noise(seed, 0.0, 0.0, 0.0) * 0.5 + 0.5) * len(cloths)) % len(cloths)

    M.add_prism(bm, (0.0, 0.0, 0.0), _POST, pole_height, 6, "wood_dark")
    width, depth, drop = size
    top = pole_height - drop * 1.05
    M.add_box(bm, (_POST, -depth * 0.5, top), (width, depth, drop * 0.8), cloths[pick])
    # Bico: cunha invertida sob o pano.
    tip = M.new_bmesh()
    M.add_wedge(tip, (0.0, 0.0, 0.0), (width, depth, drop * 0.2), cloths[pick], along_y=True)
    M.transform(tip, Matrix.Rotation(math.pi, 4, "X"))
    M.merge_into(bm, tip, (_POST, depth * 0.5, top))
    M.add_prism(bm, (0.0, 0.0, pole_height), _POST * 1.5, _POST * 2.0, 6, "gold", top_radius=0.0)
    return bm
