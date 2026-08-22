## A tela de carregamento: uma cortina e uma linha dizendo o que está acontecendo.
##
## Existe porque gerar o vale bloqueia a thread principal por cerca de um segundo — relevo,
## erosão, estrada, cidade, população — e um segundo de tela congelada sem aviso lê como
## travamento. Não há barra de progresso, e isso é honesto: a geração é uma sequência de
## chamadas síncronas, e uma barra que anda em passos inventados mente sobre o que falta.
##
## O texto muda por etapa, e é o próprio `WorldGenerator` que anuncia. Quem lê "assando a
## navegação" sabe que o jogo não morreu.
class_name LoadingScreen
extends CanvasLayer

const LAYER: int = 28

var _line: Label = null
var _screen: Control = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_screen.visible = false


func _build() -> void:
	_screen = UIKit.screen()
	add_child(_screen)
	_screen.add_child(UIKit.curtain(Params.color(&"sky_night")))

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(center)

	var column: VBoxContainer = UIKit.column()
	center.add_child(column)
	column.add_child(UIKit.label(
		Params.PROJECT_NAME, Params.UI_TITLE_FONT_SIZE, Params.color(&"thatch")
	))
	_line = UIKit.label("", Params.UI_FONT_SIZE, Params.color(&"stone_light"))
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_line)


## Mostra a cortina imediatamente, sem fade: ela precisa estar na tela **antes** do quadro
## que trava, e um fade de um terço de segundo começaria depois de a geração já ter começado.
func open(text: String) -> void:
	_line.text = text
	_screen.modulate.a = 1.0
	_screen.visible = true


func step(text: String) -> void:
	_line.text = text


func close() -> void:
	UIKit.fade(_screen, false)
