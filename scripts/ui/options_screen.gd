## As opções: qualidade, distância, densidade, sensibilidade, volumes e V-Sync.
##
## Cada controle escreve no `GameState` e manda `Settings` aplicar **na hora**. Nada de
## "aplicar" e "cancelar": um menu de opções em que a mudança só acontece depois de um
## botão é um menu em que ninguém sabe o que está ajustando. Quem quiser voltar atrás mexe
## o slider de volta, e o slider mostra onde estava.
##
## A única opção que não vale na hora é a densidade de habitantes, e ela diz isso na
## própria linha: criar ou apagar gente na frente do jogador seria pior que qualquer ganho.
class_name OptionsScreen
extends CanvasLayer

const LAYER: int = 25

signal closed

var _state: Node = null
var _stage: Node3D = null
var _density_label: Label = null
var _screen: Control = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_state = get_node_or_null(^"/root/GameState")
	_build()
	_screen.visible = false
	_screen.modulate.a = 0.0


## O estágio vivo, para as opções de mundo alcançarem o sol e o espalhamento. Sem ele, as
## opções globais (janela, áudio, V-Sync) continuam funcionando — é o caso do menu inicial.
func bind(stage: Node3D) -> void:
	_stage = stage


func open() -> void:
	UIKit.fade(_screen, true)


func close() -> void:
	if _state != null:
		Settings.save_from(_state)
	UIKit.fade(_screen, false)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _screen.visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_screen = UIKit.screen()
	add_child(_screen)
	_screen.add_child(UIKit.curtain(Color(0.0, 0.0, 0.0, BACKDROP_ALPHA)))

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(center)

	var panel: PanelContainer = UIKit.panel()
	center.add_child(panel)

	var column: VBoxContainer = UIKit.column()
	panel.add_child(column)
	column.add_child(UIKit.label("Opções", Params.UI_TITLE_FONT_SIZE, Params.color(&"thatch")))
	column.add_child(_gap())

	column.add_child(UIKit.row("Qualidade", UIKit.choice(
		Params.QUALITY_LEVELS, Params.QUALITY_LEVELS.find(_state.quality), _on_quality
	)))
	column.add_child(UIKit.row("Distância de renderização", UIKit.slider(
		Params.RENDER_DISTANCE_MIN, Params.RENDER_DISTANCE_MAX,
		_state.render_distance, _on_render_distance
	)))

	var density: HSlider = UIKit.slider(
		Params.NPC_DENSITY_MIN, Params.NPC_DENSITY_MAX, _state.npc_density, _on_density
	)
	column.add_child(UIKit.row("Densidade de habitantes", density))
	_density_label = UIKit.label(
		_density_text(), Params.UI_SMALL_FONT_SIZE, Params.color(&"stone_light")
	)
	column.add_child(_density_label)
	column.add_child(_gap())

	column.add_child(UIKit.row("Sensibilidade do mouse", UIKit.slider(
		Params.MOUSE_SENSITIVITY_MIN, Params.MOUSE_SENSITIVITY_MAX,
		_state.mouse_sensitivity, _on_sensitivity
	)))
	column.add_child(UIKit.row("Inverter eixo vertical", UIKit.check(
		_state.invert_camera_y, _on_invert
	)))
	column.add_child(_gap())

	for bus_name: Variant in _state.volumes:
		var key: StringName = StringName(bus_name)
		column.add_child(UIKit.row("Volume: %s" % _bus_label(key), UIKit.slider(
			0.0, 1.0, float(_state.volumes[key]),
			func(value: float) -> void: _on_volume(key, value)
		)))
	column.add_child(UIKit.row("Voz dos habitantes", UIKit.check(
		_state.voice_enabled, _on_voice
	)))
	column.add_child(_gap())

	column.add_child(UIKit.row("V-Sync", UIKit.check(_state.vsync_enabled, _on_vsync)))
	column.add_child(_gap())
	column.add_child(UIKit.button("Voltar", close))


const BACKDROP_ALPHA: float = 0.55


func _gap() -> Control:
	var node: Control = Control.new()
	node.custom_minimum_size = Vector2(0.0, Params.UI_SPACING)
	return node


## Nome do barramento em português. Tabela curta e explícita: `Master` na tela seria a
## única palavra em inglês de um menu inteiro em português.
static func _bus_label(bus: StringName) -> String:
	if bus == Params.BUS_MASTER:
		return "geral"
	if bus == Params.BUS_MUSIC:
		return "música"
	if bus == Params.BUS_SFX:
		return "efeitos"
	if bus == Params.BUS_AMBIENCE:
		return "ambiência"
	return String(bus).to_lower()


func _density_text() -> String:
	return "vale no próximo mundo gerado — %d habitantes" % int(
		round(float(Params.NPC_COUNT) * _state.npc_density)
	)


# --- Cada controle -------------------------------------------------------------


func _on_quality(index: int) -> void:
	_state.quality = Params.QUALITY_LEVELS[clampi(index, 0, Params.QUALITY_LEVELS.size() - 1)]
	_apply()


func _on_render_distance(value: float) -> void:
	_state.render_distance = value
	_apply()


func _on_density(value: float) -> void:
	_state.npc_density = value
	_density_label.text = _density_text()


func _on_sensitivity(value: float) -> void:
	_state.set_mouse_sensitivity(value)


func _on_invert(pressed: bool) -> void:
	_state.invert_camera_y = pressed


func _on_voice(pressed: bool) -> void:
	_state.voice_enabled = pressed


func _on_vsync(pressed: bool) -> void:
	_state.vsync_enabled = pressed
	Settings.apply_global(_state)


func _on_volume(bus: StringName, value: float) -> void:
	_state.volumes[bus] = value
	Settings.apply_global(_state)


func _apply() -> void:
	Settings.apply_global(_state)
	Settings.apply_world(_state, _stage)
