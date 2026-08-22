## As peças de interface, construídas em código.
##
## Existe pelo mesmo motivo que `MeshBuilder` existe para malha: sem um lugar só que saiba
## como um botão é feito, cinco telas inventam cinco botões e a sexta inventa o sétimo
## tamanho de fonte. Aqui há **um** botão, **um** slider e **um** título, e todos os números
## vêm de `params.py`.
##
## Nenhuma cena de UI é montada no editor. Uma `.tscn` de menu arrastada à mão seria o
## primeiro arquivo do repositório que ninguém revisa — o diff é ilegível — e a próxima
## pessoa que mexesse num espaçamento não saberia que ele deveria ter vindo do gerador.
class_name UIKit
extends RefCounted

const HALF: float = 0.5


## Rótulo simples, com contorno em vez de caixa: legível sobre parede clara e sobre sombra.
static func label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var node: Label = Label.new()
	node.text = text
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", color)
	node.add_theme_color_override(&"font_outline_color", Params.color(&"wood_dark"))
	# Divisão inteira de propósito: contorno se mede em pixels cheios, e meio pixel de
	# contorno é meio pixel que o renderizador arredonda de qualquer jeito.
	@warning_ignore("integer_division")
	var outline: int = maxi(size / OUTLINE_DIVISOR, 1)
	node.add_theme_constant_override(&"outline_size", outline)
	return node


const OUTLINE_DIVISOR: int = 6


## Botão de menu. Largura fixa para a coluna ficar alinhada sem um container de tabela.
static func button(text: String, action: Callable) -> Button:
	var node: Button = Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(Params.UI_BUTTON_WIDTH, Params.UI_BUTTON_HEIGHT)
	node.add_theme_font_size_override(&"font_size", Params.UI_FONT_SIZE)
	node.focus_mode = Control.FOCUS_ALL
	if action.is_valid():
		node.pressed.connect(action)
	return node


## Uma linha de opção: rótulo à esquerda, controle à direita.
##
## O valor aparece **ao lado do controle**, e não dentro dele: um slider sem número obriga
## o jogador a adivinhar o que "três quartos" significa em distância de renderização.
static func row(text: String, control: Control) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", Params.UI_SPACING)

	var caption: Label = label(text, Params.UI_FONT_SIZE, Params.color(&"cloth_cream"))
	caption.custom_minimum_size = Vector2(Params.UI_BUTTON_WIDTH, 0.0)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(caption)
	line.add_child(control)
	return line


static func slider(
	from: float, to: float, value: float, changed: Callable
) -> HSlider:
	var node: HSlider = HSlider.new()
	node.min_value = from
	node.max_value = to
	node.step = (to - from) / float(SLIDER_STEPS)
	node.value = value
	node.custom_minimum_size = Vector2(Params.UI_SLIDER_WIDTH, Params.UI_BUTTON_HEIGHT)
	if changed.is_valid():
		node.value_changed.connect(changed)
	return node


## Passos de um slider. Cem seria precisão que ninguém usa com o mouse; vinte é um passo
## por clique de teclado que se sente.
const SLIDER_STEPS: int = 20


static func check(pressed: bool, toggled: Callable) -> CheckButton:
	var node: CheckButton = CheckButton.new()
	node.button_pressed = pressed
	node.add_theme_font_size_override(&"font_size", Params.UI_FONT_SIZE)
	if toggled.is_valid():
		node.toggled.connect(toggled)
	return node


## Escolha entre poucas opções nomeadas. `OptionButton` e não três botões: com três
## qualidades cabe, com cinco não caberia, e a lista cresce sem redesenhar a tela.
static func choice(options: Array, current: int, chosen: Callable) -> OptionButton:
	var node: OptionButton = OptionButton.new()
	for option: Variant in options:
		node.add_item(String(option).capitalize())
	node.selected = clampi(current, 0, maxi(options.size() - 1, 0))
	node.custom_minimum_size = Vector2(Params.UI_SLIDER_WIDTH, Params.UI_BUTTON_HEIGHT)
	node.add_theme_font_size_override(&"font_size", Params.UI_FONT_SIZE)
	if chosen.is_valid():
		node.item_selected.connect(chosen)
	return node


## Painel escuro translúcido: o fundo de qualquer tela de menu.
static func panel() -> PanelContainer:
	var node: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var backdrop: Color = Params.color(&"wood_dark")
	backdrop.a = Params.UI_PANEL_ALPHA
	style.bg_color = backdrop
	style.content_margin_left = Params.UI_MARGIN
	style.content_margin_right = Params.UI_MARGIN
	style.content_margin_top = Params.UI_MARGIN
	style.content_margin_bottom = Params.UI_MARGIN
	node.add_theme_stylebox_override(&"panel", style)
	return node


## Coluna centrada na tela, que é o esqueleto de todos os menus deste jogo.
static func column() -> VBoxContainer:
	var node: VBoxContainer = VBoxContainer.new()
	node.alignment = BoxContainer.ALIGNMENT_CENTER
	node.add_theme_constant_override(&"separation", Params.UI_SPACING)
	return node


## Cobre a tela inteira com uma cor. Serve de cortina de carregamento e de escurecedor
## atrás de um menu.
static func curtain(color: Color) -> ColorRect:
	var node: ColorRect = ColorRect.new()
	node.color = color
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## O nó que uma tela de menu usa para aparecer e sumir.
##
## `CanvasLayer` não é `CanvasItem` e **não tem `modulate`**: uma camada não se desvanece.
## Quem desvanece é este `Control` que cobre a tela inteira e carrega o conteúdo dela — e
## por isso toda tela deste jogo tem um, em vez de cada uma descobrir isso por conta.
static func screen() -> Control:
	var node: Control = Control.new()
	node.name = "Screen"
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	return node


## Faz um `Control` aparecer ou sumir em `UI_FADE_SECONDS`, devolvendo o tween.
##
## O fade não é enfeite: um menu que aparece de um quadro para o outro por cima do jogo lê
## como falha de renderização, e é o mesmo motivo pelo qual o prompt de contexto tem fade
## desde a fase 11.
static func fade(target: Control, visible_now: bool) -> Tween:
	var tween: Tween = target.create_tween()
	target.visible = true
	tween.tween_property(
		target, ^"modulate:a", 1.0 if visible_now else 0.0, Params.UI_FADE_SECONDS
	)
	if not visible_now:
		tween.tween_callback(func() -> void: target.visible = false)
	return tween
