"""Gera `project.godot` a partir de `tools/params.py`.

Sim, o arquivo de projeto também é gerado. O editor do Godot reescreve `project.godot`
sempre que alguém mexe em Project Settings — e é exatamente esse tipo de mudança
invisível que a regra do projeto proíbe. Configuração muda em `tools/params.py`,
`make project` reescreve o arquivo, o diff mostra o que mudou.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

OUTPUT = Path("project.godot")


def _event(class_name: str, properties: dict[str, object]) -> str:
    fields = ",".join(f'"{key}":{_value(value)}' for key, value in properties.items())
    return f"Object({class_name},{fields})"


def _value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return P.num(value)
    return str(value)


def _input_events(spec: dict) -> list[str]:
    events: list[str] = []
    for key_name in spec.get("keys", []):
        events.append(_event("InputEventKey", {
            "device": -1,
            "physical_keycode": P.KEY[key_name],
            "pressed": False,
        }))
    for button_name in spec.get("mouse_buttons", []):
        events.append(_event("InputEventMouseButton", {
            "device": -1,
            "button_index": P.MOUSE[button_name],
            "pressed": False,
        }))
    for button_name in spec.get("joy_buttons", []):
        events.append(_event("InputEventJoypadButton", {
            "device": -1,
            "button_index": P.JOY[button_name],
            "pressed": False,
        }))
    if "joy_axis" in spec:
        axis, axis_value = spec["joy_axis"]
        events.append(_event("InputEventJoypadMotion", {
            "device": -1,
            "axis": axis,
            "axis_value": float(axis_value),
        }))
    return events


def _input_section() -> str:
    default_deadzone = 0.5
    blocks = []
    for action, spec in P.INPUT_MAP.items():
        events = _input_events(spec)
        joined = "\n, ".join(events)
        deadzone = P.num(float(spec.get("deadzone", default_deadzone)))
        blocks.append(f'{action}={{\n"deadzone": {deadzone},\n"events": [{joined}\n]\n}}')
    return "\n".join(blocks)


def _layer_section() -> str:
    return "\n".join(
        f'3d_physics/layer_{index + 1}="{name}"'
        for index, name in enumerate(P.PHYSICS_LAYERS)
    )


def _features() -> str:
    quoted = ", ".join(f'"{feature}"' for feature in P.GODOT_FEATURES)
    return f"PackedStringArray({quoted})"


def _autoloads() -> str:
    # A ordem importa: EventBus tem de existir antes de qualquer um que emita.
    entries = (
        ("EventBus", "res://scripts/core/event_bus.gd"),
        ("GameState", "res://scripts/core/game_state.gd"),
        ("AudioManager", "res://scripts/core/audio_manager.gd"),
        ("TimeSystem", "res://scripts/core/time_system.gd"),
    )
    return "\n".join(f'{name}="*{path}"' for name, path in entries)


# Avisos de GDScript ligados no projeto. `tools/check_warnings.py` reescreve este bloco
# temporariamente com tudo em 2 (erro) para provar que o projeto abre limpo.
DEFAULT_WARNING_LEVELS: dict[str, int] = {
    "untyped_declaration": 1,
    "inferred_declaration": 1,
}


def _debug_section(warning_levels: dict[str, int]) -> str:
    return "\n".join(
        f"gdscript/warnings/{key}={level}"
        for key, level in sorted(warning_levels.items())
    )


def render(warning_levels: dict[str, int] | None = None) -> str:
    levels = DEFAULT_WARNING_LEVELS if warning_levels is None else warning_levels
    return f"""{GENERATED_HEADER('tools/gen_project.py', 'tools/params.py', ';')}
config_version=5

[application]

config/name="{P.PROJECT_NAME}"
config/description="{P.PROJECT_DESCRIPTION}"
run/main_scene="{P.MAIN_SCENE}"
config/features={_features()}

[audio]

buses/default_bus_layout="{P.AUDIO_BUS_LAYOUT_PATH}"

[autoload]

{_autoloads()}

[debug]

{_debug_section(levels)}

[display]

window/size/viewport_width={P.VIEWPORT_WIDTH}
window/size/viewport_height={P.VIEWPORT_HEIGHT}
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/vsync/vsync_mode={P.VSYNC_MODE}

[input]

{_input_section()}

[layer_names]

{_layer_section()}

[physics]

common/physics_ticks_per_second={P.PHYSICS_TICKS_PER_SECOND}
3d/run_on_separate_thread=false

[rendering]

renderer/rendering_method="{P.RENDERING_METHOD}"
anti_aliasing/quality/msaa_3d={P.MSAA_3D}
anti_aliasing/quality/screen_space_aa={P.SCREEN_SPACE_AA}
anti_aliasing/quality/use_debanding={_value(P.USE_DEBANDING)}
lights_and_shadows/directional_shadow/size={P.DIRECTIONAL_SHADOW_SIZE}
lights_and_shadows/directional_shadow/soft_shadow_filter_quality={P.SHADOW_FILTER_QUALITY}
lights_and_shadows/positional_shadow/atlas_size={P.POSITIONAL_SHADOW_ATLAS_SIZE}
lights_and_shadows/positional_shadow/soft_shadow_filter_quality={P.SHADOW_FILTER_QUALITY}
occlusion_culling/use_occlusion_culling={_value(P.USE_OCCLUSION_CULLING)}
"""


def main() -> list[Path]:
    return write_if_changed(OUTPUT, render())


if __name__ == "__main__":
    main()
