# ARQUIVO GERADO — NÃO EDITE À MÃO.
# Gerado por: tools/gen_params.py
# Fonte:      tools/params.py
# Regenerar:  make all

## Constantes do projeto — arquivo único de números mágicos.
##
## Espelho gerado de `tools/params.py`. Nenhum outro .gd deve conter um literal
## numérico com significado: se você precisa de um número, ele nasce no .py e chega
## aqui por `make params`. `tools/verify.py` reprova o build se isso for violado.
##
## Uso: `Params.GRID_SIZE`, `Params.color(&"stone")`, `Params.budget(&"active_npcs")`.
class_name Params
extends RefCounted

# --- Identidade --------------------------------------------------------------

const PROJECT_NAME: String = "Mediev Vaal"
const MAIN_SCENE: String = "res://scenes/world/main.tscn"
const GENERATED_DIR: String = "res://assets/generated"
const SCREENSHOT_DIR: String = "user://screenshots"

# --- Paleta ------------------------------------------------------------------

## Cor flat por nome. Sem textura de imagem em lugar nenhum do projeto.
const PALETTE: Dictionary = {
	&"earth":           Color(0.419608, 0.337255, 0.235294, 1),
	&"earth_dark":      Color(0.290196, 0.227451, 0.156863, 1),
	&"clay":            Color(0.541176, 0.368627, 0.231373, 1),
	&"sand":            Color(0.760784, 0.658824, 0.470588, 1),
	&"stone_light":     Color(0.54902, 0.529412, 0.482353, 1),
	&"stone":           Color(0.431373, 0.411765, 0.368627, 1),
	&"stone_dark":      Color(0.290196, 0.27451, 0.243137, 1),
	&"slate":           Color(0.243137, 0.262745, 0.290196, 1),
	&"grass":           Color(0.352941, 0.478431, 0.235294, 1),
	&"grass_dark":      Color(0.247059, 0.352941, 0.164706, 1),
	&"foliage":         Color(0.290196, 0.419608, 0.2, 1),
	&"foliage_deep":    Color(0.184314, 0.290196, 0.180392, 1),
	&"moss":            Color(0.419608, 0.478431, 0.219608, 1),
	&"bark":            Color(0.309804, 0.227451, 0.156863, 1),
	&"bark_light":      Color(0.419608, 0.317647, 0.219608, 1),
	&"wood":            Color(0.419608, 0.290196, 0.184314, 1),
	&"wood_dark":       Color(0.290196, 0.2, 0.121569, 1),
	&"thatch":          Color(0.717647, 0.568627, 0.247059, 1),
	&"plaster":         Color(0.839216, 0.780392, 0.658824, 1),
	&"roof_tile":       Color(0.54902, 0.290196, 0.196078, 1),
	&"iron":            Color(0.431373, 0.447059, 0.478431, 1),
	&"iron_dark":       Color(0.290196, 0.305882, 0.333333, 1),
	&"gold":            Color(0.788235, 0.635294, 0.32549, 1),
	&"cloth_red":       Color(0.54902, 0.227451, 0.180392, 1),
	&"cloth_blue":      Color(0.207843, 0.313725, 0.419608, 1),
	&"cloth_green":     Color(0.247059, 0.419608, 0.290196, 1),
	&"cloth_cream":     Color(0.839216, 0.780392, 0.658824, 1),
	&"water":           Color(0.243137, 0.419608, 0.470588, 1),
	&"water_deep":      Color(0.156863, 0.286275, 0.352941, 1),
	&"sky_zenith":      Color(0.305882, 0.486275, 0.682353, 1),
	&"sky_horizon":     Color(0.788235, 0.721569, 0.580392, 1),
	&"sun":             Color(1.0, 0.941176, 0.854902, 1),
	&"fog":             Color(0.729412, 0.686275, 0.584314, 1),
	&"ground_default":  Color(0.470588, 0.454902, 0.415686, 1),
	&"debug_magenta":   Color(1.0, 0.0, 0.666667, 1),
}

