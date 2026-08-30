## A tela de conversa: falante, fala e até quatro escolhas. Toda construída em código.
##
## O painel não cobre a tela. Ele ocupa a faixa de baixo e deixa os dois terços de cima
## livres, porque é lá que está o enquadramento de ombro que a câmera acabou de montar —
## uma caixa de diálogo que tapa o interlocutor desfaz o trabalho da câmera.
##
## O texto se revela a `DIALOGUE_TEXT_SPEED` caracteres por segundo, e a primeira tecla
## completa a linha em vez de avançar. É a convenção que todo jogador já tem na mão: quem
## lê rápido não espera, e quem apertou sem querer não perde a fala.
class_name DialogueScreen
extends CanvasLayer

## Emitido quando o jogador escolhe. `index` é a posição na lista de escolhas visíveis.
signal chosen(index: int)

const HALF: float = 0.5
## Camada acima do prompt de contexto, que ela cobre enquanto está aberta.
const DIALOGUE_LAYER: int = 20

var _panel: PanelContainer = null
var _speaker: Label = null
var _text: RichTextLabel = null
var _choices: VBoxContainer = null
var _fade: Tween = null

var _full_text: String = ""
var _revealed: float = 0.0
var _open: bool = false


func _ready() -> void:
	layer = DIALOGUE_LAYER
	_build()
	_panel.modulate.a = 0.0
	_panel.visible = false
	set_process(false)


func _build() -> void:
	var anchor: Control = Control.new()
	anchor.name = "Anchor"
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -float(Params.DIALOGUE_PANEL_MARGIN)
	_panel.add_theme_stylebox_override(&"panel", _panel_style())
	anchor.add_child(_panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override(&"separation", Params.DIALOGUE_SPEAKER_FONT_SIZE)
	_panel.add_child(column)

	_speaker = Label.new()
	_speaker.name = "Speaker"
	_speaker.add_theme_font_size_override(&"font_size", Params.DIALOGUE_SPEAKER_FONT_SIZE)
	_speaker.add_theme_color_override(&"font_color", Params.color(&"thatch"))
	column.add_child(_speaker)

	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_size_override(&"normal_font_size", Params.DIALOGUE_FONT_SIZE)
	_text.add_theme_color_override(&"default_color", Params.color(&"cloth_cream"))
	column.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	# Divisão inteira de propósito: separação é pixel, e meio pixel não existe.
	@warning_ignore("integer_division")
	var gap: int = Params.DIALOGUE_CHOICE_FONT_SIZE / 2
	_choices.add_theme_constant_override(&"separation", gap)
	column.add_child(_choices)


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var base: Color = Params.color(&"wood_dark")
	style.bg_color = Color(base.r, base.g, base.b, Params.DIALOGUE_PANEL_ALPHA)
	style.border_color = Params.color(&"bark_light")
	var pad: int = Params.DIALOGUE_FONT_SIZE
	style.content_margin_left = float(pad)
	style.content_margin_right = float(pad)
	style.content_margin_top = float(pad)
	style.content_margin_bottom = float(pad)
	style.border_width_top = BORDER_WIDTH
	return style


const BORDER_WIDTH: int = 2


## Abre a tela com um nó de conversa já resolvido.
##
## `lines` são só os textos das escolhas visíveis: quem decidiu quais aparecem foi a
## `DialogueTree`, e esta tela não conhece condição nenhuma.
func present(speaker: String, text: String, lines: PackedStringArray) -> void:
	_panel.custom_minimum_size = Vector2(
		float(get_viewport().get_visible_rect().size.x) * Params.DIALOGUE_PANEL_WIDTH, 0.0
	)
	_speaker.text = speaker
	_full_text = text
	_revealed = 0.0
	_text.text = ""

	for child: Node in _choices.get_children():
		child.queue_free()
	for index: int in lines.size():
		_choices.add_child(_choice_label(index, lines[index]))

	if not _open:
		_open = true
		_panel.visible = true
		_fade_to(Params.DIALOGUE_PANEL_ALPHA)
	set_process(true)


func _choice_label(index: int, text: String) -> Label:
	var label: Label = Label.new()
	label.name = "Choice_%d" % index
	label.text = "%d. %s" % [index + 1, text]
	label.add_theme_font_size_override(&"font_size", Params.DIALOGUE_CHOICE_FONT_SIZE)
	label.add_theme_color_override(&"font_color", Params.color(&"cloth_cream"))
	return label


## Revela o texto aos poucos. É o único `_process` da UI, e ele se desliga sozinho quando a
## linha termina.
func _process(delta: float) -> void:
	_revealed += delta * Params.DIALOGUE_TEXT_SPEED
	var count: int = mini(int(_revealed), _full_text.length())
	_text.text = _full_text.substr(0, count)
	if count >= _full_text.length():
		set_process(false)


## A linha já está inteira na tela?
func is_revealed() -> bool:
	return _text.text.length() >= _full_text.length()


## Completa a linha de uma vez.
func reveal_all() -> void:
	_revealed = float(_full_text.length())
	_text.text = _full_text
	set_process(false)


func close() -> void:
	if not _open:
		return
	_open = false
	set_process(false)
	_fade_to(0.0)


func is_open() -> bool:
	return _open


func _fade_to(alpha: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_panel, ^"modulate:a", alpha, Params.DIALOGUE_FADE_SECONDS)
	if alpha <= 0.0:
		_fade.tween_callback(_hide_panel)


func _hide_panel() -> void:
	_panel.visible = false


## Quantas escolhas estão na tela. A prova e o runner leem daqui.
func choice_count() -> int:
	return _choices.get_child_count()


## Anuncia uma escolha. Chamado pelo runner quando a tecla correspondente é apertada.
func choose(index: int) -> void:
	if index < 0 or index >= choice_count():
		return
	chosen.emit(index)
