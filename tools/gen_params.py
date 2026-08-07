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
