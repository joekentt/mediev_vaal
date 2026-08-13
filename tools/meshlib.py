"""Helpers de baixo nível da fábrica de assets. Só roda dentro do Blender.

Este módulo é a camada que as funções paramétricas de `kit_*.py` usam para construir
geometria. Ele não conhece nenhuma peça: sabe fazer caixa, prisma, cone, extrusão,
chanfro, ruído e cor, e nada mais.

Três invariantes que tudo aqui respeita:

1. **Determinismo.** Nenhuma chamada a `random` global, nenhum `mathutils.noise` (que
   muda entre versões do Blender), nenhuma dependência de ordem de iteração do BMesh.
   Toda aleatoriedade passa por `value_noise` ou por `random.Random(seed)` alimentado em
   ordem *ordenada por posição*, não em ordem de criação.
2. **Shading flat, sem UV.** A cor sai do vertex color; a normal é por face. Nenhuma
   camada de UV é criada em lugar nenhum — o projeto não tem uma única textura.
3. **Cor pela paleta.** Face nenhuma recebe cor solta: recebe uma *chave* de
   `params.PALETTE`, guardada numa camada inteira do BMesh e resolvida na hora de
   exportar. Trocar um hex em `params.py` repinta o kit inteiro.
"""

from __future__ import annotations

import math
import random
from typing import Iterable, Sequence

# `bpy` primeiro, e não por estilo: no wheel do PyPI é a importação de `bpy` que carrega
# o runtime do Blender e registra `bmesh` e `mathutils`. Inverter a ordem dá
# ModuleNotFoundError.
import bpy  # isort: skip
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from tools import params as P

# Nome da camada inteira que carrega o índice de cor de cada face.
PALETTE_LAYER = "palette"

# Nome da camada inteira que carrega a *seção de corpo* de cada face — a que parte do
# humanoide ela pertence. Fica aqui, e não em `gen_characters`, porque quem precisa
# carregá-la intacta por triangulação, canonicalização e união é o BMesh; o kit
# simplesmente deixa tudo em 0 e nunca lê de volta.
SECTION_LAYER = "section"

# Nome do atributo de cor da malha. O exportador de glTF e o nó do material precisam
# concordar com este nome exato, senão o COLOR_0 sai vazio.
COLOR_ATTRIBUTE = "Color"

# Constantes estruturais do ruído de valor. Primos grandes para espalhar o hash.
_HASH_X = 73856093
_HASH_Y = 19349663
_HASH_Z = 83492791
_HASH_SEED = 2654435761
_HASH_MIX = 1274126177
_UINT32 = 0xFFFFFFFF

_TRIANGLE_VERTS = 3
_VOLUME_DIVISOR = 6.0

# Casas decimais usadas para ordenar a malha canônica. Um micrômetro é bem abaixo de
# qualquer coisa visível a escala de jogo, e mata o ruído de ponto flutuante na chave.
CANONICAL_PRECISION = 6


# ---------------------------------------------------------------------------
# BMesh: criação e cor
# ---------------------------------------------------------------------------


def new_bmesh() -> bmesh.types.BMesh:
    """BMesh vazio já com as camadas de paleta e de seção prontas."""
    bm = bmesh.new()
    bm.faces.layers.int.new(PALETTE_LAYER)
    bm.faces.layers.int.new(SECTION_LAYER)
    return bm


def paint(bm: bmesh.types.BMesh, faces: Iterable[bmesh.types.BMFace], key: str) -> None:
    """Pinta faces com uma cor da paleta. `key` inexistente falha na hora."""
    index = P.palette_index(key)
    layer = bm.faces.layers.int[PALETTE_LAYER]
    for face in faces:
        face[layer] = index


def face_palette_key(bm: bmesh.types.BMesh, face: bmesh.types.BMFace) -> str:
    layer = bm.faces.layers.int[PALETTE_LAYER]
    return P.PALETTE_KEYS[face[layer]]