## Materiais compartilhados gerados em `assets/generated/materials/`.
const MATERIALS: Dictionary = {
	&"terrain":  {"color": &"grass", "roughness": 0.95, "metallic": 0},
	&"rock":     {"color": &"stone", "roughness": 0.9, "metallic": 0},
	&"wood":     {"color": &"wood", "roughness": 0.85, "metallic": 0},
	&"thatch":   {"color": &"thatch", "roughness": 1, "metallic": 0},
	&"plaster":  {"color": &"plaster", "roughness": 0.9, "metallic": 0},
	&"foliage":  {"color": &"foliage", "roughness": 1, "metallic": 0},
	&"metal":    {"color": &"iron", "roughness": 0.45, "metallic": 0.85},
	&"cloth":    {"color": &"cloth_cream", "roughness": 0.95, "metallic": 0},
	&"water":    {"color": &"water", "roughness": 0.15, "metallic": 0},
	&"ground":   {"color": &"ground_default", "roughness": 0.95, "metallic": 0},
	&"debug":    {"color": &"debug_magenta", "roughness": 1, "metallic": 0},
}

# --- Escala do mundo ---------------------------------------------------------

const GRID_SIZE: float = 2 ## Metros por célula. Tudo se alinha a isto.
const CHUNK_CELLS: int = 16
const CHUNK_SIZE: float = 32
const WORLD_RADIUS_CHUNKS: int = 8
const WALL_HEIGHT: float = 3
const FLOOR_HEIGHT: float = 3.5
const DOOR_WIDTH: float = 1.2
const DOOR_HEIGHT: float = 2.2
const STREET_WIDTH: float = 6

# --- Estágio (cena vazia da fase 1) ------------------------------------------

const STAGE_GROUND_SIZE: float = 200
const STAGE_CAMERA_HEIGHT: float = 2.5
const STAGE_CAMERA_DISTANCE: float = 8
const STAGE_CAMERA_PITCH_DEG: float = -12
const STAGE_CAMERA_FOV: float = 70
const STAGE_CAMERA_FAR: float = 300
const STAGE_SUN_PITCH_DEG: float = -50
const STAGE_SUN_YAW_DEG: float = -35
const STAGE_SUN_HEIGHT: float = 12
const STAGE_SUN_ENERGY: float = 1.1
const STAGE_GROUND_CELLS: int = 20
const STAGE_GROUND_TONE_JITTER: float = 0.04

# --- Orçamentos --------------------------------------------------------------

const TARGET_FPS: int = 60
const FRAME_BUDGET_MS: float = 16.6

## Tetos de cena. Não são metas: são o limite que reprova a fase.
const BUDGET: Dictionary = {
	&"draw_calls_city":        200,
	&"draw_calls_wilderness":  140,
	&"active_npcs":            40,
	&"unique_materials":       16,
	&"visible_tris":           150000,
	&"shadow_casting_lights":  5,
	&"multimesh_instances":    20000,
	&"physics_bodies_active":  120,
	&"audio_voices":           32,
}

## Teto de triângulos por categoria de malha gerada.
const TRI_BUDGET: Dictionary = {
	&"terrain_chunk":     900,
	&"building_small":    300,
	&"building_large":    900,
	&"city_block":        4000,
	&"prop":              120,
	&"tree":              250,
	&"rock":              60,
	&"foliage_instance":  24,
	&"npc":               900,
	&"player":            1200,
	&"weapon":            150,
	&"stage_ground":      1000,
}

# --- Render ------------------------------------------------------------------

const SHADOW_MAX_DISTANCE: float = 120
const FOG_DENSITY: float = 0.004
const FOG_SKY_AFFECT: float = 0
const AMBIENT_SKY_CONTRIBUTION: float = 0.7
const TONEMAP_MODE: String = "aces"
const TONEMAP_WHITE: float = 6
const SKY_CURVE: float = 0.12
const SUN_ANGLE_MAX: float = 18
const SUN_CURVE: float = 0.2

# --- Camadas de física -------------------------------------------------------

## Máscara da camada de física 1 (`world`).
const LAYER_WORLD: int = 1
## Máscara da camada de física 2 (`player`).
const LAYER_PLAYER: int = 2
## Máscara da camada de física 3 (`npc`).
const LAYER_NPC: int = 4
## Máscara da camada de física 4 (`interactable`).
const LAYER_INTERACTABLE: int = 8
## Máscara da camada de física 5 (`trigger`).
const LAYER_TRIGGER: int = 16

