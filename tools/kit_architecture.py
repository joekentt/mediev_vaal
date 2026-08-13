"""Peças de arquitetura do kit modular.

Todas assentam no grid de 2 m: a largura de um painel é `GRID_SIZE`, a altura útil é
`WALL_HEIGHT`, e a origem sai no canto inferior mínimo (o driver cuida disso). Duas peças
vizinhas encaixam sem cálculo de offset — é isso que torna a fase 6 montagem, não
modelagem.

**Convenção de assinatura.** Toda função recebe `seed: int` como primeiro parâmetro,
mesmo quando não usa (peça de arquitetura é determinística por construção; a semente
existe para variação futura sem quebrar chamador). Os demais parâmetros são as
proporções da peça, com padrão vindo de `params.py` quando a medida é compartilhada, ou
expresso como fração do grid quando é interno à peça.

Toda função devolve um `BMesh` já pintado, sem UV, sem origem ajustada — o driver em
`gen_assets.py` normaliza, tritura, confere normais e exporta.
"""

from __future__ import annotations

import math

import bmesh
from mathutils import Matrix, Vector

from tools import meshlib as M
from tools import params as P

# Proporções internas do kit, nomeadas. Não são "números mágicos escondidos": são as
# medidas que só esta família de peças usa, e que não fazem sentido em params.py.
_PLINTH_HEIGHT = 0.35          # rodapé de pedra na base da parede
_LINTEL_HEIGHT = 0.22          # verga sobre porta e janela
_CAPITAL_HEIGHT = 0.18         # ábaco no topo do pilar
_RAIL_THICKNESS = 0.09
_SIGN_BOARD = (0.9, 0.06, 0.5)
_TOWER_BAND_HEIGHT = 0.25
_BRIDGE_DECK_THICKNESS = 0.18
_MERLON_COUNT = 6


def wall(
    seed: int,
    width: float = P.GRID_SIZE,
    height: float = P.WALL_HEIGHT,
    thickness: float = P.WALL_THICKNESS,
) -> bmesh.types.BMesh:
    """Painel de parede cheio, com rodapé de pedra.

    seed      ignorado (peça determinística)
    width     largura, normalmente uma célula do grid
    height    pé-direito
    thickness espessura do painel
    """
    del seed
    bm = M.new_bmesh()
    M.add_box(bm, (0.0, 0.0, _PLINTH_HEIGHT), (width, thickness, height - _PLINTH_HEIGHT), "plaster")
    M.add_box(bm, (0.0, 0.0, 0.0), (width, thickness, _PLINTH_HEIGHT), "stone")
    return bm


def wall_window(
    seed: int,
    width: float = P.GRID_SIZE,
    height: float = P.WALL_HEIGHT,
    thickness: float = P.WALL_THICKNESS,
    window_width: float = P.WINDOW_WIDTH,
    window_height: float = P.WINDOW_HEIGHT,
    sill: float = P.WINDOW_SILL,
) -> bmesh.types.BMesh:
    """Parede com vão de janela, peitoril e verga.

    seed          ignorado
    window_width  largura do vão
    window_height altura do vão
    sill          altura do peitoril a partir do chão
    """
    del seed
    bm = M.new_bmesh()
    hole_x = (width - window_width) * 0.5
    M.add_frame(
        bm, (0.0, 0.0, 0.0), (width, thickness, height),
        (hole_x, sill), (window_width, window_height),
        "plaster", reveal_key="wood_dark",
    )
    M.add_box(bm, (0.0, 0.0, 0.0), (width, thickness, _PLINTH_HEIGHT), "stone")
    # Peitoril saliente e verga: leitura de profundidade sem sombra e sem textura.
    M.add_box(
        bm, (hole_x - _RAIL_THICKNESS, -_RAIL_THICKNESS, sill - _RAIL_THICKNESS),
        (window_width + _RAIL_THICKNESS * 2, thickness + _RAIL_THICKNESS * 2, _RAIL_THICKNESS),
        "stone",
    )
    M.add_box(
        bm, (hole_x, -_RAIL_THICKNESS, sill + window_height),
        (window_width, thickness + _RAIL_THICKNESS, _LINTEL_HEIGHT),
        "wood",
    )
    return bm