def mark(bm: bmesh.types.BMesh, faces: Iterable[bmesh.types.BMFace], section: int) -> None:
    """Carimba faces com o índice da seção de corpo a que pertencem.

    É a metade "envelope" do skinning: dizer que estas faces são a coxa esquerda é
    conhecimento que o construtor tem de graça e que nenhuma heurística de distância
    recupera com segurança — sem isto, o peito fica perto demais do osso do braço e
    acaba pendurado nele.
    """
    layer = bm.faces.layers.int[SECTION_LAYER]
    for face in faces:
        face[layer] = section


def face_section(bm: bmesh.types.BMesh, face: bmesh.types.BMFace) -> int:
    layer = bm.faces.layers.int[SECTION_LAYER]
    return face[layer]


# ---------------------------------------------------------------------------
# Primitivas
# ---------------------------------------------------------------------------


def add_box(
    bm: bmesh.types.BMesh,
    corner: Sequence[float],
    size: Sequence[float],
    key: str,
) -> list[bmesh.types.BMFace]:
    """Caixa com o canto mínimo em `corner` e as dimensões de `size` (Blender é Z-up)."""
    x0, y0, z0 = corner
    sx, sy, sz = size
    x1, y1, z1 = x0 + sx, y0 + sy, z0 + sz

    coords = [
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    ]
    verts = [bm.verts.new(c) for c in coords]
    quads = [
        (0, 3, 2, 1),  # base  (-Z)
        (4, 5, 6, 7),  # topo  (+Z)
        (0, 1, 5, 4),  # -Y
        (2, 3, 7, 6),  # +Y
        (1, 2, 6, 5),  # +X
        (3, 0, 4, 7),  # -X
    ]
    faces = [bm.faces.new([verts[i] for i in quad]) for quad in quads]
    paint(bm, faces, key)
    return faces


def add_prism(
    bm: bmesh.types.BMesh,
    center: Sequence[float],
    radius: float,
    height: float,
    sides: int,
    key: str,
    top_radius: float | None = None,
    rotation: float = 0.0,
) -> dict[str, list[bmesh.types.BMFace]]:
    """Prisma de `sides` lados, base em `center` (canto inferior no eixo Z).

    `top_radius` menor que `radius` dá um tronco de cone — é assim que saem barris,
    potes e copas de conífera sem custar segmentos a mais.
    """
    cx, cy, cz = center
    top = radius if top_radius is None else top_radius
    step = math.tau / sides

    ring_bottom = []
    ring_top = []
    for index in range(sides):
        angle = rotation + step * index
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        ring_bottom.append(bm.verts.new((cx + cos_a * radius, cy + sin_a * radius, cz)))
        ring_top.append(bm.verts.new((cx + cos_a * top, cy + sin_a * top, cz + height)))

    side_faces = []
    for index in range(sides):
        nxt = (index + 1) % sides
        side_faces.append(bm.faces.new([
            ring_bottom[index], ring_bottom[nxt], ring_top[nxt], ring_top[index],
        ]))
    cap_bottom = bm.faces.new(list(reversed(ring_bottom)))
    cap_top = bm.faces.new(ring_top)

    faces = side_faces + [cap_bottom, cap_top]
    paint(bm, faces, key)
    return {"sides": side_faces, "bottom": [cap_bottom], "top": [cap_top]}


