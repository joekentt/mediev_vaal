"""Gera `scripts/core/params.gd` a partir de `tools/params.py`.

O .gd é um espelho tipado do .py. Existir em duas linguagens é inevitável (o pipeline é
Python, o jogo é GDScript), mas só uma delas é editável: esta aqui gera a outra.
`tools/verify.py` reprova o build se o .gd na árvore divergir do que seria gerado agora.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT = Path("scripts/core/params.gd")


def _color_entries() -> str:
    width = max(len(name) for name in P.PALETTE)
    lines = []
    for name, hex_color in P.PALETTE.items():
        key = f'&"{name}":'.ljust(width + 5)
        lines.append(f"\t{key} {P.color_literal(hex_color)},")
    return "\n".join(lines)


def _material_entries() -> str:
    width = max(len(name) for name in P.MATERIALS)
    lines = []
    for name, (color, roughness, metallic) in P.MATERIALS.items():
        key = f'&"{name}":'.ljust(width + 5)
        lines.append(
            f'\t{key} {{"color": &"{color}", '
            f'"roughness": {P.num(roughness)}, "metallic": {P.num(metallic)}}},'
        )
    return "\n".join(lines)


def _int_dict_entries(data: dict[str, int]) -> str:
    width = max(len(name) for name in data)
    lines = []
    for name, value in data.items():
        key = f'&"{name}":'.ljust(width + 5)
        lines.append(f"\t{key} {value},")
    return "\n".join(lines)


def _layer_consts() -> str:
    lines = []
    for index, name in enumerate(P.PHYSICS_LAYERS):
        bit = 1 << index
        lines.append(f"## Máscara da camada de física {index + 1} (`{name}`).")
        lines.append(f"const LAYER_{name.upper()}: int = {bit}")
    return "\n".join(lines)


def _shot_points() -> str:
    lines = []
    for name, position, target in P.SHOT_POINTS:
        lines.append(
            f'\t[&"{name}", {_vec3(position)}, {_vec3(target)}],'
        )
    return "\n".join(lines)


def _bench_route() -> str:
    return "\n".join(f"\t{_vec3(point)}," for point in P.BENCH_ROUTE)


def _vec3(values) -> str:
    x, y, z = values
    return f"Vector3({P.num(x)}, {P.num(y)}, {P.num(z)})"


def _gait_profiles() -> str:
    """Perfis de marcha como dicionário aninhado, uma linha por campo."""
    lines = []
    for posture, profile in P.GAIT_PROFILES.items():
        lines.append(f'\t&"{posture}": {{')
        width = max(len(field) for field in profile)
        for field, value in profile.items():
            key = f'&"{field}":'.ljust(width + 5)
            # Float explícito, e não `P.num`: um `1` cru aqui entra no dicionário como
            # int, e a primeira divisão por ele vira divisão inteira sem avisar.
            lines.append(f"\t\t{key} {float(value)!r},")
        lines.append("\t},")
    return "\n".join(lines)


def _floats(values) -> str:
    return ", ".join(P.num(float(v)) for v in values)


def _scatter_types() -> str:
    """Tipos de espalhamento como dicionários tipados, um por linha."""
    lines = []
    for spec in P.SCATTER_TYPES:
        low, high = spec["altitude"]
        scale_low, scale_high = spec["scale"]
        lines.append(
            f'\t{{"part": &"{spec["part"]}", "density": {P.num(spec["density"])}, '
            f'"max_slope": {P.num(spec["max_slope"])}, '
            f'"altitude": Vector2({P.num(low)}, {P.num(high)}), '
            f'"scale": Vector2({P.num(scale_low)}, {P.num(scale_high)}), '
            f'"far": {"true" if spec["far"] else "false"}}},'
        )
    return "\n".join(lines)


def _building_types() -> str:
    lines = []
    for spec in P.CITY_BUILDING_TYPES:
        floors_low, floors_high = spec["floors"]
        width_low, width_high = spec["width"]
        depth_low, depth_high = spec["depth"]
        lines.append(
            f'\t{{"name": &"{spec["name"]}", "weight": {P.num(spec["weight"])}, '
            f'"plaza_bias": {P.num(spec["plaza_bias"])}, '
            f'"floors": Vector2i({floors_low}, {floors_high}), '
            f'"width": Vector2i({width_low}, {width_high}), '
            f'"depth": Vector2i({depth_low}, {depth_high}), '
            f'"marker": &"{spec["marker"]}"}},'
        )
    return "\n".join(lines)


def _interior_types() -> str:
    return ", ".join(f'&"{name}"' for name in P.CITY_INTERIOR_TYPES)


def _city_shots() -> str:
    lines = []
    for name, marker, distance, height, pitch in P.CITY_SHOT_POINTS:
        lines.append(
            f'\t[&"{name}", &"{marker}", {P.num(distance)}, '
            f"{P.num(height)}, {P.num(pitch)}],"
        )
    return "\n".join(lines)


def _character_bodies() -> str:
    return ", ".join(f'&"{entry["name"]}"' for entry in P.CHARACTER_ROSTER)


def _npc_archetypes() -> str:
    lines = []
    for spec in P.NPC_ARCHETYPES:
        bodies = ", ".join(f'&"{b}"' for b in spec["bodies"])
        lines.append(
            f'\t{{"name": &"{spec["name"]}", "share": {P.num(spec["share"])}, '
            f'"bodies": [{bodies}], "work": &"{spec["work"]}", '
            f'"schedule": &"{spec["schedule"]}"}},'
        )
    return "\n".join(lines)


def _voice_profiles() -> str:
    lines = []
    for posture, values in P.VOICE_PROFILES.items():
        fields = ", ".join(f'&"{k}": {float(v)!r}' for k, v in values.items())
        lines.append(f'\t&"{posture}": {{{fields}}},')
    return "\n".join(lines)


def _factions() -> str:
    return ", ".join(f'&"{name}"' for name in P.FACTIONS)


def _dialogue_ids() -> str:
    return ", ".join(f'&"{name}"' for name in P.DIALOGUES)


def _dialogue_by_archetype() -> str:
    lines = []
    for archetype, tree in P.DIALOGUE_BY_ARCHETYPE.items():
        lines.append(f'\t&"{archetype}": &"{tree}",')
    return "\n".join(lines)


def _npc_lines() -> str:
    lines = []
    for name, phrases in P.NPC_LINES.items():
        joined = ", ".join(f'"{text}"' for text in phrases)
        lines.append(f'\t&"{name}": [{joined}],')
    return "\n".join(lines)


def _anim_comparison() -> str:
    return ", ".join(f'"{name}"' for name in P.ANIM_GAIT_COMPARISON)


def _period_enum() -> str:
    return ", ".join(P.period_names())


def _period_bounds() -> str:
    """Limites de hora para o cálculo de período, em ordem crescente."""
    bounds = [f"{hour}" for name, hour in P.DAY_PERIODS if name != "NIGHT"]
    return ", ".join(bounds)


def render() -> str:
    return f'''{GENERATED_HEADER('tools/gen_params.py', 'tools/params.py', '#')}
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

const PROJECT_NAME: String = "{P.PROJECT_NAME}"
const MAIN_SCENE: String = "{P.MAIN_SCENE}"
const GENERATED_DIR: String = "{P.GENERATED_DIR}"
const SCREENSHOT_DIR: String = "{P.SCREENSHOT_DIR}"

# --- Paleta ------------------------------------------------------------------

## Cor flat por nome. Sem textura de imagem em lugar nenhum do projeto.
const PALETTE: Dictionary = {{
{_color_entries()}
}}

## Materiais compartilhados gerados em `assets/generated/materials/`.
const MATERIALS: Dictionary = {{
{_material_entries()}
}}

# --- Escala do mundo ---------------------------------------------------------

const GRID_SIZE: float = {P.num(P.GRID_SIZE)} ## Metros por célula. Tudo se alinha a isto.
const CHUNK_CELLS: int = {P.CHUNK_CELLS}
const CHUNK_SIZE: float = {P.num(P.CHUNK_SIZE)}
const WORLD_RADIUS_CHUNKS: int = {P.WORLD_RADIUS_CHUNKS}
const WALL_HEIGHT: float = {P.num(P.WALL_HEIGHT)}
const FLOOR_HEIGHT: float = {P.num(P.FLOOR_HEIGHT)}
const DOOR_WIDTH: float = {P.num(P.DOOR_WIDTH)}
const DOOR_HEIGHT: float = {P.num(P.DOOR_HEIGHT)}
const STREET_WIDTH: float = {P.num(P.STREET_WIDTH)}
const WALL_THICKNESS: float = {P.num(P.WALL_THICKNESS)}

# --- Estágio (cena vazia da fase 1) ------------------------------------------

const STAGE_GROUND_SIZE: float = {P.num(P.STAGE_GROUND_SIZE)}
const STAGE_CAMERA_HEIGHT: float = {P.num(P.STAGE_CAMERA_HEIGHT)}
const STAGE_CAMERA_DISTANCE: float = {P.num(P.STAGE_CAMERA_DISTANCE)}
const STAGE_CAMERA_PITCH_DEG: float = {P.num(P.STAGE_CAMERA_PITCH_DEG)}
const STAGE_CAMERA_FOV: float = {P.num(P.STAGE_CAMERA_FOV)}
const STAGE_CAMERA_FAR: float = {P.num(P.STAGE_CAMERA_FAR)}
const STAGE_SUN_PITCH_DEG: float = {P.num(P.STAGE_SUN_PITCH_DEG)}
const STAGE_SUN_YAW_DEG: float = {P.num(P.STAGE_SUN_YAW_DEG)}
const STAGE_SUN_HEIGHT: float = {P.num(P.STAGE_SUN_HEIGHT)}
const STAGE_SUN_ENERGY: float = {P.num(P.STAGE_SUN_ENERGY)}
const STAGE_GROUND_CELLS: int = {P.STAGE_GROUND_CELLS}
const STAGE_GROUND_TONE_JITTER: float = {P.num(P.STAGE_GROUND_TONE_JITTER)}

# --- Orçamentos --------------------------------------------------------------

const TARGET_FPS: int = {P.TARGET_FPS}
const FRAME_BUDGET_MS: float = {P.num(P.FRAME_BUDGET_MS)}

## Tetos de cena. Não são metas: são o limite que reprova a fase.
const BUDGET: Dictionary = {{
{_int_dict_entries(P.BUDGET)}
}}

## Teto de triângulos por categoria de malha gerada.
const TRI_BUDGET: Dictionary = {{
{_int_dict_entries(P.TRI_BUDGET)}
}}

# --- Render ------------------------------------------------------------------

const SHADOW_MAX_DISTANCE: float = {P.num(P.SHADOW_MAX_DISTANCE)}
const PHYSICS_TICKS_PER_SECOND: int = {P.PHYSICS_TICKS_PER_SECOND}
const SHADOW_DIRECTIONAL_SPLITS: String = "{P.SHADOW_DIRECTIONAL_SPLITS}"
const FOG_DENSITY: float = {P.num(P.FOG_DENSITY)}
const FOG_SKY_AFFECT: float = {P.num(P.FOG_SKY_AFFECT)}
const AMBIENT_SKY_CONTRIBUTION: float = {P.num(P.AMBIENT_SKY_CONTRIBUTION)}
const TONEMAP_MODE: String = "{P.TONEMAP_MODE}"
const TONEMAP_WHITE: float = {P.num(P.TONEMAP_WHITE)}
const SKY_CURVE: float = {P.num(P.SKY_CURVE)}
const SUN_ANGLE_MAX: float = {P.num(P.SUN_ANGLE_MAX)}
const SUN_CURVE: float = {P.num(P.SUN_CURVE)}

# --- Camadas de física -------------------------------------------------------

{_layer_consts()}

# --- Áudio -------------------------------------------------------------------

const BUS_MASTER: StringName = &"{P.AUDIO_BUSES[0][0]}"
const BUS_MUSIC: StringName = &"{P.AUDIO_BUSES[1][0]}"
const BUS_SFX: StringName = &"{P.AUDIO_BUSES[2][0]}"
const BUS_AMBIENCE: StringName = &"{P.AUDIO_BUSES[3][0]}"
const BUS_UI: StringName = &"{P.AUDIO_BUSES[4][0]}"
const SFX_POOL_SIZE: int = {P.SFX_POOL_SIZE}
const SFX_3D_POOL_SIZE: int = {P.SFX_3D_POOL_SIZE}
const MUSIC_CROSSFADE_SEC: float = {P.num(P.MUSIC_CROSSFADE_SEC)}
const SILENT_DB: float = {P.num(P.SILENT_DB)}
const SFX_3D_MAX_DISTANCE: float = {P.num(P.SFX_3D_MAX_DISTANCE)}
const SFX_3D_UNIT_SIZE: float = {P.num(P.SFX_3D_UNIT_SIZE)}
const MUSIC_PLAYER_COUNT: int = {P.MUSIC_PLAYER_COUNT}

# --- Tempo de jogo -----------------------------------------------------------

const HOURS_PER_DAY: int = {P.HOURS_PER_DAY}
const MINUTES_PER_HOUR: int = {P.MINUTES_PER_HOUR}
const SECONDS_PER_GAME_DAY: float = {P.num(P.SECONDS_PER_GAME_DAY)}
const START_HOUR: float = {P.num(P.START_HOUR)}

## Períodos do dia, na ordem cronológica de um ciclo.
enum Period {{ {_period_enum()} }}

## Hora em que cada período começa, exceto NIGHT (que fecha o ciclo).
const PERIOD_START_HOURS: Array[int] = [{_period_bounds()}]

# --- Entrada -----------------------------------------------------------------

const MOUSE_SENSITIVITY: float = {P.num(P.MOUSE_SENSITIVITY)}
const MOUSE_SENSITIVITY_MIN: float = {P.num(P.MOUSE_SENSITIVITY_MIN)}
const MOUSE_SENSITIVITY_MAX: float = {P.num(P.MOUSE_SENSITIVITY_MAX)}

# --- Geração -----------------------------------------------------------------

const WORLD_SEED: int = {P.WORLD_SEED}
const BENCH_WARMUP_FRAMES: int = {P.BENCH_WARMUP_FRAMES}
const BENCH_SAMPLE_FRAMES: int = {P.BENCH_SAMPLE_FRAMES}
const SCREENSHOT_WAIT_FRAMES: int = {P.SCREENSHOT_WAIT_FRAMES}

# --- Vale: terreno -----------------------------------------------------------

const TERRAIN_SIZE: float = {P.num(P.TERRAIN_SIZE)}
const TERRAIN_CELL: float = {P.num(P.TERRAIN_CELL)}
const TERRAIN_CHUNK_CELLS: int = {P.TERRAIN_CHUNK_CELLS}
const TERRAIN_HEIGHT: float = {P.num(P.TERRAIN_HEIGHT)}
const TERRAIN_BASE_FREQUENCY: float = {P.num(P.TERRAIN_BASE_FREQUENCY)}
const TERRAIN_BASE_OCTAVES: int = {P.TERRAIN_BASE_OCTAVES}
const TERRAIN_BASE_LACUNARITY: float = {P.num(P.TERRAIN_BASE_LACUNARITY)}
const TERRAIN_BASE_GAIN: float = {P.num(P.TERRAIN_BASE_GAIN)}
const TERRAIN_DETAIL_FREQUENCY: float = {P.num(P.TERRAIN_DETAIL_FREQUENCY)}
const TERRAIN_DETAIL_OCTAVES: int = {P.TERRAIN_DETAIL_OCTAVES}
const TERRAIN_DETAIL_WEIGHT: float = {P.num(P.TERRAIN_DETAIL_WEIGHT)}
const TERRAIN_VALLEY_POWER: float = {P.num(P.TERRAIN_VALLEY_POWER)}
const TERRAIN_RIM_START: float = {P.num(P.TERRAIN_RIM_START)}
const TERRAIN_RIM_HEIGHT: float = {P.num(P.TERRAIN_RIM_HEIGHT)}
const TERRAIN_EROSION_PASSES: int = {P.TERRAIN_EROSION_PASSES}
const TERRAIN_TALUS: float = {P.num(P.TERRAIN_TALUS)}
const TERRAIN_EROSION_RATE: float = {P.num(P.TERRAIN_EROSION_RATE)}
const TERRAIN_PLAIN_CENTER: Vector2 = Vector2({P.num(P.TERRAIN_PLAIN_CENTER[0])}, {P.num(P.TERRAIN_PLAIN_CENTER[1])})
const TERRAIN_PLAIN_WANDER: float = {P.num(P.TERRAIN_PLAIN_WANDER)}
const TERRAIN_PLAIN_RADIUS: float = {P.num(P.TERRAIN_PLAIN_RADIUS)}
const TERRAIN_PLAIN_FALLOFF: float = {P.num(P.TERRAIN_PLAIN_FALLOFF)}
const TERRAIN_PLAIN_FLATNESS: float = {P.num(P.TERRAIN_PLAIN_FLATNESS)}
const TERRAIN_SLOPE_ROCK: float = {P.num(P.TERRAIN_SLOPE_ROCK)}
const TERRAIN_SLOPE_DIRT: float = {P.num(P.TERRAIN_SLOPE_DIRT)}
const TERRAIN_ALTITUDE_ROCK: float = {P.num(P.TERRAIN_ALTITUDE_ROCK)}
const TERRAIN_ALTITUDE_GRASS: float = {P.num(P.TERRAIN_ALTITUDE_GRASS)}
const TERRAIN_TONE_JITTER: float = {P.num(P.TERRAIN_TONE_JITTER)}

# --- Vale: estrada -----------------------------------------------------------

const ROAD_WIDTH: float = {P.num(P.ROAD_WIDTH)}
const ROAD_SHOULDER: float = {P.num(P.ROAD_SHOULDER)}
const ROAD_MAX_SLOPE: float = {P.num(P.ROAD_MAX_SLOPE)}
const ROAD_GRADE_MARGIN: float = {P.num(P.ROAD_GRADE_MARGIN)}
const ROAD_SAMPLES: int = {P.ROAD_SAMPLES}
const ROAD_SMOOTH_PASSES: int = {P.ROAD_SMOOTH_PASSES}
const ROAD_CONTROL_POINTS: int = {P.ROAD_CONTROL_POINTS}
const ROAD_WANDER: float = {P.num(P.ROAD_WANDER)}
const ROAD_ENTRY_MARGIN: float = {P.num(P.ROAD_ENTRY_MARGIN)}
const ROAD_BED_CELLS: float = {P.num(P.ROAD_BED_CELLS)}

# --- Vale: vegetação ---------------------------------------------------------

const SCATTER_TILE: float = {P.num(P.SCATTER_TILE)}
const SCATTER_JITTER: float = {P.num(P.SCATTER_JITTER)}
const SCATTER_ROAD_CLEARANCE: float = {P.num(P.SCATTER_ROAD_CLEARANCE)}

## Tipos espalhados pelo vale. Cada entrada vira um `MultiMeshInstance3D` por faixa de
## LOD e por bloco — trocar a lista aqui muda a vegetação inteira.
const SCATTER_TYPES: Array[Dictionary] = [
{_scatter_types()}
]

const SCATTER_LOD_BANDS: Array[float] = [{_floats(P.SCATTER_LOD_BANDS)}]
const SCATTER_LOD_FADE: float = {P.num(P.SCATTER_LOD_FADE)}
const SCATTER_LOD_THINNING: Array[float] = [{_floats(P.SCATTER_LOD_THINNING)}]
const SCATTER_PROXY_SIDES: Array[int] = [{", ".join(str(v) for v in P.SCATTER_PROXY_SIDES)}]
const SCATTER_PROXY_TAPER: float = {P.num(P.SCATTER_PROXY_TAPER)}

# --- Vale: navegação ---------------------------------------------------------

const NAV_CELL_SIZE: float = {P.num(P.NAV_CELL_SIZE)}
const NAV_CELL_HEIGHT: float = {P.num(P.NAV_CELL_HEIGHT)}
const NAV_AGENT_RADIUS: float = {P.num(P.NAV_AGENT_RADIUS)}
const NAV_AGENT_HEIGHT: float = {P.num(P.NAV_AGENT_HEIGHT)}
const NAV_AGENT_MAX_CLIMB: float = {P.num(P.NAV_AGENT_MAX_CLIMB)}
const NAV_AGENT_MAX_SLOPE_DEG: float = {P.num(P.NAV_AGENT_MAX_SLOPE_DEG)}
const NAV_GROUP: StringName = &"{P.NAV_GROUP}"

# --- Vale: prova -------------------------------------------------------------

const VALLEY_DIR: String = "res://{P.VALLEY_DIR}"
const VALLEY_SEEDS: Array[int] = [{", ".join(str(v) for v in P.VALLEY_SEEDS)}]
const VALLEY_MIN_DIFFERENCE: float = {P.num(P.VALLEY_MIN_DIFFERENCE)}
const VALLEY_MIN_WALKABLE: float = {P.num(P.VALLEY_MIN_WALKABLE)}

# --- Cidade: sítio e muralha -------------------------------------------------

const CITY_SITE_CANDIDATES: int = {P.CITY_SITE_CANDIDATES}
const CITY_SITE_PROBES: int = {P.CITY_SITE_PROBES}
const CITY_SITE_MAX_SLOPE: float = {P.num(P.CITY_SITE_MAX_SLOPE)}
const CITY_SITE_ROAD_REACH: float = {P.num(P.CITY_SITE_ROAD_REACH)}
const CITY_SITE_ROAD_MIN: float = {P.num(P.CITY_SITE_ROAD_MIN)}
const CITY_SITE_SEARCH_RADIUS: float = {P.num(P.CITY_SITE_SEARCH_RADIUS)}

const CITY_RADIUS: float = {P.num(P.CITY_RADIUS)}
const CITY_WALL_SIDES: int = {P.CITY_WALL_SIDES}
const CITY_RADIUS_JITTER: float = {P.num(P.CITY_RADIUS_JITTER)}
const CITY_WALL_ANGLE_JITTER: float = {P.num(P.CITY_WALL_ANGLE_JITTER)}
const CITY_WALL_MODULE: float = {P.num(P.CITY_WALL_MODULE)}
const CITY_WALL_MARGIN: float = {P.num(P.CITY_WALL_MARGIN)}
const CITY_TOWER_EVERY: int = {P.CITY_TOWER_EVERY}
const CITY_GATE_WIDTH: float = {P.num(P.CITY_GATE_WIDTH)}

const CITY_TERRACE_FALLOFF: float = {P.num(P.CITY_TERRACE_FALLOFF)}
const CITY_TERRACE_FLATNESS: float = {P.num(P.CITY_TERRACE_FLATNESS)}

# --- Cidade: ruas e lotes ----------------------------------------------------

const CITY_PLAZA_RADIUS: float = {P.num(P.CITY_PLAZA_RADIUS)}
const CITY_MAIN_STREET_WIDTH: float = {P.num(P.CITY_MAIN_STREET_WIDTH)}
const CITY_STREET_WIDTH: float = {P.num(P.CITY_STREET_WIDTH)}
const CITY_ALLEY_WIDTH: float = {P.num(P.CITY_ALLEY_WIDTH)}
const CITY_MAIN_STREET_BENDS: int = {P.CITY_MAIN_STREET_BENDS}
const CITY_MAIN_STREET_JITTER: float = {P.num(P.CITY_MAIN_STREET_JITTER)}
const CITY_BLOCK_MIN: float = {P.num(P.CITY_BLOCK_MIN)}
const CITY_SPLIT_JITTER: float = {P.num(P.CITY_SPLIT_JITTER)}
const CITY_SPLIT_MAX_DEPTH: int = {P.CITY_SPLIT_MAX_DEPTH}
const CITY_GRID_JITTER_DEG: float = {P.num(P.CITY_GRID_JITTER_DEG)}

const CITY_LOT_MIN: float = {P.num(P.CITY_LOT_MIN)}
const CITY_LOT_MAX: float = {P.num(P.CITY_LOT_MAX)}
const CITY_LOT_DEPTH_MAX: float = {P.num(P.CITY_LOT_DEPTH_MAX)}
const CITY_LOT_SETBACK: float = {P.num(P.CITY_LOT_SETBACK)}
const CITY_LOT_GAP: float = {P.num(P.CITY_LOT_GAP)}
const CITY_LOT_EMPTY_CHANCE: float = {P.num(P.CITY_LOT_EMPTY_CHANCE)}

# --- Cidade: prédios ---------------------------------------------------------

const CITY_BUILDING_MODULE: float = {P.num(P.CITY_BUILDING_MODULE)}
const CITY_BUILDING_DEPTH_STEP: float = {P.num(P.CITY_BUILDING_DEPTH_STEP)}
const CITY_FLOOR_HEIGHT: float = {P.num(P.CITY_FLOOR_HEIGHT)}
const CITY_WINDOW_CHANCE: float = {P.num(P.CITY_WINDOW_CHANCE)}
const CITY_TINT_JITTER: float = {P.num(P.CITY_TINT_JITTER)}
const CITY_HIP_ROOF_CHANCE: float = {P.num(P.CITY_HIP_ROOF_CHANCE)}
const CITY_ROOF_DROP: float = {P.num(P.CITY_ROOF_DROP)}

const CITY_BUILDING_TYPES: Array[Dictionary] = [
{_building_types()}
]

# --- Cidade: props e interiores ----------------------------------------------

const CITY_PLAZA_STALLS: int = {P.CITY_PLAZA_STALLS}
const CITY_PLAZA_STALL_RING: float = {P.num(P.CITY_PLAZA_STALL_RING)}
const CITY_LANTERN_SPACING: float = {P.num(P.CITY_LANTERN_SPACING)}
const CITY_PROP_DENSITY: float = {P.num(P.CITY_PROP_DENSITY)}
const CITY_YARD_PROPS: int = {P.CITY_YARD_PROPS}
const CITY_CLOTHESLINE_CHANCE: float = {P.num(P.CITY_CLOTHESLINE_CHANCE)}
const CITY_CLOTHESLINE_HEIGHT: float = {P.num(P.CITY_CLOTHESLINE_HEIGHT)}
const CITY_CLOTHESLINE_MAX_SPAN: float = {P.num(P.CITY_CLOTHESLINE_MAX_SPAN)}

const CITY_GROUND_BLEND: float = {P.num(P.CITY_GROUND_BLEND)}
const CITY_INTERIOR_TYPES: Array[StringName] = [{_interior_types()}]
const CITY_INTERIOR_CARD_INSET: float = {P.num(P.CITY_INTERIOR_CARD_INSET)}
const CITY_INTERIOR_CARD_DARKEN: float = {P.num(P.CITY_INTERIOR_CARD_DARKEN)}
const CITY_INTERIOR_PROPS: int = {P.CITY_INTERIOR_PROPS}

# --- Cidade: prova -----------------------------------------------------------

const CITY_DIR: String = "res://{P.CITY_DIR}"
const CITY_SHOT_WIDTH: int = {P.CITY_SHOT_WIDTH}
const CITY_SHOT_HEIGHT: int = {P.CITY_SHOT_HEIGHT}
const CITY_SEEDS: Array[int] = [{", ".join(str(v) for v in P.CITY_SEEDS)}]
const CITY_DOOR_REACH: float = {P.num(P.CITY_DOOR_REACH)}
const CITY_MIN_BUILDINGS: int = {P.CITY_MIN_BUILDINGS}
const CITY_MAX_DEAD_ENDS: int = {P.CITY_MAX_DEAD_ENDS}

## Pontos de câmera das capturas: nome, marcador de referência, distância, altura e pitch.
const CITY_SHOT_POINTS: Array[Array] = [
{_city_shots()}
]

# --- População ---------------------------------------------------------------

## Corpos que `make characters` produz. O povoamento só sorteia entre estes.
const CHARACTER_BODIES: Array[StringName] = [{_character_bodies()}]

const NPC_SCENE: String = "res://{P.NPC_SCENE}"
const NPC_DIR: String = "res://{P.NPC_DIR}"
const NPC_COUNT: int = {P.NPC_COUNT}
const NPC_SEED_OFFSET: int = {P.NPC_SEED_OFFSET}
const NPC_WALK_SPEED: float = {P.num(P.NPC_WALK_SPEED)}
const NPC_HURRY_SPEED: float = {P.num(P.NPC_HURRY_SPEED)}
const NPC_TURN_RATE: float = {P.num(P.NPC_TURN_RATE)}
const NPC_ARRIVE_RADIUS: float = {P.num(P.NPC_ARRIVE_RADIUS)}
const NPC_REPATH_SECONDS: float = {P.num(P.NPC_REPATH_SECONDS)}
const NPC_STUCK_SECONDS: float = {P.num(P.NPC_STUCK_SECONDS)}
const NPC_STUCK_PROGRESS: float = {P.num(P.NPC_STUCK_PROGRESS)}
const NPC_TARGET_SPREAD: float = {P.num(P.NPC_TARGET_SPREAD)}
const NPC_IDLE_MIN: float = {P.num(P.NPC_IDLE_MIN)}
const NPC_IDLE_MAX: float = {P.num(P.NPC_IDLE_MAX)}
const NPC_WANDER_CHANCE: float = {P.num(P.NPC_WANDER_CHANCE)}
const NPC_WANDER_RADIUS: float = {P.num(P.NPC_WANDER_RADIUS)}
const NPC_WORK_BOB: float = {P.num(P.NPC_WORK_BOB)}
const NPC_SENSE_RADIUS: float = {P.num(P.NPC_SENSE_RADIUS)}
const NPC_LOOK_SECONDS: float = {P.num(P.NPC_LOOK_SECONDS)}
const NPC_SPEAK_COOLDOWN: float = {P.num(P.NPC_SPEAK_COOLDOWN)}
const NPC_SPEAK_CHANCE: float = {P.num(P.NPC_SPEAK_CHANCE)}
const NPC_SPEAK_SECONDS: float = {P.num(P.NPC_SPEAK_SECONDS)}
const NPC_SPEAK_HEIGHT: float = {P.num(P.NPC_SPEAK_HEIGHT)}
const NPC_REACT_SECONDS: float = {P.num(P.NPC_REACT_SECONDS)}
const NPC_SHADOW_RADIUS: float = {P.num(P.NPC_SHADOW_RADIUS)}
const NPC_ACTIVE_RADIUS: float = {P.num(P.NPC_ACTIVE_RADIUS)}
const NPC_ACTIVE_HYSTERESIS: float = {P.num(P.NPC_ACTIVE_HYSTERESIS)}
const NPC_DIRECTOR_HZ: float = {P.num(P.NPC_DIRECTOR_HZ)}
const NPC_ABSTRACT_SPEED: float = {P.num(P.NPC_ABSTRACT_SPEED)}

## Falas curtas por arquétipo. Texto flutuante, não diálogo — a fase 11 traz a conversa.
const NPC_LINES: Dictionary = {{
{_npc_lines()}
}}

## Arquétipos: quem é, com que corpo, onde trabalha e com que rotina.
const NPC_ARCHETYPES: Array[Dictionary] = [
{_npc_archetypes()}
]

# --- Vida ambiente -----------------------------------------------------------

const AMBIENT_SMOKE_CHIMNEYS: int = {P.AMBIENT_SMOKE_CHIMNEYS}
const AMBIENT_SMOKE_PARTICLES: int = {P.AMBIENT_SMOKE_PARTICLES}
const AMBIENT_SMOKE_LIFETIME: float = {P.num(P.AMBIENT_SMOKE_LIFETIME)}
const AMBIENT_SMOKE_RISE: float = {P.num(P.AMBIENT_SMOKE_RISE)}
const AMBIENT_SMOKE_SCALE: float = {P.num(P.AMBIENT_SMOKE_SCALE)}
const AMBIENT_BIRD_FLOCKS: int = {P.AMBIENT_BIRD_FLOCKS}
const AMBIENT_BIRDS_PER_FLOCK: int = {P.AMBIENT_BIRDS_PER_FLOCK}
const AMBIENT_BIRD_HEIGHT: float = {P.num(P.AMBIENT_BIRD_HEIGHT)}
const AMBIENT_BIRD_RADIUS: float = {P.num(P.AMBIENT_BIRD_RADIUS)}
const AMBIENT_BIRD_SECONDS: float = {P.num(P.AMBIENT_BIRD_SECONDS)}
const AMBIENT_BIRD_SPREAD: float = {P.num(P.AMBIENT_BIRD_SPREAD)}
const AMBIENT_LEAF_COUNT: int = {P.AMBIENT_LEAF_COUNT}
const AMBIENT_LEAF_LIFETIME: float = {P.num(P.AMBIENT_LEAF_LIFETIME)}
const AMBIENT_LEAF_FALL: float = {P.num(P.AMBIENT_LEAF_FALL)}
const AMBIENT_LEAF_SCALE: float = {P.num(P.AMBIENT_LEAF_SCALE)}
const AMBIENT_WIND_SPEED: float = {P.num(P.AMBIENT_WIND_SPEED)}
const AMBIENT_WIND_SWAY_DEG: float = {P.num(P.AMBIENT_WIND_SWAY_DEG)}
const AMBIENT_DOG_SPEED: float = {P.num(P.AMBIENT_DOG_SPEED)}
const AMBIENT_DOG_PAUSE: float = {P.num(P.AMBIENT_DOG_PAUSE)}
const AMBIENT_DOG_STOPS: int = {P.AMBIENT_DOG_STOPS}
const AMBIENT_HAMMER_PERIOD: float = {P.num(P.AMBIENT_HAMMER_PERIOD)}
const AMBIENT_HAMMER_LIFT: float = {P.num(P.AMBIENT_HAMMER_LIFT)}

# --- População: prova --------------------------------------------------------

const POPULATION_DIR: String = "res://{P.POPULATION_DIR}"
const POPULATION_SECONDS: float = {P.num(P.POPULATION_SECONDS)}
const POPULATION_SAMPLE_HZ: float = {P.num(P.POPULATION_SAMPLE_HZ)}
const POPULATION_MIN_MOVERS: float = {P.num(P.POPULATION_MIN_MOVERS)}
const POPULATION_WINDOW: float = {P.num(P.POPULATION_WINDOW)}
const POPULATION_MIN_NOVELTY: float = {P.num(P.POPULATION_MIN_NOVELTY)}
const POPULATION_MAX_STUCK: int = {P.POPULATION_MAX_STUCK}
const POPULATION_MAX_CLIPPING: int = {P.POPULATION_MAX_CLIPPING}

# --- Interação ---------------------------------------------------------------

const INTERACT_SENSE_RADIUS: float = {P.num(P.INTERACT_SENSE_RADIUS)}
const INTERACT_MAX_ANGLE_DEG: float = {P.num(P.INTERACT_MAX_ANGLE_DEG)}
const INTERACT_REFRESH_HZ: float = {P.num(P.INTERACT_REFRESH_HZ)}
const INTERACT_CENTER_BIAS: float = {P.num(P.INTERACT_CENTER_BIAS)}
const INTERACT_FOCUS_HEIGHT: float = {P.num(P.INTERACT_FOCUS_HEIGHT)}
const INTERACT_AREA_RADIUS: float = {P.num(P.INTERACT_AREA_RADIUS)}

const PROMPT_FADE_SECONDS: float = {P.num(P.PROMPT_FADE_SECONDS)}
const PROMPT_BOTTOM_MARGIN: int = {P.PROMPT_BOTTOM_MARGIN}
const PROMPT_FONT_SIZE: int = {P.PROMPT_FONT_SIZE}
const PROMPT_KEY_FONT_SIZE: int = {P.PROMPT_KEY_FONT_SIZE}
const PROMPT_ALPHA: float = {P.num(P.PROMPT_ALPHA)}

# --- Diálogo -----------------------------------------------------------------

const DIALOGUE_DIR: String = "res://{P.DIALOGUE_DIR}"
const DIALOGUE_MAX_CHOICES: int = {P.DIALOGUE_MAX_CHOICES}
const DIALOGUE_PANEL_WIDTH: float = {P.num(P.DIALOGUE_PANEL_WIDTH)}
const DIALOGUE_PANEL_MARGIN: int = {P.DIALOGUE_PANEL_MARGIN}
const DIALOGUE_FADE_SECONDS: float = {P.num(P.DIALOGUE_FADE_SECONDS)}
const DIALOGUE_TEXT_SPEED: float = {P.num(P.DIALOGUE_TEXT_SPEED)}
const DIALOGUE_FONT_SIZE: int = {P.DIALOGUE_FONT_SIZE}
const DIALOGUE_SPEAKER_FONT_SIZE: int = {P.DIALOGUE_SPEAKER_FONT_SIZE}
const DIALOGUE_CHOICE_FONT_SIZE: int = {P.DIALOGUE_CHOICE_FONT_SIZE}
const DIALOGUE_PANEL_ALPHA: float = {P.num(P.DIALOGUE_PANEL_ALPHA)}

const DIALOGUE_CAMERA_BLEND: float = {P.num(P.DIALOGUE_CAMERA_BLEND)}
const DIALOGUE_CAMERA_SIDE: float = {P.num(P.DIALOGUE_CAMERA_SIDE)}
const DIALOGUE_CAMERA_BACK: float = {P.num(P.DIALOGUE_CAMERA_BACK)}
const DIALOGUE_CAMERA_RISE: float = {P.num(P.DIALOGUE_CAMERA_RISE)}
const DIALOGUE_CAMERA_FOV: float = {P.num(P.DIALOGUE_CAMERA_FOV)}

## Toda árvore gerada, pelo nome. Não é registro: ninguém precisa desta lista para abrir
## uma conversa — o runner monta o caminho a partir do identificador e carrega. Ela existe
## para a prova poder percorrer o que foi gerado, inclusive as árvores que caminho de código
## nenhum referencia.
const DIALOGUE_IDS: Array[StringName] = [{_dialogue_ids()}]

## Qual árvore cada arquétipo usa. Nome, não caminho — o runner monta o caminho.
const DIALOGUE_BY_ARCHETYPE: Dictionary = {{
{_dialogue_by_archetype()}
}}

# --- Voz procedural ----------------------------------------------------------

const VOICE_SAMPLE_RATE: int = {P.VOICE_SAMPLE_RATE}
const VOICE_SYLLABLE_MS: int = {P.VOICE_SYLLABLE_MS}
const VOICE_GAP_MS: int = {P.VOICE_GAP_MS}
const VOICE_SYLLABLES_PER_LINE: int = {P.VOICE_SYLLABLES_PER_LINE}
const VOICE_ATTACK: float = {P.num(P.VOICE_ATTACK)}
const VOICE_RELEASE: float = {P.num(P.VOICE_RELEASE)}
const VOICE_PITCH_JITTER: float = {P.num(P.VOICE_PITCH_JITTER)}
const VOICE_VOLUME_DB: float = {P.num(P.VOICE_VOLUME_DB)}
const VOICE_HARMONICS: int = {P.VOICE_HARMONICS}

## Perfil de voz por postura do corpo. Um corpo novo herda voz sem tabela nova.
const VOICE_PROFILES: Dictionary = {{
{_voice_profiles()}
}}

# --- Facções -----------------------------------------------------------------

const FACTIONS: Array[StringName] = [{_factions()}]
const REPUTATION_MIN: int = {P.REPUTATION_MIN}
const REPUTATION_MAX: int = {P.REPUTATION_MAX}
const REPUTATION_START: int = {P.REPUTATION_START}

const DIALOGUE_PROOF_SECONDS: float = {P.num(P.DIALOGUE_PROOF_SECONDS)}
const DIALOGUE_PROOF_TOLERANCE: float = {P.num(P.DIALOGUE_PROOF_TOLERANCE)}

# --- Jogador -----------------------------------------------------------------

const PLAYER_SCENE: String = "res://{P.PLAYER_SCENE}"
const PLAYER_BODY: StringName = &"{P.PLAYER_BODY}"
const PLAYER_WALK_SPEED: float = {P.num(P.PLAYER_WALK_SPEED)}
const PLAYER_RUN_SPEED: float = {P.num(P.PLAYER_RUN_SPEED)}
const PLAYER_ACCELERATION: float = {P.num(P.PLAYER_ACCELERATION)}
const PLAYER_DECELERATION: float = {P.num(P.PLAYER_DECELERATION)}
const PLAYER_AIR_CONTROL: float = {P.num(P.PLAYER_AIR_CONTROL)}
const PLAYER_TURN_SPEED: float = {P.num(P.PLAYER_TURN_SPEED)}
const PLAYER_JUMP_HEIGHT: float = {P.num(P.PLAYER_JUMP_HEIGHT)}
const PLAYER_GRAVITY: float = {P.num(P.PLAYER_GRAVITY)}
const PLAYER_FALL_GRAVITY_SCALE: float = {P.num(P.PLAYER_FALL_GRAVITY_SCALE)}
const PLAYER_TERMINAL_VELOCITY: float = {P.num(P.PLAYER_TERMINAL_VELOCITY)}
const PLAYER_COYOTE_TIME: float = {P.num(P.PLAYER_COYOTE_TIME)}
const PLAYER_JUMP_BUFFER: float = {P.num(P.PLAYER_JUMP_BUFFER)}
const PLAYER_CAPSULE_RADIUS: float = {P.num(P.PLAYER_CAPSULE_RADIUS)}
const PLAYER_FLOOR_MAX_ANGLE_DEG: float = {P.num(P.PLAYER_FLOOR_MAX_ANGLE_DEG)}
const PLAYER_FLOOR_SNAP: float = {P.num(P.PLAYER_FLOOR_SNAP)}
const PLAYER_INTERACT_RANGE: float = {P.num(P.PLAYER_INTERACT_RANGE)}

# --- Câmera de terceira pessoa -----------------------------------------------

const CAMERA_DISTANCE: float = {P.num(P.CAMERA_DISTANCE)}
const CAMERA_DISTANCE_MIN: float = {P.num(P.CAMERA_DISTANCE_MIN)}
const CAMERA_DISTANCE_MAX: float = {P.num(P.CAMERA_DISTANCE_MAX)}
const CAMERA_ZOOM_STEP: float = {P.num(P.CAMERA_ZOOM_STEP)}
const CAMERA_TARGET_HEIGHT: float = {P.num(P.CAMERA_TARGET_HEIGHT)}
const CAMERA_PITCH_MIN_DEG: float = {P.num(P.CAMERA_PITCH_MIN_DEG)}
const CAMERA_PITCH_MAX_DEG: float = {P.num(P.CAMERA_PITCH_MAX_DEG)}
const CAMERA_START_PITCH_DEG: float = {P.num(P.CAMERA_START_PITCH_DEG)}
const CAMERA_SPRING_MARGIN: float = {P.num(P.CAMERA_SPRING_MARGIN)}
const CAMERA_PROBE_RADIUS: float = {P.num(P.CAMERA_PROBE_RADIUS)}
const CAMERA_FOLLOW_LAG: float = {P.num(P.CAMERA_FOLLOW_LAG)}
const CAMERA_FOV: float = {P.num(P.CAMERA_FOV)}
const CAMERA_FOV_RUN_BONUS: float = {P.num(P.CAMERA_FOV_RUN_BONUS)}
const CAMERA_FOV_LERP: float = {P.num(P.CAMERA_FOV_LERP)}
const CAMERA_SHAKE_AMPLITUDE: float = {P.num(P.CAMERA_SHAKE_AMPLITUDE)}
const CAMERA_SHAKE_DECAY: float = {P.num(P.CAMERA_SHAKE_DECAY)}
const CAMERA_SHAKE_FREQUENCY: float = {P.num(P.CAMERA_SHAKE_FREQUENCY)}
const CAMERA_SHAKE_MIN_FALL: float = {P.num(P.CAMERA_SHAKE_MIN_FALL)}
const CAMERA_SHAKE_MAX_FALL: float = {P.num(P.CAMERA_SHAKE_MAX_FALL)}

# --- Prova do controlador ----------------------------------------------------

const PLAYTEST_DIR: String = "res://{P.PLAYTEST_DIR}"
const PLAYTEST_ARENA_RADIUS: float = {P.num(P.PLAYTEST_ARENA_RADIUS)}
const PLAYTEST_LEDGE_OFFSET: Vector2 = Vector2({P.num(P.PLAYTEST_LEDGE_OFFSET[0])}, {P.num(P.PLAYTEST_LEDGE_OFFSET[1])})
const PLAYTEST_LEDGE_HEIGHT: float = {P.num(P.PLAYTEST_LEDGE_HEIGHT)}
const PLAYTEST_SETTLE_FRAMES: int = {P.PLAYTEST_SETTLE_FRAMES}
const PLAYTEST_TOLERANCE: float = {P.num(P.PLAYTEST_TOLERANCE)}

# --- Locomoção procedural ----------------------------------------------------

## Perfis de marcha gerados em `resources/gaits/`, um por postura.
const GAIT_DIR: String = "res://{P.GAIT_DIR}"

const GAIT_MOVE_THRESHOLD: float = {P.num(P.GAIT_MOVE_THRESHOLD)}
const GAIT_RUN_SPEED: float = {P.num(P.GAIT_RUN_SPEED)}
const GAIT_STRIDE_HIP_FACTOR: float = {P.num(P.GAIT_STRIDE_HIP_FACTOR)}
const GAIT_STRIDE_SPEED_FACTOR: float = {P.num(P.GAIT_STRIDE_SPEED_FACTOR)}
const GAIT_STRIDE_MIN: float = {P.num(P.GAIT_STRIDE_MIN)}
const GAIT_STRIDE_MAX: float = {P.num(P.GAIT_STRIDE_MAX)}
const GAIT_DUTY_WALK: float = {P.num(P.GAIT_DUTY_WALK)}
const GAIT_DUTY_RUN: float = {P.num(P.GAIT_DUTY_RUN)}
const GAIT_SPEED_SMOOTHING: float = {P.num(P.GAIT_SPEED_SMOOTHING)}
const GAIT_BLEND_SPEED: float = {P.num(P.GAIT_BLEND_SPEED)}
const GAIT_GROUND_PROBE_UP: float = {P.num(P.GAIT_GROUND_PROBE_UP)}
const GAIT_GROUND_PROBE_DOWN: float = {P.num(P.GAIT_GROUND_PROBE_DOWN)}
const GAIT_ANKLE_HEIGHT: float = {P.num(P.GAIT_ANKLE_HEIGHT)}

## Perfil de marcha por postura. É o parâmetro por povo que faz corpos diferentes
## andarem diferente sem uma linha de código específica: o mesmo nó lê outro perfil.
const GAIT_PROFILES: Dictionary = {{
{_gait_profiles()}
}}

const ARM_REST_DROP_DEG: float = {P.num(P.ARM_REST_DROP_DEG)}
const ARM_OUTWARD_DEG: float = {P.num(P.ARM_OUTWARD_DEG)}
const FOOT_SWING_TILT_DEG: float = {P.num(P.FOOT_SWING_TILT_DEG)}
const JUMP_TUCK_LEG_FACTOR: float = {P.num(P.JUMP_TUCK_LEG_FACTOR)}
const SIT_FOOT_FORWARD: float = {P.num(P.SIT_FOOT_FORWARD)}

# --- Camadas aditivas --------------------------------------------------------

const BREATH_FREQUENCY: float = {P.num(P.BREATH_FREQUENCY)}
const BREATH_CHEST_DEG: float = {P.num(P.BREATH_CHEST_DEG)}
const BREATH_RISE: float = {P.num(P.BREATH_RISE)}
const LOOK_MAX_HEAD_YAW_DEG: float = {P.num(P.LOOK_MAX_HEAD_YAW_DEG)}
const LOOK_MAX_HEAD_PITCH_DEG: float = {P.num(P.LOOK_MAX_HEAD_PITCH_DEG)}
const LOOK_TORSO_SHARE: float = {P.num(P.LOOK_TORSO_SHARE)}
const LOOK_SMOOTHING: float = {P.num(P.LOOK_SMOOTHING)}
const CAMERA_BOB_AMPLITUDE: float = {P.num(P.CAMERA_BOB_AMPLITUDE)}
const CAMERA_BOB_SIDE: float = {P.num(P.CAMERA_BOB_SIDE)}
const CAMERA_BOB_HARMONIC: float = {P.num(P.CAMERA_BOB_HARMONIC)}

# --- Estados extras ----------------------------------------------------------

const JUMP_CROUCH_TIME: float = {P.num(P.JUMP_CROUCH_TIME)}
const JUMP_CROUCH_DEPTH: float = {P.num(P.JUMP_CROUCH_DEPTH)}
const JUMP_LAUNCH_TIME: float = {P.num(P.JUMP_LAUNCH_TIME)}
const JUMP_LAUNCH_RISE: float = {P.num(P.JUMP_LAUNCH_RISE)}
const JUMP_TUCK_DEG: float = {P.num(P.JUMP_TUCK_DEG)}
const JUMP_LAND_TIME: float = {P.num(P.JUMP_LAND_TIME)}
const JUMP_LAND_DEPTH: float = {P.num(P.JUMP_LAND_DEPTH)}
const INTERACT_REACH_TIME: float = {P.num(P.INTERACT_REACH_TIME)}
const INTERACT_HOLD_TIME: float = {P.num(P.INTERACT_HOLD_TIME)}
const INTERACT_RETURN_TIME: float = {P.num(P.INTERACT_RETURN_TIME)}
const SIT_HIP_DROP: float = {P.num(P.SIT_HIP_DROP)}
const SIT_HIP_TIME: float = {P.num(P.SIT_HIP_TIME)}
const SIT_KNEE_DEG: float = {P.num(P.SIT_KNEE_DEG)}
const SIT_TORSO_DEG: float = {P.num(P.SIT_TORSO_DEG)}
const CARRY_ARM_DEG: float = {P.num(P.CARRY_ARM_DEG)}
const CARRY_ELBOW_DEG: float = {P.num(P.CARRY_ELBOW_DEG)}
const CARRY_TORSO_LEAN_DEG: float = {P.num(P.CARRY_TORSO_LEAN_DEG)}
const CARRY_BLEND_TIME: float = {P.num(P.CARRY_BLEND_TIME)}

# --- Prova visual da locomoção -----------------------------------------------

## Tiras de quadros de `tools/anim_preview.gd`. Derivado: está no .gitignore.
const ANIM_DIR: String = "res://{P.ANIM_DIR}"
const ANIM_FRAME_WIDTH: int = {P.ANIM_FRAME_WIDTH}
const ANIM_FRAME_HEIGHT: int = {P.ANIM_FRAME_HEIGHT}
const ANIM_STRIP_COLUMNS: int = {P.ANIM_STRIP_COLUMNS}
const ANIM_STEP_FRAMES: int = {P.ANIM_STEP_FRAMES}
const ANIM_SETTLE_FRAMES: int = {P.ANIM_SETTLE_FRAMES}
const ANIM_CAMERA_FOV: float = {P.num(P.ANIM_CAMERA_FOV)}
const ANIM_CAMERA_HEIGHT: float = {P.num(P.ANIM_CAMERA_HEIGHT)}
const ANIM_CAMERA_DISTANCE: float = {P.num(P.ANIM_CAMERA_DISTANCE)}
const ANIM_CAMERA_YAW_DEG: float = {P.num(P.ANIM_CAMERA_YAW_DEG)}
const ANIM_WALK_SPEED: float = {P.num(P.ANIM_WALK_SPEED)}
const ANIM_RUN_SPEED: float = {P.num(P.ANIM_RUN_SPEED)}
const ANIM_JUMP_SPEED: float = {P.num(P.ANIM_JUMP_SPEED)}
const ANIM_FOOT_SLIDE_LIMIT: float = {P.num(P.ANIM_FOOT_SLIDE_LIMIT)}
const ANIM_SUBJECT: String = "{P.ANIM_SUBJECT}"
const PREVIEW_FIGURE_HEIGHT_FALLBACK: float = {P.num(P.PREVIEW_FIGURE_HEIGHT_FALLBACK)}
const ANIM_GAIT_COMPARISON: Array[String] = [{_anim_comparison()}]
const ANIM_COMPARISON_PHASE: float = {P.num(P.ANIM_COMPARISON_PHASE)}
const ANIM_STATE_FRAMES: int = {P.ANIM_STATE_FRAMES}
const ANIM_INTERACT_REACH: Vector3 = {_vec3(P.ANIM_INTERACT_REACH)}
const ANIM_LOOK_AT: Vector3 = {_vec3(P.ANIM_LOOK_AT)}
const CHARACTER_DIR: String = "res://{P.CHARACTER_DIR}"
const KIT_DIR: String = "res://{P.KIT_DIR}"

# --- Olhos: capturas e benchmark ---------------------------------------------

## Onde `tools/godot_shot.gd` grava as capturas. Derivado: está no .gitignore.
const SHOTS_DIR: String = "res://{P.SHOTS_DIR}"
## Última medição de `tools/bench.gd`.
const BENCH_JSON: String = "res://{P.BENCH_JSON}"
## Histórico acumulado, uma linha por execução. **Versionado** — é o que mostra regressão.
const BENCH_HISTORY: String = "res://{P.BENCH_HISTORY}"

## Pontos de câmera nomeados: [nome, posição, alvo].
const SHOT_POINTS: Array = [
{_shot_points()}
]

## Rota fixa do benchmark. Fixa de propósito: um passeio diferente a cada execução
## tornaria o histórico ruído em vez de sinal.
const BENCH_ROUTE: Array[Vector3] = [
{_bench_route()}
]
const BENCH_ROUTE_SECONDS: float = {P.num(P.BENCH_ROUTE_SECONDS)}
const BENCH_CAMERA_CLEARANCE: float = {P.num(P.BENCH_CAMERA_CLEARANCE)}
const BENCH_LOW_PERCENTILE: float = {P.num(P.BENCH_LOW_PERCENTILE)}

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
'''


def main() -> list[Path]:
    return write_if_changed(OUTPUT, render())


if __name__ == "__main__":
    main()
