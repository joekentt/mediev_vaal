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
    "draw_calls_city":        200,    # pior ângulo dentro da cidade
    "draw_calls_wilderness":  140,
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
