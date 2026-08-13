"""Natureza: pedra, árvore e mato.

É aqui que a semente pesa. Uma cidade com duas árvores repetidas vinte vezes se denuncia
na hora; a mesma função chamada com vinte sementes diferentes, não. Toda peça deste
módulo usa `seed` de verdade, e `make assets` gera uma variante por peça — a fase 3
chamará estas mesmas funções com a semente do chunk para popular a floresta.

Orçamento: 300 triângulos, exceto árvore, que tem direito a 600 (`KIT_TRI_BUDGET`).
A copa é o que custa, e é o que se vê de longe.
"""

from __future__ import annotations

import math

import bmesh
from mathutils import Matrix

from tools import meshlib as M
from tools import params as P

_ROCK_RADIUS = 0.5
_BOULDER_RADIUS = 1.3
_TRUNK_RADIUS = 0.16
_TRUNK_HEIGHT = 2.6
_TRUNK_TAPER = 0.55
_CANOPY_RADIUS = 1.1
_CONIFER_HEIGHT = 4.2
_CONIFER_RADIUS = 1.2
_BUSH_RADIUS = 0.45
_GRASS_HEIGHT = 0.35
_GRASS_BLADE = 0.05
_LOG_LENGTH = 1.6
_LOG_RADIUS = 0.22
_STUMP_HEIGHT = 0.45
_ROOT_COUNT = 4


def rock(seed: int, radius: float = _ROCK_RADIUS,
         subdivisions: int = P.ROCK_SUBDIVISIONS) -> bmesh.types.BMesh:
    """Pedra solta de mão cheia, achatada e facetada.

    seed         define o formato inteiro — é o parâmetro que interessa
    radius       raio nominal
    subdivisions 0 dá 20 faces, 1 dá 80; acima disso perde a cara low poly
    """
    bm = M.new_bmesh()
    M.add_icosphere(bm, (0.0, 0.0, 0.0), radius, subdivisions, "stone")
    M.deform_by_noise(bm, seed, amount=radius * P.ROCK_NOISE, scale=2.2)
    # Achatar: pedra que assenta no chão, não bola de gude.
    M.transform(bm, Matrix.Diagonal((1.0, 1.0, 0.65)).to_4x4())
    return bm


def boulder(seed: int, radius: float = _BOULDER_RADIUS,
            subdivisions: int = P.ROCK_SUBDIVISIONS) -> bmesh.types.BMesh:
    """Matacão de marcar paisagem, com uma quina de musgo no topo.

    seed         define o formato
    radius       raio nominal
    subdivisions detalhe da icosfera
    """
    bm = M.new_bmesh()
    faces = M.add_icosphere(bm, (0.0, 0.0, 0.0), radius, subdivisions, "stone_dark")
    M.deform_by_noise(bm, seed, amount=radius * P.ROCK_NOISE * 1.4, scale=1.4)
    # As faces mais viradas para cima ganham musgo: pista de leitura, custo zero.
    bm.normal_update()
    M.paint(bm, [face for face in faces if face.normal.z > 0.55], "moss")
    M.transform(bm, Matrix.Diagonal((1.0, 0.85, 0.7)).to_4x4())
    return bm


def tree_broadleaf(seed: int, trunk_height: float = _TRUNK_HEIGHT,
                   trunk_radius: float = _TRUNK_RADIUS,
                   canopy_radius: float = _CANOPY_RADIUS,
                   blobs: int = P.TREE_CANOPY_BLOBS) -> bmesh.types.BMesh:
    """Árvore de folha larga: tronco cônico e copa de icosferas agrupadas.

    seed          inclina o tronco, distribui os lóbulos da copa e escolhe o verde
    trunk_height  altura do fuste
    trunk_radius  raio na base
    canopy_radius raio de cada lóbulo da copa
    blobs         lóbulos — 3 já lê como copa, 5 já estoura o orçamento
    """
    bm = M.new_bmesh()
    M.add_prism(
        bm, (0.0, 0.0, 0.0), trunk_radius, trunk_height, P.TREE_TRUNK_SIDES, "bark",
        top_radius=trunk_radius * _TRUNK_TAPER,
    )

    greens = ("foliage", "foliage_deep", "grass_dark")
    for index in range(blobs):
        angle = math.tau * index / blobs + M.value_noise(seed, float(index), 0.0, 0.0)
        spread = canopy_radius * 0.45
        offset_x = math.cos(angle) * spread
        offset_y = math.sin(angle) * spread
        offset_z = trunk_height + canopy_radius * (0.55 + 0.25 * M.value_noise(seed, 0.0, float(index), 0.0))
        blob_radius = canopy_radius * (0.75 + 0.25 * abs(M.value_noise(seed, 0.0, 0.0, float(index))))
        tone = greens[index % len(greens)]
        M.add_icosphere(bm, (offset_x, offset_y, offset_z), blob_radius, 0, tone)

    M.deform_by_noise(bm, seed, amount=canopy_radius * P.TREE_CANOPY_NOISE, scale=1.1)
    # Inclinação leve: nenhuma árvore cresce no prumo.
    lean = M.value_noise(seed, 3.0, 0.0, 0.0) * math.radians(7.0)
    M.transform(bm, Matrix.Rotation(lean, 4, "Y"))
    return bm


