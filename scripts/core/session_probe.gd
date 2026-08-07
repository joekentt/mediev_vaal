## Modo headless de medição e captura, dirigido pela linha de comando.
##
## É o que dá números a `make preview` e `make bench` sem ninguém olhar para a tela.
## Argumentos passados depois de `--`:
##
##     --bench                mede `Params.BENCH_SAMPLE_FRAMES` frames e encerra
##     --screenshot <arquivo> salva um PNG do viewport e encerra
##     --out <arquivo>        grava o resumo em JSON no caminho dado
##     --budget <chave>       teto de draw calls a cobrar (padrão: draw_calls_wilderness)
##
## Sem nenhum desses argumentos o nó não faz nada — o jogo roda normalmente.
class_name SessionProbe
extends Node

const ARG_BENCH: String = "--bench"
const ARG_SCREENSHOT: String = "--screenshot"
const ARG_OUT: String = "--out"
const ARG_BUDGET: String = "--budget"
const RESULT_PREFIX: String = "MEDIEV_RESULT "
const HEADLESS_DISPLAY: String = "headless"
const DEFAULT_BUDGET_KEY: StringName = &"draw_calls_wilderness"

var _samples: Array[Dictionary] = []
var _screenshot_path: String = ""
var _out_path: String = ""
var _budget_key: StringName = DEFAULT_BUDGET_KEY
var _wants_bench: bool = false


## Verdadeiro se a linha de comando pediu alguma medição.
static func is_requested() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	return args.has(ARG_BENCH) or args.has(ARG_SCREENSHOT)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_arguments()
	_run.call_deferred()


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_wants_bench = args.has(ARG_BENCH)
	_screenshot_path = _value_after(args, ARG_SCREENSHOT)
	_out_path = _value_after(args, ARG_OUT)
	var budget: String = _value_after(args, ARG_BUDGET)
	if not budget.is_empty():
		_budget_key = StringName(budget)


func _value_after(args: PackedStringArray, flag: String) -> String:
	var index: int = args.find(flag)
	if index < 0 or index + 1 >= args.size():
		return ""
	var value: String = args[index + 1]
	if value.begins_with("--"):
		return ""
	return value


func _run() -> void:
	# `RenderingServer.frame_post_draw` nunca dispara sem display — numa sessão headless
	# ele travaria o processo. O laço anda por `process_frame`, que existe nos dois casos.
	var headless: bool = DisplayServer.get_name() == HEADLESS_DISPLAY

	for _frame: int in Params.BENCH_WARMUP_FRAMES:
		await get_tree().process_frame

	var frames: int = Params.BENCH_SAMPLE_FRAMES if _wants_bench else Params.SCREENSHOT_WAIT_FRAMES
	for _frame: int in frames:
		await get_tree().process_frame
		_samples.append(Metrics.sample(get_viewport()))

	if not _screenshot_path.is_empty():
		if headless:
			push_warning("Captura ignorada: sessão headless não desenha nada.")
		else:
			await RenderingServer.frame_post_draw
			_save_screenshot(_screenshot_path)

	var summary: Dictionary = Metrics.summarize(_samples)
	summary["budget_key"] = String(_budget_key)
	summary["violations"] = Metrics.check_budget(summary, _budget_key)
	summary["headless"] = headless
	EventBus.metrics_sampled.emit(summary)

	_report(summary)
	get_tree().quit()


func _save_screenshot(path: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_error("Não foi possível capturar o viewport.")
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Falha ao salvar %s (erro %d)." % [path, error])


func _report(summary: Dictionary) -> void:
	var payload: String = JSON.stringify(summary)
	# Prefixo fixo: é assim que tools/preview.py acha o resultado no meio do log do Godot.
	print(RESULT_PREFIX + payload)

	if _out_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível escrever %s." % _out_path)
		return
	file.store_string(JSON.stringify(summary, "  "))
	file.close()
