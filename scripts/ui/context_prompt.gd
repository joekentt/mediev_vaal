## O prompt de contexto: uma linha no rodapé que aparece e some.
##
## Construído inteiro em código, como tudo neste projeto. Uma cena de UI montada no editor
## seria o primeiro arquivo do repositório que ninguém revisa — o diff de um `.tscn`
## arrastado à mão é ilegível, e a próxima pessoa que mexer num tamanho de fonte não vai
## saber que ele devia ter vindo de `params.py`.
##
## Discreto quer dizer o que está escrito aqui: uma linha, sem caixa, sem ícone grande, sem
## barra de fundo. O que informa é o verbo — "Conversar" — e a tecla ao lado dele. Tudo o
## resto é ruído em cima de um cenário que a fase 8 levou uma fase inteira para desenhar.
##
## O fade não é enfeite: sem ele, andar por uma rua com habitantes dos dois lados faz o
## prompt piscar a cada passo, e piscar no canto do olho é a forma mais rápida de tornar
## uma informação invisível.
class_name ContextPrompt
extends CanvasLayer

const KEY_HINT_SEPARATOR: String = "   "

var _row: HBoxContainer = null
var _key: Label = null
var _verb: Label = null
var _fade: Tween = null
var _visible_now: bool = false


func _ready() -> void:
	layer = PROMPT_LAYER
	_build()
	_row.modulate.a = 0.0


## Passa a escutar o foco de interação e a conversa.
##
## Separado do `_ready` porque o prompt existe mesmo em cena sem jogador — e sem jogador
## não há foco nenhum para escutar. Quem liga é `WorldGenerator`, quando há alguém para
## apertar a tecla.
func watch() -> void:
	var bus: Node = get_node_or_null(EVENT_BUS_PATH)
	if bus == null:
		return
	bus.interactable_focused.connect(_on_focused)
	# Durante a conversa o prompt não tem o que oferecer, e mantê-lo faria a tecla abrir a
	# mesma conversa por cima dela mesma.
	bus.dialogue_requested.connect(_on_dialogue_started)
	bus.dialogue_finished.connect(_on_dialogue_finished)


const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"
## Tecla mostrada no prompt. Espelha a ação `interact` do input map gerado.
const KEY_HINT: String = "E"

var _muted: bool = false


func _on_focused(target: Interactable) -> void:
	if _muted:
		return
	show_for(target, KEY_HINT)


func _on_dialogue_started(_dialogue_id: StringName, _speaker: Node3D) -> void:
	_muted = true
	show_for(null, KEY_HINT)


func _on_dialogue_finished(_dialogue_id: StringName) -> void:
	_muted = false


## Camada de UI. Acima do mundo e abaixo da tela de conversa, que precisa cobrir isto.
const PROMPT_LAYER: int = 10


func _build() -> void:
	var anchor: Control = Control.new()
	anchor.name = "Anchor"
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_row.offset_bottom = -float(Params.PROMPT_BOTTOM_MARGIN)
	_row.offset_top = _row.offset_bottom - float(Params.PROMPT_FONT_SIZE * ROW_HEIGHT_FACTOR)
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override(&"separation", Params.PROMPT_FONT_SIZE)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_row)

	_key = _label(Params.PROMPT_KEY_FONT_SIZE, Params.color(&"thatch"))
	_key.name = "Key"
	_row.add_child(_key)

	_verb = _label(Params.PROMPT_FONT_SIZE, Params.color(&"cloth_cream"))
	_verb.name = "Verb"
	_row.add_child(_verb)


const ROW_HEIGHT_FACTOR: int = 2


func _label(size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	# Contorno em vez de caixa: o texto continua legível sobre parede clara e sobre sombra,
	# e não custa um retângulo escuro em cima do cenário.
	label.add_theme_color_override(&"font_outline_color", Params.color(&"wood_dark"))
	# Divisão inteira de propósito: contorno é largura em pixel, e meio pixel não existe.
	@warning_ignore("integer_division")
	var outline: int = size / OUTLINE_DIVISOR
	label.add_theme_constant_override(&"outline_size", outline)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## Divisor do contorno em relação ao tamanho da fonte. Estrutural: contorno é proporção.
const OUTLINE_DIVISOR: int = 5


## Mostra o prompt de um alvo, ou esconde quando `target` é nulo.
func show_for(target: Interactable, key_hint: String) -> void:
	if target == null:
		_fade_to(false)
		return
	_key.text = "[%s]" % key_hint
	_verb.text = target.prompt_text
	_fade_to(true)


func _fade_to(wanted: bool) -> void:
	if _visible_now == wanted:
		return
	_visible_now = wanted
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(
		_row, ^"modulate:a", Params.PROMPT_ALPHA if wanted else 0.0, Params.PROMPT_FADE_SECONDS
	)


## Visível agora? A prova lê daqui.
func is_showing() -> bool:
	return _visible_now
