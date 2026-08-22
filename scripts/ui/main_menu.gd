## Menu inicial: continuar, começar, opções, sair.
##
## "Continuar" só existe quando há save, e é o primeiro item porque é o que se quer em
## nove de cada dez aberturas. Um botão desabilitado no topo seria pior que a ausência
## dele: ocupa o lugar do que se quer clicar e não faz nada.
##
## O fundo é uma cor chapada da paleta, e não uma captura do jogo: uma imagem de fundo
## seria a única textura do projeto, e o projeto não tem textura de imagem em lugar nenhum.
class_name MainMenu
extends CanvasLayer

const LAYER: int = 20

signal start_requested(from_save: bool)
signal options_requested
signal quit_requested

var _screen: Control = null
var _column: VBoxContainer = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func open() -> void:
	_screen.visible = true
	_screen.modulate.a = 1.0


func close() -> void:
	UIKit.fade(_screen, false)


func _build() -> void:
	_screen = UIKit.screen()
	add_child(_screen)
	_screen.add_child(UIKit.curtain(Params.color(&"sky_night")))

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(center)

	_column = UIKit.column()
	center.add_child(_column)

	_column.add_child(UIKit.label(
		Params.PROJECT_NAME, Params.UI_TITLE_FONT_SIZE, Params.color(&"thatch")
	))
	_column.add_child(UIKit.label(
		"um vale, uma estrada, uma cidade", Params.UI_SMALL_FONT_SIZE,
		Params.color(&"stone_light")
	))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, Params.UI_MARGIN)
	_column.add_child(gap)

	if SaveGame.exists():
		_column.add_child(UIKit.button(
			"Continuar", func() -> void: start_requested.emit(true)
		))
	_column.add_child(UIKit.button(
		"Novo vale", func() -> void: start_requested.emit(false)
	))
	_column.add_child(UIKit.button("Opções", func() -> void: options_requested.emit()))
	_column.add_child(UIKit.button("Sair", func() -> void: quit_requested.emit()))