# --- Áudio -------------------------------------------------------------------

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_AMBIENCE: StringName = &"Ambience"
const BUS_UI: StringName = &"UI"
const SFX_POOL_SIZE: int = 16
const SFX_3D_POOL_SIZE: int = 24
const MUSIC_CROSSFADE_SEC: float = 1.5
const SILENT_DB: float = -60
const SFX_3D_MAX_DISTANCE: float = 40
const SFX_3D_UNIT_SIZE: float = 6
const MUSIC_PLAYER_COUNT: int = 2

# --- Tempo de jogo -----------------------------------------------------------

const HOURS_PER_DAY: int = 24
const MINUTES_PER_HOUR: int = 60
const SECONDS_PER_GAME_DAY: float = 1200
const START_HOUR: float = 8

## Períodos do dia, na ordem cronológica de um ciclo.
enum Period { NIGHT, DAWN, MORNING, AFTERNOON, DUSK }

## Hora em que cada período começa, exceto NIGHT (que fecha o ciclo).
const PERIOD_START_HOURS: Array[int] = [5, 7, 12, 17, 20]

# --- Entrada -----------------------------------------------------------------

const MOUSE_SENSITIVITY: float = 0.12
const MOUSE_SENSITIVITY_MIN: float = 0.02
const MOUSE_SENSITIVITY_MAX: float = 1

# --- Geração -----------------------------------------------------------------

const WORLD_SEED: int = 20250107
const BENCH_WARMUP_FRAMES: int = 30
const BENCH_SAMPLE_FRAMES: int = 240
const SCREENSHOT_WAIT_FRAMES: int = 10

# --- Olhos: capturas e benchmark ---------------------------------------------

## Onde `tools/godot_shot.gd` grava as capturas. Derivado: está no .gitignore.
const SHOTS_DIR: String = "res://docs/shots"
## Última medição de `tools/bench.gd`.
const BENCH_JSON: String = "res://docs/bench.json"
## Histórico acumulado, uma linha por execução. **Versionado** — é o que mostra regressão.
const BENCH_HISTORY: String = "res://docs/bench_history.csv"

## Pontos de câmera nomeados: [nome, posição, alvo].
const SHOT_POINTS: Array = [
	[&"wide", Vector3(0, 12, 26), Vector3(0, 0, 0)],
	[&"eye", Vector3(0, 1.7, 9), Vector3(0, 1.6, 0)],
	[&"top", Vector3(0, 40, 0.1), Vector3(0, 0, 0)],
	[&"horizon", Vector3(18, 2.2, 18), Vector3(0, 1, 0)],
]

## Rota fixa do benchmark. Fixa de propósito: um passeio diferente a cada execução
## tornaria o histórico ruído em vez de sinal.
const BENCH_ROUTE: Array[Vector3] = [
	Vector3(0, 1.7, 20),
	Vector3(20, 1.7, 20),
	Vector3(20, 8, -20),
	Vector3(-20, 3, -20),
	Vector3(-20, 1.7, 20),
]
const BENCH_ROUTE_SECONDS: float = 8
const BENCH_LOW_PERCENTILE: float = 1

# --- Acesso ------------------------------------------------------------------


## Cor da paleta pelo nome. Falha alto: cor inexistente vira magenta de depuração.
static func color(key: StringName) -> Color:
	if not PALETTE.has(key):
		push_error("Cor inexistente na paleta: %s" % key)
		return PALETTE[&"debug_magenta"]
	return PALETTE[key]


## Teto de cena pelo nome (ver `BUDGET`).
static func budget(key: StringName) -> int:
	if not BUDGET.has(key):
		push_error("Orçamento inexistente: %s" % key)
		return 0
	return BUDGET[key]


## Teto de triângulos de uma categoria de malha (ver `TRI_BUDGET`).
static func tri_budget(key: StringName) -> int:
	if not TRI_BUDGET.has(key):
		push_error("Orçamento de triângulos inexistente: %s" % key)
		return 0
	return TRI_BUDGET[key]


## Alinha um valor ao grid do mundo.
static func snap_to_grid(value: float) -> float:
	return snappedf(value, GRID_SIZE)


## Alinha uma posição ao grid do mundo, preservando a altura.
static func snap_vec_to_grid(value: Vector3) -> Vector3:
	return Vector3(snappedf(value.x, GRID_SIZE), value.y, snappedf(value.z, GRID_SIZE))
