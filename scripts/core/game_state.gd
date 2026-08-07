extends Node

## Estado global e volátil da sessão. Stub da fase 1.
##
## Guarda só o que é de fato global: fase do jogo, pausa, preferências de entrada e
## flags de mundo. Nada de regra de gameplay aqui. Toda mudança relevante é anunciada
## pelo `EventBus`; ninguém consulta o `GameState` em `_process`.

enum Phase {
	BOOT, ## Autoloads subindo, nada gerado ainda.
	MAIN_MENU, ## Menu inicial.
	GENERATING, ## Mundo sendo construído por `generators/`.
	PLAYING, ## Jogo em andamento.
	PAUSED, ## Pausado pelo jogador.
	CUTSCENE, ## Controle tomado por uma cena roteirizada.
}

## Sensibilidade do mouse para a câmera, em graus por pixel.
var mouse_sensitivity: float = Params.MOUSE_SENSITIVITY

## Inverte o eixo vertical da câmera.
var invert_camera_y: bool = false

var _phase: int = Phase.BOOT
var _is_paused: bool = false
var _world_flags: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Fase atual do jogo (ver `Phase`).
func get_phase() -> int:
	return _phase


func set_phase(new_phase: int) -> void:
	if _phase == new_phase:
		return
	_phase = new_phase
	EventBus.game_phase_changed.emit(_phase)


func is_paused() -> bool:
	return _is_paused


## Pausa a árvore inteira. Autoloads seguem rodando (`PROCESS_MODE_ALWAYS`).
func set_paused(value: bool) -> void:
	if _is_paused == value:
		return
	_is_paused = value
	get_tree().paused = value
	set_phase(Phase.PAUSED if value else Phase.PLAYING)
	EventBus.game_paused_changed.emit(_is_paused)


func toggle_pause() -> void:
	set_paused(not _is_paused)


## Sensibilidade do mouse, presa a limites sãos (ver `Params`).
func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(
		value, Params.MOUSE_SENSITIVITY_MIN, Params.MOUSE_SENSITIVITY_MAX
	)


## Flags de mundo: fatos pequenos e persistentes ("portao_norte_aberto", ...).
func set_flag(key: StringName, value: Variant) -> void:
	_world_flags[key] = value


func get_flag(key: StringName, default_value: Variant = null) -> Variant:
	return _world_flags.get(key, default_value)


func has_flag(key: StringName) -> bool:
	return _world_flags.has(key)


func clear_flags() -> void:
	_world_flags.clear()
