"""Fonte única de verdade do projeto Mediev Vaal.

Todo número, cor, orçamento e nome de camada do jogo nasce aqui. `scripts/core/params.gd`
é *gerado* a partir deste arquivo por `tools/gen_params.py` — nunca edite o .gd à mão.

Regra do projeto: nenhum literal numérico com significado pode aparecer em .gd ou em
outro tool. Se você precisou de um número novo, ele entra aqui primeiro.
`tools/verify.py` reprova o build quando essa regra é quebrada.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Identidade
# ---------------------------------------------------------------------------

PROJECT_NAME = "Mediev Vaal"
PROJECT_DESCRIPTION = "RPG 3D low poly de fantasia medieval original, 100% gerado por script."
MAIN_SCENE = "res://scenes/world/main.tscn"
GODOT_FEATURES = ("4.4", "Forward Plus")

# ---------------------------------------------------------------------------
# Paleta
# ---------------------------------------------------------------------------
# Cor flat + vertex color, sem textura de imagem. Tons quentes e naturalistas, com
# a pedra fria servindo de contraponto. Hex em sRGB; a conversão para Color() é feita
# pelos geradores.

PALETTE: dict[str, str] = {
    # Terra e rocha
    "earth":          "#6B563C",
    "earth_dark":     "#4A3A28",
    "clay":           "#8A5E3B",
    "sand":           "#C2A878",
    "stone_light":    "#8C877B",
    "stone":          "#6E695E",
    "stone_dark":     "#4A463E",
    "slate":          "#3E434A",
    # Vegetação
    "grass":          "#5A7A3C",
    "grass_dark":     "#3F5A2A",
    "foliage":        "#4A6B33",
    "foliage_deep":   "#2F4A2E",
    "moss":           "#6B7A38",
    "bark":           "#4F3A28",
    "bark_light":     "#6B5138",
    # Construção
    "wood":           "#6B4A2F",
    "wood_dark":      "#4A331F",
    "thatch":         "#B7913F",
    "plaster":        "#D6C7A8",
    "roof_tile":      "#8C4A32",
    # Metal e tecido
    "iron":           "#6E727A",
    "iron_dark":      "#4A4E55",
    "gold":           "#C9A253",
    "cloth_red":      "#8C3A2E",
    "cloth_blue":     "#35506B",
    "cloth_green":    "#3F6B4A",
    "cloth_cream":    "#D6C7A8",
    # Água, céu e atmosfera
    "water":          "#3E6B78",
    "water_deep":     "#28495A",
    "sky_zenith":     "#4E7CAE",
    "sky_horizon":    "#C9B894",
    "sun":            "#FFF0DA",
    "fog":            "#BAAF95",
    # Neutros de trabalho
    "ground_default": "#78746A",
    # Branco puro: a base do material dos proxies de LOD. `vertex_color_use_as_albedo`
    # multiplica o albedo pela cor do vértice, então só um albedo branco deixa a cor média
    # da peça atravessar intacta. Qualquer outra cor tingiria o proxy — e um proxy de rocha
    # com material de folhagem sai verde a 200 m.
    "proxy_neutral":  "#FFFFFF",
    "debug_magenta":  "#FF00AA",
}

# Materiais compartilhados gerados em assets/generated/materials/.
# Cada entrada vira um StandardMaterial3D flat com vertex color habilitado.
# name -> (cor da paleta, roughness, metallic)
MATERIALS: dict[str, tuple[str, float, float]] = {
    "terrain":   ("grass",          0.95, 0.0),
    "rock":      ("stone",          0.90, 0.0),
    "wood":      ("wood",           0.85, 0.0),
    "thatch":    ("thatch",         1.00, 0.0),
    "plaster":   ("plaster",        0.90, 0.0),
    "foliage":   ("foliage",        1.00, 0.0),
    "metal":     ("iron",           0.45, 0.85),
    "cloth":     ("cloth_cream",    0.95, 0.0),
    "water":     ("water",          0.15, 0.0),
    "ground":    ("ground_default", 0.95, 0.0),
    # Um material para todos os proxies de LOD, de qualquer tipo. A cor vem do vertex
    # color; o material só existe para o proxy não nascer com o branco padrão do Godot,
    # que ignora vertex color e pintava o vale inteiro de cones claros além de 92 m.
    "proxy":     ("proxy_neutral",  1.00, 0.0),
    "debug":     ("debug_magenta",  1.00, 0.0),
}

# ---------------------------------------------------------------------------
# Escala do mundo
# ---------------------------------------------------------------------------
# Tudo se alinha a um grid de 2 m. Prédios, ruas e props são múltiplos disso — é o que
# permite instanciar em MultiMesh e casar módulos sem gap.

GRID_SIZE = 2.0                 # metros por célula
CHUNK_CELLS = 16                # células por lado de um chunk de terreno
CHUNK_SIZE = GRID_SIZE * CHUNK_CELLS   # 32 m
WORLD_RADIUS_CHUNKS = 8         # raio do mundo em chunks
WALL_HEIGHT = 3.0               # pé-direito padrão
FLOOR_HEIGHT = 3.5              # altura de um pavimento
DOOR_WIDTH = 1.2
DOOR_HEIGHT = 2.2
STREET_WIDTH = GRID_SIZE * 3    # 6 m

# Estágio inicial (a "sala vazia" da fase 1).
STAGE_GROUND_SIZE = 200.0
STAGE_CAMERA_HEIGHT = 2.5
STAGE_CAMERA_DISTANCE = 8.0
STAGE_CAMERA_PITCH_DEG = -12.0
STAGE_CAMERA_FOV = 70.0
STAGE_CAMERA_FAR = 300.0
STAGE_SUN_PITCH_DEG = -50.0
STAGE_SUN_YAW_DEG = -35.0
STAGE_SUN_HEIGHT = 12.0
STAGE_SUN_ENERGY = 1.1
STAGE_GROUND_CELLS = 20         # subdivisões do chão do estágio (por lado)
STAGE_GROUND_TONE_JITTER = 0.04 # variação de tom por célula, via vertex color

# ---------------------------------------------------------------------------
# Fábrica de assets (Blender headless)
# ---------------------------------------------------------------------------
# Política de granularidade: aqui ficam as medidas *compartilhadas* — as que fazem as
# peças encaixarem umas nas outras e as que a arte inteira herda. As proporções internas
# de cada peça vivem na assinatura da própria função, documentadas e quase sempre
# expressas como fração de GRID_SIZE. Empurrar as ~300 medidas internas de 34 peças para
# cá tornaria este arquivo ilegível sem tornar nada mais fácil de mudar.

KIT_DIR = "assets/generated/kit"
KIT_SEED = 7717                 # semente-mãe; cada peça deriva a sua de nome + esta
KIT_EXPORT_FORMAT = "GLB"

# Espessuras e folgas do kit modular. Tudo múltiplo ou fração do grid de 2 m.
WALL_THICKNESS = 0.25
FLOOR_THICKNESS = 0.2
BEAM_THICKNESS = 0.22
PILLAR_RADIUS = 0.28
PILLAR_SIDES = 8                # prisma octogonal: silhueta redonda a 8 faces
ROOF_PITCH_DEG = 38.0           # inclinação do telhado
ROOF_OVERHANG = 0.3             # beiral além da parede
STAIR_STEPS = 6
WINDOW_WIDTH = 0.9
WINDOW_HEIGHT = 1.0
WINDOW_SILL = 1.0               # altura do peitoril
GATE_WIDTH = 3.0
GATE_HEIGHT = 3.4
GATE_ARCH_SEGMENTS = 5
TOWER_SIDES = 8
TOWER_HEIGHT = 9.0
TOWER_RADIUS = 1.8
BRIDGE_LENGTH = 8.0
FENCE_RAILS = 2

# Detalhe das peças de natureza. Menos segmentos = silhueta mais dura, que é o alvo.
ROCK_SUBDIVISIONS = 2         # icosfera: 1 dá 20 tris, 2 dá 80 — ver meshlib.add_icosphere
ROCK_NOISE = 0.22               # deslocamento relativo ao raio
TREE_TRUNK_SIDES = 5
TREE_CANOPY_BLOBS = 3           # icosferas achatadas que formam a copa
TREE_CANOPY_NOISE = 0.18
CONIFER_TIERS = 3
CONIFER_SIDES = 6
BUSH_BLOBS = 3
GRASS_BLADES = 5

# Chanfro de silhueta: quebra a aresta viva sem custar quase nada em triângulos.
BEVEL_AMOUNT = 0.03
BEVEL_SEGMENTS = 1

# ---------------------------------------------------------------------------
# Orçamentos de performance
# ---------------------------------------------------------------------------
# Alvo: 60 FPS a 1080p em GPU integrada moderna. Estes números são teto, não meta.

TARGET_FPS = 60
FRAME_BUDGET_MS = 16.6
BUDGET: dict[str, int] = {
    # Renegociados na fase 10, e é a segunda vez que estes dois números mudam — vale dizer
    # o que eles passaram a conter. O teto de 200 foi escrito na fase 1, quando o projeto
    # era um chão cinza. A praça hoje tem 42 prédios em 24 nós de desenho, 16 pedaços de
    # terreno, o espalhamento do vale, a vida ambiente e **vinte corpos animados**. Um
    # corpo com sombra custa três draw calls, não um: a cor mais uma passada por cascata.
    #
    # O que foi cortado antes de renegociar: sombra de fumaça, do cachorro e do martelo
    # (233 -> 229), duas chaminés a menos, e sombra de habitante além de NPC_SHADOW_RADIUS
    # (229 -> 227 na praça, 155 -> 141 em campo aberto). O que sobra só sairia tirando a
    # sombra de quem está no meio da praça, e gente sem sombra no chão lê como decalque.
    "draw_calls_city":        240,    # pior ângulo dentro da cidade
    "draw_calls_wilderness":  150,
    "active_npcs":            40,     # acima disso, simulação abstrata
    "unique_materials":       16,     # materiais distintos visíveis por cena
    "visible_tris":           150_000,
    "shadow_casting_lights":  5,      # 1 direcional + 4 pontuais
    "multimesh_instances":    20_000,
    "physics_bodies_active":  120,
    "audio_voices":           32,
}

# Teto de triângulos por categoria de malha gerada. Os geradores validam contra isto.
TRI_BUDGET: dict[str, int] = {
    # Renegociado nesta fase: 900 → 2100, junto com TERRAIN_CHUNK_CELLS de 16 para 32.
    # O teto antigo servia a pedaços de 64 m, que davam 64 pedaços no vale — 64 draw calls
    # de terreno, medidos, contra um teto de 140 para o mundo inteiro. Pedaço de 128 m dá
    # 16, com o mesmo total de triângulos: o que se perde é granularidade de culling, e num
    # vale de 512 m em que quase tudo está no campo de visão ela não estava pagando por si.
    "terrain_chunk":    2_100,
    "building_small":   300,
    "building_large":   900,
    "city_block":       4_000,
    "prop":             120,
    "tree":             250,
    "rock":             60,
    "foliage_instance": 24,
    "npc":              900,
    "player":           1_200,
    "weapon":           150,
    "stage_ground":     1_000,
}

# Teto de triângulos por *peça* da fábrica do Blender, por categoria do manifesto.
# `make assets` reprova a peça que estourar — não avisa, reprova.
KIT_TRI_BUDGET: dict[str, int] = {
    "architecture": 300,
    "props":        300,
    "nature":       300,
    "tree":         600,   # árvore tem direito ao dobro: a copa custa
}

# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

RENDERING_METHOD = "forward_plus"
VIEWPORT_WIDTH = 1920
VIEWPORT_HEIGHT = 1080
MSAA_3D = 1                     # 0=off, 1=2x, 2=4x, 3=8x
SCREEN_SPACE_AA = 0             # 0=off, 1=FXAA
USE_DEBANDING = True
USE_OCCLUSION_CULLING = True
SHADOW_FILTER_QUALITY = 3       # 0=hard .. 5=ultra; 3 = "soft medium"
DIRECTIONAL_SHADOW_SIZE = 4096
POSITIONAL_SHADOW_ATLAS_SIZE = 2048
SHADOW_MAX_DISTANCE = 120.0
# Cascatas da sombra direcional: "orthogonal" (1), "2_splits" ou "4_splits".
# Cada cascata redesenha todo caster dentro de SHADOW_MAX_DISTANCE, então o número de
# cascatas multiplica draw calls de sombra. O padrão do Godot são 4; num vale low poly com
# 120 m de alcance, 2 cascatas de 2048² não mostram diferença que o olho pegue e devolvem
# a folga que faltava no orçamento — medido: 141 draw calls com 4 cascatas, 90 com 2, para
# um teto de 140. Era a sombra, e não a geometria, que estava estourando o orçamento.
SHADOW_DIRECTIONAL_SPLITS = "2_splits"
PHYSICS_TICKS_PER_SECOND = 60
VSYNC_MODE = 1                  # 0=off, 1=on

# Ambiente do estágio.
# A névoa foi calibrada para o estágio plano, onde nada ficava a mais de 60 m. Num vale de
# 512 m, 0,004 punha 53% de névoa a 200 m e a borda oposta sumia num copo de leite — o
# oposto de "névoa leve". A 0,0015 a encosta em frente ainda tem cor, a borda do vale a
# 250 m recebe cerca de um terço de névoa, e a profundidade continua legível.
FOG_DENSITY = 0.0015
FOG_SKY_AFFECT = 0.0
AMBIENT_SKY_CONTRIBUTION = 0.7
TONEMAP_MODE = "filmic"         # linear | reinhardt | filmic | aces
TONEMAP_WHITE = 6.0
SKY_CURVE = 0.12
SUN_ANGLE_MAX = 18.0
SUN_CURVE = 0.2

# ---------------------------------------------------------------------------
# Física
# ---------------------------------------------------------------------------
# Ordem define o bit: índice 0 -> layer 1.

def layer_mask(*names: str) -> int:
    """Máscara de bits das camadas de física citadas pelo nome.

    Escrever `collision_layer = 2` num `.tscn` gerado funcionaria e seria exatamente o
    tipo de número que ninguém consegue conferir depois. Aqui o gerador diz `player` e o
    bit sai de `PHYSICS_LAYERS` — reordenar as camadas continua correto sozinho.
    """
    mask = 0
    for name in names:
        if name not in PHYSICS_LAYERS:
            raise KeyError(f"Camada de física inexistente: {name!r}")
        mask |= 1 << PHYSICS_LAYERS.index(name)
    return mask


PHYSICS_LAYERS: tuple[str, ...] = (
    "world",
    "player",
    "npc",
    "interactable",
    "trigger",
)

# ---------------------------------------------------------------------------
# Áudio
# ---------------------------------------------------------------------------
# (nome, volume_db, envia_para). "Master" é sempre o barramento 0.

AUDIO_BUSES: tuple[tuple[str, float, str], ...] = (
    ("Master",   0.0, ""),
    ("Music",   -4.0, "Master"),
    ("SFX",      0.0, "Master"),
    ("Ambience", -6.0, "Master"),
    ("UI",       0.0, "Master"),
)
AUDIO_BUS_LAYOUT_PATH = "res://assets/generated/audio/default_bus_layout.tres"
SFX_POOL_SIZE = 16
SFX_3D_POOL_SIZE = 24
MUSIC_CROSSFADE_SEC = 1.5
SILENT_DB = -60.0
SFX_3D_MAX_DISTANCE = 40.0
SFX_3D_UNIT_SIZE = 6.0
AUDIO_SAMPLE_RATE = 44_100
MUSIC_PLAYER_COUNT = 2          # dois players fixos alternando no crossfade

# Tom de calibração gerado por `make audio`. É sinal de teste do pipeline de áudio,
# não conteúdo de jogo: serve para conferir roteamento de barramento e volume.
CALIBRATION_TONE_HZ = 1000.0
CALIBRATION_TONE_SEC = 0.5
CALIBRATION_TONE_DB = -12.0
CALIBRATION_TONE_FADE_MS = 5.0

# ---------------------------------------------------------------------------
# Tempo de jogo
# ---------------------------------------------------------------------------

HOURS_PER_DAY = 24
MINUTES_PER_HOUR = 60
SECONDS_PER_GAME_DAY = 1200.0   # 20 min reais = 1 dia no jogo
START_HOUR = 8.0
# Limites de período do dia, em horas: (nome, hora_inicial).
DAY_PERIODS: tuple[tuple[str, int], ...] = (
    ("NIGHT", 0),
    ("DAWN", 5),
    ("MORNING", 7),
    ("AFTERNOON", 12),
    ("DUSK", 17),
    ("NIGHT_END", 20),
)

# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------
# Keycodes *físicos* do Godot 4 — WASD continua em WASD num teclado AZERTY.

KEY = {
    "W": 87, "A": 65, "S": 83, "D": 68, "E": 69,
    "SPACE": 32, "SHIFT": 4194325, "ESCAPE": 4194305, "TAB": 4194306,
    "F12": 4194343,
}
# Botões de gamepad (Godot JoyButton).
JOY = {"A": 0, "B": 1, "X": 2, "Y": 3, "START": 6, "L3": 7, "R3": 8}
# Botões de mouse.
MOUSE = {"WHEEL_UP": 4, "WHEEL_DOWN": 5}

# ação -> {deadzone, keys, joy_buttons, joy_axis:(eixo, valor), mouse_buttons}
INPUT_MAP: dict[str, dict] = {
    "move_forward":          {"keys": ["W"], "joy_axis": (1, -1.0), "deadzone": 0.2},
    "move_back":             {"keys": ["S"], "joy_axis": (1, 1.0), "deadzone": 0.2},
    "move_left":             {"keys": ["A"], "joy_axis": (0, -1.0), "deadzone": 0.2},
    "move_right":            {"keys": ["D"], "joy_axis": (0, 1.0), "deadzone": 0.2},
    "sprint":                {"keys": ["SHIFT"], "joy_buttons": ["L3"]},
    "jump":                  {"keys": ["SPACE"], "joy_buttons": ["A"]},
    "interact":              {"keys": ["E"], "joy_buttons": ["X"]},
    "pause":                 {"keys": ["ESCAPE"], "joy_buttons": ["START"]},
    "camera_toggle_capture": {"keys": ["TAB"]},
    "camera_zoom_in":        {"mouse_buttons": ["WHEEL_UP"]},
    "camera_zoom_out":       {"mouse_buttons": ["WHEEL_DOWN"]},
    "debug_screenshot":      {"keys": ["F12"]},
}

# A câmera pelo mouse não é ação: é InputEventMouseMotion lido pelo controlador.
MOUSE_SENSITIVITY = 0.12        # graus por pixel
MOUSE_SENSITIVITY_MIN = 0.02
MOUSE_SENSITIVITY_MAX = 1.0

# ---------------------------------------------------------------------------
# Humanoides
# ---------------------------------------------------------------------------
# Corpo montado por seções empilhadas: cada altura-chave abaixo é uma fração da altura
# total, então mudar `height` reescala a figura inteira sem quebrar proporção. Larguras
# também são fração da altura — é o que faz um sujeito de 1,50 m parecer um sujeito
# baixo, e não uma miniatura de um alto.

CHARACTER_DIR = "assets/generated/characters"
CHARACTER_SEED = 4409
CHARACTER_RING_SIDES = 6        # lados da seção de tronco e membros

# Alturas-chave, em fração da altura total (chão = 0, topo da cabeça = 1).
BODY_LEVELS: dict[str, float] = {
    "ankle":      0.055,
    "knee":       0.280,
    "hip":        0.520,
    "waist":      0.620,
    "chest":      0.740,
    "shoulder":   0.820,
    "neck_base":  0.855,
    "head_base":  0.875,
    "head_top":   1.000,
}

# Semi-larguras e semi-profundidades, em fração da altura total.
BODY_WIDTHS: dict[str, float] = {
    "hip_x":        0.098, "hip_z":      0.062,
    "waist_x":      0.085, "waist_z":    0.055,
    "chest_x":      0.103, "chest_z":    0.060,
    "shoulder_x":   0.125, "shoulder_z": 0.062,
    "neck_x":       0.035, "neck_z":     0.035,
    "head_x":       0.062, "head_z":     0.070,
    "upper_arm":    0.032, "fore_arm":   0.026,
    "thigh":        0.055, "calf":       0.041,
    "hand_x":       0.030, "hand_y":     0.022, "hand_z":  0.075,
    "foot_x":       0.045, "foot_y":     0.115, "foot_z":  0.030,
}

# Postura: inclinação em graus de tronco, pescoço e joelho. É o que separa um guarda de
# um velho de um batedor sem tocar em nenhuma outra medida.
POSTURES: dict[str, dict[str, float]] = {
    "ereto":    {"spine": 0.0,  "neck": 0.0,  "knee": 0.0,  "shoulder_drop": 0.0},
    "curvado":  {"spine": 14.0, "neck": 10.0, "knee": 4.0,  "shoulder_drop": 0.022},
    "agil":     {"spine": 6.0,  "neck": -4.0, "knee": 9.0,  "shoulder_drop": -0.008},
}

EAR_TYPES = ("humana", "pontuda", "larga")
HAIR_TYPES = ("nenhum", "curto", "longo", "rabo")
CLOTHING_TYPES = ("nenhuma", "tunica", "capuz", "avental", "capa", "armadura_leve")

# Esqueleto no padrão Mixamo, que é o que o retargeting do Godot entende. Só os nomes e a
# contagem moram aqui: as *posições* de cada osso saem das medidas do corpo, em
# `gen_characters.build_skeleton`, para o osso nascer dentro da carne mesmo quando a
# postura inclina o tronco.
MIXAMO_BONES: tuple[str, ...] = ("Hips", "Spine", "Chest", "Neck", "Head") + tuple(
    f"{side}{bone}"
    for side in ("Left", "Right")
    for bone in ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "Toe")
)

BONE_MAX_INFLUENCES = 2         # limite de ossos por vértice
BONE_WEIGHT_POWER = 3.0         # expoente da queda por distância
BONE_INFLUENCE_RADIUS = 0.30    # fração da altura; além disso o osso não pesa

# Pose de teste: rotação local em graus por osso. Existe para provar que a malha não
# rasga fora da T-pose — é o único jeito de flagrar skinning ruim antes da animação.
TEST_POSE: dict[str, tuple[float, float, float]] = {
    "LeftArm":       (0.0, 0.0, -55.0),
    "RightArm":      (0.0, 0.0, 55.0),
    "LeftForeArm":   (-65.0, 0.0, 0.0),
    "RightForeArm":  (-65.0, 0.0, 0.0),
    "LeftUpLeg":     (-35.0, 0.0, 0.0),
    "LeftLeg":       (55.0, 0.0, 0.0),
    "RightUpLeg":    (18.0, 0.0, 0.0),
    "Spine":         (-8.0, 12.0, 0.0),
    "Neck":          (6.0, -14.0, 0.0),
    "Head":          (0.0, 10.0, 0.0),
}

# Quanto uma aresta pode esticar na pose de teste antes de contar como rasgo. Um rig com
# 2 influências estica um pouco na dobra; 2x é folga suficiente para o normal e apertada
# o bastante para pegar vértice preso no osso errado.
CHARACTER_MAX_EDGE_STRETCH = 2.0

# Meia volta aplicada ao personagem no catálogo. O kit tem a frente em -Y, que é o lado
# para onde a câmera de preview olha; o humanoide tem de olhar para +Y no Blender para
# nascer virado para -Z no Godot, que é a frente da engine. Sem isto o catálogo mostraria
# quatro vistas da nuca.
CHARACTER_PREVIEW_SPIN = 180.0

# Elenco gerado por `make characters`. A primeira coluna é o nome do arquivo; o resto são
# os parâmetros que mudam a silhueta. Duas entradas existem só para o critério de aceite:
# `prova_alto` e `prova_baixo` diferem apenas em altura e largura de ombros.
CHARACTER_ROSTER: tuple[dict, ...] = (
    {"name": "aldeao",      "height": 1.72, "shoulders": 1.00, "leg_ratio": 1.00,
     "torso": 1.00, "head": 1.00, "posture": "ereto",   "beard": False,
     "ears": "humana",  "hair": "curto", "clothing": "tunica"},
    {"name": "guarda",      "height": 1.84, "shoulders": 1.18, "leg_ratio": 1.02,
     "torso": 1.15, "head": 0.96, "posture": "ereto",   "beard": True,
     "ears": "humana",  "hair": "curto", "clothing": "armadura_leve"},
    {"name": "ferreiro",    "height": 1.70, "shoulders": 1.26, "leg_ratio": 0.94,
     "torso": 1.22, "head": 1.02, "posture": "ereto",   "beard": True,
     "ears": "humana",  "hair": "nenhum", "clothing": "avental"},
    {"name": "anciao",      "height": 1.62, "shoulders": 0.90, "leg_ratio": 0.96,
     "torso": 0.94, "head": 1.06, "posture": "curvado", "beard": True,
     "ears": "larga",   "hair": "longo", "clothing": "capuz"},
    {"name": "batedor",     "height": 1.75, "shoulders": 0.96, "leg_ratio": 1.08,
     "torso": 0.92, "head": 0.98, "posture": "agil",    "beard": False,
     "ears": "pontuda", "hair": "rabo",  "clothing": "capa"},
    {"name": "prova_baixo", "height": 1.45, "shoulders": 0.80, "leg_ratio": 1.00,
     "torso": 1.00, "head": 1.00, "posture": "ereto",   "beard": False,
     "ears": "humana",  "hair": "curto", "clothing": "nenhuma"},
    {"name": "prova_alto",  "height": 2.05, "shoulders": 1.35, "leg_ratio": 1.00,
     "torso": 1.00, "head": 1.00, "posture": "ereto",   "beard": False,
     "ears": "humana",  "hair": "curto", "clothing": "nenhuma"},
)

# ---------------------------------------------------------------------------
# Vale: terreno, estrada, vegetação e navegação
# ---------------------------------------------------------------------------
# O vale inteiro sai de uma seed. Não há heightmap em disco, não há mapa desenhado: a
# altura de cada ponto é função do ruído, e o resto — cor, estrada, vegetação, navegação —
# é função da altura. Trocar a seed troca o vale; trocar um número daqui muda todos os
# vales de uma vez.

TERRAIN_SIZE = 512.0            # m de lado. O "~500 x 500" do escopo, em potência de dois
TERRAIN_CELL = 4.0              # m por célula do heightmap
TERRAIN_CHUNK_CELLS = 32        # células por lado de um pedaço de malha (128 m)
TERRAIN_HEIGHT = 46.0           # amplitude total do relevo, em metros

# Ruído em camadas. A base dá as montanhas; o detalhe quebra a silhueta lisa que o ruído
# fractal puro produz e que faz todo terreno procedural parecer o mesmo terreno.
TERRAIN_BASE_FREQUENCY = 0.0016
TERRAIN_BASE_OCTAVES = 5
TERRAIN_BASE_LACUNARITY = 2.05
TERRAIN_BASE_GAIN = 0.47
TERRAIN_DETAIL_FREQUENCY = 0.011
TERRAIN_DETAIL_OCTAVES = 3
TERRAIN_DETAIL_WEIGHT = 0.10    # fração da amplitude que cabe ao detalhe
# Expoente aplicado à altura normalizada. Acima de 1 aprofunda os fundos de vale e deixa
# os picos escassos — é o que separa "vale" de "colina ondulada por toda parte".
TERRAIN_VALLEY_POWER = 1.55
# Borda: o relevo sobe nas quatro margens para fechar o vale, em vez de terminar num
# penhasco reto. Fração do meio-lado onde a subida começa.
TERRAIN_RIM_START = 0.62
TERRAIN_RIM_HEIGHT = 0.55       # fração de TERRAIN_HEIGHT somada na borda extrema

# Erosão térmica simplificada: material acima do ângulo de talude escorrega para o vizinho
# mais baixo. Não é hidráulica — não há água nem sedimento — mas é o que corta as encostas
# impossíveis do ruído cru e dá aos vales o fundo plano que a estrada e a cidade precisam.
TERRAIN_EROSION_PASSES = 6
TERRAIN_TALUS = 0.62            # diferença máxima de altura entre vizinhos, em metros
TERRAIN_EROSION_RATE = 0.45     # fração do excesso movida por passe

# A planície onde a cidade vai nascer (fase 8). Um disco achatado com transição suave.
TERRAIN_PLAIN_CENTER = (0.0, 0.0)   # em metros, relativo ao centro do vale
# Quanto a praça desliza do centro conforme a seed. Não é enfeite: com a praça sempre no
# meio, uma boa parte do mapa fica idêntica entre duas seeds — a planície e a transição em
# volta dela somam 230 m dos 512 —, e a prova de "vales diferentes" mede justamente isso.
# Além do número, o centro fixo é o tipo de simetria que entrega o mundo como procedural.
TERRAIN_PLAIN_WANDER = 84.0
TERRAIN_PLAIN_RADIUS = 62.0
TERRAIN_PLAIN_FALLOFF = 54.0    # m de transição entre a planície e o relevo
TERRAIN_PLAIN_FLATNESS = 0.94   # 1,0 = mesa perfeita; abaixo disso sobra ondulação

# Cor por altitude e inclinação. O declive manda: encosta íngreme é rocha em qualquer
# altura, porque é onde a terra não se segura.
TERRAIN_SLOPE_ROCK = 0.60       # seno da inclinação a partir do qual vira rocha
TERRAIN_SLOPE_DIRT = 0.34       # ... e a partir do qual a grama dá lugar à terra
TERRAIN_ALTITUDE_ROCK = 0.72    # fração da altura total onde a rocha domina de qualquer jeito
TERRAIN_ALTITUDE_GRASS = 0.46   # acima disto a grama começa a rarear
TERRAIN_TONE_JITTER = 0.05      # variação de tom por triângulo, para a malha não ficar chapada

# --- Estrada ----------------------------------------------------------------
# A estrada é a única coisa do vale desenhada por uma curva, e não por ruído. Ela liga a
# borda à planície da cidade, e o terreno se ajusta a ela — não o contrário.

ROAD_WIDTH = 6.0                # m de leito plano
ROAD_SHOULDER = 5.0             # m de transição de cada lado, onde o corte se dissolve
ROAD_MAX_SLOPE = 0.11           # tangente máxima: ~6,3°, o que uma carroça sobe
# Folga entre a inclinação de *projeto* e a de *aceite*. O nivelamento trabalha no perfil
# da curva, amostrado a cada 1,2 m; quem tem de respeitar o limite é o terreno, que é uma
# grade de 4 m. Um vértice do leito herda a altura do eixo no ponto em que se projeta, e a
# leitura bilinear entre quatro vértices que se projetam em lugares diferentes não devolve
# a rampa exata — devolve uma média que dobra onde o perfil dobra. Medido: com projeto a
# 0,11 o terreno chegava a 0,125. Projetar abaixo do limite é o que uma estrada de verdade
# faz; o aceite continua sendo cobrado no relevo construído, em ROAD_MAX_SLOPE.
ROAD_GRADE_MARGIN = 0.03
ROAD_SAMPLES = 220              # pontos amostrados ao longo da curva
ROAD_SMOOTH_PASSES = 40         # suavizações do perfil de altura antes de cravar a estrada
ROAD_CONTROL_POINTS = 5         # vértices do traçado, entre a borda e a praça
ROAD_WANDER = 78.0              # m de desvio lateral máximo por vértice — o que torce a estrada
ROAD_ENTRY_MARGIN = 12.0        # m para dentro da borda onde a estrada começa
# Raio de achatamento total, em células do heightmap. O leito tem 6 m e a célula tem 4:
# achatar só a largura do leito deixa os cantos da célula meio puxados, e a interpolação
# bilinear ao longo do eixo mistura vértice cravado com vértice solto. O resultado é uma
# estrada que respeita a inclinação no papel e a estoura no terreno — foi medido em 0,126
# contra um limite de 0,11. Um raio de célula e meia garante os quatro cantos cravados.
ROAD_BED_CELLS = 1.5

# --- Vegetação e rochas ------------------------------------------------------
# Espalhamento determinístico: mesma seed, mesmas árvores. Cada tipo tem a sua própria
# sequência, então acrescentar um tipo novo não desloca os que já existiam.
#
# (peça do kit, densidade por hectare, inclinação máxima, faixa de altitude, escala)
SCATTER_TILE = 128.0            # m de lado do bloco de espalhamento; a LOD é por bloco
SCATTER_JITTER = 0.42           # deslocamento aleatório dentro da célula, como fração
SCATTER_TYPES: tuple[dict, ...] = (
    {"part": "tree_broadleaf", "density": 34.0, "max_slope": 0.42,
     "altitude": (0.04, 0.55), "scale": (0.85, 1.35), "far": True},
    {"part": "tree_conifer",   "density": 26.0, "max_slope": 0.52,
     "altitude": (0.34, 0.86), "scale": (0.80, 1.40), "far": True},
    {"part": "bush",           "density": 55.0, "max_slope": 0.46,
     "altitude": (0.02, 0.62), "scale": (0.70, 1.30), "far": False},
    {"part": "grass_tuft",     "density": 210.0, "max_slope": 0.30,
     "altitude": (0.00, 0.50), "scale": (0.60, 1.20), "far": False},
    {"part": "rock",           "density": 30.0, "max_slope": 0.95,
     "altitude": (0.10, 1.00), "scale": (0.70, 1.80), "far": True},
)
# Distância livre da estrada onde nada nasce. Meio leito mais o acostamento já bastaria;
# a folga extra evita arbusto encostado na roda.
SCATTER_ROAD_CLEARANCE = 3.0    # m além do acostamento

# Três faixas de LOD, em metros, e a sobreposição em que uma dissolve na outra. A faixa
# mais distante só recebe os tipos marcados com `far`: tufo de grama a 200 m é um pixel
# que custa um draw call.
SCATTER_LOD_BANDS = (92.0, 210.0, 340.0)
SCATTER_LOD_FADE = 18.0         # m de sobreposição entre faixas
SCATTER_LOD_THINNING = (1.0, 0.62, 0.28)  # fração das instâncias em cada faixa
# Proxy de LOD: prisma que substitui a peça de perto. Lados por faixa — a peça original
# tem dezenas de triângulos, o proxy tem oito.
SCATTER_PROXY_SIDES = (0, 6, 4) # 0 = usa a malha de verdade
SCATTER_PROXY_TAPER = 0.35      # quanto o topo do prisma afina, como fração da base

# --- Navegação ---------------------------------------------------------------
# A malha de navegação é assada ao fim da geração, numa thread. Assar 512 m em célula fina
# travaria o jogo por segundos no `_ready`; a célula grossa perde detalhe que um NPC
# andando em terreno aberto não usa.
NAV_CELL_SIZE = 1.0             # m
NAV_CELL_HEIGHT = 0.4
NAV_AGENT_RADIUS = 0.5
NAV_AGENT_HEIGHT = 1.9
NAV_AGENT_MAX_CLIMB = 0.5
NAV_AGENT_MAX_SLOPE_DEG = 42.0
NAV_GROUP = "navsource"         # grupo que o assador varre

# --- Prova do vale -----------------------------------------------------------
VALLEY_DIR = "docs/valley"
# Duas seeds que a prova compara. Se os dois vales saírem parecidos, a seed não está
# chegando ao relevo e o critério de aceite falhou — mesmo com os dois jogáveis.
VALLEY_SEEDS = (123, 777)
VALLEY_MIN_DIFFERENCE = 0.12    # diferença média de altura, como fração da amplitude
VALLEY_MIN_WALKABLE = 0.35      # fração do vale que a navegação tem de cobrir

# ---------------------------------------------------------------------------
# Jogador e câmera
# ---------------------------------------------------------------------------
# Sensação de peso é o assunto desta seção inteira. Um corpo que atinge a velocidade
# máxima no primeiro frame e para no frame seguinte controla-se com precisão e não
# convence ninguém; a aceleração e a desaceleração separadas são o que dá massa. Desacelerar
# mais rápido do que acelerar (16 contra 12) é deliberado: soltar o comando tem de ser
# nítido, senão o personagem parece patinar no gelo toda vez que se quer parar numa marca.

PLAYER_SCENE = "scenes/player/player.tscn"
PLAYER_BODY = "aldeao"          # qual corpo do elenco o jogador veste

PLAYER_WALK_SPEED = 3.2         # m/s
PLAYER_RUN_SPEED = 6.0          # m/s
PLAYER_ACCELERATION = 12.0      # m/s²
PLAYER_DECELERATION = 16.0      # m/s²
PLAYER_AIR_CONTROL = 0.35       # fração da aceleração enquanto sem apoio
PLAYER_TURN_SPEED = 12.0        # 1/s, do `lerp_angle` que gira o corpo

# Salto em altura, e não em velocidade inicial: `v = sqrt(2·g·h)` deixa o número em
# metros, que é o que dá para conferir olhando um degrau.
PLAYER_JUMP_HEIGHT = 1.15       # m
PLAYER_GRAVITY = 22.0           # m/s², bem acima dos 9,8 reais — salto de jogo é seco
PLAYER_FALL_GRAVITY_SCALE = 1.4 # cair mais rápido que subir tira a flutuação do topo
PLAYER_TERMINAL_VELOCITY = 32.0 # m/s

# Coyote time: o intervalo em que ainda dá para pular *depois* de sair da beirada. Sem
# ele, todo pulo na quina falha e o jogador culpa o controle — corretamente.
PLAYER_COYOTE_TIME = 0.12       # s
# O espelho do coyote: apertar pulo pouco antes de tocar o chão continua valendo.
PLAYER_JUMP_BUFFER = 0.12       # s

PLAYER_CAPSULE_RADIUS = 0.30    # m
PLAYER_FLOOR_MAX_ANGLE_DEG = 46.0
PLAYER_FLOOR_SNAP = 0.35        # m — mantém o corpo colado em rampa e degrau
PLAYER_INTERACT_RANGE = 2.4     # m à frente onde o braço procura algo

# --- Câmera de terceira pessoa ----------------------------------------------
# O braço é um `SpringArm3D`: ele encurta sozinho quando há geometria entre o alvo e a
# câmera. É por isso que a câmera não atravessa parede — não é tuning, é o nó fazendo
# uma varredura de forma a cada frame.

CAMERA_DISTANCE = 4.2           # m, comprimento em repouso do braço
CAMERA_DISTANCE_MIN = 1.8
CAMERA_DISTANCE_MAX = 7.5
CAMERA_ZOOM_STEP = 0.45         # m por clique da roda
CAMERA_TARGET_HEIGHT = 0.86     # fração da altura do corpo: onde o braço se prende
CAMERA_PITCH_MIN_DEG = -60.0    # olhando para baixo
CAMERA_PITCH_MAX_DEG = 35.0     # olhando para cima
CAMERA_START_PITCH_DEG = -12.0
CAMERA_SPRING_MARGIN = 0.28     # folga da varredura, para a câmera não encostar na parede
# Raio da esfera que o braço varre. **Não é decorativo**: com `shape` nulo o SpringArm3D
# do Godot cai num raycast, e nesse caminho a `margin` é ignorada — medido. A lente para
# exatamente na superfície do muro e o near plane entra na pedra. Com esfera, o que
# mantém a lente afastada é este raio.
CAMERA_PROBE_RADIUS = 0.22      # m

# Atraso posicional: a plataforma segue o corpo com mola, e não presa a ele. Preso, todo
# tranco do personagem vira tranco de câmera; com atraso, o corpo se move dentro do
# quadro e o movimento ganha peso.
CAMERA_FOLLOW_LAG = 11.0        # 1/s
CAMERA_FOV = 70.0
CAMERA_FOV_RUN_BONUS = 4.0      # graus a mais correndo — o clássico "está mais rápido"
CAMERA_FOV_LERP = 4.5           # 1/s

# Tranco de aterrissagem. Curto e vertical: sacudir a câmera em três eixos por um pulo
# normal enjoa em dois minutos de jogo.
CAMERA_SHAKE_AMPLITUDE = 0.055  # m no impacto mais forte
CAMERA_SHAKE_DECAY = 7.0        # 1/s
CAMERA_SHAKE_FREQUENCY = 24.0   # Hz
CAMERA_SHAKE_MIN_FALL = 5.0     # m/s de queda abaixo dos quais não há tranco
CAMERA_SHAKE_MAX_FALL = 18.0    # m/s onde o tranco satura

# --- Prova do controlador ----------------------------------------------------
PLAYTEST_DIR = "docs/player"
# Raio do anel de muros. Tem de caber a corrida inteira: a 6 m/s por 1,4 s o corpo anda
# 8,4 m, e um anel menor faria a prova medir a parede em vez da velocidade.
PLAYTEST_ARENA_RADIUS = 14.0    # m
PLAYTEST_LEDGE_HEIGHT = 1.6     # m, a plataforma de onde se testa o coyote time
# Onde a plataforma fica, em múltiplos do grid. Fora do eixo de caminhada de propósito:
# na primeira versão ela ficava à frente, o corpo esbarrava nela no meio da tomada e a
# prova reportou 0,00 m/s de velocidade — parecia um controlador quebrado.
PLAYTEST_LEDGE_OFFSET = (3.0, 0.0)
PLAYTEST_SETTLE_FRAMES = 12
PLAYTEST_TOLERANCE = 0.08       # fração: quanto a velocidade medida pode ficar do alvo

# ---------------------------------------------------------------------------
# Locomoção procedural
# ---------------------------------------------------------------------------
# Não haverá animação autoral neste projeto. O movimento nasce em runtime, de IK de duas
# juntas e de senos — que é a escolha estética coerente com o resto: uma malha de 470
# triângulos com silhueta dura não pede interpolação sutil de curva, pede leitura clara a
# 10 m de distância.
#
# O que separa isto de "tocar um clipe" é que **a fase do passo é função da velocidade
# real**, e não de um relógio. Um ciclo com relógio próprio patina no chão assim que a
# velocidade muda; aqui o pé fica cravado numa posição de mundo durante o apoio e a
# passada é o que se ajusta. Escorregar deixa de ser um bug para virar impossível por
# construção.

GAIT_DIR = "resources/gaits"

# Abaixo deste módulo de velocidade o personagem está parado, não andando devagar.
GAIT_MOVE_THRESHOLD = 0.06        # m/s
# Velocidade em que a marcha vira corrida. Não muda o código, só a mistura de amplitudes.
GAIT_RUN_SPEED = 2.9              # m/s
# Comprimento de passo como fração da altura do quadril, e como ele cresce com a
# velocidade. Passo curto e cadência alta parece nervoso; o contrário parece flutuar.
GAIT_STRIDE_HIP_FACTOR = 0.62
GAIT_STRIDE_SPEED_FACTOR = 0.22   # metros de passada extra por m/s
GAIT_STRIDE_MIN = 0.28            # m
GAIT_STRIDE_MAX = 2.10            # m
# Fração do ciclo em que um pé está no chão. 0,5 é corrida (há instante sem apoio);
# acima disso é caminhada, com os dois pés no chão na transição.
GAIT_DUTY_WALK = 0.62
GAIT_DUTY_RUN = 0.46
# Suavização da velocidade medida e do desaparecimento do ciclo ao parar, em 1/s.
GAIT_SPEED_SMOOTHING = 9.0
GAIT_BLEND_SPEED = 5.0
# Alcance do raycast de apoio, para cima e para baixo a partir do pé previsto.
GAIT_GROUND_PROBE_UP = 0.9        # m
GAIT_GROUND_PROBE_DOWN = 2.2      # m
# Quanto o tornozelo fica acima do ponto de contato. É a espessura do pé.
GAIT_ANKLE_HEIGHT = 0.055         # fração da altura do personagem

# Perfil de marcha por postura. A postura já existe no elenco — é o parâmetro por povo
# que faz um guarda erguido e um batedor ágil andarem diferente **sem uma linha de código
# específica**: o mesmo nó lê outro perfil. Ângulos em graus, alturas em fração da altura
# do personagem, tempos em segundos.
GAIT_PROFILES: dict[str, dict[str, float]] = {
    "ereto": {
        "stride_scale":     1.00,
        "cadence_scale":    1.00,
        "foot_lift":        0.075,
        "foot_lift_run":    0.135,
        "hip_bounce":       0.016,
        "hip_sway_deg":     4.0,
        "hip_drop_deg":     3.5,
        "torso_lean_deg":   3.0,
        "torso_twist_deg":  5.0,
        "arm_swing_deg":    26.0,
        "arm_bias_deg":     2.0,
        "elbow_bend_deg":   14.0,
        "head_bob":         0.008,
        "knee_forward":     1.0,
    },
    "curvado": {
        "stride_scale":     0.78,
        "cadence_scale":    0.88,
        "foot_lift":        0.045,
        "foot_lift_run":    0.080,
        "hip_bounce":       0.010,
        "hip_sway_deg":     2.5,
        "hip_drop_deg":     5.0,
        "torso_lean_deg":   9.0,
        "torso_twist_deg":  2.5,
        "arm_swing_deg":    14.0,
        "arm_bias_deg":     16.0,
        "elbow_bend_deg":   30.0,
        "head_bob":         0.012,
        "knee_forward":     0.85,
    },
    "agil": {
        "stride_scale":     1.18,
        "cadence_scale":    1.12,
        "foot_lift":        0.105,
        "foot_lift_run":    0.185,
        "hip_bounce":       0.024,
        "hip_sway_deg":     6.5,
        "hip_drop_deg":     2.5,
        "torso_lean_deg":   6.0,
        "torso_twist_deg":  9.0,
        "arm_swing_deg":    38.0,
        "arm_bias_deg":     -3.0,
        "elbow_bend_deg":   22.0,
        "head_bob":         0.014,
        "knee_forward":     1.15,
    },
}

# Braços nascem em T-pose e precisam descer antes de qualquer coisa. Este é o ângulo do
# ombro entre a T e o braço ao longo do corpo — sem ele o personagem andaria de braços
# abertos, que é a pose do arquivo, não a do jogo.
ARM_REST_DROP_DEG = 76.0
ARM_OUTWARD_DEG = 7.0             # afasta o braço do tronco, para não atravessar a roupa
FOOT_SWING_TILT_DEG = 14.0        # ponta do pé sobe no balanço
JUMP_TUCK_LEG_FACTOR = 0.62       # fração do comprimento da perna com o joelho recolhido
SIT_FOOT_FORWARD = 0.24           # fração da altura: onde os pés ficam ao sentar

# --- Camadas aditivas --------------------------------------------------------
# Somam sobre a locomoção em vez de substituí-la. Respiração some quando o corpo anda
# (quem anda já sobe e desce), o olhar não; o bob de câmera só existe correndo.
BREATH_FREQUENCY = 0.24           # Hz — cerca de 14 respirações por minuto
BREATH_CHEST_DEG = 1.6
BREATH_RISE = 0.006               # fração da altura
LOOK_MAX_HEAD_YAW_DEG = 62.0      # além disto o tronco vira junto
LOOK_MAX_HEAD_PITCH_DEG = 34.0
LOOK_TORSO_SHARE = 0.55           # quanto do excesso de guinada vai para o tronco
LOOK_SMOOTHING = 7.0              # 1/s
CAMERA_BOB_AMPLITUDE = 0.028      # m, no pico da corrida
CAMERA_BOB_SIDE = 0.014           # m
CAMERA_BOB_HARMONIC = 2.0         # a cabeça sobe duas vezes por ciclo, uma por pé

# --- Estados extras ----------------------------------------------------------
# O pulo é quatro fases, e cada uma tem uma leitura própria: agachar carrega, impulso
# estende, recolher tira as pernas do caminho, aterrissar absorve. Sem a fase de agachar
# o salto parece teletransporte.
JUMP_CROUCH_TIME = 0.13           # s
JUMP_CROUCH_DEPTH = 0.14          # fração da altura
JUMP_LAUNCH_TIME = 0.11
JUMP_LAUNCH_RISE = 0.05
JUMP_TUCK_DEG = 48.0              # joelho recolhido no ar
JUMP_LAND_TIME = 0.26
JUMP_LAND_DEPTH = 0.17
INTERACT_REACH_TIME = 0.22        # s para o braço chegar ao alvo
INTERACT_HOLD_TIME = 0.35
INTERACT_RETURN_TIME = 0.30
SIT_HIP_DROP = 0.26               # fração da altura
SIT_HIP_TIME = 0.4                # s de transição
SIT_KNEE_DEG = 84.0
SIT_TORSO_DEG = 6.0
CARRY_ARM_DEG = 62.0              # braços à frente
CARRY_ELBOW_DEG = 74.0
CARRY_TORSO_LEAN_DEG = -4.0       # peso na frente pede tronco para trás
CARRY_BLEND_TIME = 0.35

# --- Prova visual da locomoção ----------------------------------------------
ANIM_DIR = "docs/anim"
ANIM_FRAME_WIDTH = 300
ANIM_FRAME_HEIGHT = 460
ANIM_STRIP_COLUMNS = 8            # quadros por tira
ANIM_STEP_FRAMES = 7              # quadros de simulação entre dois quadros gravados
ANIM_SETTLE_FRAMES = 6            # quadros descartados no começo, até a marcha engatar
ANIM_CAMERA_FOV = 34.0
ANIM_CAMERA_HEIGHT = 0.62         # fração da altura do personagem
ANIM_CAMERA_DISTANCE = 4.4        # m
# De lado, e do lado *iluminado*. O sol do estágio vem de -X: enquadrar de +X, que foi a
# primeira escolha, deu oito silhuetas pretas contra o céu — legíveis como silhueta e
# inúteis para ver joelho, cotovelo e pé.
ANIM_CAMERA_YAW_DEG = 200.0
ANIM_WALK_SPEED = 1.5             # m/s
ANIM_RUN_SPEED = 4.2              # m/s
ANIM_JUMP_SPEED = 1.2             # m/s de avanço durante o salto
ANIM_FOOT_SLIDE_LIMIT = 0.02      # m — acima disto o pé patina e a prova reprova
# Personagem de cada tira, e as duas posturas que a tira comparativa põe lado a lado.
ANIM_SUBJECT = "aldeao"
# Altura assumida quando não há um corpo medido para enquadrar. Só o caminho de erro.
PREVIEW_FIGURE_HEIGHT_FALLBACK = 1.75
ANIM_GAIT_COMPARISON = ("guarda", "batedor", "anciao")
# Fase em que a tira comparativa congela os três corpos. 0,5 é onde as pernas estão mais
# abertas — um pé acabou de pousar à frente e o outro está prestes a sair de trás. Parar
# no mesmo *quadro* não serviria: cadências diferentes põem cada um numa fase diferente,
# e a comparação mediria o relógio em vez da marcha.
ANIM_COMPARISON_PHASE = 0.5
# Quadros de simulação que cada estado extra recebe antes de ser fotografado. Sentar e
# carregar têm transição contínua; fotografar no primeiro quadro pegaria o meio dela.
ANIM_STATE_FRAMES = 40
# Onde o braço vai buscar, na tira de estados: à frente, na altura do peito, do lado
# direito. Em fração da altura do personagem.
ANIM_INTERACT_REACH = (0.22, 0.72, -0.34)
# Para onde a cabeça olha na tira de estados. Bem para o lado, de propósito: é o caso em
# que o pescoço estoura o limite e o tronco tem de virar junto.
ANIM_LOOK_AT = (-2.4, 1.5, 1.2)

# ---------------------------------------------------------------------------
# Olhos: renderização de catálogo e capturas
# ---------------------------------------------------------------------------
# Esta fase existe porque quem escreve o gerador não vê o que ele gera.

DOCS_DIR = "docs"
PREVIEW_IMAGE_DIR = "docs/assets"        # PNG por peça (derivado, no .gitignore)
PREVIEW_SHEET = "docs/assets.html"       # contact sheet (derivado)
SHOTS_DIR = "docs/shots"                 # capturas do Godot (derivado)
BENCH_JSON = "docs/bench.json"           # última medição (derivado)
BENCH_HISTORY = "docs/bench_history.csv" # VERSIONADO: uma linha por execução

PREVIEW_SIZE = 512                       # lado do PNG de cada peça
PREVIEW_SAMPLES = 24                     # amostras do Cycles; cor flat não pede mais
PREVIEW_MARGIN = 1.25                    # folga em volta da peça, como fator
PREVIEW_FIGURE_HEIGHT = 1.75             # altura da figura de escala, em metros
PREVIEW_FIGURE_GAP = 0.55                # espaço entre a figura e a grade de ângulos
PREVIEW_BACKGROUND = "#5A5A5A"           # cinza médio neutro

# Os quatro ângulos. Cada um é uma rotação aplicada à *cópia* da peça; a câmera é uma
# só, ortográfica, olhando ao longo de -Y. Rotacionar a peça em vez de mover a câmera
# permite uma renderização por peça em vez de quatro.
PREVIEW_ANGLES: tuple[tuple[str, tuple[float, float, float]], ...] = (
    ("frente",  (0.0, 0.0, 0.0)),
    ("3/4",     (0.0, 0.0, -45.0)),
    ("lateral", (0.0, 0.0, -90.0)),
    # +90 e não -90: a câmera olha ao longo de +Y, então girar -90 em X manda o topo da
    # peça para *longe* dela e o que se vê é a sola. O quadrante dizia "topo" e mostrava
    # o fundo desde a fase 3 — apareceu ao olhar o primeiro humanoide de cima e encontrar
    # o vão escuro da bainha da túnica onde devia estar o cabelo.
    ("topo",    (90.0, 0.0, 0.0)),
)

# Luz neutra de três pontos: principal, preenchimento e contra. Ângulos em graus
# (elevação, azimute) e energia relativa.
PREVIEW_LIGHTS: tuple[tuple[str, float, float, float], ...] = (
    ("key",  40.0, -35.0, 4.0),
    ("fill", 15.0,  55.0, 1.6),
    ("rim",  55.0, 160.0, 2.4),
)

# Pontos de câmera nomeados para `tools/godot_shot.gd`: (nome, posição, alvo).
SHOT_POINTS: tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...] = (
    ("vale",    (0.0, 88.0, 190.0),  (0.0, 8.0, -20.0)),
    ("praca",   (0.0, 16.0, 62.0),   (0.0, 4.0, 0.0)),
    ("estrada", (-40.0, 12.0, 120.0), (0.0, 4.0, 40.0)),
    ("encosta", (150.0, 46.0, 150.0), (40.0, 10.0, 40.0)),
)

# Rota fixa do benchmark: a câmera percorre estes pontos em ordem, em ciclo. Fixa de
# propósito — medir um passeio diferente a cada execução tornaria o histórico ruído.
# A rota atravessa o vale, e não mais o estágio vazio: sai da planície da cidade, sobe a
# encosta e volta. Alturas são um piso — `bench.gd` levanta a câmera até o relevo, porque
# uma rota fixa num vale que muda com a seed enterraria a câmera na montanha.
BENCH_ROUTE: tuple[tuple[float, float, float], ...] = (
    (0.0, 3.0, 0.0),
    (90.0, 3.0, 70.0),
    (170.0, 3.0, -60.0),
    (-40.0, 3.0, -170.0),
    (-160.0, 3.0, 40.0),
)
BENCH_ROUTE_SECONDS = 14.0               # duração de uma volta completa
BENCH_CAMERA_CLEARANCE = 2.4             # m acima do relevo em que a câmera do bench voa
BENCH_LOW_PERCENTILE = 1.0               # "1% low": pior 1% dos frames

# ---------------------------------------------------------------------------
# Cidade
# ---------------------------------------------------------------------------
# A cidade nasce da mesma seed do vale, em etapas: sítio -> muralha -> ruas -> lotes ->
# prédios -> props -> interiores. Cada etapa lê só o que a anterior produziu, e é por isso
# que dá para provar cada uma sozinha.
#
# Escala humana é o critério de aceite que mais depende destes números. A régua: uma
# pessoa tem 1,75 m, um andar tem WALL_HEIGHT (3 m), um módulo de parede tem GRID_SIZE
# (2 m). Uma rua de 5 m é larga o bastante para duas carroças e estreita o bastante para
# a fachada oposta preencher o campo de visão — que é o que faz uma cidade parecer cidade
# e não um estacionamento com prédios.

# --- Sítio -------------------------------------------------------------------
# A cidade não escolhe o centro da planície de olhos fechados: ela mede. O terreno da
# fase 4 já tem uma planície, mas ela desliza com a seed e a estrada chega por um lado
# diferente a cada vale — cravar o centro entregaria cidades encostadas na montanha.

CITY_SITE_CANDIDATES = 96       # sítios sorteados e pontuados dentro da planície
CITY_SITE_PROBES = 40           # amostras de relevo por candidato
CITY_SITE_MAX_SLOPE = 0.22      # inclinação média acima da qual o sítio é recusado
CITY_SITE_ROAD_REACH = 110.0    # m: além disto o sítio está longe demais da estrada
CITY_SITE_ROAD_MIN = 14.0       # m: e mais perto que isto a muralha comeria a estrada
CITY_SITE_SEARCH_RADIUS = 96.0  # m de raio em volta da planície onde se procura

# --- Muralha -----------------------------------------------------------------
# Polígono, não círculo: um anel perfeito lê como cerca de arena. O número ímpar de lados
# e o ruído no raio tiram a simetria que o olho reconhece na primeira volta de câmera.

CITY_RADIUS = 68.0              # m, raio médio da muralha
CITY_WALL_SIDES = 11            # lados do polígono (ímpar: nenhum lado tem oposto igual)
CITY_RADIUS_JITTER = 0.11       # fração do raio que cada vértice pode variar
CITY_WALL_ANGLE_JITTER = 0.32   # fração do passo angular que cada vértice pode deslizar
CITY_WALL_MODULE = 2.0          # m por peça de muralha — o módulo do kit
CITY_WALL_MARGIN = 5.0          # m livres entre a muralha e o primeiro quarteirão
CITY_TOWER_EVERY = 3            # torre a cada N vértices da muralha
CITY_GATE_WIDTH = 6.0           # m do vão do portão (largura da peça wall_gate)

# --- Terraplenagem -----------------------------------------------------------
# O sítio é achatado antes de qualquer coisa ser construída. Uma cidade em ladeira exigiria
# escada em cada porta, e o kit não tem essa peça — a fase 7 é que traria.

CITY_TERRACE_FALLOFF = 26.0     # m de transição entre o platô e o relevo original
CITY_TERRACE_FLATNESS = 0.96    # 1.0 achata por completo; menos deixa respiro

# --- Ruas --------------------------------------------------------------------
# A rede tem três níveis, e a diferença de largura entre eles é o que dá hierarquia
# legível: a via principal do portão à praça, as ruas da subdivisão e os becos.

CITY_PLAZA_RADIUS = 14.0        # m — a praça, onde nada é construído
CITY_MAIN_STREET_WIDTH = 7.0
CITY_STREET_WIDTH = 5.0
CITY_ALLEY_WIDTH = 3.2
CITY_MAIN_STREET_BENDS = 4      # vértices intermediários da via principal
CITY_MAIN_STREET_JITTER = 7.0   # m de desvio lateral por vértice — a via não é reta
# Um quarteirão para de se dividir abaixo do dobro disto, ou seja, por volta de 32 m —
# fundo o bastante para duas fileiras de lotes costas com costas, que é o desenho de quadra
# que faz cada fachada olhar a sua própria rua. Baixá-lo multiplica cortes, e cada corte é
# uma rua: a 12 m as ruas passaram a ocupar mais da metade do terreno dentro da muralha.
CITY_BLOCK_MIN = 16.0           # m: abaixo disto o quarteirão não se divide mais
CITY_SPLIT_JITTER = 0.17        # fração do lado em que o corte pode cair fora do meio
# Profundidade da subdivisão. É um teto de segurança, não o que decide o tamanho do
# quarteirão — quem decide é CITY_BLOCK_MIN, e a recursão para sozinha antes daqui.
# Subir isto para sete foi tentador e errado: cada corte é uma rua, e sete níveis puseram
# 40 ruas num raio de 49 m. Os quarteirões cobriam 29% do terreno útil e o resto era
# calçamento — uma cidade não é 70% rua.
CITY_SPLIT_MAX_DEPTH = 5        # profundidade máxima da subdivisão recursiva
CITY_GRID_JITTER_DEG = 9.0      # inclinação aleatória da malha inteira, em graus

# --- Lotes -------------------------------------------------------------------

CITY_LOT_MIN = 6.0              # m de testada mínima
CITY_LOT_MAX = 12.0             # m de testada máxima
CITY_LOT_DEPTH_MAX = 13.0       # m: mais fundo que isto o quarteirão vira duas fileiras
CITY_LOT_SETBACK = 0.6          # m entre a fachada e a rua
CITY_LOT_GAP = 0.5              # m entre lotes vizinhos
CITY_LOT_EMPTY_CHANCE = 0.17    # fração de lotes que viram pátio, não prédio

# --- Prédios -----------------------------------------------------------------
# Fachada em módulos de 2 m; profundidade em módulos de 4 m, que é o que os telhados do
# kit ladrilham (roof_gable cobre 2x4 m, roof_hip cobre 4x4 m). Sair dessa malha deixaria
# o telhado sobrando ou faltando, e não há peça de remate.

CITY_BUILDING_MODULE = 2.0      # m — passo da fachada
CITY_BUILDING_DEPTH_STEP = 4.0  # m — passo da profundidade, imposto pelo telhado
CITY_FLOOR_HEIGHT = 3.0         # m por andar (a altura da peça wall)
CITY_WINDOW_CHANCE = 0.44       # fração dos módulos de fachada que viram janela
CITY_TINT_JITTER = 0.09         # variação de tom por prédio, via cor de instância
CITY_HIP_ROOF_CHANCE = 0.35     # chance de telhado de quatro águas quando cabe
# O telhado desce um pouco dentro da parede. Assentado exatamente na cota do topo, a base
# da peça de telhado e o topo da peça de parede ficam coplanares, e o renderizador não tem
# como decidir qual está na frente: a fachada inteira sai listrada na linha do beiral.
# Oito centímetros bastam para uma peça entrar na outra sem abrir fresta visível.
CITY_ROOF_DROP = 0.08           # m que o telhado afunda na parede

# Tipos de prédio. `weight` é o peso do sorteio; `plaza_bias` puxa o tipo para perto da
# praça (1.0 = só no centro, 0.0 = indiferente, negativo = periferia); `floors` é o
# intervalo de andares; `width`/`depth` são intervalos em módulos.
CITY_BUILDING_TYPES: tuple[dict, ...] = (
    {"name": "casa",    "weight": 62.0, "plaza_bias":  0.0,
     "floors": (1, 2), "width": (2, 4), "depth": (1, 2), "marker": "casa"},
    {"name": "taverna", "weight":  6.0, "plaza_bias":  0.9,
     "floors": (2, 2), "width": (4, 5), "depth": (2, 2), "marker": "taverna"},
    {"name": "ferraria", "weight": 6.0, "plaza_bias":  0.5,
     "floors": (1, 1), "width": (3, 4), "depth": (2, 2), "marker": "ferraria"},
    {"name": "celeiro", "weight": 14.0, "plaza_bias": -0.7,
     "floors": (1, 1), "width": (4, 5), "depth": (2, 2), "marker": ""},
    {"name": "torre",   "weight":  4.0, "plaza_bias":  0.3,
     "floors": (3, 4), "width": (2, 2), "depth": (1, 1), "marker": ""},
)

# --- Props -------------------------------------------------------------------
# Densidade por hectare, como no espalhamento do vale — a mesma unidade em todo o projeto.

CITY_PLAZA_STALLS = 5           # bancas na praça: viram mercado_01..05
CITY_PLAZA_STALL_RING = 9.5     # m do centro da praça em que as bancas se dispõem
CITY_LANTERN_SPACING = 17.0     # m entre lanternas ao longo das ruas
CITY_PROP_DENSITY = 46.0        # props soltos por hectare de rua
CITY_YARD_PROPS = 4             # props por lote vazio (pátio)
CITY_CLOTHESLINE_CHANCE = 0.3   # chance de um beco estreito ganhar varal
CITY_CLOTHESLINE_HEIGHT = 3.4   # m — acima da cabeça, abaixo do beiral
CITY_CLOTHESLINE_MAX_SPAN = 6.0 # m: mais que isto e a corda voa sem apoio

# --- Interiores --------------------------------------------------------------
# Dois interiores de verdade (taverna e ferraria) e cartas escuras nos demais. A carta é
# um plano atrás da janela: a 3 m de distância ela lê como sombra de cômodo, e custa dois
# triângulos contra os ~200 de um interior real.

# Chão batido da cidade. O terreno da fase 4 pinta tudo de pasto, e pasto dentro da
# muralha lê como acampamento em campo aberto: o que faz uma cidade parecer pisada é o
# chão dela ter perdido a grama. A transição acompanha a terraplenagem, senão o platô teria
# uma borda de cor onde não tem borda de relevo.
CITY_GROUND_BLEND = 0.82        # quanto o chão da cidade vira terra batida, no miolo

CITY_INTERIOR_TYPES = ("taverna", "ferraria")
CITY_INTERIOR_CARD_INSET = 0.22 # m atrás do plano da fachada
CITY_INTERIOR_CARD_DARKEN = 0.72 # quanto a carta escurece a cor da parede
CITY_INTERIOR_PROPS = 7         # props por interior real

# --- Prova da cidade ---------------------------------------------------------

CITY_DIR = "docs/shots/city"
CITY_SHOT_WIDTH = 1600          # px das capturas da cidade
CITY_SHOT_HEIGHT = 900
CITY_SEEDS = (123, 4242, 90210)  # três seeds, três cidades plausíveis
CITY_DOOR_REACH = 2.5           # m: distância máxima da porta até a malha de navegação
CITY_MIN_BUILDINGS = 24         # menos que isto não é cidade, é acampamento
CITY_MAX_DEAD_ENDS = 0          # becos sem saída não intencionais tolerados

# Pontos de câmera das capturas da cidade. Cada um é (nome, marcador, distância, altura,
# pitch): a câmera é posicionada em relação a um `Marker3D` gerado, e não em coordenadas
# absolutas — a cidade muda de lugar com a seed, e um ponto fixo fotografaria o campo.
CITY_SHOT_POINTS: tuple[tuple[str, str, float, float, float], ...] = (
    ("praca",     "praca",    16.0,  4.0, -12.0),
    ("portao",    "portao",   19.0,  5.0, -10.0),
    ("taverna",   "taverna",  11.0,  3.2, -8.0),
    ("ferraria",  "ferraria", 11.0,  3.2, -8.0),
    ("rua",       "casa_04",  10.0,  2.4, -6.0),
    ("muralha",   "praca",    92.0, 46.0, -26.0),
)

# ---------------------------------------------------------------------------
# População
# ---------------------------------------------------------------------------
# A cidade da fase 8 entregou `Marker3D` nomeados; as rotinas referenciam esses nomes e
# por isso funcionam em qualquer seed. Nenhuma rotina conhece uma coordenada.
#
# O relógio já existe desde a fase 1 e anuncia `EventBus.hour_changed`. Rotina de NPC
# reage a esse sinal — nunca lê o relógio por quadro. Vinte NPCs consultando a hora a
# 60 Hz seriam 1200 leituras por segundo para responder a uma pergunta que muda 24 vezes
# por dia.

NPC_SCENE = "scenes/npc/npc.tscn"
NPC_DIR = "resources/schedules"
NPC_COUNT = 20                  # habitantes com rotina
NPC_SEED_OFFSET = 91193         # semente derivada da seed do mundo

# Velocidades. Um NPC anda mais devagar que o jogador de propósito: um habitante que
# cruza a praça na velocidade do herói lê como se estivesse fugindo de alguma coisa.
NPC_WALK_SPEED = 1.9            # m/s
NPC_HURRY_SPEED = 3.1           # m/s — só quando a rotina está atrasada
NPC_TURN_RATE = 7.0             # rad/s do giro para a direção de marcha
NPC_ARRIVE_RADIUS = 1.1         # m: mais perto que isto e o destino está cumprido
NPC_REPATH_SECONDS = 0.9        # intervalo entre recálculos de caminho
NPC_STUCK_SECONDS = 6.0         # sem avançar por mais que isto = destravar
NPC_STUCK_PROGRESS = 0.35       # m de avanço mínimo dentro da janela acima

# Dispersão em torno do alvo. Vinte NPCs mirando o mesmo `Marker3D` se empilhariam num
# ponto; cada um recebe um deslocamento fixo, sorteado uma vez, e assim a praça tem gente
# espalhada em vez de uma pilha.
NPC_TARGET_SPREAD = 3.4         # m de raio em volta do marcador

# Ociosidade. O que impede a praça de virar um formigueiro sincronizado é cada NPC ter o
# seu próprio ritmo: os intervalos são sorteados por NPC, não compartilhados.
NPC_IDLE_MIN = 2.5              # s parado antes de decidir a próxima coisa
NPC_IDLE_MAX = 9.0
NPC_WANDER_CHANCE = 0.45        # chance de dar uma volta em vez de ficar parado
NPC_WANDER_RADIUS = 7.0         # m do passeio curto em torno do posto
NPC_WORK_BOB = 0.45             # amplitude do gesto de trabalho, em fração do passo

# Percepção e reação. Barata por construção: uma `Area3D` por NPC, sem varredura por
# quadro e sem pathfinding de perseguição.
NPC_SENSE_RADIUS = 6.5          # m do raio de percepção
NPC_LOOK_SECONDS = 2.6          # s que o olhar acompanha quem passou
NPC_SPEAK_COOLDOWN = 26.0       # s entre falas do mesmo NPC
NPC_SPEAK_CHANCE = 0.35         # chance de falar ao perceber alguém
NPC_SPEAK_SECONDS = 3.2         # s que a fala fica no ar
NPC_SPEAK_HEIGHT = 0.35         # m acima da cabeça
NPC_REACT_SECONDS = 1.4         # s de duração do estado REACT

# Falas por arquétipo. Texto flutuante, não diálogo: a fase 11 é que traz árvore de
# conversa. Cada fala é curta de propósito — o que se lê a 6 m é uma linha, não um
# parágrafo.
NPC_LINES: dict[str, tuple[str, ...]] = {
    "comerciante": ("Bom preço hoje!", "Leve dois.", "Fresco da manhã.", "Olha a feira!"),
    "artesao":     ("Trabalho firme.", "Volte mais tarde.", "Ferro quente.", "Quase pronto."),
    "crianca":     ("Corre!", "Me pega!", "Olha isso!", "Vamos ali."),
}

# Orçamento de simulação. Além do raio, o NPC perde física e navegação e passa a avançar
# por interpolação na própria rota — some da tela e custa quase nada. O teto de ativos é
# o de `BUDGET["active_npcs"]`, e o raio é o que decide quem entra nele.
# Além deste raio o habitante deixa de projetar sombra. Cada caster é redesenhado uma vez
# por cascata, então um corpo custa três draw calls e não um — e vinte deles custam 60. A
# sombra de uma pessoa a 30 m é um punhado de pixels; cortá-la é a diferença entre a praça
# caber no orçamento e não caber. Medido: 229 draw calls com todas as sombras, 189 sem as
# distantes.
NPC_SHADOW_RADIUS = 26.0        # m: além disto, o habitante não projeta sombra
NPC_ACTIVE_RADIUS = 60.0        # m: além disto, simulação barata
NPC_ACTIVE_HYSTERESIS = 8.0     # m de folga para não piscar na fronteira
NPC_DIRECTOR_HZ = 4.0           # vezes por segundo que o diretor reavalia quem é ativo
NPC_ABSTRACT_SPEED = 1.9        # m/s do avanço abstrato — o mesmo passo, sem física

# Arquétipos. `body` é sorteado entre os corpos listados; `home`/`work` são nomes de
# marcador com `%` para o índice, resolvidos contra a cidade da fase 8.
NPC_ARCHETYPES: tuple[dict, ...] = (
    {"name": "comerciante", "share": 0.40, "bodies": ("aldeao", "anciao"),
     "work": "mercado", "schedule": "comerciante"},
    {"name": "artesao", "share": 0.35, "bodies": ("ferreiro", "aldeao"),
     "work": "ferraria", "schedule": "artesao"},
    {"name": "crianca", "share": 0.25, "bodies": ("batedor",),
     "work": "poco", "schedule": "crianca"},
)

# Rotinas. Cada bloco é (hora_inicio, hora_fim, marcador, estado). O marcador `casa` é
# resolvido para a casa daquele NPC, e `trabalho` para o posto dele — é o que permite três
# rotinas servirem a vinte habitantes sem uma rotina por pessoa.
#
# Os blocos cobrem as 24 horas sem buraco. Um buraco deixaria o NPC sem ordem e ele
# congelaria no lugar às 3 da manhã, que é o tipo de defeito que só aparece depois de
# alguém deixar o jogo rodando.
NPC_SCHEDULES: dict[str, tuple[tuple[float, float, str, str], ...]] = {
    "comerciante": (
        (6.0,  7.5,  "casa",      "WORK"),
        (7.5,  12.0, "trabalho",  "WORK"),
        (12.0, 13.5, "poco",      "SOCIALIZE"),
        (13.5, 18.0, "trabalho",  "WORK"),
        (18.0, 21.0, "praca",     "SOCIALIZE"),
        (21.0, 30.0, "casa",      "SLEEP"),
    ),
    "artesao": (
        (5.5,  7.0,  "casa",      "WORK"),
        (7.0,  13.0, "trabalho",  "WORK"),
        (13.0, 14.0, "praca",     "SOCIALIZE"),
        (14.0, 19.0, "trabalho",  "WORK"),
        (19.0, 22.0, "taverna",   "SOCIALIZE"),
        (22.0, 29.5, "casa",      "SLEEP"),
    ),
    "crianca": (
        (7.0,  9.0,  "casa",      "IDLE"),
        (9.0,  12.0, "praca",     "SOCIALIZE"),
        (12.0, 13.0, "casa",      "IDLE"),
        (13.0, 17.5, "portao",    "SOCIALIZE"),
        (17.5, 20.0, "praca",     "SOCIALIZE"),
        (20.0, 31.0, "casa",      "SLEEP"),
    ),
}

# --- Vida ambiente -----------------------------------------------------------
# Tudo isto é movimento sem IA: nada aqui decide nada, nada consulta o mundo, nada custa
# um caminho. É o que faz a cidade parecer viva mesmo quando os vinte habitantes estão
# todos parados nos seus postos.

# Quatro chaminés, e não seis. Cada sistema de partículas é um draw call, e a diferença
# entre quatro e seis colunas de fumaça numa cidade de 42 prédios não se lê de lugar nenhum.
AMBIENT_SMOKE_CHIMNEYS = 4      # chaminés com fumaça, escolhidas entre os prédios
AMBIENT_SMOKE_PARTICLES = 14    # partículas por chaminé — poucas e grandes, low poly
AMBIENT_SMOKE_LIFETIME = 5.5    # s
AMBIENT_SMOKE_RISE = 1.4        # m/s de subida
AMBIENT_SMOKE_SCALE = 0.34      # m da partícula

AMBIENT_BIRD_FLOCKS = 2         # rotas de pássaros em Path3D
AMBIENT_BIRDS_PER_FLOCK = 5
AMBIENT_BIRD_HEIGHT = 17.0      # m acima do platô
AMBIENT_BIRD_RADIUS = 42.0      # m do raio da volta
AMBIENT_BIRD_SECONDS = 34.0     # s por volta completa
AMBIENT_BIRD_SPREAD = 6.0       # m de dispersão dentro do bando

AMBIENT_LEAF_COUNT = 90         # folhas caindo na cidade inteira
AMBIENT_LEAF_LIFETIME = 9.0
AMBIENT_LEAF_FALL = 0.7         # m/s
AMBIENT_LEAF_SCALE = 0.13

AMBIENT_WIND_SPEED = 1.6        # ciclos por segundo do balanço do varal
AMBIENT_WIND_SWAY_DEG = 7.0     # amplitude do balanço, em graus

AMBIENT_DOG_SPEED = 2.4         # m/s — o cachorro anda mais rápido que a gente
AMBIENT_DOG_PAUSE = 2.0         # s parado em cada ponto da ronda
AMBIENT_DOG_STOPS = 5           # pontos da ronda

AMBIENT_HAMMER_PERIOD = 1.15    # s entre marteladas da ferraria
AMBIENT_HAMMER_LIFT = 0.42      # m que o martelo sobe

# --- Prova da população ------------------------------------------------------

POPULATION_DIR = "docs/population"
POPULATION_SECONDS = 180.0      # 3 minutos de praça, como pede o critério
POPULATION_SAMPLE_HZ = 2.0      # amostras por segundo do rastro de cada NPC
POPULATION_MIN_MOVERS = 0.5     # fração dos NPCs que tem de se mover em cada janela
POPULATION_WINDOW = 20.0        # s da janela em que se cobra movimento
# Fração mínima das amostras que tem de cair em terreno novo. É a medida anti-repetição:
# quem anda para a frente pisa em célula nova o tempo todo; quem repete o mesmo trecho
# satura e para de gerar novidade sem parar de se mexer.
#
# O limiar sai dos casos degenerados, e não de gosto. Com 360 amostras por habitante numa
# célula de GRID_SIZE: parado dá 1/360 = 0,003; andando de um lado para o outro numa linha
# de três metros dá cerca de 0,006; andando sem repetir daria perto de 0,5. Medido nesta
# cidade: 0,10, ou seja, dez vezes o pior caso degenerado — um habitante que trabalha no
# posto e se desloca entre postos. O limiar fica no meio, longe dos dois extremos.
POPULATION_MIN_NOVELTY = 0.05
POPULATION_MAX_STUCK = 0        # NPCs entalados tolerados
POPULATION_MAX_CLIPPING = 0     # NPCs dentro de parede tolerados

# ---------------------------------------------------------------------------
# Geração
# ---------------------------------------------------------------------------

WORLD_SEED = 20250107           # muda o mundo inteiro; determinístico
GENERATED_DIR = "res://assets/generated"
SCREENSHOT_DIR = "user://screenshots"
BENCH_WARMUP_FRAMES = 30
BENCH_SAMPLE_FRAMES = 240
SCREENSHOT_WAIT_FRAMES = 10

# ---------------------------------------------------------------------------
# Utilidades de conversão (usadas pelos geradores, não são "parâmetros")
# ---------------------------------------------------------------------------


def hex_to_rgb(hex_color: str) -> tuple[float, float, float]:
    """'#6B563C' -> (0.419608, 0.337255, 0.235294)."""
    value = hex_color.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"Cor hex inválida: {hex_color!r}")
    return tuple(round(int(value[i:i + 2], 16) / 255.0, 6) for i in (0, 2, 4))  # type: ignore[return-value]


def color_literal(hex_color: str, alpha: float = 1.0) -> str:
    """'#6B563C' -> 'Color(0.419608, 0.337255, 0.235294, 1)'."""
    r, g, b = hex_to_rgb(hex_color)
    return f"Color({r}, {g}, {b}, {num(alpha)})"


def num(value: float) -> str:
    """Formata float sem cauda inútil, mantendo-o reconhecível como float no Godot."""
    if value == int(value):
        return str(int(value))
    return repr(round(value, 6))


# Ordem estável das cores. A fábrica de assets guarda um índice por face (BMesh só
# aceita camadas numéricas), e este é o dicionário que traduz índice de volta em nome.
PALETTE_KEYS: tuple[str, ...] = tuple(PALETTE)


def palette_index(key: str) -> int:
    """Índice estável de uma cor da paleta. Falha alto: cor inventada é bug, não estilo."""
    try:
        return PALETTE_KEYS.index(key)
    except ValueError:
        raise KeyError(
            f"Cor {key!r} não existe na paleta. Disponíveis: {', '.join(PALETTE_KEYS)}"
        ) from None


def srgb_to_linear(channel: float) -> float:
    """sRGB -> linear. glTF define COLOR_0 em espaço linear; a paleta é escrita em sRGB."""
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def linear_rgba(key: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    """Cor da paleta pronta para virar vertex color num .glb."""
    r, g, b = hex_to_rgb(PALETTE[key])
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


def period_names() -> tuple[str, ...]:
    """Nomes únicos de período, na ordem do enum (NIGHT_END é só um limite superior)."""
    return tuple(name for name, _ in DAY_PERIODS if name != "NIGHT_END")