def wall_door(
    seed: int,
    width: float = P.GRID_SIZE,
    height: float = P.WALL_HEIGHT,
    thickness: float = P.WALL_THICKNESS,
    door_width: float = P.DOOR_WIDTH,
    door_height: float = P.DOOR_HEIGHT,
) -> bmesh.types.BMesh:
    """Parede com vão de porta até o chão, com verga de madeira.

    seed        ignorado
    door_width  largura do vão
    door_height altura do vão
    """
    del seed
    bm = M.new_bmesh()
    hole_x = (width - door_width) * 0.5
    M.add_frame(
        bm, (0.0, 0.0, 0.0), (width, thickness, height),
        (hole_x, 0.0), (door_width, door_height),
        "plaster", reveal_key="wood_dark",
    )
    M.add_box(bm, (0.0, 0.0, 0.0), (hole_x, thickness, _PLINTH_HEIGHT), "stone")
    M.add_box(bm, (hole_x + door_width, 0.0, 0.0), (width - hole_x - door_width, thickness, _PLINTH_HEIGHT), "stone")
    M.add_box(
        bm, (hole_x - _RAIL_THICKNESS, -_RAIL_THICKNESS, door_height),
        (door_width + _RAIL_THICKNESS * 2, thickness + _RAIL_THICKNESS * 2, _LINTEL_HEIGHT),
        "wood",
    )
    return bm


def roof_gable(
    seed: int,
    width: float = P.GRID_SIZE,
    depth: float = P.GRID_SIZE * 2,
    pitch_deg: float = P.ROOF_PITCH_DEG,
    overhang: float = P.ROOF_OVERHANG,
) -> bmesh.types.BMesh:
    """Telhado de duas águas, cumeeira no eixo X.

    seed      ignorado
    width     vão coberto (eixo X)
    depth     comprimento da cumeeira (eixo Y)
    pitch_deg inclinação das águas
    overhang  beiral além da parede, nos quatro lados
    """
    del seed
    bm = M.new_bmesh()
    span = depth + overhang * 2.0
    rise = math.tan(math.radians(pitch_deg)) * (span * 0.5)
    M.add_wedge(bm, (-overhang, -overhang, 0.0), (width + overhang * 2.0, span, rise), "roof_tile")
    return bm


def roof_hip(
    seed: int,
    width: float = P.GRID_SIZE * 2,
    depth: float = P.GRID_SIZE * 2,
    pitch_deg: float = P.ROOF_PITCH_DEG,
    overhang: float = P.ROOF_OVERHANG,
) -> bmesh.types.BMesh:
    """Telhado de quatro águas com cumeeira curta no eixo X.

    seed      ignorado
    width     vão no eixo X
    depth     vão no eixo Y
    pitch_deg inclinação
    overhang  beiral
    """
    del seed
    bm = M.new_bmesh()
    x0, y0 = -overhang, -overhang
    x1, y1 = width + overhang, depth + overhang
    rise = math.tan(math.radians(pitch_deg)) * ((y1 - y0) * 0.5)
    ridge_inset = (x1 - x0) * 0.25
    mid_y = (y0 + y1) * 0.5

    base = [bm.verts.new(c) for c in [(x0, y0, 0.0), (x1, y0, 0.0), (x1, y1, 0.0), (x0, y1, 0.0)]]
    ridge = [
        bm.verts.new((x0 + ridge_inset, mid_y, rise)),
        bm.verts.new((x1 - ridge_inset, mid_y, rise)),
    ]
    faces = [
        bm.faces.new([base[0], base[3], base[2], base[1]]),   # base
        bm.faces.new([base[0], base[1], ridge[1], ridge[0]]),  # água -Y
        bm.faces.new([base[2], base[3], ridge[0], ridge[1]]),  # água +Y
        bm.faces.new([base[1], base[2], ridge[1]]),            # tacaniça +X
        bm.faces.new([base[3], base[0], ridge[0]]),            # tacaniça -X
    ]
    M.paint(bm, faces, "roof_tile")
    return bm


def beam(
    seed: int,
    length: float = P.GRID_SIZE,
    thickness: float = P.BEAM_THICKNESS,
) -> bmesh.types.BMesh:
    """Viga de madeira chanfrada, deitada no eixo X.

    seed      ignorado
    length    comprimento
    thickness seção quadrada
    """
    del seed
    bm = M.new_bmesh()
    M.add_box(bm, (0.0, 0.0, 0.0), (length, thickness, thickness), "wood")
    M.bevel_flat(bm)
    return bm


