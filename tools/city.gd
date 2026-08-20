## Gera cada seed de cidade num processo do Godot só, mede-a e fotografa-a.
##
##     godot --script res://tools/city.gd
##
## Os critérios de aceite da fase são três frases de olho — "lê como habitável", "60 FPS na
## praça" e "três seeds, três cidades plausíveis, nenhuma quebrada" — e este script
## transforma em número tudo o que dá.
##
## **Nenhuma quebrada** se decompõe no que `CityGenerator.validate` já cobra sem cena
## (sobreposição, marcadores, becos sem saída) mais o que só existe depois do assado:
## **toda porta alcançável pela malha de navegação**. Alcançável de verdade, com caminho
## saindo da praça — perguntar só se há navegação *perto* da porta aprovaria uma casa
## murada por dentro de um quarteirão fechado.
##
## **60 FPS na praça** é medido onde dói: a câmera vai para a praça, que é o ponto mais
## carregado da cidade, e lê draw calls, triângulos e frame time do renderizador. Sem GPU
## o frame time não significa nada, e o script diz isso em vez de fingir que sim; draw
## calls e triângulos não dependem de GPU e continuam valendo.
##
## **Lê como habitável** não vira número nenhum, e é por isso que as seis capturas existem.
extends SceneTree

const HEADLESS_DISPLAY: String = "headless"
const RESULT_PREFIX: String = "MEDIEV_CITY "
const SEEDS_ENV: String = "MEDIEV_CITY_SEEDS"
const SHOT_EXTENSION: String = ".png"
## Quadros de espera antes de medir, para o assado terminar e o LOD assentar.
const SETTLE_FRAMES: int = 20
## Quadros medidos na praça. Poucos: o que se quer é o pico de draw calls, não uma média.
const MEASURE_FRAMES: int = 24
## Teto de espera pelo assado da navegação, em quadros.
const BAKE_TIMEOUT_FRAMES: int = 1200
const HALF: float = 0.5
## Campos de um ponto de captura, na ordem em que `CITY_SHOT_POINTS` os empacota.
const SHOT_NAME: int = 0
const SHOT_MARKER: int = 1
const SHOT_DISTANCE: int = 2
const SHOT_HEIGHT: int = 3
const SHOT_PITCH: int = 4

var _stage: Node3D = null
var _viewport: SubViewport = null
var _camera: Camera3D = null


func _initialize() -> void:
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		push_error(
			"Sem display: sem renderizador não há captura nem contador de draw call, e a "
			+ "prova da cidade entrega seis imagens pretas. Rode com xvfb-run."
		)
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	_build_viewport()

	var cities: Array[Dictionary] = []
	var seeds: Array[int] = _seeds()
	for index: int in seeds.size():
		var result: Dictionary = await _grow(seeds[index], index == 0)
		cities.append(result)
		print(
			"  seed %-8d %d prédios  %d lotes  %d ruas  %d marcadores  "
			% [
				seeds[index], int(result["buildings"]), int(result["lots"]),
				int(result["streets"]), int(result["markers"])
			]
			+ "praça %d draw calls  %d tris  %d portas fora do navmesh"
			% [
				int(result["plaza_draw_calls"]), int(result["plaza_triangles"]),
				int(result["doors_unreachable"])
			]
		)

	print(RESULT_PREFIX + JSON.stringify({
		"cities": cities,
		"draw_call_ceiling": Params.budget(&"draw_calls_city"),
		"triangle_ceiling": Params.budget(&"visible_tris"),
		"frame_budget_ms": Params.FRAME_BUDGET_MS,
		"min_buildings": Params.CITY_MIN_BUILDINGS,
		"dir": Params.CITY_DIR,
	}))
	quit(0)


func _seeds() -> Array[int]:
	var raw: String = OS.get_environment(SEEDS_ENV)
	if raw.is_empty():
		return Params.CITY_SEEDS
	var out: Array[int] = []
	for piece: String in raw.split(",", false):
		out.append(int(piece.strip_edges()))
	return out