def tree_conifer(seed: int, height: float = _CONIFER_HEIGHT,
                 radius: float = _CONIFER_RADIUS,
                 tiers: int = P.CONIFER_TIERS,
                 sides: int = P.CONIFER_SIDES) -> bmesh.types.BMesh:
    """Conífera: tronco reto e `tiers` saias cônicas empilhadas.

    seed   gira cada saia e varia a altura, para a mata não virar padrão
    height altura total
    radius raio da saia mais baixa
    tiers  número de saias
    sides  lados de cada cone
    """
    bm = M.new_bmesh()
    trunk_height = height * 0.28
    M.add_prism(
        bm, (0.0, 0.0, 0.0), _TRUNK_RADIUS * 0.9, trunk_height, P.TREE_TRUNK_SIDES, "bark",
        top_radius=_TRUNK_RADIUS * 0.6,
    )

    tier_span = (height - trunk_height) / tiers
    for index in range(tiers):
        ratio = 1.0 - index / (tiers + 1.0)
        spin = M.value_noise(seed, float(index), 0.0, 0.0) * math.pi
        base_z = trunk_height + index * tier_span * 0.78
        M.add_cone(
            bm, (0.0, 0.0, base_z), radius * ratio, tier_span * 1.5, sides,
            "foliage_deep" if index % 2 == 0 else "foliage", rotation=spin,
        )
    return bm


def bush(seed: int, radius: float = _BUSH_RADIUS,
         blobs: int = P.BUSH_BLOBS) -> bmesh.types.BMesh:
    """Arbusto: icosferas baixas agrupadas, sem tronco visível.

    seed   distribui e deforma os lóbulos
    radius raio de cada lóbulo
    blobs  lóbulos
    """
    bm = M.new_bmesh()
    greens = ("foliage", "grass_dark", "moss")
    for index in range(blobs):
        angle = math.tau * index / blobs + M.value_noise(seed, float(index), 1.0, 0.0)
        spread = radius * 0.6
        M.add_icosphere(
            bm,
            (math.cos(angle) * spread, math.sin(angle) * spread, radius * 0.7),
            radius * (0.8 + 0.2 * abs(M.value_noise(seed, float(index), 0.0, 2.0))),
            0,
            greens[index % len(greens)],
        )
    M.deform_by_noise(bm, seed, amount=radius * 0.2, scale=2.0)
    M.transform(bm, Matrix.Diagonal((1.0, 1.0, 0.75)).to_4x4())
    return bm


def grass_tuft(seed: int, height: float = _GRASS_HEIGHT,
               blades: int = P.GRASS_BLADES) -> bmesh.types.BMesh:
    """Touceira de capim: lâminas cruzadas, para instanciar em MultiMesh aos milhares.

    A peça mais barata do kit de propósito — é a que vai aparecer 20 000 vezes.

    seed   gira e inclina cada lâmina
    height altura das lâminas
    blades número de lâminas
    """
    bm = M.new_bmesh()
    for index in range(blades):
        blade = M.new_bmesh()
        blade_height = height * (0.7 + 0.5 * abs(M.value_noise(seed, float(index), 0.0, 0.0)))
        M.add_prism(
            blade, (0.0, 0.0, 0.0), _GRASS_BLADE, blade_height, 3,
            "grass" if index % 2 == 0 else "grass_dark", top_radius=_GRASS_BLADE * 0.15,
        )
        lean = M.value_noise(seed, 0.0, float(index), 0.0) * math.radians(25.0)
        M.transform(blade, Matrix.Rotation(lean, 4, "X"))
        angle = math.tau * index / blades
        spread = height * 0.28
        M.merge_into(bm, blade, (math.cos(angle) * spread, math.sin(angle) * spread, 0.0))
    return bm


def log(seed: int, length: float = _LOG_LENGTH, radius: float = _LOG_RADIUS) -> bmesh.types.BMesh:
    """Tronco caído, deitado no eixo Y, com as pontas serradas claras.

    seed   deforma a casca e gira o tronco em torno do próprio eixo
    length comprimento
    radius raio
    """
    bm = M.new_bmesh()
    parts = M.add_prism(bm, (0.0, 0.0, 0.0), radius, length, P.TREE_TRUNK_SIDES, "bark",
                        top_radius=radius * 0.92)
    M.paint(bm, parts["bottom"] + parts["top"], "bark_light")
    M.deform_by_noise(bm, seed, amount=radius * 0.12, scale=3.0, axis_weights=(1.0, 0.2, 1.0))
    M.transform(bm, Matrix.Rotation(math.radians(90.0), 4, "X"))
    return bm


def stump(seed: int, height: float = _STUMP_HEIGHT, radius: float = _LOG_RADIUS * 1.6,
          roots: int = _ROOT_COUNT) -> bmesh.types.BMesh:
    """Cepo com raízes expostas.

    seed   deforma a casca e distribui as raízes
    height altura do cepo
    radius raio
    roots  raízes visíveis
    """
    bm = M.new_bmesh()
    parts = M.add_prism(bm, (0.0, 0.0, 0.0), radius, height, P.TREE_TRUNK_SIDES, "bark",
                        top_radius=radius * 0.85)
    M.paint(bm, parts["top"], "bark_light")
    for index in range(roots):
        angle = math.tau * index / roots + M.value_noise(seed, float(index), 0.0, 0.0) * 0.5
        root = M.new_bmesh()
        M.add_prism(root, (0.0, 0.0, 0.0), radius * 0.3, radius * 1.4, 4, "bark",
                    top_radius=radius * 0.12)
        M.transform(root, Matrix.Rotation(math.radians(70.0), 4, "X"))
        M.transform(root, Matrix.Rotation(angle, 4, "Z"))
        M.merge_into(bm, root, (math.cos(angle) * radius * 0.7, math.sin(angle) * radius * 0.7, height * 0.28))
    M.deform_by_noise(bm, seed, amount=radius * 0.1, scale=3.0)
    return bm