def pillar(
    seed: int,
    height: float = P.WALL_HEIGHT,
    radius: float = P.PILLAR_RADIUS,
    sides: int = P.PILLAR_SIDES,
) -> bmesh.types.BMesh:
    """Pilar octogonal com base e capitel de pedra.

    seed   ignorado
    height altura total
    radius raio do fuste
    sides  lados do prisma — 8 dá silhueta redonda a custo baixo
    """
    del seed
    bm = M.new_bmesh()
    base_height = _CAPITAL_HEIGHT
    shaft = height - base_height * 2.0
    M.add_box(bm, (-radius, -radius, 0.0), (radius * 2.0, radius * 2.0, base_height), "stone")
    M.add_prism(bm, (0.0, 0.0, base_height), radius, shaft, sides, "stone_light")
    M.add_box(
        bm, (-radius, -radius, base_height + shaft),
        (radius * 2.0, radius * 2.0, base_height), "stone",
    )
    return bm


def stairs(
    seed: int,
    width: float = P.GRID_SIZE,
    rise: float = P.WALL_HEIGHT * 0.5,
    run: float = P.GRID_SIZE,
    steps: int = P.STAIR_STEPS,
) -> bmesh.types.BMesh:
    """Escada reta de `steps` degraus.

    seed  ignorado
    width largura
    rise  altura total vencida
    run   profundidade total
    steps número de degraus
    """
    del seed
    bm = M.new_bmesh()
    step_rise = rise / steps
    step_run = run / steps
    for index in range(steps):
        # Cada degrau é um bloco maciço desde o chão: mais barato que uma escada oca e
        # dá colisão correta de graça.
        M.add_box(
            bm,
            (0.0, index * step_run, 0.0),
            (width, run - index * step_run, step_rise * (index + 1)),
            "stone" if index % 2 == 0 else "stone_light",
        )
    return bm


def floor_tile(
    seed: int,
    size: float = P.GRID_SIZE,
    thickness: float = P.FLOOR_THICKNESS,
) -> bmesh.types.BMesh:
    """Laje de piso de uma célula, com os quadrantes em tons alternados.

    seed      escolhe qual diagonal recebe o tom claro
    size      lado da laje
    thickness espessura
    """
    bm = M.new_bmesh()
    half = size * 0.5
    rng = M.value_noise(seed, 0.0, 0.0, 0.0)
    flip = rng > 0.0
    for column in range(2):
        for row in range(2):
            light = ((column + row) % 2 == 0) != flip
            M.add_box(
                bm,
                (column * half, row * half, 0.0),
                (half, half, thickness),
                "stone_light" if light else "stone",
            )
    return bm


def wall_gate(
    seed: int,
    width: float = P.GRID_SIZE * 3,
    height: float = P.GATE_HEIGHT + 1.0,
    thickness: float = P.WALL_THICKNESS * 2.0,
    gate_width: float = P.GATE_WIDTH,
    gate_height: float = P.GATE_HEIGHT,
    segments: int = P.GATE_ARCH_SEGMENTS,
) -> bmesh.types.BMesh:
    """Muralha com portão em arco.

    O arco é escalonado em `segments` colunas em vez de curvo: a silhueta em degraus é
    deliberada — lê como cantaria a 5 m e custa uma fração dos triângulos de um arco
    tesselado.

    seed        ignorado
    gate_width  vão do portão
    gate_height altura até o topo do arco
    segments    colunas que aproximam a curva (ímpar dá coroamento simétrico)
    """
    del seed
    bm = M.new_bmesh()
    side = (width - gate_width) * 0.5
    M.add_box(bm, (0.0, 0.0, 0.0), (side, thickness, height), "stone")
    M.add_box(bm, (width - side, 0.0, 0.0), (side, thickness, height), "stone")

    springline = gate_height - gate_width * 0.5
    column_width = gate_width / segments
    for index in range(segments):
        # Meio-círculo amostrado no centro de cada coluna.
        center = (index + 0.5) / segments
        arc = math.sin(math.pi * center)
        top = springline + (gate_width * 0.5) * arc
        M.add_box(
            bm,
            (side + index * column_width, 0.0, top),
            (column_width, thickness, height - top),
            "stone_light" if index % 2 == 0 else "stone",
        )
    return bm


