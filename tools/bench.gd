## Benchmark: percorre uma rota fixa e mede o que o orçamento cobra.
##
##     godot --script res://tools/bench.gd
##     xvfb-run -a -s '-screen 0 1920x1080x24' godot --script res://tools/bench.gd
##
## Escreve `docs/bench.json` (a corrida de agora) e **acrescenta** uma linha a
## `docs/bench_history.csv` (todas as corridas até hoje). O CSV é o artefato que importa:
## um número solto não diz nada, uma coluna de números mostra regressão.
##
## **Por que 1% low e não só a média.** Média de FPS esconde engasgo: 240 frames a 60 e
## 3 frames a 12 dão uma média confortável e uma experiência ruim. O 1% low é o pior
## percentil — é o número que corresponde ao que o jogador sente como travada.
##
## **Sobre "tempo de script".** A coluna é `process_ms`, não `script_ms`: o Godot só expõe
## o passo idle inteiro (`TIME_PROCESS`), que inclui trabalho da engine além do GDScript.
## Separar os dois exige o profiler do editor, que não roda por linha de comando. Melhor
## uma coluna com o nome do que ela de fato mede.
##
## **Precisa de display, e por isso não usa `--headless`.** Nessa flag o Godot não
## renderiza, e draw calls e frame time viram zero e ruído. Gravar isso no histórico seria
## pior que não medir: a coluna pareceria saudável e esconderia a regressão que o CSV
## existe para mostrar. Sem renderizador, o script sai com erro.
extends SceneTree

const SCENE_PATH: String = "res://scenes/world/main.tscn"
const HEADLESS_DISPLAY: String = "headless"
const RESULT_PREFIX: String = "MEDIEV_BENCH "
## Distância mínima entre a câmera e o alvo para o `look_at` ser bem definido.
const MIN_LOOK_DISTANCE: float = 0.01
const CSV_HEADER: String = (
	"timestamp,scene,frames,fps_avg,fps_1pct_low,frame_ms_avg,frame_ms_worst,"
	+ "draw_calls,triangles,objects,physics_ms,process_ms,memory_mb,violations"
)
const PERCENT: float = 100.0
const USEC_PER_MS: float = 1000.0
const CSV_SEPARATOR: String = ","

var _root: Node3D = null
var _camera: Camera3D = null
var _samples: Array[Dictionary] = []


func _initialize() -> void:
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		push_error(
			"Sem display: draw calls e frame time não significam nada sem renderizador. "
			+ "Rode com xvfb-run ou numa sessão gráfica."
		)
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = ResourceLoader.load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Não consegui carregar %s" % SCENE_PATH)
		quit(1)
		return

	_root = packed.instantiate() as Node3D
	root.add_child(_root)

	_camera = Camera3D.new()
	_camera.fov = Params.STAGE_CAMERA_FOV
	_camera.far = Params.STAGE_CAMERA_FAR
	root.add_child(_camera)
	_camera.make_current()

	# Aquecimento: os primeiros frames pagam compilação de shader e alocação, e
	# entrariam no histórico como uma regressão que não existe.
	for _frame: int in Params.BENCH_WARMUP_FRAMES:
		_move_camera(0.0)
		await RenderingServer.frame_post_draw

	# Frame time por relógio, não pelo monitor de FPS: o monitor é suavizado, e é
	# justamente o frame isolado ruim que o 1% low precisa enxergar.
	var elapsed: float = 0.0
	var previous_usec: int = Time.get_ticks_usec()
	for frame: int in Params.BENCH_SAMPLE_FRAMES:
		var progress: float = float(frame) / float(Params.BENCH_SAMPLE_FRAMES)
		_move_camera(progress)
		await RenderingServer.frame_post_draw
		var now_usec: int = Time.get_ticks_usec()
		var sample: Dictionary = Metrics.sample(root)
		sample["frame_ms"] = float(now_usec - previous_usec) / USEC_PER_MS
		sample["in_city"] = _in_city()
		previous_usec = now_usec
		_samples.append(sample)
		elapsed += float(sample["frame_ms"])

	var report: Dictionary = _summarize(elapsed)
	_write_json(report)
	_append_history(report)
	_print(report)
	print(RESULT_PREFIX + JSON.stringify(report))
	quit(0)


