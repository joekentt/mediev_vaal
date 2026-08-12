"""`make characters` — humanoides low poly rigados, sem uma linha de modelagem manual.

`make_humanoid(spec)` empilha seções — pés, pernas, quadril, tronco, ombros, braços,
mãos, pescoço, cabeça — a partir de alturas e larguras que são **fração da altura total**.
É o que faz a silhueta mudar de verdade: dobrar `shoulders` alarga o sujeito inteiro,
e baixar `height` produz alguém baixo, não uma miniatura de alguém alto.

**Por que casca contínua e não um monte de caixas.** Caixas soltas nunca rasgam porque
nunca dobram: cada uma gira rígida com o seu osso. Aqui os membros são anéis costurados
(`meshlib.add_loft`), então o anel da articulação reparte peso entre dois ossos e o
cotovelo dobra. O preço é que skinning ruim aparece como rasgo — e por isso
`make characters` mede a deformação na pose de teste em vez de confiar no olho.

**O rosto não tem geometria de olho.** Olho é um plano com vertex color, afundado na
face. A 900 triângulos, um olho modelado custaria mais do que a cabeça inteira e leria
pior a 5 m de distância.

**Orientação.** No Blender o personagem olha para +Y e o seu lado direito é +X. O
exportador manda `(x, y, z) → (x, z, -y)`, então no Godot ele olha para -Z, que é a
frente da engine, e continua com o direito em +X. Sem isso o sujeito nasceria de costas
para a direção em que anda — e ninguém repara nisso lendo o log.

**Dois arquivos por personagem.** `<nome>.glb` é o entregável: malha + esqueleto em
T-pose. `<nome>_pose.glb` é prova: a mesma malha *já deformada* na pose de teste,
estática. Existe para o catálogo mostrar a dobra sem que o renderizador precise saber o
que é um osso, e é exatamente a malha que o teste de rasgo mede.

    blender --background --python tools/gen_characters.py -- [nomes...]
    python -m tools.gen_characters [nomes...]
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import params as P  # noqa: E402

OUTPUT_DIR = ROOT / P.CHARACTER_DIR
MANIFEST = OUTPUT_DIR / "manifest.json"
MATERIAL_NAME = "character_flat"
BUDGET_KEY = "npc"
POSE_SUFFIX = "_pose"
_ROUND = 4

# Espessura do plano de olho/boca: fundo o bastante para o zbuffer não brigar, raso o
# bastante para não virar buraco.
_FACE_INSET = 0.004

# Lado do corpo. +X é a direita do personagem depois da conversão para o espaço do Godot.
SIDES: dict[float, str] = {-1.0: "Left", 1.0: "Right"}


# ---------------------------------------------------------------------------
# Seções de corpo: a metade "envelope" do skinning
# ---------------------------------------------------------------------------
# Cada face nasce carimbada com a seção a que pertence, e a seção diz quais ossos podem
# disputá-la. Sem isso, peso puramente por distância pendura o peito no osso do braço:
# a meia-largura do tórax é 0,10 da altura e o ombro começa em 0,125 — mais perto do
# úmero do que da coluna. O construtor sabe de graça o que nenhuma heurística recupera.

_SECTION_BONES: dict[str, tuple[str, ...]] = {
    "torso": ("Hips", "Spine", "Chest"),
    "neck":  ("Neck", "Chest", "Head"),
    "head":  ("Head", "Neck"),
    # Cabelo segue o crânio e mais nada. Deixá-lo disputar com o pescoço fazia a mecha
    # comprida do `anciao` esticar 1,74x na pose de teste — ainda dentro do limite, mas
    # pelo motivo errado: cabelo não dobra no pescoço.
    "hair":  ("Head",),
    "robe":  ("Hips", "Spine", "Chest"),
    "hood":  ("Head", "Neck", "Chest"),
    "leg":   ("{side}UpLeg", "{side}Leg", "Hips"),
    "foot":  ("{side}Foot", "{side}Toe", "{side}Leg"),
    "arm":   ("{side}Shoulder", "{side}Arm", "{side}ForeArm"),
    "hand":  ("{side}Hand", "{side}ForeArm"),
}

_SIDELESS = ("torso", "neck", "head", "hair", "robe", "hood")
_SIDED = ("leg", "foot", "arm", "hand")

# O índice 0 fica vago de propósito: é o valor que uma face não carimbada carrega, e
# `_vertex_sections` reprova o build quando encontra um. Esquecer um `M.mark` é o tipo de
# erro que passaria como "esse braço ficou meio duro".
SECTION_KEYS: tuple[tuple[str, str], ...] = (
    tuple((label, "") for label in _SIDELESS)
    + tuple((label, side) for label in _SIDED for side in ("Left", "Right"))
)
SECTION_INDEX: dict[tuple[str, str], int] = {
    key: index + 1 for index, key in enumerate(SECTION_KEYS)
}


def section_id(label: str, side: float | None = None) -> int:
    return SECTION_INDEX[(label, "" if side is None else SIDES[side])]


def section_bones(index: int) -> tuple[str, ...]:
    label, side = SECTION_KEYS[index - 1]
    return tuple(name.format(side=side) for name in _SECTION_BONES[label])


# ---------------------------------------------------------------------------
# Medidas derivadas
# ---------------------------------------------------------------------------


class Figure:
    """As medidas de um humanoide, já em metros.

    Malha e esqueleto leem daqui, e só daqui. É o que garante que o osso caia dentro da
    carne: se o construtor do braço e o construtor do úmero calculassem o cotovelo cada
    um por conta, bastaria um fator diferente para o osso sair pela manga.
    """

    def __init__(self, spec: dict) -> None:
        self.spec = spec
        self.name: str = spec["name"]
        self.height: float = float(spec["height"])
        self.posture: dict = P.POSTURES[spec["posture"]]

        leg_ratio = float(spec["leg_ratio"])
        torso_scale = float(spec["torso"])
        shoulder_scale = float(spec["shoulders"])
        head_scale = float(spec["head"])

        level = {name: value * self.height for name, value in P.BODY_LEVELS.items()}
        # `leg_ratio` move o quadril: perna mais longa empurra o quadril para cima e
        # comprime o tronco, sem mexer na altura total.
        hip = level["hip"] * leg_ratio
        level["hip"] = hip
        level["knee"] = level["ankle"] + (hip - level["ankle"]) * 0.48
        for name in ("waist", "chest", "shoulder"):
            span = P.BODY_LEVELS[name] - P.BODY_LEVELS["hip"]
            level[name] = hip + span * self.height * torso_scale
        # Pescoço e cabeça reencaixam acima do ombro, e a cabeça mantém a altura total.
        neck_span = (P.BODY_LEVELS["neck_base"] - P.BODY_LEVELS["shoulder"]) * self.height
        level["neck_base"] = level["shoulder"] + neck_span
        head_span = (P.BODY_LEVELS["head_top"] - P.BODY_LEVELS["head_base"]) * self.height
        level["head_top"] = self.height
        level["head_base"] = self.height - head_span * head_scale
        self.level = level

        width = {name: value * self.height for name, value in P.BODY_WIDTHS.items()}
        for name in ("shoulder_x", "chest_x"):
            width[name] *= shoulder_scale
        for name in ("chest_z", "waist_x", "waist_z", "hip_x"):
            width[name] *= 1.0 + (torso_scale - 1.0) * 0.7
        for name in ("head_x", "head_z"):
            width[name] *= head_scale
        self.width = width

        self.shoulder_y = level["shoulder"] - self.posture["shoulder_drop"] * self.height
        self.sides = P.CHARACTER_RING_SIDES

        # Articulações compartilhadas entre carne e osso.
        self.knee_bend = math.sin(math.radians(self.posture["knee"])) * (
            level["hip"] - level["ankle"]
        )
        self.arm_level = self.shoulder_y - width["upper_arm"] * 0.6
        self.arm_y = self.lean(self.arm_level)
        self.head_y = self.lean(level["head_base"]) + math.sin(
            math.radians(self.posture["neck"])
        ) * (level["head_top"] - level["head_base"])

    def lean(self, height_value: float) -> float:
        """Deslocamento em Y da postura: o tronco inclina progressivamente acima do quadril.

        `spine` positivo joga o peso para +Y, que é para onde o personagem olha — um
        `curvado` curva para a frente, e não para trás.
        """
        hip = self.level["hip"]
        if height_value <= hip:
            return 0.0
        above = height_value - hip
        return math.sin(math.radians(self.posture["spine"])) * above

    def arm_x(self, side: float) -> tuple[float, float, float, float]:
        """Ombro, cotovelo, pulso e ponta da mão em X, para um lado."""
        span = self.width["shoulder_x"]
        shoulder = span * side
        elbow = shoulder + span * 0.85 * side
        wrist = elbow + span * 0.80 * side
        return shoulder, elbow, wrist, wrist + self.width["hand_z"] * side

    def leg_x(self, side: float) -> float:
        return self.width["hip_x"] * 0.5 * side

    def foot_span(self) -> tuple[float, float]:
        """Recuo e avanço do pé em Y, a partir do tornozelo."""
        depth = self.width["foot_y"]
        return depth * 0.35, depth * 0.65


# ---------------------------------------------------------------------------
# Corpo
# ---------------------------------------------------------------------------


def _ring(figure: Figure, level: float, half_x: float, half_z: float, sides: int | None = None):
    from tools import meshlib as M

    return M.ring((0.0, figure.lean(level), level), half_x, half_z, sides or figure.sides)


def _offset(points, dx: float = 0.0, dy: float = 0.0):
    from mathutils import Vector

    return [point + Vector((dx, dy, 0.0)) for point in points]


def _between(lower, upper):
    """Anel intermediário entre dois anéis: média ponto a ponto.

    Existe por causa da deformação, não da forma. Com um anel só em cada ponta do úmero,
    a aresta que os liga atravessa o osso inteiro: uma ponta pesa metade no ombro, a
    outra metade no antebraço, e na pose de teste ela esticava 1,74x — o "braço de
    borracha" clássico da mistura linear. Um laço no meio corta a aresta pela metade e o
    número cai junto. Custa 12 triângulos por membro, num orçamento com folga de 500.
    """
    return [(low + high) * 0.5 for low, high in zip(lower, upper)]


def build_torso(bm, figure: Figure) -> None:
    """Quadril → cintura → peito → ombros, numa casca só."""
    from tools import meshlib as M

    width = figure.width
    rings = [
        _ring(figure, figure.level["hip"] - width["hip_z"] * 0.4,
              width["hip_x"] * 0.92, width["hip_z"]),
        _ring(figure, figure.level["hip"], width["hip_x"], width["hip_z"]),
        _ring(figure, figure.level["waist"], width["waist_x"], width["waist_z"]),
        _ring(figure, figure.level["chest"], width["chest_x"], width["chest_z"]),
        _ring(figure, figure.shoulder_y, width["shoulder_x"], width["shoulder_z"]),
    ]
    M.mark(bm, M.add_loft(bm, rings, "cloth_cream"), section_id("torso"))


def build_leg(bm, figure: Figure, side: float) -> None:
    """Pé, canela e coxa. `side` é -1 (esquerda) ou +1 (direita)."""
    from tools import meshlib as M

    width = figure.width
    level = figure.level
    leg_x = figure.leg_x(side)

    ankle = _offset(_ring(figure, level["ankle"], width["calf"] * 0.9, width["calf"] * 0.9),
                    dx=leg_x)
    knee = _offset(_ring(figure, level["knee"], width["calf"], width["calf"]),
                   dx=leg_x, dy=figure.knee_bend)
    hip = _offset(_ring(figure, level["hip"] * 0.98, width["thigh"], width["thigh"]), dx=leg_x)
    rings = [ankle, _between(ankle, knee), knee, _between(knee, hip), hip]
    M.mark(bm, M.add_loft(bm, rings, "slate"), section_id("leg", side))

    # Pé: bloco simples, apontando para +Y — a mesma frente do rosto.
    back, _front = figure.foot_span()
    M.mark(
        bm,
        M.add_box(
            bm,
            (leg_x - width["foot_x"], figure.lean(level["ankle"]) - back, 0.0),
            (width["foot_x"] * 2.0, width["foot_y"], width["foot_z"]),
            "bark",
        ),
        section_id("foot", side),
    )


def build_arm(bm, figure: Figure, side: float) -> None:
    """Braço em T-pose: ombro → cotovelo → pulso, mais a mão em bloco."""
    from mathutils import Vector

    from tools import meshlib as M

    width = figure.width
    shoulder_x, elbow_x, wrist_x, _tip_x = figure.arm_x(side)
    level = figure.arm_level

    # Anéis no plano YZ, porque o braço corre no eixo X. `ring` desenha em XY, então o
    # X do ponto vira Y e o Y vira Z — e o centro tem de ser somado **depois** da
    # remontagem. Somá-lo antes (que foi como isto nasceu) jogava o recuo da postura no
    # eixo Z: num `curvado`, o braço subia 12 cm e saía de cima do próprio osso, e o
    # sintoma aparecia lá na frente como 2,5x de esticão na pose de teste.
    def arm_ring(x_value: float, radius: float):
        points = M.ring((0.0, 0.0, 0.0), radius, radius, figure.sides)
        return [
            Vector((x_value, figure.arm_y + point.x, level + point.y)) for point in points
        ]

    shoulder = arm_ring(shoulder_x, width["upper_arm"])
    elbow = arm_ring(elbow_x, width["upper_arm"] * 0.86)
    wrist = arm_ring(wrist_x, width["fore_arm"])
    M.mark(
        bm,
        M.add_loft(
            bm,
            [shoulder, _between(shoulder, elbow), elbow, _between(elbow, wrist), wrist],
            "cloth_cream",
        ),
        section_id("arm", side),
    )

    M.mark(
        bm,
        M.add_box(
            bm,
            (min(wrist_x, wrist_x + width["hand_z"] * side),
             figure.arm_y - width["hand_y"],
             level - width["hand_x"]),
            (width["hand_z"], width["hand_y"] * 2.0, width["hand_x"] * 2.0),
            "sand",
        ),
        section_id("hand", side),
    )


def build_head(bm, figure: Figure) -> None:
    """Pescoço, crânio e rosto. Olhos e boca são planos coloridos, não geometria."""
    from tools import meshlib as M

    width = figure.width
    level = figure.level

    M.mark(
        bm,
        M.add_loft(
            bm,
            [
                _ring(figure, figure.shoulder_y, width["neck_x"] * 1.15, width["neck_z"] * 1.15),
                _ring(figure, level["head_base"], width["neck_x"], width["neck_z"]),
            ],
            "sand",
            cap_end=False,
        ),
        section_id("neck"),
    )

    head = section_id("head")
    M.mark(
        bm,
        M.add_box(
            bm,
            (-width["head_x"], figure.head_y - width["head_z"], level["head_base"]),
            (width["head_x"] * 2.0, width["head_z"] * 2.0,
             level["head_top"] - level["head_base"]),
            "sand",
        ),
        head,
    )

    _build_face(bm, figure, head)
    _build_ears(bm, figure, head)
    _build_hair(bm, figure, head)


def _build_face(bm, figure: Figure, head: int) -> None:
    """Olhos e boca como planos rasos na face frontal (+Y)."""
    from tools import meshlib as M

    width = figure.width
    level = figure.level
    head_height = level["head_top"] - level["head_base"]
    front = figure.head_y + width["head_z"]

    eye_w = width["head_x"] * 0.30
    eye_h = head_height * 0.13
    eye_z = level["head_base"] + head_height * 0.58
    for side in (-1.0, 1.0):
        offset = width["head_x"] * 0.40 * side
        M.mark(
            bm,
            M.add_box(bm, (offset - eye_w * 0.5, front, eye_z - eye_h * 0.5),
                      (eye_w, _FACE_INSET, eye_h), "slate"),
            head,
        )

    mouth_w = width["head_x"] * 0.55
    M.mark(
        bm,
        M.add_box(bm, (-mouth_w * 0.5, front, level["head_base"] + head_height * 0.25),
                  (mouth_w, _FACE_INSET, head_height * 0.06), "wood_dark"),
        head,
    )

    if figure.spec["beard"]:
        M.mark(
            bm,
            M.add_box(
                bm,
                (-width["head_x"] * 0.78, figure.head_y + width["head_z"] * 0.47,
                 level["head_base"] + head_height * 0.02),
                (width["head_x"] * 1.56, width["head_z"] * 0.55, head_height * 0.38),
                "bark",
            ),
            head,
        )


def _build_ears(bm, figure: Figure, head: int) -> None:
    from tools import meshlib as M

    width = figure.width
    level = figure.level
    head_height = level["head_top"] - level["head_base"]
    kind = figure.spec["ears"]
    ear_z = level["head_base"] + head_height * 0.55

    length, height_factor, depth = {
        "humana":  (0.16, 0.20, 0.055),
        "pontuda": (0.14, 0.34, 0.045),
        "larga":   (0.24, 0.22, 0.070),
    }[kind]

    for side in (-1.0, 1.0):
        base_x = width["head_x"] * side
        corner = (
            min(base_x, base_x + width["head_x"] * length * side),
            figure.head_y - width["head_z"] * depth,
            ear_z,
        )
        size = (
            width["head_x"] * length,
            width["head_z"] * depth * 2.0,
            head_height * height_factor,
        )
        # A orelha pontuda é uma cunha, não uma caixa: a ponta é a leitura.
        faces = (
            M.add_wedge(bm, corner, size, "sand", along_y=True) if kind == "pontuda"
            else M.add_box(bm, corner, size, "sand")
        )
        M.mark(bm, faces, head)


def _build_hair(bm, figure: Figure, head: int) -> None:
    del head  # o cabelo tem seção própria: gira com o crânio e não dobra no pescoço
    from tools import meshlib as M

    kind = figure.spec["hair"]
    if kind == "nenhum":
        return

    width = figure.width
    level = figure.level
    head_height = level["head_top"] - level["head_base"]
    cap_height = head_height * 0.30
    hair = section_id("hair")

    M.mark(
        bm,
        M.add_box(
            bm,
            (-width["head_x"] * 1.04, figure.head_y - width["head_z"] * 1.04,
             level["head_top"] - cap_height),
            (width["head_x"] * 2.08, width["head_z"] * 2.08, cap_height),
            "bark",
        ),
        hair,
    )

    # Cabelo comprido e rabo caem atrás, em -Y: a frente é o rosto.
    if kind == "longo":
        M.mark(
            bm,
            M.add_box(
                bm,
                (-width["head_x"] * 1.02, figure.head_y - width["head_z"] * 1.05,
                 level["head_base"] - head_height * 0.35),
                (width["head_x"] * 2.04, width["head_z"] * 0.5, head_height * 1.05),
                "bark",
            ),
            hair,
        )
    elif kind == "rabo":
        M.mark(
            bm,
            M.add_box(
                bm,
                (-width["head_x"] * 0.30, figure.head_y - width["head_z"] * 1.6,
                 level["head_base"] - head_height * 0.45),
                (width["head_x"] * 0.60, width["head_z"] * 0.7, head_height * 0.85),
                "bark",
            ),
            hair,
        )


# ---------------------------------------------------------------------------
# Roupas
# ---------------------------------------------------------------------------


def build_clothing(bm, figure: Figure) -> None:
    """Geometria adicional colada ao mesmo corpo — e, depois, ao mesmo esqueleto.

    Roupa aqui não é camada de simulação: é casca com a mesma topologia de anéis, um
    pouco mais larga que a carne. Pesa nos mesmos ossos porque passa pelo mesmo cálculo
    de distância, então dobra junto sem tratamento especial.
    """
    from tools import meshlib as M

    kind = figure.spec["clothing"]
    if kind == "nenhuma":
        return

    width = figure.width
    level = figure.level
    pad = figure.height * 0.008

    if kind in ("tunica", "avental", "armadura_leve"):
        color = {"tunica": "cloth_blue", "avental": "bark_light", "armadura_leve": "iron"}[kind]
        hem = level["hip"] - figure.height * (0.16 if kind == "tunica" else 0.10)
        flare = 1.25 if kind == "tunica" else 1.05
        rings = [
            _ring(figure, hem, width["hip_x"] * flare + pad, width["hip_z"] * flare + pad),
            _ring(figure, level["hip"], width["hip_x"] + pad, width["hip_z"] + pad),
            _ring(figure, level["waist"], width["waist_x"] + pad, width["waist_z"] + pad),
            _ring(figure, level["chest"], width["chest_x"] + pad, width["chest_z"] + pad),
        ]
        if kind == "avental":
            # Avental é curto: some com o anel do peito.
            rings = rings[:3]
        # Tampa em cima, aberto embaixo: a bainha é por onde saem as pernas, e o topo
        # some dentro do tórax. Sem a tampa, a vista de topo do catálogo mostra um buraco
        # preto — dá para ver o tubo por dentro.
        M.mark(bm, M.add_loft(bm, rings, color, cap_start=False), section_id("robe"))

    if kind == "capuz":
        M.mark(
            bm,
            M.add_box(
                bm,
                (-width["head_x"] * 1.12, figure.head_y - width["head_z"] * 1.12,
                 level["head_base"] - figure.height * 0.02),
                (width["head_x"] * 2.24, width["head_z"] * 2.24,
                 (level["head_top"] - level["head_base"]) * 1.08),
                "cloth_green",
            ),
            section_id("hood"),
        )
        M.mark(
            bm,
            M.add_loft(
                bm,
                [
                    _ring(figure, level["chest"],
                          width["chest_x"] * 1.10, width["chest_z"] * 1.10),
                    _ring(figure, figure.shoulder_y,
                          width["shoulder_x"] * 1.06, width["shoulder_z"] * 1.06),
                ],
                "cloth_green",
                cap_start=False,
            ),
            section_id("robe"),
        )

    if kind == "capa":
        # A capa recua conforme desce: presa no ombro, caindo atrás. Sem o recuo ela vira
        # um tubo em volta do corpo e lê como vestido, não como manto.
        drape = figure.height * 0.05
        M.mark(
            bm,
            M.add_loft(
                bm,
                [
                    _offset(
                        _ring(figure, level["hip"] - figure.height * 0.14,
                              width["hip_x"] * 1.35, width["hip_z"] * 1.35),
                        dy=-drape,
                    ),
                    _offset(
                        _ring(figure, level["chest"],
                              width["chest_x"] * 1.12, width["chest_z"] * 1.12),
                        dy=-drape * 0.4,
                    ),
                    _ring(figure, figure.shoulder_y,
                          width["shoulder_x"] * 1.05, width["shoulder_z"] * 1.05),
                ],
                "cloth_red",
                cap_start=False,
            ),
            section_id("robe"),
        )


# ---------------------------------------------------------------------------
# Montagem da malha
# ---------------------------------------------------------------------------


def make_humanoid(spec: dict):
    """Constrói o corpo inteiro e devolve `(bmesh, figure)`.

    A ordem é a da anatomia — pés, pernas, quadril, tronco, ombros, braços, mãos,
    pescoço, cabeça — e cada seção lê as medidas da mesma `Figure`, que é o que mantém
    o esqueleto alinhado com a carne mais adiante.
    """
    from tools import meshlib as M

    figure = Figure(spec)
    bm = M.new_bmesh()

    for side in SIDES:
        build_leg(bm, figure, side)
    build_torso(bm, figure)
    for side in SIDES:
        build_arm(bm, figure, side)
    build_head(bm, figure)
    build_clothing(bm, figure)
    return bm, figure


# ---------------------------------------------------------------------------
# Esqueleto
# ---------------------------------------------------------------------------


def build_skeleton(figure: Figure) -> list[tuple[str, str | None, tuple, tuple]]:
    """Ossos no padrão Mixamo, em coordenadas do Blender (Z para cima).

    Os nomes são os que o importador do Godot reconhece para retargeting — `Hips`,
    `Spine`, `Chest`, `Neck`, `Head`, e os pares `Left`/`Right` de `Shoulder`, `Arm`,
    `ForeArm`, `Hand`, `UpLeg`, `Leg`, `Foot`, `Toe`. Cada ponta sai de `Figure`, então o
    osso nasce onde a carne está, mesmo quando a postura inclina o tronco.

    A lista já vem em ordem de hierarquia: pai sempre antes de filho.
    """
    level = figure.level
    lean = figure.lean
    shoulder = (0.0, lean(figure.shoulder_y), figure.shoulder_y)
    head_base = (0.0, figure.head_y, level["head_base"])

    bones: list[tuple[str, str | None, tuple, tuple]] = [
        ("Hips",  None,    (0.0, lean(level["hip"]), level["hip"]),
                           (0.0, lean(level["waist"]), level["waist"])),
        ("Spine", "Hips",  (0.0, lean(level["waist"]), level["waist"]),
                           (0.0, lean(level["chest"]), level["chest"])),
        ("Chest", "Spine", (0.0, lean(level["chest"]), level["chest"]), shoulder),
        ("Neck",  "Chest", shoulder, head_base),
        ("Head",  "Neck",  head_base, (0.0, figure.head_y, level["head_top"])),
    ]

    back, front = figure.foot_span()
    ankle_y = lean(level["ankle"])
    sole = figure.width["foot_z"] * 0.5

    for side, name in SIDES.items():
        shoulder_x, elbow_x, wrist_x, tip_x = figure.arm_x(side)
        arm_point = lambda x: (x, figure.arm_y, figure.arm_level)  # noqa: E731
        leg_x = figure.leg_x(side)
        hip_point = (leg_x, lean(level["hip"]), level["hip"])
        knee_point = (leg_x, lean(level["knee"]) + figure.knee_bend, level["knee"])
        ankle_point = (leg_x, ankle_y, level["ankle"])

        bones += [
            (f"{name}Shoulder", "Chest", shoulder, arm_point(shoulder_x)),
            (f"{name}Arm", f"{name}Shoulder", arm_point(shoulder_x), arm_point(elbow_x)),
            (f"{name}ForeArm", f"{name}Arm", arm_point(elbow_x), arm_point(wrist_x)),
            (f"{name}Hand", f"{name}ForeArm", arm_point(wrist_x), arm_point(tip_x)),
            (f"{name}UpLeg", "Hips", hip_point, knee_point),
            (f"{name}Leg", f"{name}UpLeg", knee_point, ankle_point),
            (f"{name}Foot", f"{name}Leg", ankle_point,
             (leg_x, ankle_y - back + figure.width["foot_y"] * 0.75, sole)),
            (f"{name}Toe", f"{name}Foot",
             (leg_x, ankle_y - back + figure.width["foot_y"] * 0.75, sole),
             (leg_x, ankle_y + front, sole)),
        ]

    produced = tuple(name for name, _parent, _head, _tail in bones)
    if set(produced) != set(P.MIXAMO_BONES):
        raise CharacterError(
            f"{figure.name}: o esqueleto saiu com {sorted(produced)}, e params.py define "
            f"{sorted(P.MIXAMO_BONES)}. Os nomes são contrato com o importador do Godot."
        )
    return bones


def create_armature(bones: list[tuple[str, str | None, tuple, tuple]], name: str):
    """Cria o objeto de armature a partir da lista de ossos."""
    import bpy
    from mathutils import Vector

    data = bpy.data.armatures.new(f"{name}_skeleton")
    obj = bpy.data.objects.new("Armature", data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, parent, head, tail in bones:
        edit_bone = data.edit_bones.new(bone_name)
        edit_bone.head = Vector(head)
        edit_bone.tail = Vector(tail)
        # `use_connect` fica desligado de propósito: ombro e coxa saem do centro do corpo
        # para o lado, e conectar arrastaria a cabeça do filho para a cauda do pai.
        edit_bone.use_connect = False
        if parent is not None:
            edit_bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


# ---------------------------------------------------------------------------
# Skinning
# ---------------------------------------------------------------------------


def _distance_to_segment(point, head, tail) -> float:
    """Distância de um ponto ao segmento de osso."""
    from mathutils import Vector

    start = Vector(head)
    axis = Vector(tail) - start
    length_squared = axis.length_squared
    if length_squared <= 0.0:
        return (Vector(point) - start).length
    t = max(0.0, min(1.0, (Vector(point) - start).dot(axis) / length_squared))
    return (Vector(point) - (start + axis * t)).length


def compute_weights(
    positions: list, sections: list[set[int]], bones: list, height: float
) -> list[list[tuple[str, float]]]:
    """Peso por vértice: distância ao osso, dentro da seção, com no máximo 2 influências.

    A queda é `((R - d) / (R * d))^p`: infinita no osso, exatamente zero no raio de
    influência `R`. Não é `(1 - d/R)^p`, que foi a primeira tentativa e é lisa demais —
    com `R` na casa de meio metro, o meio do úmero recebia quase tanto do antebraço
    quanto do próprio osso, e o braço inteiro virava um tubo mole. Aqui o vértice colado
    num osso pesa duas ordens de grandeza mais que o vizinho, e só na articulação — onde
    os dois estão à mesma distância — o peso reparte de verdade. É ali que se quer dobra.
    """
    radius = P.BONE_INFLUENCE_RADIUS * height
    floor = height * 0.005
    by_name = {bone[0]: bone for bone in bones}

    weights: list[list[tuple[str, float]]] = []
    for position, section_set in zip(positions, sections):
        candidates: list[str] = []
        for index in sorted(section_set):
            for bone_name in section_bones(index):
                if bone_name not in candidates:
                    candidates.append(bone_name)

        scored: list[tuple[str, float]] = []
        nearest: tuple[str, float] | None = None
        for bone_name in candidates:
            _name, _parent, head, tail = by_name[bone_name]
            distance = _distance_to_segment(position, head, tail)
            if nearest is None or distance < nearest[1]:
                nearest = (bone_name, distance)
            if distance >= radius:
                continue
            clamped = max(distance, floor)
            scored.append((bone_name, ((radius - clamped) / (radius * clamped)) ** P.BONE_WEIGHT_POWER))

        if not scored:
            # Fora do raio de todo osso da seção: cola no mais próximo, rígido.
            scored = [(nearest[0], 1.0)]

        scored.sort(key=lambda item: (-item[1], item[0]))
        scored = scored[:P.BONE_MAX_INFLUENCES]
        total = sum(weight for _name, weight in scored)
        weights.append([(name, weight / total) for name, weight in scored])
    return weights


def _vertex_sections(mesh, name: str) -> list[set[int]]:
    """Seções que tocam cada vértice, lidas do atributo de face carregado pelo BMesh."""
    from tools import meshlib as M

    attribute = mesh.attributes.get(M.SECTION_LAYER)
    if attribute is None:
        raise CharacterError(f"{name}: a malha perdeu a camada de seções no caminho.")

    sections: list[set[int]] = [set() for _ in mesh.vertices]
    for polygon, value in zip(mesh.polygons, attribute.data):
        if value.value == 0:
            raise CharacterError(
                f"{name}: há face sem seção de corpo — algum construtor esqueceu o "
                f"`meshlib.mark`, e esses vértices iriam para o osso errado em silêncio."
            )
        for vertex_index in polygon.vertices:
            sections[vertex_index].add(value.value)
    return sections


def skin(obj, armature, figure: Figure, bones: list) -> dict:
    """Cria os grupos de vértice, aplica os pesos e prende a malha ao esqueleto."""
    mesh = obj.data
    sections = _vertex_sections(mesh, figure.name)
    positions = [vertex.co.copy() for vertex in mesh.vertices]
    weights = compute_weights(positions, sections, bones, figure.height)

    groups = {name: obj.vertex_groups.new(name=name) for name, _parent, _h, _t in bones}
    for index, influences in enumerate(weights):
        for bone_name, weight in influences:
            groups[bone_name].add([index], weight, "REPLACE")

    obj.parent = armature
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True

    used = {name for influences in weights for name, _weight in influences}
    return {
        "influences_max": max(len(influences) for influences in weights),
        "bones_used": len(used),
        "bones_idle": sorted({name for name, _p, _h, _t in bones} - used),
    }


# ---------------------------------------------------------------------------
# Pose de teste e prova de que a malha não rasga
# ---------------------------------------------------------------------------


def apply_test_pose(armature) -> None:
    import bpy
    from mathutils import Euler

    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        angles = P.TEST_POSE.get(pose_bone.name)
        pose_bone.rotation_euler = Euler(
            (0.0, 0.0, 0.0) if angles is None
            else tuple(math.radians(value) for value in angles),
            "XYZ",
        )
    bpy.context.view_layer.update()


def clear_pose(armature) -> None:
    import bpy
    from mathutils import Euler

    for pose_bone in armature.pose.bones:
        pose_bone.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
    bpy.context.view_layer.update()


def _evaluated_mesh(obj):
    """A malha depois dos modificadores — isto é, já deformada pela pose."""
    import bpy

    depsgraph = bpy.context.evaluated_depsgraph_get()
    return bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), depsgraph=depsgraph)


def measure_stretch(obj, name: str) -> dict:
    """Mede quanto cada aresta estica entre a T-pose e a pose de teste.

    Esta é a forma executável de "nenhum vértice se deforma de forma quebrada". Um
    vértice preso ao osso errado não fica feio de leve: ele voa junto com um membro que
    está do outro lado do corpo, e a aresta que o liga ao vizinho estica várias vezes.
    Olhar o render pega isso quando é grosseiro; medir pega quando é sutil, e pega em CI.

    Depende da malha estar *soldada* (`canonicalize(weld=True)`): sem vértice
    compartilhado não existe aresta entre triângulos vizinhos e o teste mediria só as
    arestas internas de cada triângulo, que nunca rasgam.
    """
    rest = [vertex.co.copy() for vertex in obj.data.vertices]
    edges = [tuple(edge.vertices) for edge in obj.data.edges]

    posed_mesh = _evaluated_mesh(obj)
    posed = [vertex.co.copy() for vertex in posed_mesh.vertices]
    import bpy

    bpy.data.meshes.remove(posed_mesh)

    if len(posed) != len(rest):
        raise CharacterError(f"{name}: a pose mudou a contagem de vértices.")

    worst = 0.0
    worst_edge = (0, 0)
    moved = 0.0
    for a, b in edges:
        before = (rest[a] - rest[b]).length
        if before < 1e-5:
            continue
        ratio = (posed[a] - posed[b]).length / before
        if ratio > worst:
            worst, worst_edge = ratio, (a, b)
    for before, after in zip(rest, posed):
        moved = max(moved, (after - before).length)

    return {
        "max_edge_stretch": round(worst, 3),
        "worst_edge": list(worst_edge),
        "max_vertex_travel": round(moved, _ROUND),
        "edges": len(edges),
    }


# ---------------------------------------------------------------------------
# Construção de um personagem
# ---------------------------------------------------------------------------


class CharacterError(RuntimeError):
    """Um personagem violou uma restrição dura. O build inteiro para."""


def build_character(spec: dict) -> dict:
    """Constrói, riga, confere e exporta um personagem. Devolve a entrada do manifesto."""
    from tools import meshlib as M

    M.clear_scene()
    bm, figure = make_humanoid(spec)
    M.triangulate(bm)

    triangles = M.triangle_count(bm)
    ceiling = P.TRI_BUDGET[BUDGET_KEY]
    if triangles > ceiling:
        raise CharacterError(
            f"{figure.name}: {triangles} triângulos para um teto de {ceiling} "
            f"({BUDGET_KEY}). Simplifique o corpo ou renegocie o teto em params.py."
        )

    (min_corner, max_corner) = M.bounds(bm)
    # Soldado, e não separado por face como o kit: o teste de rasgo precisa de arestas
    # entre triângulos vizinhos para ter o que medir.
    bm = M.canonicalize(bm, weld=True)

    material = M.flat_material(MATERIAL_NAME)
    obj = M.to_object(bm, figure.name, material)
    bm.free()

    if obj.data.uv_layers:
        raise CharacterError(f"{figure.name}: tem camada de UV — o projeto não usa textura.")

    bones = build_skeleton(figure)
    armature = create_armature(bones, figure.name)
    rig = skin(obj, armature, figure, bones)

    path = OUTPUT_DIR / f"{figure.name}.glb"
    _export_glb([obj, armature], path, skins=True)

    apply_test_pose(armature)
    stretch = measure_stretch(obj, figure.name)
    if stretch["max_edge_stretch"] > P.CHARACTER_MAX_EDGE_STRETCH:
        raise CharacterError(
            f"{figure.name}: uma aresta estica {stretch['max_edge_stretch']:.2f}x na pose "
            f"de teste, acima do limite de {P.CHARACTER_MAX_EDGE_STRETCH:g}x. Há vértice "
            f"pendurado no osso errado — confira a seção de corpo que o cobre."
        )

    pose_path = OUTPUT_DIR / f"{figure.name}{POSE_SUFFIX}.glb"
    _export_posed(obj, pose_path)
    clear_pose(armature)

    size = [round(high - low, _ROUND) for low, high in zip(min_corner, max_corner)]
    return {
        "name": figure.name,
        "category": "characters",
        "file": path.name,
        "pose_file": pose_path.name,
        "tris": triangles,
        "budget": ceiling,
        "bones": len(bones),
        "verts": len(obj.data.vertices),
        "height": round(figure.height, _ROUND),
        "size": size,
        "bbox_min": [round(value, _ROUND) for value in min_corner],
        "bbox_max": [round(value, _ROUND) for value in max_corner],
        "shoulder_span": round(figure.width["shoulder_x"] * 2.0, _ROUND),
        "posture": spec["posture"],
        "clothing": spec["clothing"],
        "ears": spec["ears"],
        "hair": spec["hair"],
        "beard": bool(spec["beard"]),
        "influences_max": rig["influences_max"],
        "bones_used": rig["bones_used"],
        "bones_idle": rig["bones_idle"],
        "max_edge_stretch": stretch["max_edge_stretch"],
        "max_vertex_travel": stretch["max_vertex_travel"],
    }


def _export_glb(objects: list, path: Path, skins: bool) -> None:
    import bpy

    path.parent.mkdir(parents=True, exist_ok=True)
    for other in bpy.data.objects:
        other.select_set(other in objects)
    bpy.context.view_layer.objects.active = objects[0]

    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format=P.KIT_EXPORT_FORMAT,
        use_selection=True,
        # `export_apply` fica desligado com esqueleto: aplicar modificadores assaria o
        # modificador de armature na malha e o .glb sairia sem skin nenhum.
        export_apply=not skins,
        export_yup=True,
        export_texcoords=False,
        export_normals=True,
        export_materials="EXPORT",
        export_vertex_color="MATERIAL",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=skins,
        export_morph=False,
        export_extras=False,
    )


def _export_posed(obj, path: Path) -> None:
    """Assa a pose de teste numa malha estática e exporta — o arquivo de prova."""
    import bpy

    from tools import meshlib as M

    baked_data = _evaluated_mesh(obj)
    baked = bpy.data.objects.new(f"{obj.name}{POSE_SUFFIX}", baked_data)
    bpy.context.scene.collection.objects.link(baked)
    for polygon in baked.data.polygons:
        polygon.use_smooth = False
    if not baked.data.materials:
        baked.data.materials.append(M.flat_material(MATERIAL_NAME))

    _export_glb([baked], path, skins=False)
    bpy.data.objects.remove(baked, do_unlink=True)
    bpy.data.meshes.remove(baked_data)


# ---------------------------------------------------------------------------
# Prova de silhueta
# ---------------------------------------------------------------------------


def check_silhouettes(entries: list[dict]) -> list[str]:
    """`prova_baixo` e `prova_alto` diferem só em altura e ombros — e têm de parecer.

    O critério de aceite fala em "silhuetas claramente distintas", que é uma frase de
    olho. Aqui vira número: a diferença de altura e de vão de ombros entre as duas provas
    tem de ser maior que a variação que um mesmo corpo teria por arredondamento.
    """
    by_name = {entry["name"]: entry for entry in entries}
    low, high = by_name.get("prova_baixo"), by_name.get("prova_alto")
    if low is None or high is None:
        return []

    problems: list[str] = []
    height_gap = high["size"][2] - low["size"][2]
    # Vão de ombros, não a extensão em X da malha: em T-pose o X é a envergadura dos
    # braços, que cresceria mesmo se `shoulders` não chegasse a lugar nenhum.
    span_gap = high["shoulder_span"] - low["shoulder_span"]
    if height_gap < low["size"][2] * 0.2:
        problems.append(
            f"prova_alto é só {height_gap:.3f} m mais alto que prova_baixo — a altura "
            f"não está chegando na malha."
        )
    if span_gap < low["shoulder_span"] * 0.2:
        problems.append(
            f"prova_alto tem só {span_gap:.3f} m a mais de ombro que prova_baixo — a "
            f"largura de ombros não está chegando na malha."
        )
    print(
        f"  silhueta: prova_baixo {low['size'][2]:.2f} m de altura e "
        f"{low['shoulder_span']:.2f} m de ombro  vs  prova_alto {high['size'][2]:.2f} m e "
        f"{high['shoulder_span']:.2f} m"
    )
    return problems


# ---------------------------------------------------------------------------
# Manifesto
# ---------------------------------------------------------------------------


def write_manifest(entries: list[dict]) -> None:
    payload = {
        "_generated_by": "tools/gen_characters.py",
        "_source": "tools/params.py",
        "_warning": "ARQUIVO GERADO — NÃO EDITE À MÃO. Regenerar: make characters",
        "character_seed": P.CHARACTER_SEED,
        "material": MATERIAL_NAME,
        "tri_budget": P.TRI_BUDGET[BUDGET_KEY],
        "max_influences": P.BONE_MAX_INFLUENCES,
        "max_edge_stretch": P.CHARACTER_MAX_EDGE_STRETCH,
        "pose_suffix": POSE_SUFFIX,
        "test_pose": {name: list(angles) for name, angles in P.TEST_POSE.items()},
        "character_count": len(entries),
        "total_tris": sum(entry["tris"] for entry in entries),
        "characters": sorted(entries, key=lambda entry: entry["name"]),
    }
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")


# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------


def run_in_blender(selected: list[str]) -> int:
    roster = list(P.CHARACTER_ROSTER)
    if selected:
        unknown = sorted(set(selected) - {spec["name"] for spec in roster})
        if unknown:
            print(f"ERRO: personagem desconhecido: {', '.join(unknown)}", file=sys.stderr)
            return 1
        roster = [spec for spec in roster if spec["name"] in selected]

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    entries: list[dict] = []
    failures: list[str] = []

    for spec in roster:
        try:
            entry = build_character(spec)
        except CharacterError as error:
            failures.append(str(error))
            continue
        entries.append(entry)
        print(
            f"  {entry['name']:<14} {entry['tris']:>4} tris  {entry['bones']:>2} ossos  "
            f"{entry['height']:.2f} m  estica {entry['max_edge_stretch']:.2f}x"
        )

    if not selected:
        failures += check_silhouettes(entries)

    if failures:
        print(f"\n  {len(failures)} problema(s):", file=sys.stderr)
        for failure in failures:
            print(f"    - {failure}", file=sys.stderr)
        return 1

    if not selected:
        write_manifest(entries)
        print(f"\n  {len(entries)} personagens, "
              f"{sum(entry['tris'] for entry in entries)} triângulos no total")
        print(f"  manifesto: {MANIFEST.relative_to(ROOT)}")
    return 0


def main(argv: list[str] | None = None) -> int:
    from tools import gen_assets

    argv = sys.argv[1:] if argv is None else argv
    selected = [arg for arg in argv if not arg.startswith("-")]
    return gen_assets.dispatch(Path(__file__), run_in_blender, selected)


if __name__ == "__main__":
    from tools import gen_assets

    if gen_assets._is_inside_blender():
        raise SystemExit(run_in_blender(gen_assets.script_args()))
    raise SystemExit(main())