def tower(
    seed: int,
    height: float = P.TOWER_HEIGHT,
    radius: float = P.TOWER_RADIUS,
    sides: int = P.TOWER_SIDES,
    merlons: int = _MERLON_COUNT,
) -> bmesh.types.BMesh:
    """Torre poligonal com cinta de pedra e coroamento ameado.

    seed    ignorado
    height  altura do fuste
    radius  raio
    sides   lados do prisma
    merlons ameias no topo
    """
    del seed
    bm = M.new_bmesh()
    M.add_prism(bm, (0.0, 0.0, 0.0), radius, height, sides, "stone")
    M.add_prism(
        bm, (0.0, 0.0, height - _TOWER_BAND_HEIGHT),
        radius * 1.12, _TOWER_BAND_HEIGHT, sides, "stone_light",
    )
    merlon_size = radius * 0.3
    for index in range(merlons):
        angle = math.tau * index / merlons
        M.add_box(
            bm,
            (
                math.cos(angle) * radius - merlon_size * 0.5,
                math.sin(angle) * radius - merlon_size * 0.5,
                height,
            ),
            (merlon_size, merlon_size, merlon_size * 2.0),
            "stone",
        )
    return bm


def bridge(
    seed: int,
    length: float = P.BRIDGE_LENGTH,
    width: float = P.GRID_SIZE,
    rail_height: float = 0.8,
) -> bmesh.types.BMesh:
    """Ponte de tabuleiro reto com guarda-corpo e dois pegões.

    seed        ignorado
    length      vão no eixo Y
    width       largura do tabuleiro
    rail_height altura do guarda-corpo
    """
    del seed
    bm = M.new_bmesh()
    M.add_box(bm, (0.0, 0.0, 0.0), (width, length, _BRIDGE_DECK_THICKNESS), "wood")
    for side_x in (0.0, width - _RAIL_THICKNESS):
        M.add_box(
            bm, (side_x, 0.0, _BRIDGE_DECK_THICKNESS),
            (_RAIL_THICKNESS, length, rail_height), "wood_dark",
        )
    pier_width = width * 0.8
    for pier_y in (length * 0.15, length * 0.75):
        M.add_box(
            bm, ((width - pier_width) * 0.5, pier_y, -P.WALL_HEIGHT),
            (pier_width, length * 0.1, P.WALL_HEIGHT), "stone",
        )
    return bm


def fence(
    seed: int,
    length: float = P.GRID_SIZE,
    height: float = 1.1,
    rails: int = P.FENCE_RAILS,
) -> bmesh.types.BMesh:
    """Cerca de uma célula: dois montantes e `rails` travessas.

    seed   ignorado
    length comprimento (uma célula do grid)
    height altura do montante
    rails  número de travessas horizontais
    """
    del seed
    bm = M.new_bmesh()
    post = _RAIL_THICKNESS * 1.6
    for post_x in (0.0, length - post):
        M.add_box(bm, (post_x, 0.0, 0.0), (post, post, height), "wood_dark")
    for index in range(rails):
        rail_z = height * (index + 1) / (rails + 1)
        M.add_box(
            bm, (0.0, post * 0.25, rail_z),
            (length, _RAIL_THICKNESS * 0.6, _RAIL_THICKNESS), "wood",
        )
    return bm


def sign(
    seed: int,
    post_height: float = 2.0,
    board: tuple[float, float, float] = _SIGN_BOARD,
) -> bmesh.types.BMesh:
    """Placa de rua: poste, tabuleta e mão-francesa.

    seed        inclina levemente a tabuleta, para a rua não ficar com placas idênticas
    post_height altura do poste
    board       dimensões da tabuleta (x, y, z)
    """
    bm = M.new_bmesh()
    post = _RAIL_THICKNESS * 1.4
    M.add_box(bm, (0.0, 0.0, 0.0), (post, post, post_height), "wood_dark")

    board_bm = M.new_bmesh()
    M.add_box(board_bm, (0.0, 0.0, 0.0), board, "wood")
    M.add_box(board_bm, (0.0, 0.0, board[2]), (board[0], board[1], _RAIL_THICKNESS * 0.4), "iron")
    tilt = M.value_noise(seed, 1.0, 0.0, 0.0) * math.radians(6.0)
    M.transform(board_bm, Matrix.Rotation(tilt, 4, "Y"))
    M.merge_into(bm, board_bm, Vector((post, -board[1] * 0.5, post_height - board[2] * 1.4)))
    return bm