def add_cone(
    bm: bmesh.types.BMesh,
    center: Sequence[float],
    radius: float,
    height: float,
    sides: int,
    key: str,
    rotation: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Cone de base `radius` e ápice em `height`. Copa de conífera e telhado de torre."""
    cx, cy, cz = center
    step = math.tau / sides
    ring = []
    for index in range(sides):
        angle = rotation + step * index
        ring.append(bm.verts.new((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius, cz)))
    apex = bm.verts.new((cx, cy, cz + height))

    faces = []
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append(bm.faces.new([ring[index], ring[nxt], apex]))
    faces.append(bm.faces.new(list(reversed(ring))))
    paint(bm, faces, key)
    return faces


def add_icosphere(
    bm: bmesh.types.BMesh,
    center: Sequence[float],
    radius: float,
    subdivisions: int,
    key: str,
) -> list[bmesh.types.BMFace]:
    """Icosfera — a base de pedra, pedregulho e copa de folhagem.

    Cuidado com a contagem, que não é a intuitiva: `subdivisions` 0 **e** 1 dão os mesmos
    20 triângulos do icosaedro base; 2 dá 80; 3 dá 320 e já saiu do low poly. Medido, não
    suposto — a documentação do Blender não deixa isso óbvio.
    """
    before = set(bm.faces)
    matrix = Matrix.Translation(Vector(center))
    try:
        bmesh.ops.create_icosphere(
            bm, subdivisions=subdivisions, radius=radius, matrix=matrix, calc_uvs=False
        )
    except TypeError:
        # Blender < 3.0 chamava o parâmetro de `diameter`.
        bmesh.ops.create_icosphere(
            bm, subdivisions=subdivisions, diameter=radius, matrix=matrix, calc_uvs=False
        )
    faces = [face for face in bm.faces if face not in before]
    paint(bm, faces, key)
    return faces


def ring(
    center: Sequence[float],
    half_x: float,
    half_y: float,
    sides: int,
    rotation: float = 0.0,
) -> list[Vector]:
    """Anel elíptico de `sides` pontos, no plano XY, à altura de `center`.

    A ordem é sempre a mesma (ângulo crescente), o que deixa dois anéis costuráveis sem
    torção — `add_loft` conta com isso.
    """
    cx, cy, cz = center
    step = math.tau / sides
    points = []
    for index in range(sides):
        angle = rotation + step * index
        points.append(Vector((cx + math.cos(angle) * half_x, cy + math.sin(angle) * half_y, cz)))
    return points


def add_loft(
    bm: bmesh.types.BMesh,
    rings: Sequence[Sequence[Vector]],
    key: str,
    cap_start: bool = True,
    cap_end: bool = True,
) -> list[bmesh.types.BMFace]:
    """Costura anéis consecutivos numa casca contínua.

    É a base do corpo humanoide, e a razão de ele não ser um monte de caixas soltas:
    numa malha contínua o anel da articulação tem vértices que podem repartir peso entre
    dois ossos, e o cotovelo dobra em vez de quebrar. Caixas separadas nunca rasgam
    porque nunca dobram — e é justamente a dobra que queremos.

    Todos os anéis precisam ter a mesma contagem de pontos.
    """
    counts = {len(single) for single in rings}
    if len(counts) != 1:
        raise ValueError(f"anéis com contagens diferentes de pontos: {sorted(counts)}")

    layers = [[bm.verts.new(point) for point in single] for single in rings]
    sides = len(layers[0])
    faces: list[bmesh.types.BMFace] = []

    for index in range(len(layers) - 1):
        lower, upper = layers[index], layers[index + 1]
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append(bm.faces.new([lower[step], lower[nxt], upper[nxt], upper[step]]))

    if cap_start:
        faces.append(bm.faces.new(list(reversed(layers[0]))))
    if cap_end:
        faces.append(bm.faces.new(layers[-1]))

    paint(bm, faces, key)
    return faces


def add_wedge(
    bm: bmesh.types.BMesh,
    corner: Sequence[float],
    size: Sequence[float],
    key: str,
    along_y: bool = False,
) -> list[bmesh.types.BMFace]:
    """Cunha: caixa com o topo colapsado numa aresta. Base de telhado e de rampa."""
    x0, y0, z0 = corner
    sx, sy, sz = size
    x1, y1, z1 = x0 + sx, y0 + sy, z0 + sz

    if along_y:
        mid = (x0 + x1) * 0.5
        coords = [
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (mid, y0, z1), (mid, y1, z1),
        ]
        quads = [(0, 3, 2, 1)]
        tris = [(0, 1, 4), (2, 3, 5)]
        side_quads = [(1, 2, 5, 4), (3, 0, 4, 5)]
    else:
        mid = (y0 + y1) * 0.5
        coords = [
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, mid, z1), (x1, mid, z1),
        ]
        quads = [(0, 3, 2, 1)]
        tris = [(0, 4, 3), (1, 2, 5)]
        side_quads = [(0, 1, 5, 4), (2, 3, 4, 5)]

    verts = [bm.verts.new(c) for c in coords]
    faces = [bm.faces.new([verts[i] for i in quad]) for quad in quads]
    faces += [bm.faces.new([verts[i] for i in tri]) for tri in tris]
    faces += [bm.faces.new([verts[i] for i in quad]) for quad in side_quads]
    paint(bm, faces, key)
    return faces


def add_frame(
    bm: bmesh.types.BMesh,
    corner: Sequence[float],
    size: Sequence[float],
    hole_min: Sequence[float],
    hole_size: Sequence[float],
    key: str,
    reveal_key: str | None = None,
) -> list[bmesh.types.BMFace]:
    """Painel com um vão retangular passante — a base de `wall_window` e `wall_door`.

    O vão é construído por composição de quatro painéis sólidos em vez de booleana: o
    resultado é previsível, sem n-gon degenerado, e o orçamento de triângulos é conhecido
    de antemão. `hole_min`/`hole_size` são relativos ao canto do painel, no plano XZ.
    """
    x0, y0, z0 = corner
    sx, sy, sz = size
    hx, hz = hole_min
    hw, hh = hole_size

    faces: list[bmesh.types.BMFace] = []
    # Faixa de baixo, faixa de cima, e as duas laterais entre elas.
    if hz > 0.0:
        faces += add_box(bm, (x0, y0, z0), (sx, sy, hz), key)
    if hz + hh < sz:
        faces += add_box(bm, (x0, y0, z0 + hz + hh), (sx, sy, sz - hz - hh), key)
    if hx > 0.0:
        faces += add_box(bm, (x0, y0, z0 + hz), (hx, sy, hh), key)
    if hx + hw < sx:
        faces += add_box(bm, (x0 + hx + hw, y0, z0 + hz), (sx - hx - hw, sy, hh), key)

    if reveal_key is not None:
        # A moldura interna do vão ganha um tom próprio: é o que dá leitura de
        # profundidade sem sombra e sem textura.
        inner = [
            face for face in faces
            if _touches_hole(face, x0 + hx, x0 + hx + hw, z0 + hz, z0 + hz + hh)
        ]
        paint(bm, inner, reveal_key)
    return faces


def _touches_hole(face: bmesh.types.BMFace, x_min: float, x_max: float,
                  z_min: float, z_max: float, tolerance: float = 1e-5) -> bool:
    center = face.calc_center_median()
    normal = face.normal
    if abs(normal.z) > 0.5:
        return z_min - tolerance <= center.z <= z_max + tolerance and x_min <= center.x <= x_max
    if abs(normal.x) > 0.5:
        return x_min - tolerance <= center.x <= x_max + tolerance and z_min <= center.z <= z_max
    return False


# ---------------------------------------------------------------------------
# Operações
# ---------------------------------------------------------------------------


def extrude(
    bm: bmesh.types.BMesh,
    faces: Sequence[bmesh.types.BMFace],
    vector: Sequence[float],
) -> list[bmesh.types.BMFace]:
    """Extruda faces ao longo de `vector`. Devolve as faces novas do topo."""
    result = bmesh.ops.extrude_face_region(bm, geom=list(faces))
    new_geometry = result["geom"]
    new_verts = [item for item in new_geometry if isinstance(item, bmesh.types.BMVert)]
    new_faces = [item for item in new_geometry if isinstance(item, bmesh.types.BMFace)]
    bmesh.ops.translate(bm, verts=new_verts, vec=Vector(vector))
    bmesh.ops.delete(bm, geom=list(faces), context="FACES")
    return new_faces


def bevel_flat(
    bm: bmesh.types.BMesh,
    edges: Sequence[bmesh.types.BMEdge] | None = None,
    amount: float = P.BEVEL_AMOUNT,
    segments: int = P.BEVEL_SEGMENTS,
) -> None:
    """Chanfro de silhueta: quebra a aresta viva sem arredondar nada.

    Um segmento só, de propósito. O objetivo não é suavizar — é pegar um fiapo de luz na
    quina para a peça não sumir contra o fundo. Dois segmentos custariam o dobro de
    triângulos por uma diferença que ninguém vê a 5 m de distância.
    """
    target = list(bm.edges) if edges is None else list(edges)
    if not target or amount <= 0.0:
        return
    bmesh.ops.bevel(
        bm,
        geom=target,
        offset=amount,
        segments=segments,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
        material=-1,
    )


def deform_by_noise(
    bm: bmesh.types.BMesh,
    seed: int,
    amount: float,
    scale: float = 1.0,
    axis_weights: Sequence[float] = (1.0, 1.0, 1.0),
) -> None:
    """Empurra cada vértice ao longo da sua normal por um ruído de valor semeado.

    É o que tira a cara de "caixa" de pedra, tronco e mato. Determinístico por posição:
    dois vértices na mesma coordenada recebem o mesmo deslocamento, então superfícies que
    se encontram não se abrem. A ordem de iteração do BMesh não influi — o ruído é função
    da posição, não da ordem.
    """
    if amount <= 0.0:
        return
    bm.normal_update()
    for vert in bm.verts:
        position = vert.co
        offset = value_noise(seed, position.x * scale, position.y * scale, position.z * scale)
        direction = vert.normal if vert.normal.length > 0.0 else Vector(position).normalized()
        displacement = direction * (offset * amount)
        vert.co.x += displacement.x * axis_weights[0]
        vert.co.y += displacement.y * axis_weights[1]
        vert.co.z += displacement.z * axis_weights[2]


def jitter_vertices(
    bm: bmesh.types.BMesh,
    seed: int,
    amount: float,
    verts: Sequence[bmesh.types.BMVert] | None = None,
) -> None:
    """Deslocamento aleatório por vértice, em ordem ordenada por posição.

    Ordenar antes de sortear é o que separa "determinístico" de "quase sempre igual": a
    ordem de `bm.verts` pode mudar entre operações e levaria a outro sorteio.
    """
    if amount <= 0.0:
        return
    target = list(bm.verts) if verts is None else list(verts)
    target.sort(key=lambda v: (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5)))
    rng = random.Random(seed)
    for vert in target:
        vert.co.x += rng.uniform(-amount, amount)
        vert.co.y += rng.uniform(-amount, amount)
        vert.co.z += rng.uniform(-amount, amount)


def taper_z(bm: bmesh.types.BMesh, base_z: float, height: float, factor: float) -> None:
    """Afina a malha conforme sobe: 1.0 no chão, `factor` no topo. Tronco de árvore."""
    if height <= 0.0:
        return
    for vert in bm.verts:
        ratio = min(1.0, max(0.0, (vert.co.z - base_z) / height))
        scale = 1.0 + (factor - 1.0) * ratio
        vert.co.x *= scale
        vert.co.y *= scale


def transform(bm: bmesh.types.BMesh, matrix: Matrix,
              verts: Sequence[bmesh.types.BMVert] | None = None) -> None:
    bmesh.ops.transform(bm, matrix=matrix, verts=list(bm.verts) if verts is None else list(verts))


def canonicalize(bm: bmesh.types.BMesh, weld: bool = False) -> bmesh.types.BMesh:
    """Reconstrói a malha numa ordem que só depende da geometria. Devolve um BMesh novo.

    Sem isto o determinismo seria sorte. `bmesh.ops.bevel` — e vários outros ops — emitem
    a geometria numa ordem que acompanha a alocação interna do BMesh, não a forma. Duas
    execuções idênticas produzem a mesma malha com os elementos em ordens diferentes, e o
    `.glb` sai com bytes diferentes. Foi medido: `beam`, a única peça chanfrada, era a
    única que variava entre execuções.

    Dava para tirar o chanfro da `beam` e o sintoma sumiria. Seria consertar o termômetro:
    a próxima peça que usasse `bevel_flat`, `remove_doubles` ou qualquer op de topologia
    traria o problema de volta, e aí sem ninguém olhando. Aqui a ordem passa a ser função
    da forma — face ordenada pelo seu menor vértice, vértices na ordem do próprio anel
    rotacionado para começar no menor. O sentido de percurso é preservado, então as
    normais não mudam.

    Chame **depois** de `inspect_normals`: a canonicalização separa os vértices por face
    (que é o que o shading flat quer de qualquer forma), e aí a malha deixa de parecer
    fechada para o teste de topologia.

    `weld=True` mantém um vértice só por posição em vez de um por canto de face. O kit não
    quer isso — vértice separado é o que dá a normal dura de face. Um humanoide rigado
    quer: sem vértice compartilhado a malha não tem aresta entre triângulos, e aí o teste
    de rasgo na pose de teste mede apenas as arestas *dentro* de cada triângulo, que nunca
    rasgam. O shading continua flat porque a cor é por canto e `use_smooth` é False.
    """
    layer_source = bm.faces.layers.int[PALETTE_LAYER]
    section_source = bm.faces.layers.int[SECTION_LAYER]
    records: list[tuple[list, list, int, int]] = []
    for face in bm.faces:
        coords = [tuple(vert.co) for vert in face.verts]
        keys = [tuple(round(value, CANONICAL_PRECISION) for value in co) for co in coords]
        start = keys.index(min(keys))
        records.append((keys[start:] + keys[:start], coords[start:] + coords[:start],
                        face[layer_source], face[section_source]))
    records.sort(key=lambda record: (record[0], record[2], record[3]))

    canonical = new_bmesh()
    layer_target = canonical.faces.layers.int[PALETTE_LAYER]
    section_target = canonical.faces.layers.int[SECTION_LAYER]
    shared: dict[tuple[float, ...], bmesh.types.BMVert] = {}

    def vertex(key: tuple[float, ...], co: tuple[float, float, float]) -> bmesh.types.BMVert:
        if not weld:
            return canonical.verts.new(Vector(co))
        existing = shared.get(key)
        if existing is None:
            existing = canonical.verts.new(Vector(co))
            shared[key] = existing
        return existing

    for keys, coords, palette, section in records:
        if weld and len(set(keys)) != len(keys):
            continue  # face degenerada depois da soldagem: dois cantos na mesma posição
        verts = [vertex(key, co) for key, co in zip(keys, coords)]
        try:
            new_face = canonical.faces.new(verts)
        except ValueError:
            continue  # face repetida sobre os mesmos vértices
        new_face[layer_target] = palette
        new_face[section_target] = section
    canonical.normal_update()
    bm.free()
    return canonical


def merge_into(target: bmesh.types.BMesh, source: bmesh.types.BMesh,
               offset: Sequence[float] = (0.0, 0.0, 0.0)) -> None:
    """Copia `source` para dentro de `target`, deslocado, preservando a cor por face.

    O BMesh não tem união pronta que carregue camada customizada, e unir via objetos do
    bpy perderia a camada de paleta. É o caminho para compor uma peça a partir de
    sub-peças construídas na origem e depois posicionadas.

    `source` é liberado no fim: quem chama não deve mais tocá-lo.
    """
    layer_source = source.faces.layers.int[PALETTE_LAYER]
    layer_target = target.faces.layers.int[PALETTE_LAYER]
    section_source = source.faces.layers.int[SECTION_LAYER]
    section_target = target.faces.layers.int[SECTION_LAYER]
    source.verts.ensure_lookup_table()
    shift = Vector(offset)
    mapping = {vert.index: target.verts.new(vert.co + shift) for vert in source.verts}
    for face in source.faces:
        new_face = target.faces.new([mapping[vert.index] for vert in face.verts])
        new_face[layer_target] = face[layer_source]
        new_face[section_target] = face[section_source]
    source.free()


def triangulate(bm: bmesh.types.BMesh) -> None:
    """Triangula tudo. O orçamento é contado em triângulos, então contamos o que sai."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="FIXED", ngon_method="EAR_CLIP")


def recalc_normals(bm: bmesh.types.BMesh) -> None:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()


def remove_doubles(bm: bmesh.types.BMesh, distance: float = 1e-4) -> None:
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=distance)


