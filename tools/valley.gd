## Prova que a seed manda no vale, e que os dois vales que ela produz são jogáveis.
##
##     godot --script res://tools/valley.gd
##
## Os critérios de aceite da fase são duas frases de olho — "duas seeds diferentes
## produzem vales reconhecivelmente diferentes" e "ambos jogáveis" — e este script as
## transforma em número.
##
## **Diferentes** é medido comparando os dois campos de altura ponto a ponto, e não
## olhando duas capturas. Duas capturas parecidas podem ser o mesmo vale de ângulos
## diferentes; a diferença média de altura, como fração da amplitude, não tem como mentir.
## A entrada da estrada entra junto: é o que mais muda a leitura do mapa entre duas seeds.
##
## A comparação olha **para dentro da borda**, e normaliza pela amplitude do que olhou. A
## subida das bordas é função só da posição: ela é idêntica em toda seed, por construção, e
## ainda por cima é a parte mais alta do mapa. Incluí-la punha no denominador 20 m de
## relevo que nenhuma seed tem como mudar, e a mesma diferença de vale aparecia como 11%
## em vez de 18%. Não é afrouxar o critério: é medir o vale, que é onde se joga, em vez do
## muro em volta dele.
##
## Junto vai o **caso nulo**: a mesma seed gerada duas vezes tem de dar diferença zero. Sem
## ele, um número como "18% de diferença" não teria piso — poderia ser ruído de medição do
## mesmo tamanho. Com ele, o critério tem os dois lados: zero quando é o mesmo vale, acima
## de `VALLEY_MIN_DIFFERENCE` quando não é.
##
## **Jogável** se decompõe em três coisas verificáveis: a estrada não passa da inclinação
## máxima em nenhum trecho, a malha de navegação cobre uma fração razoável do vale, e o
## ponto de nascimento do jogador está apoiado em chão de verdade. Um vale bonito com
## navegação vazia não é jogável, e a captura não mostraria isso.
##
## Cada seed é gerada **num processo do Godot só**, uma depois da outra, com o mundo
## inteiro descartado no meio. Gerar as duas lado a lado seria mais rápido e provaria
## menos: o que se quer saber é se o mesmo caminho de código, rodado duas vezes, dá vales
## diferentes — e não se duas instâncias coexistem.
extends SceneTree

const HEADLESS_DISPLAY: String = "headless"
const RESULT_PREFIX: String = "MEDIEV_VALLEY "
## Amostras por lado na comparação de relevo. 64x64 cobre o vale com granularidade de 8 m,
## que é mais fina que qualquer diferença que o olho chamaria de "outro vale".
const COMPARE_SAMPLES: int = 64
## Quadros de espera antes de capturar, para o assado de navegação terminar e a
## vegetação entrar nas faixas de LOD.
const SETTLE_FRAMES: int = 20
## Teto de espera pelo assado da navegação, em quadros. É trava, não expectativa.
const BAKE_TIMEOUT_FRAMES: int = 900


var _stage: Node3D = null
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _shots: Array[Image] = []


func _initialize() -> void:
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		push_error(
			"Sem display: sem renderizador não há captura, e a prova do vale entrega "
			+ "duas imagens pretas. Rode com xvfb-run ou numa sessão gráfica."
		)
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(Params.ANIM_FRAME_WIDTH, Params.ANIM_FRAME_HEIGHT))
	_run.call_deferred()


func _run() -> void:
	_build_viewport()

	var valleys: Array[Dictionary] = []
	var samples: Array[PackedFloat32Array] = []

	for world_seed: int in Params.VALLEY_SEEDS:
		var result: Dictionary = await _grow(world_seed)
		valleys.append(result)
		samples.append(result["heights"])
		result.erase("heights")
		print(
			"  seed %-8d relevo %.1f m  estrada %.3f (limite %.2f)  "
			% [world_seed, result["span_m"], result["road_slope"], Params.ROAD_MAX_SLOPE]
			+ "nav %.0f%% do vale  %d pedaços  %d plantas"
			% [
				float(result["walkable"]) * PERCENT,
				int(result["chunks"]),
				int(result["scatter_instances"]),
			]
		)

	var difference: float = _difference(samples[0], samples[1])
	var null_difference: float = _null_difference(samples[0])
	_save_strip()

	print(RESULT_PREFIX + JSON.stringify({
		"valleys": valleys,
		"difference": difference,
		"null_difference": null_difference,
		"min_difference": Params.VALLEY_MIN_DIFFERENCE,
		"min_walkable": Params.VALLEY_MIN_WALKABLE,
		"slope_limit": Params.ROAD_MAX_SLOPE,
		"dir": Params.VALLEY_DIR,
	}))
	quit(0)