# --- Uma seed -----------------------------------------------------------------


func _grow(world_seed: int, with_shots: bool) -> Dictionary:
	_write_seed(world_seed)

	if _stage != null:
		root.remove_child(_stage)
		_stage.queue_free()
		await process_frame

	_stage = Node3D.new()
	root.add_child(_stage)
	var started: int = Time.get_ticks_msec()
	WorldGenerator.build_stage(_stage, false)
	var build_ms: float = float(Time.get_ticks_msec() - started)
	# Três cidades sob o mesmo céu: o que se compara aqui é traçado, e uma delas medida
	# debaixo de chuva teria menos draw calls por causa da névoa, não por causa do traçado.
	WorldGenerator.pin_sky(_stage, Params.SHOT_HOUR)

	var layout: CityLayout = WorldGenerator.last_city
	var report: Dictionary = WorldGenerator.last_report.duplicate()
	var region: NavigationRegion3D = _find_region(_stage)
	await _wait_for_bake(region)
	for _frame: int in SETTLE_FRAMES:
		await process_frame

	var doors: Dictionary = _check_doors(layout, region)
	var plaza: Dictionary = await _measure_at(layout, _shot_transform(layout, Params.CITY_SHOT_POINTS[0]))
	if with_shots:
		await _capture_all(layout)

	return {
		"seed": world_seed,
		"buildings": int(report.get("buildings", 0)),
		"lots": int(report.get("lots", 0)),
		"streets": int(report.get("streets", 0)),
		"markers": int(report.get("markers", 0)),
		"house_markers": int(report.get("house_markers", 0)),
		"dead_ends": int(report.get("dead_ends", 0)),
		"layout_problems": int(report.get("city_problems", 0)),
		"instances": int(report.get("city_instances", 0)),
		"draw_nodes": int(report.get("city_draw_nodes", 0)),
		"occluders": int(report.get("city_occluders", 0)),
		"site_slope": float(report.get("site_slope", 0.0)),
		"terrace_cut_m": float(report.get("terrace_cut_m", 0.0)),
		"gate_road_distance_m": float(report.get("gate_road_distance_m", 0.0)),
		"doors_total": int(doors["total"]),
		"doors_unreachable": int(doors["unreachable"]),
		"doors_worst_gap_m": float(doors["worst_gap"]),
		"plaza_draw_calls": int(plaza["draw_calls"]),
		"plaza_triangles": int(plaza["triangles"]),
		"plaza_frame_ms": float(plaza["frame_ms"]),
		"build_ms": build_ms,
	}


## Escreve a seed no manifesto — o mesmo caminho de `make world SEED=123`.
func _write_seed(world_seed: int) -> void:
	var path: String = "%s/world/world_manifest.json" % Params.GENERATED_DIR
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Manifesto do mundo ausente: %s. Rode `make world`." % path)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("Manifesto do mundo ilegível: %s" % path)
		quit(1)
		return
	var manifest: Dictionary = parsed as Dictionary
	manifest["seed"] = world_seed
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(manifest, "  "))
	out.close()


func _find_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node as NavigationRegion3D
	for child: Node in node.get_children():
		var found: NavigationRegion3D = _find_region(child)
		if found != null:
			return found
	return null


func _wait_for_bake(region: NavigationRegion3D) -> void:
	if region == null:
		return
	var waited: int = 0
	while region.is_baking() and waited < BAKE_TIMEOUT_FRAMES:
		await process_frame
		waited += 1
	if region.is_baking():
		push_warning("Assado de navegação não terminou em %d quadros." % BAKE_TIMEOUT_FRAMES)
	# O mapa de navegação só publica a região no passo seguinte ao assado; medir antes
	# disso devolve um mapa vazio e reprovaria todas as portas de uma cidade correta.
	await physics_frame
	await physics_frame