# ---------------------------------------------------------------------------
# Ruído de valor determinístico
# ---------------------------------------------------------------------------


def _hash01(seed: int, ix: int, iy: int, iz: int) -> float:
    """Hash inteiro -> [0, 1). Estável entre máquinas e versões de Python."""
    value = (ix * _HASH_X) ^ (iy * _HASH_Y) ^ (iz * _HASH_Z) ^ (seed * _HASH_SEED)
    value &= _UINT32
    value ^= value >> 13
    value = (value * _HASH_MIX) & _UINT32
    value ^= value >> 16
    return value / float(_UINT32 + 1)


def _smoothstep(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


def value_noise(seed: int, x: float, y: float, z: float) -> float:
    """Ruído de valor trilinear em [-1, 1]. Sem numpy, sem `mathutils.noise`.

    `mathutils.noise` seria mais rápido, mas o seu resultado é um detalhe de
    implementação do Blender: mudar de versão mudaria toda a natureza do jogo sem uma
    linha de diff. Este aqui é nosso e não muda.
    """
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    ux, uy, uz = _smoothstep(fx), _smoothstep(fy), _smoothstep(fz)

    def corner(dx: int, dy: int, dz: int) -> float:
        return _hash01(seed, ix + dx, iy + dy, iz + dz)

    c00 = corner(0, 0, 0) + (corner(1, 0, 0) - corner(0, 0, 0)) * ux
    c10 = corner(0, 1, 0) + (corner(1, 1, 0) - corner(0, 1, 0)) * ux
    c01 = corner(0, 0, 1) + (corner(1, 0, 1) - corner(0, 0, 1)) * ux
    c11 = corner(0, 1, 1) + (corner(1, 1, 1) - corner(0, 1, 1)) * ux
    c0 = c00 + (c10 - c00) * uy
    c1 = c01 + (c11 - c01) * uy
    return (c0 + (c1 - c0) * uz) * 2.0 - 1.0


def part_seed(name: str, master: int = P.KIT_SEED) -> int:
    """Semente estável de uma peça, derivada do nome. Renomear muda a peça — de propósito.

    `hash()` de string em Python é randomizado por processo (PYTHONHASHSEED), então usar
    `hash(name)` daria uma peça diferente a cada execução. Aqui a soma é explícita.
    """
    accumulator = master & _UINT32
    for char in name:
        accumulator = ((accumulator * 31) + ord(char)) & _UINT32
    return accumulator


# ---------------------------------------------------------------------------
# Conferência de normais e orçamento
# ---------------------------------------------------------------------------


def signed_volume(bm: bmesh.types.BMesh) -> float:
    """Volume com sinal. Positivo = normais para fora. Só vale para malha fechada."""
    total = 0.0
    for face in bm.faces:
        verts = face.verts[:]
        origin = verts[0].co
        for index in range(1, len(verts) - 1):
            total += origin.dot(verts[index].co.cross(verts[index + 1].co))
    return total / _VOLUME_DIVISOR


def inspect_normals(bm: bmesh.types.BMesh) -> dict:
    """Diagnóstico de orientação. O driver reprova a peça a partir daqui.

    Duas perguntas diferentes:

    - *Consistente?* Toda aresta compartilhada é percorrida em sentidos opostos pelas
      duas faces (`edge.is_contiguous`). Uma face invertida no meio de uma malha aparece
      aqui, fechada ou não.
    - *Para fora?* Só faz sentido em malha fechada, e aí o volume com sinal responde.
      Malha aberta (uma bandeira, uma cerca) não tem "fora", e forçar o teste daria um
      falso reprovado.
    """
    open_edges = [edge for edge in bm.edges if len(edge.link_faces) != 2]
    inconsistent = [
        edge for edge in bm.edges
        if len(edge.link_faces) == 2 and not edge.is_contiguous
    ]
    is_closed = not open_edges
    volume = signed_volume(bm) if is_closed else 0.0
    return {
        "closed": is_closed,
        "consistent": not inconsistent,
        "open_edges": len(open_edges),
        "inconsistent_edges": len(inconsistent),
        "signed_volume": volume,
        "outward": (not is_closed) or volume > 0.0,
    }


def triangle_count(bm: bmesh.types.BMesh) -> int:
    """Triângulos que a malha vai custar depois de triangulada."""
    return sum(len(face.verts) - (_TRIANGLE_VERTS - 1) for face in bm.faces)


def bounds(bm: bmesh.types.BMesh) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    coords = [vert.co for vert in bm.verts]
    return (
        (min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)),
        (max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)),
    )


