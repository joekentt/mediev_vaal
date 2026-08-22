## Contador de quadros, em F3. Escondido até alguém pedir.
##
## Mostra o que se olha quando o jogo engasga: FPS, o pior quadro da janela, draw calls,
## triângulos e a hora do mundo. FPS sozinho é a média que esconde o engasgo — é a mesma
## razão pela qual `make bench` guarda o 1% low ao lado da média.
##
## Atualiza `FPS_REFRESH_HZ` vezes por segundo, não por quadro: um número que troca sessenta
## vezes por segundo é ilegível, e o custo de montar a string entraria na medida que ele
## mesmo está mostrando.
class_name FPSCounter
extends CanvasLayer

const LAYER: int = 30
const MS_PER_SEC: float = 1000.0

var _label: Label = null
var _timer: Timer = null
var _worst_ms: float = 0.0
var _time: Node = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_time = get_node_or_null(^"/root/TimeSystem")

	var anchor: Control = Control.new()
	anchor.name = "Anchor"
	anchor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_label = UIKit.label("", Params.FPS_FONT_SIZE, Params.color(&"cloth_cream"))
	_label.name = "Readout"
	_label.position = Vector2(Params.UI_SPACING, Params.UI_SPACING)
	anchor.add_child(_label)

	_timer = Timer.new()
	_timer.name = "Refresh"
	_timer.wait_time = 1.0 / maxf(Params.FPS_REFRESH_HZ, MIN_RATE)
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	_timer.start()

	visible = false


const MIN_RATE: float = 0.01


## O pior quadro é medido **entre atualizações**, e não desde sempre: o que interessa é o
## engasgo de agora, não o carregamento de três minutos atrás.
func _process(delta: float) -> void:
	_worst_ms = maxf(_worst_ms, delta * MS_PER_SEC)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fps"):
		visible = not visible
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not visible:
		_worst_ms = 0.0
		return
	var sample: Dictionary = Metrics.sample(get_viewport())
	_label.text = "%d FPS  (pior %.1f ms)   %d draw  %s tri   %s" % [
		Engine.get_frames_per_second(),
		_worst_ms,
		int(sample["draw_calls"]),
		_thousands(int(sample["triangles"])),
		_time.format_clock() if _time != null else "",
	]
	_worst_ms = 0.0


## 128574 -> "128 574". Um número de seis dígitos sem separador é uma parede de dígitos.
static func _thousands(value: int) -> String:
	var digits: String = str(value)
	var out: String = ""
	var count: int = 0
	for index: int in range(digits.length() - 1, -1, -1):
		out = digits[index] + out
		count += 1
		if count % GROUP == 0 and index > 0:
			out = " " + out
	return out


const GROUP: int = 3