## Toda porta tem de ter caminho até ela **saindo da praça**.
func _check_doors(layout: CityLayout, region: NavigationRegion3D) -> Dictionary:
	if layout == null or region == null:
		return {"total": 0, "unreachable": 0, "worst_gap": 0.0}

	var map: RID = region.get_navigation_map()
	var origin: Vector3 = NavigationServer3D.map_get_closest_point(map, layout.markers[&"praca"])
	var unreachable: int = 0
	var worst: float = 0.0

	for building: Dictionary in layout.buildings:
		var door: Vector3 = layout.ground(building["door"])
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, origin, door, true)
		var gap: float = INF
		if not path.is_empty():
			gap = Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(
				Vector2(door.x, door.z)
			)
		if gap > Params.CITY_DOOR_REACH:
			unreachable += 1
			worst = maxf(worst, gap if gap < INF else Params.CITY_DOOR_REACH)
		else:
			worst = maxf(worst, gap)
	return {"total": layout.buildings.size(), "unreachable": unreachable, "worst_gap": worst}


# --- Medição e captura --------------------------------------------------------


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(Params.CITY_SHOT_WIDTH, Params.CITY_SHOT_HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = Params.STAGE_CAMERA_FOV
	_camera.far = Params.STAGE_CAMERA_FAR
	_viewport.add_child(_camera)
	_camera.make_current()


## Posição e alvo de um ponto de captura, em torno do marcador que ele nomeia.
func _shot_transform(layout: CityLayout, shot: Array) -> Dictionary:
	var marker: StringName = shot[SHOT_MARKER]
	var target: Vector3 = layout.markers.get(marker, layout.markers[&"praca"])
	# A câmera fica entre o marcador e a praça, olhando para o marcador: assim o
	# enquadramento sempre tem cidade atrás do assunto, e não muralha e campo.
	var away: Vector2 = Vector2(target.x, target.z) - layout.plaza
	if away.length() < Params.CITY_PLAZA_RADIUS:
		away = Vector2(cos(layout.angle), sin(layout.angle)) * Params.CITY_PLAZA_RADIUS
	var direction: Vector2 = away.normalized()
	var spot: Vector2 = Vector2(target.x, target.z) + direction * float(shot[SHOT_DISTANCE])
	return {
		"position": Vector3(spot.x, target.y + float(shot[SHOT_HEIGHT]), spot.y),
		"target": target + Vector3.UP * float(shot[SHOT_PITCH]) * -HALF,
	}


func _aim(view: Dictionary) -> void:
	_camera.global_position = view["position"]
	_camera.look_at(view["target"], Vector3.UP)


func _measure_at(layout: CityLayout, view: Dictionary) -> Dictionary:
	if layout == null:
		return {"draw_calls": 0, "triangles": 0, "frame_ms": 0.0}
	_aim(view)

	var draw_calls: int = 0
	var triangles: int = 0
	var frame_total: float = 0.0
	for _frame: int in MEASURE_FRAMES:
		await RenderingServer.frame_post_draw
		var sample: Dictionary = Metrics.sample(_viewport)
		draw_calls = maxi(draw_calls, int(sample["draw_calls"]))
		triangles = maxi(triangles, int(sample["triangles"]))
		frame_total += float(sample["process_ms"])
	return {
		"draw_calls": draw_calls,
		"triangles": triangles,
		"frame_ms": frame_total / float(MEASURE_FRAMES),
	}


func _capture_all(layout: CityLayout) -> void:
	DirAccess.make_dir_recursive_absolute(Params.CITY_DIR)
	for shot: Array in Params.CITY_SHOT_POINTS:
		_aim(_shot_transform(layout, shot))
		for _frame: int in Params.SCREENSHOT_WAIT_FRAMES:
			await RenderingServer.frame_post_draw
		var image: Image = _viewport.get_texture().get_image()
		var path: String = "%s/%s%s" % [Params.CITY_DIR, String(shot[SHOT_NAME]), SHOT_EXTENSION]
		if image.save_png(path) == OK:
			print("  captura -> %s" % path)