# ---------------------------------------------------------------------------
# Do BMesh ao objeto Blender
# ---------------------------------------------------------------------------


def snap_origin_to_grid(
    bm: bmesh.types.BMesh,
    grid: float = P.GRID_SIZE,
    grid_axes: Sequence[str] = (),
    tolerance: float = 1e-3,
) -> dict:
    """Leva o canto inferior da malha para a origem e confere o encaixe no grid.

    "Canto inferior" é o mínimo em X, Y e Z. É o ponto que a fase 6 vai usar para assentar
    a peça numa célula sem calcular offset nenhum: posicionar vira somar coordenada de
    célula, e nada mais.

    `grid_axes` lista os eixos horizontais que *precisam* medir um múltiplo do grid — e é
    uma decisão por peça, não uma regra global. Uma parede vence uma célula em X e tem
    25 cm de espessura em Y; um telhado ultrapassa a célula de propósito, por causa do
    beiral. Exigir alinhamento nos dois eixos de tudo reprovaria o kit inteiro sem que
    nada estivesse errado.

    **A pegadinha dos eixos.** O Blender é Z-up e o glTF é Y-up; o exportador converte
    `(x, y, z)` do Blender em `(x, z, -y)` no Godot. Zerar o mínimo nos três eixos aqui
    daria, lá, uma peça com `Z` de `-espessura` a `0` — a origem cairia no canto *máximo*
    em profundidade, e a fase 6 teria de compensar peça a peça. Então zeramos o mínimo em
    X e Z, mas o **máximo** em Y: depois da conversão, os três eixos saem de zero para
    positivo no Godot, que é onde a peça vai ser usada. Medido no Godot, não deduzido.

    Devolve a pegada, quantas células cada eixo ocupa, e quais eixos declarados falharam.
    """
    (min_x, min_y, min_z), (max_x, max_y, max_z) = bounds(bm)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector((-min_x, -max_y, -min_z)))

    footprint = (max_x - min_x, max_y - min_y, max_z - min_z)
    misaligned = [
        axis for axis in grid_axes
        if abs(footprint["xyz".index(axis)] / grid - round(footprint["xyz".index(axis)] / grid))
        > tolerance
    ]
    return {
        "footprint": footprint,
        "cells": [round(footprint[0] / grid, 3), round(footprint[1] / grid, 3)],
        "misaligned": misaligned,
    }


