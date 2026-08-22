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


## O mundo é construído aqui, e não carregando `main.tscn`: desde o MVP a cena principal
## abre no **menu**, e esperar que ela gere um vale sozinha mediria uma tela preta com um
## botão no meio. A coluna `scene` do histórico continua sendo o caminho da cena, para as
## linhas antigas seguirem comparáveis com as novas.
func _run() -> void:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	_root = WorldGenerator.build_stage(holder)

	_camera = Camera3D.new()
	_camera.fov = Params.STAGE_CAMERA_FOV
	_camera.far = Params.STAGE_CAMERA_FAR
	root.add_child(_camera)
	_camera.make_current()

	# Céu travado na hora de fábrica e no tempo firme. A rota é fixa para que duas
	# execuções sejam comparáveis, e um sorteio de clima no meio faria a diferença de draw
	# calls entre elas ser nuvem — sem que ninguém saiba disso lendo o CSV.
	WorldGenerator.pin_sky(_root, Params.SHOT_HOUR)

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
	report["stations"] = await _measure_stations()
	for station: Dictionary in report["stations"]:
		for problem: String in station["violations"]:
			var tagged: String = "%s: %s" % [station["name"], problem]
			if not (report["violations"] as Array).has(tagged):
				(report["violations"] as Array).append(tagged)
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


# --- Estações -----------------------------------------------------------------


## Três câmeras paradas, uma por regime de custo: campo aberto, portão e praça lotada.
##
## A rota mede o passeio e é o que vai para o histórico; as estações medem o **pior caso**
## de cada regime, que é o que se otimiza. Uma média de rota dilui exatamente o quadro que
## dói — e foi por isso que a auditoria desta fase precisou de pontos parados.
func _measure_stations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var layout: CityLayout = WorldGenerator.last_city
	if layout == null:
		return out
	for station: Array in Params.BENCH_STATIONS:
		out.append(await _measure_station(station, layout))
	return out


func _measure_station(station: Array, layout: CityLayout) -> Dictionary:
	var name: StringName = station[STATION_NAME]
	if bool(station[STATION_CROWD]):
		_crowd_the_plaza(layout)

	_aim(station, layout)
	for _frame: int in Params.BENCH_STATION_SETTLE:
		await RenderingServer.frame_post_draw

	var samples: Array[Dictionary] = []
	var previous_usec: int = Time.get_ticks_usec()
	for _frame: int in Params.BENCH_STATION_FRAMES:
		await RenderingServer.frame_post_draw
		var now_usec: int = Time.get_ticks_usec()
		var sample: Dictionary = Metrics.sample(root)
		sample["frame_ms"] = float(now_usec - previous_usec) / USEC_PER_MS
		previous_usec = now_usec
		samples.append(sample)

	var in_city: bool = _in_city()
	var summary: Dictionary = {
		"name": String(name),
		"in_city": in_city,
		"draw_calls": Metrics.peak(samples, "draw_calls"),
		"triangles": Metrics.peak(samples, "triangles"),
		"objects": Metrics.peak(samples, "objects"),
		"frame_ms_avg": Metrics.average(samples, "frame_ms"),
		"physics_ms": Metrics.average(samples, "physics_ms"),
		"process_ms": Metrics.average(samples, "process_ms"),
		"npcs_visible": _visible_npcs(),
	}
	summary["fps_avg"] = (
		Metrics.MS_PER_SEC / float(summary["frame_ms_avg"])
		if float(summary["frame_ms_avg"]) > 0.0 else 0.0
	)
	# Cada estação contra o teto do seu próprio regime: o portão e a praça são cidade, o
	# vale é campo aberto. Cobrar o teto de campo aberto na praça mede a coisa errada.
	var key: StringName = &"draw_calls_city" if in_city else &"draw_calls_wilderness"
	summary["ceiling"] = Params.budget(key)
	summary["violations"] = Metrics.check_budget(summary, key)
	return summary


const STATION_NAME: int = 0
const STATION_MARKER: int = 1
const STATION_DISTANCE: int = 2
const STATION_HEIGHT: int = 3
const STATION_PITCH: int = 4
const STATION_TURN: int = 5
const STATION_CROWD: int = 6