const PERCENT: float = 100.0


# --- Uma seed -----------------------------------------------------------------


## Gera um vale, mede-o e fotografa-o. Descarta tudo ao sair.
func _grow(world_seed: int) -> Dictionary:
	_write_seed(world_seed)

	if _stage != null:
		root.remove_child(_stage)
		_stage.queue_free()
		await process_frame

	_stage = Node3D.new()
	root.add_child(_stage)
	WorldGenerator.build_stage(_stage, false)
	# As duas seeds são fotografadas do mesmo ponto para se comparar o relevo. Sob céus
	# diferentes, a diferença que salta aos olhos seria a luz, e não o vale.
	WorldGenerator.pin_sky(_stage, Params.SHOT_HOUR)

	var field: HeightField = WorldGenerator.last_field
	var report: Dictionary = WorldGenerator.last_report.duplicate()
	var region: NavigationRegion3D = _find_region(_stage)
	var walkable: float = await _wait_for_bake(region, field)

	for _frame: int in SETTLE_FRAMES:
		await process_frame
	_shots.append(await _capture(field))

	return {
		"seed": world_seed,
		"span_m": field.span(),
		"road_slope": float(report["road_slope"]),
		"chunks": int(report["chunks"]),
		"scatter_instances": int(report["scatter_instances"]),
		"scatter_nodes": int(report["scatter_nodes"]),
		"build_ms": float(report["build_ms"]),
		"walkable": walkable,
		"spawn": _spawn_check(field),
		"heights": _sample_heights(field),
	}


## Escreve a seed no manifesto e faz o `WorldGenerator` enxergá-la.
##
## É o mesmo caminho de `make world SEED=123`, exercitado de dentro do jogo: se o
## manifesto deixasse de ser lido, esta prova falharia junto com o comando.
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


## Espera o assado terminar e devolve a fração do vale que a navegação cobre.
##
## A cobertura é a área dos polígonos da malha de navegação dividida pela área do vale.
## Não é "quanto dá para andar" ao pé da letra — encosta íngreme não deveria mesmo estar
## lá —, mas é o número que separa "navegação existe" de "navegação vazia", que é o modo
## como esta parte falha na prática.
func _wait_for_bake(region: NavigationRegion3D, field: HeightField) -> float:
	if region == null:
		return 0.0
	var waited: int = 0
	while region.is_baking() and waited < BAKE_TIMEOUT_FRAMES:
		await process_frame
		waited += 1
	if region.is_baking():
		push_warning("Assado de navegação não terminou em %d quadros." % BAKE_TIMEOUT_FRAMES)
		return 0.0

	var mesh: NavigationMesh = region.navigation_mesh
	var vertices: PackedVector3Array = mesh.get_vertices()
	var area: float = 0.0
	for index: int in mesh.get_polygon_count():
		var polygon: PackedInt32Array = mesh.get_polygon(index)
		for corner: int in range(1, polygon.size() - 1):
			var a: Vector3 = vertices[polygon[0]]
			var b: Vector3 = vertices[polygon[corner]]
			var c: Vector3 = vertices[polygon[corner + 1]]
			# Área projetada em planta: é com ela que "fração do vale" faz sentido, já
			# que o vale é medido em metros quadrados de mapa e não de encosta.
			area += absf((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)) * 0.5
	return area / (field.size() * field.size())


## O ponto de nascimento tem de estar em cima do chão, e não dentro nem acima dele.
func _spawn_check(field: HeightField) -> Dictionary:
	var spawn: Vector3 = WorldGenerator.spawn_point(field)
	var ground: float = field.height_at(spawn.x, spawn.z)
	return {
		"y": spawn.y,
		"ground_y": ground,
		"clearance": spawn.y - ground,
		"slope": field.slope_at(spawn.x, spawn.z),
	}


