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
    "terrain_chunk":    900,
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
PHYSICS_TICKS_PER_SECOND = 60
VSYNC_MODE = 1                  # 0=off, 1=on

# Ambiente do estágio.
FOG_DENSITY = 0.004
FOG_SKY_AFFECT = 0.0
AMBIENT_SKY_CONTRIBUTION = 0.7
TONEMAP_MODE = "aces"           # linear | reinhardt | filmic | aces
TONEMAP_WHITE = 6.0
SKY_CURVE = 0.12
SUN_ANGLE_MAX = 18.0
SUN_CURVE = 0.2

# ---------------------------------------------------------------------------
# Física
# ---------------------------------------------------------------------------
# Ordem define o bit: índice 0 -> layer 1.

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
    ("topo",    (-90.0, 0.0, 0.0)),
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
    ("wide",    (0.0, 12.0, 26.0),  (0.0, 0.0, 0.0)),
    ("eye",     (0.0, 1.7, 9.0),    (0.0, 1.6, 0.0)),
    ("top",     (0.0, 40.0, 0.1),   (0.0, 0.0, 0.0)),
    ("horizon", (18.0, 2.2, 18.0),  (0.0, 1.0, 0.0)),
)

# Rota fixa do benchmark: a câmera percorre estes pontos em ordem, em ciclo. Fixa de
# propósito — medir um passeio diferente a cada execução tornaria o histórico ruído.
BENCH_ROUTE: tuple[tuple[float, float, float], ...] = (
    (0.0, 1.7, 20.0),
    (20.0, 1.7, 20.0),
    (20.0, 8.0, -20.0),
    (-20.0, 3.0, -20.0),
    (-20.0, 1.7, 20.0),
)
BENCH_ROUTE_SECONDS = 8.0                # duração de uma volta completa
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