def to_object(bm: bmesh.types.BMesh, name: str, material: bpy.types.Material) -> bpy.types.Object:
    """Converte o BMesh em objeto com shading flat, vertex color e zero UV."""
    mesh = bpy.data.meshes.new(name)
    colors = [P.linear_rgba(face_palette_key(bm, face)) for face in bm.faces]
    bm.to_mesh(mesh)

    # Flat em tudo: é a estética do projeto, e é o que faz cada triângulo ter a sua
    # própria normal na exportação.
    for polygon in mesh.polygons:
        polygon.use_smooth = False

    attribute = mesh.color_attributes.new(name=COLOR_ATTRIBUTE, type="FLOAT_COLOR", domain="CORNER")
    for polygon, color in zip(mesh.polygons, colors):
        for loop_index in polygon.loop_indices:
            attribute.data[loop_index].color = color
    mesh.color_attributes.active_color_index = 0
    mesh.color_attributes.default_color_name = attribute.name
    mesh.color_attributes.active_color_name = attribute.name

    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def flat_material(name: str) -> bpy.types.Material:
    """Material único do kit: branco, sem textura, multiplicado pelo vertex color.

    O glTF multiplica `baseColorFactor` pelo `COLOR_0`, então branco aqui significa "a cor
    é a do vértice". Um material só para todas as peças é o que permite ao Godot agrupar
    o kit inteiro numa punhado de draw calls.
    """
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    principled = nodes.get("Principled BSDF")
    if principled is None:
        return material

    principled.inputs["Roughness"].default_value = 1.0
    principled.inputs["Metallic"].default_value = 0.0

    # O nó de cor de vértice não é decoração: o exportador de glTF só escreve COLOR_0
    # quando o atributo de cor é **usado na árvore de nós do material**. Sem esta ligação
    # ele avisa "will not be exported" no log e entrega um .glb cinza — e o aviso passa
    # despercebido no meio da conversa do Blender.
    color_node = nodes.new("ShaderNodeVertexColor")
    color_node.layer_name = COLOR_ATTRIBUTE
    material.node_tree.links.new(color_node.outputs["Color"], principled.inputs["Base Color"])
    return material


def clear_scene() -> None:
    """Cena vazia entre peças. Sem isto, a peça anterior vaza para o .glb da seguinte."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
