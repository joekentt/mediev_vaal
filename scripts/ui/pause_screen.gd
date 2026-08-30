## Pausa: continuar, salvar, opções, voltar ao menu.
##
## **A pausa não quebra o relógio do mundo.** `TimeSystem` é `PROCESS_MODE_PAUSABLE`, então
## ele para junto com o jogo e recomeça na mesma hora — não há salto de céu ao despausar, e
## não há hora avançando enquanto o jogador lê o menu. O ciclo do dia é pausável pela mesma
## razão, e os dois voltam coerentes porque nenhum dos dois acumula tempo parado.
##
## Esta tela é `PROCESS_MODE_ALWAYS`, senão ela se pausaria a si mesma e não haveria como
## despausar — o erro clássico, e o motivo de a pausa deste projeto viver num nó só.
##
## Durante uma conversa, `Esc` é da conversa e não da pausa: sair do diálogo é o gesto
## esperado ali, e abrir o menu por cima do painel de fala deixaria dois modais na tela.
class_name PauseScreen
extends CanvasLayer

const LAYER: int = 22
const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"
const GAME_STATE_PATH: NodePath = ^"/root/GameState"

signal options_requested
signal save_requested
signal menu_requested

var _state: Node = null
var _talking: bool = false
var _screen: Control = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_state = get_node_or_null(GAME_STATE_PATH)
	_build()
	_screen.visible = false
	_screen.modulate.a = 0.0

	var bus: Node = get_node_or_null(EVENT_BUS_PATH)
	if bus != null:
		bus.dialogue_requested.connect(_on_dialogue_started)
		bus.dialogue_finished.connect(_on_dialogue_finished)


func is_open() -> bool:
	return _screen.visible


func open() -> void:
	if _state != null:
		_state.set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIKit.fade(_screen, true)


func close() -> void:
	if _state != null:
		_state.set_paused(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	UIKit.fade(_screen, false)


func _unhandled_input(event: InputEvent) -> void:
	if _talking or not event.is_action_pressed(&"pause"):
		return
	if _screen.visible:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func _on_dialogue_started(_dialogue_id: StringName, _speaker: Node3D) -> void:
	_talking = true


func _on_dialogue_finished(_dialogue_id: StringName) -> void:
	_talking = false


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
	column.add_child(UIKit.label("Pausa", Params.UI_TITLE_FONT_SIZE, Params.color(&"thatch")))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, Params.UI_SPACING)
	column.add_child(gap)

	column.add_child(UIKit.button("Continuar", close))
	column.add_child(UIKit.button("Salvar", func() -> void: save_requested.emit()))
	column.add_child(UIKit.button("Opções", func() -> void: options_requested.emit()))
	column.add_child(UIKit.button("Menu principal", func() -> void: menu_requested.emit()))


const BACKDROP_ALPHA: float = 0.5