## Põe a câmera onde a estação pede: a tantos metros para fora do marcador, olhando de
## volta para ele, e então girada pelo `turn` e baixada pelo `pitch`.
##
## O giro é do **olhar**, não da posição, e essa distinção custou uma medição: girando a
## posição, a estação do vale nascia 170 m para dentro da cidade e media o casario inteiro
## de costas — 127 draw calls e vinte habitantes num ponto que deveria ser campo aberto.
## Girando o olhar, ela fica onde o nome diz, na estrada fora do portão, de costas para a
## muralha.
func _aim(station: Array, layout: CityLayout) -> void:
	var marker: StringName = station[STATION_MARKER]
	var anchor: Vector3 = layout.markers.get(marker, layout.markers[&"praca"])
	var away: Vector2 = Vector2(anchor.x, anchor.z) - layout.center
	if away.length() < MIN_LOOK_DISTANCE:
		# Marcador no centro (a praça): não há "para fora" definido, e a direção da malha
		# da cidade serve — é a mesma em qualquer seed, e é o que faz a captura repetir.
		away = Vector2(cos(layout.angle), sin(layout.angle))
	away = away.normalized()

	var flat: Vector2 = Vector2(anchor.x, anchor.z) + away * float(station[STATION_DISTANCE])
	var spot: Vector3 = Vector3(flat.x, anchor.y + float(station[STATION_HEIGHT]), flat.y)
	var field: HeightField = WorldGenerator.last_field
	if field != null:
		spot.y = maxf(spot.y, field.height_at(spot.x, spot.z) + Params.BENCH_CAMERA_CLEARANCE)

	_camera.global_position = spot
	_camera.look_at(Vector3(anchor.x, spot.y, anchor.z), Vector3.UP)
	_camera.rotate_object_local(Vector3.UP, deg_to_rad(float(station[STATION_TURN])))
	_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(station[STATION_PITCH])))


## Reúne todos os habitantes na praça, para a estação lotada ser lotada de verdade.
##
## Por construção e não por espera: a agenda junta onze pessoas no poço ao meio-dia, mas
## depender disso seria medir o relógio. O critério da fase 10 fala em vinte NPCs à vista, e
## é isso que se põe à vista — o pior caso, não o caso típico.
func _crowd_the_plaza(layout: CityLayout) -> void:
	var npcs: Array[Node] = []
	_collect_npcs(_root, npcs)
	if npcs.is_empty():
		return
	var center: Vector3 = layout.markers.get(&"praca", Vector3.ZERO)
	for index: int in npcs.size():
		var angle: float = TAU * float(index) / float(npcs.size())
		var radius: float = Params.BENCH_CROWD_RADIUS * (HALF + HALF * float(index % 2))
		var spot: Vector3 = center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var body: Node3D = npcs[index] as Node3D
		body.global_position = spot
		# De pé, olhando para o meio da praça: um bando de costas esconderia metade dos
		# rostos, e rosto é onde o corpo tem triângulo.
		body.look_at(Vector3(center.x, spot.y, center.z), Vector3.UP)


const HALF: float = 0.5


func _collect_npcs(node: Node, out: Array[Node]) -> void:
	if node is NPCController:
		out.append(node)
	for child: Node in node.get_children():
		_collect_npcs(child, out)


## Quantos habitantes estão dentro do tronco de visão da câmera agora.
func _visible_npcs() -> int:
	var npcs: Array[Node] = []
	_collect_npcs(_root, npcs)
	var seen: int = 0
	for npc: Node in npcs:
		var spot: Vector3 = (npc as Node3D).global_position
		if _camera.is_position_in_frustum(spot + Vector3.UP):
			seen += 1
	return seen


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


## Este quadro é um quadro de cidade?
##
## Pela **imagem**, e não pela posição da câmera. O orçamento tem dois tetos de draw call
## porque desenhar uma cidade custa mais que desenhar campo aberto — e o que custa é o que
## está no quadro, não onde estão os pés de quem olha. Do lado de fora do portão, a 19 m da
## muralha, a tela é casario de ponta a ponta: cobrar dela o teto de campo aberto mede a
## coisa errada, e foi o que aconteceu na primeira medição desta fase (137 de 150, com a
## cidade inteira em cena).
##
## Dentro da cidade continua sendo cidade mesmo olhando para fora: dali sempre há muralha e
## telhado em volta.
func _in_city() -> bool:
	var layout: CityLayout = WorldGenerator.last_city
	if layout == null:
		return false
	var spot: Vector3 = _camera.global_position
	if Vector2(spot.x, spot.z).distance_to(layout.center) < Params.CITY_RADIUS:
		return true
	var heart: Vector3 = layout.ground(layout.center)
	return _camera.is_position_in_frustum(heart)


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
	var stations: Array = report.get("stations", [])
	if not stations.is_empty():
		print("")
		print("  estação    draw calls   triângulos    NPCs    ms/frame")
		for station: Dictionary in stations:
			print(
				"  %-10s %4d/%-4d    %7d    %4d    %8.1f"
				% [
					station["name"], station["draw_calls"], station["ceiling"],
					station["triangles"], station["npcs_visible"], station["frame_ms_avg"],
				]
			)
		print("")

	var violations: Array = report["violations"]
	for violation: String in violations:
		print("  ESTOUROU: %s" % violation)
