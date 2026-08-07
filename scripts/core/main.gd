extends Node3D

## Raiz da cena principal.
##
## A cena em disco tem só este nó. Todo o resto — céu, sol, chão, colisão, câmera — é
## construído por `generators/world_generator.gd` quando isto roda. Se algo aqui só
## existisse por ter sido arrastado no editor, estaria errado.

const WORLD_ID: StringName = &"stage"
const USEC_PER_MS: float = 1000.0


func _ready() -> void:
	GameState.set_phase(GameState.Phase.GENERATING)

	var started_usec: int = Time.get_ticks_usec()
	var stage: Node3D = WorldGenerator.build_stage(self)
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / USEC_PER_MS

	GameState.set_phase(GameState.Phase.PLAYING)
	EventBus.world_generated.emit(WORLD_ID, {
		"nodes": stage.get_child_count(),
		"build_ms": elapsed_ms,
	})
	print("Estágio gerado em %.2f ms." % elapsed_ms)

	if SessionProbe.is_requested():
		add_child(SessionProbe.new())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		GameState.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_screenshot"):
		_save_screenshot()
		get_viewport().set_input_as_handled()


func _save_screenshot() -> void:
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		return
	DirAccess.make_dir_recursive_absolute(Params.SCREENSHOT_DIR)
	var path: String = "%s/%s.png" % [
		Params.SCREENSHOT_DIR,
		Time.get_datetime_string_from_system().replace(":", "-"),
	]
	if image.save_png(path) == OK:
		print("Captura salva em %s" % ProjectSettings.globalize_path(path))