## Move a câmera pela rota, interpolando entre os pontos. `progress` vai de 0 a 1.
func _move_camera(progress: float) -> void:
	var route: Array[Vector3] = Params.BENCH_ROUTE
	var segments: int = route.size()
	var position: float = progress * float(segments)
	var index: int = int(position) % segments
	var next_index: int = (index + 1) % segments
	var blend: float = position - floorf(position)

	var spot: Vector3 = route[index].lerp(route[next_index], blend)
	# A rota é fixa mas o vale muda com a seed: a altura de cada ponto é um piso, e a
	# câmera sobe até o relevo. Sem isto, trocar de seed enterraria a câmera dentro de uma
	# montanha e o bench mediria a face interna de um triângulo.
	var field: HeightField = WorldGenerator.last_field
	if field != null:
		var ground: float = field.height_at(spot.x, spot.z) + Params.BENCH_CAMERA_CLEARANCE
		spot.y = maxf(spot.y, ground)
	_camera.global_position = spot

	# Olhar para o próximo ponto da rota, e não para o centro: num vale de 512 m o centro
	# fica longe demais e metade da volta seria a mesma vista.
	var ahead: Vector3 = route[next_index]
	if field != null:
		ahead.y = maxf(ahead.y, field.height_at(ahead.x, ahead.z))
	if ahead.distance_to(spot) > MIN_LOOK_DISTANCE:
		_camera.look_at(ahead, Vector3.UP)


func _summarize(elapsed_ms: float) -> Dictionary:
	var frame_times: Array[float] = []
	for sample: Dictionary in _samples:
		frame_times.append(float(sample["frame_ms"]))
	frame_times.sort()

	var count: int = frame_times.size()
	var average_ms: float = elapsed_ms / float(count) if count > 0 else 0.0
	var worst_ms: float = frame_times[count - 1] if count > 0 else 0.0

	# 1% low: média dos piores 1% dos frames, não o pior isolado. Um único frame ruim é
	# ruído; a média do pior percentil é o engasgo reproduzível.
	var low_count: int = maxi(1, int(float(count) * Params.BENCH_LOW_PERCENTILE / PERCENT))
	var low_total: float = 0.0
	for index: int in low_count:
		low_total += frame_times[count - 1 - index]
	var low_ms: float = low_total / float(low_count)

	var summary: Dictionary = {
		"scene": SCENE_PATH,
		# A seed vai no relatório porque sem ela o histórico deixa de ser comparável: dois
		# vales diferentes dão números diferentes, e a linha do CSV não diria por quê.
		"seed": WorldGenerator.current_seed(),
		"world": WorldGenerator.last_report,
		"frames": count,
		"fps_avg": Metrics.MS_PER_SEC / average_ms if average_ms > 0.0 else 0.0,
		"fps_1pct_low": Metrics.MS_PER_SEC / low_ms if low_ms > 0.0 else 0.0,
		"frame_ms_avg": average_ms,
		"frame_ms_worst": worst_ms,
		"draw_calls": Metrics.peak(_samples, "draw_calls"),
		# O pico de campo aberto é medido **só nos quadros de campo aberto**. A rota fixa
		# passa dentro da cidade desde a fase 8, e cobrar o teto de campo aberto num quadro
		# com uma cidade inteira em cena mede a coisa errada: o orçamento sempre teve dois
		# tetos, e o que faltava era a rota saber em qual dos dois estava.
		"draw_calls_wilderness": _peak_where("draw_calls", false),
		"draw_calls_city": _peak_where("draw_calls", true),
		"city_frames": _count_where(true),
		"triangles": Metrics.peak(_samples, "triangles"),
		"objects": Metrics.peak(_samples, "objects"),
		"physics_ms": Metrics.average(_samples, "physics_ms"),
		"process_ms": Metrics.average(_samples, "process_ms"),
		"memory_mb": float(_samples[count - 1]["memory_mb"]),
		"materials_loaded": int(_samples[count - 1]["materials_loaded"]),
	}
	# Cada região contra o seu próprio teto. O resumo guarda o pico geral em `draw_calls`
	# para o histórico continuar comparável linha a linha.
	var wilderness: Dictionary = summary.duplicate()
	wilderness["draw_calls"] = summary["draw_calls_wilderness"]
	var violations: Array[String] = Metrics.check_budget(wilderness, &"draw_calls_wilderness")

	if int(summary["city_frames"]) > 0:
		var city: Dictionary = summary.duplicate()
		city["draw_calls"] = summary["draw_calls_city"]
		for problem: String in Metrics.check_budget(city, &"draw_calls_city"):
			if not violations.has(problem):
				violations.append(problem)
	summary["violations"] = violations
	return summary