## Amostra o relevo do vale numa grade grosseira, para comparar dois vales.
##
## A janela para em `TERRAIN_RIM_START`, onde a subida das bordas começa: dali para fora o
## relevo é o mesmo em qualquer seed, e comparar duas cópias da mesma parede não diz nada
## sobre se os vales são diferentes.
func _sample_heights(field: HeightField) -> PackedFloat32Array:
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(COMPARE_SAMPLES * COMPARE_SAMPLES)
	var reach: float = field.size() * 0.5 * Params.TERRAIN_RIM_START
	var step: float = (reach * 2.0) / float(COMPARE_SAMPLES)
	for row: int in COMPARE_SAMPLES:
		for column: int in COMPARE_SAMPLES:
			var x: float = -reach + (float(column) + 0.5) * step
			var z: float = -reach + (float(row) + 0.5) * step
			heights[row * COMPARE_SAMPLES + column] = field.height_at(x, z)
	return heights


## Diferença média entre dois relevos, como fração da amplitude que os dois cobrem.
##
## O denominador é a amplitude **do que foi amostrado**, e não a do campo inteiro: é o
## contraste que o jogador enxerga dentro do vale que dá sentido à fração.
func _difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var lowest: float = a[0]
	var highest: float = a[0]
	var total: float = 0.0
	for index: int in a.size():
		total += absf(a[index] - b[index])
		lowest = minf(lowest, minf(a[index], b[index]))
		highest = maxf(highest, maxf(a[index], b[index]))
	var span: float = highest - lowest
	if span <= 0.0:
		return 0.0
	return (total / float(a.size())) / span


## Caso nulo: a mesma seed, gerada de novo, tem de dar o mesmo vale.
##
## Só o campo de altura é reconstruído — nem malha, nem espalhamento, nem navegação. O que
## está em prova é o caminho ruído → planície → erosão → terraplenagem → estrada, que é de
## onde qualquer diferença poderia vir. Montar o mundo de novo custaria minutos e não
## provaria mais nada.
##
## A terraplenagem da cidade entra aqui **porque ela mexe no relevo**. Reconstruir só ruído
## e estrada comparava um vale sem cidade com um vale com cidade, e o caso nulo acusava
## 0,83% de diferença numa geração que é determinística — um falso positivo que teria
## mandado procurar não-determinismo onde não havia.
func _null_difference(reference: PackedFloat32Array) -> float:
	var world_seed: int = Params.VALLEY_SEEDS[0]
	var field: HeightField = TerrainGenerator.build_field(world_seed)
	var layout: CityLayout = CityGenerator.plan(field, world_seed)
	RoadGenerator.carve(field, world_seed, layout)
	return _difference(reference, _sample_heights(field))


# --- Captura ------------------------------------------------------------------


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(Params.ANIM_FRAME_WIDTH * 2, Params.ANIM_FRAME_HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = Params.STAGE_CAMERA_FOV
	_camera.far = Params.STAGE_CAMERA_FAR
	_viewport.add_child(_camera)
	_camera.make_current()


## Uma vista aérea do vale inteiro, do mesmo ponto para as duas seeds.
##
## Mesmo ponto é o que torna a comparação honesta: dois ângulos diferentes fariam qualquer
## par de vales parecer distinto.
func _capture(field: HeightField) -> Image:
	var point: Array = Params.SHOT_POINTS[0]
	_camera.global_position = point[1]
	_camera.look_at(field.ground_point(point[2].x, point[2].z), Vector3.UP)
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


func _save_strip() -> void:
	if _shots.is_empty():
		return
	var width: int = _shots[0].get_width()
	var height: int = _shots[0].get_height()
	var strip: Image = Image.create_empty(
		width, height * _shots.size(), false, _shots[0].get_format()
	)
	for index: int in _shots.size():
		strip.blit_rect(
			_shots[index],
			Rect2i(Vector2i.ZERO, Vector2i(width, height)),
			Vector2i(0, index * height)
		)
	DirAccess.make_dir_recursive_absolute(Params.VALLEY_DIR)
	var path: String = "%s/seeds.png" % Params.VALLEY_DIR
	if strip.save_png(path) == OK:
		print("  tira -> %s" % path)