## A câmera está dentro da cidade neste quadro?
func _in_city() -> bool:
	var layout: CityLayout = WorldGenerator.last_city
	if layout == null:
		return false
	var spot: Vector3 = _camera.global_position
	return Vector2(spot.x, spot.z).distance_to(layout.center) < Params.CITY_RADIUS


func _peak_where(key: String, in_city: bool) -> int:
	var highest: int = 0
	for sample: Dictionary in _samples:
		if bool(sample["in_city"]) == in_city:
			highest = maxi(highest, int(sample[key]))
	return highest


func _count_where(in_city: bool) -> int:
	var total: int = 0
	for sample: Dictionary in _samples:
		if bool(sample["in_city"]) == in_city:
			total += 1
	return total


func _write_json(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(Params.BENCH_JSON.get_base_dir())
	var file: FileAccess = FileAccess.open(Params.BENCH_JSON, FileAccess.WRITE)
	if file == null:
		push_error("Não consegui escrever %s" % Params.BENCH_JSON)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()


## Acrescenta uma linha ao histórico, criando o cabeçalho na primeira vez.
func _append_history(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(Params.BENCH_HISTORY.get_base_dir())
	var existed: bool = FileAccess.file_exists(Params.BENCH_HISTORY)

	var previous: String = ""
	if existed:
		var reader: FileAccess = FileAccess.open(Params.BENCH_HISTORY, FileAccess.READ)
		if reader != null:
			previous = reader.get_as_text()
			reader.close()

	var file: FileAccess = FileAccess.open(Params.BENCH_HISTORY, FileAccess.WRITE)
	if file == null:
		push_error("Não consegui escrever %s" % Params.BENCH_HISTORY)
		return
	if previous.is_empty():
		file.store_string(CSV_HEADER + "\n")
	else:
		file.store_string(previous if previous.ends_with("\n") else previous + "\n")

	var violations: Array = report["violations"]
	var row: Array[String] = [
		Time.get_datetime_string_from_system(true),
		String(report["scene"]),
		str(report["frames"]),
		"%.2f" % report["fps_avg"],
		"%.2f" % report["fps_1pct_low"],
		"%.3f" % report["frame_ms_avg"],
		"%.3f" % report["frame_ms_worst"],
		str(report["draw_calls"]),
		str(report["triangles"]),
		str(report["objects"]),
		"%.3f" % report["physics_ms"],
		"%.3f" % report["process_ms"],
		"%.1f" % report["memory_mb"],
		str(violations.size()),
	]
	file.store_string(CSV_SEPARATOR.join(row) + "\n")
	file.close()


func _print(report: Dictionary) -> void:
	print("  frames            %d" % report["frames"])
	print("  fps médio         %.1f" % report["fps_avg"])
	print("  fps 1%% low        %.1f" % report["fps_1pct_low"])
	print("  frame time médio  %.2f ms" % report["frame_ms_avg"])
	print("  frame time pior   %.2f ms" % report["frame_ms_worst"])
	print("  draw calls (pico) %d" % report["draw_calls"])
	print("  triângulos (pico) %d" % report["triangles"])
	print("  física            %.3f ms" % report["physics_ms"])
	print("  passo idle        %.3f ms" % report["process_ms"])
	var violations: Array = report["violations"]
	for violation: String in violations:
		print("  ESTOUROU: %s" % violation)
