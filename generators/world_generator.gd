## Monta o mundo por código, em runtime.
##
## `scenes/world/main.tscn` contém um `Node3D` e nada mais. Céu, sol, terreno, estrada,
## vegetação, navegação e jogador são criados aqui, a partir de `Params` e de uma seed.
## Nenhum nó deste mundo existe porque alguém arrastou algo no editor — é o que torna o
## mundo inteiro regenerável e o que faz `make world SEED=123` significar alguma coisa.
##
## A ordem importa e é a única possível:
##
##   relevo → estrada (que corta o relevo) → malha e colisão → vegetação → navegação
##
## A estrada precisa do relevo para saber por onde passar e precisa alterá-lo antes de a
## malha existir; a vegetação precisa da estrada para não nascer no meio dela; a navegação
## precisa da malha final, porque é dela que o assador lê a geometria.
##
## O estágio plano da fase 1 continua aqui, em `build_flat_stage`: as provas de locomoção
## e de controle precisam de um piso previsível, porque medir passada em terreno acidentado
## mediria o terreno e não a passada.
class_name WorldGenerator
extends RefCounted

const STAGE_ROOT_NAME: StringName = &"Stage"
const TERRAIN_ROOT_NAME: StringName = &"Terrain"
const SCATTER_ROOT_NAME: StringName = &"Scatter"
const NAV_ROOT_NAME: StringName = &"Navigation"
const PLAYER_NODE_NAME: StringName = &"Player"
const DIALOGUE_NODE_NAME: StringName = &"Dialogue"
const PROMPT_NODE_NAME: StringName = &"Prompt"
const CYCLE_NODE_NAME: StringName = &"DayNight"
const WEATHER_NODE_NAME: StringName = &"Weather"
const SOUNDSCAPE_NODE_NAME: StringName = &"Soundscape"
const GROUND_MATERIAL: StringName = &"ground"
const GROUND_MESH_CATEGORY: StringName = &"stage_ground"
const MANIFEST_PATH: String = "/world/world_manifest.json"

const TONEMAP_LINEAR: String = "linear"
const TONEMAP_REINHARDT: String = "reinhardt"
const TONEMAP_FILMIC: String = "filmic"
const TONEMAP_ACES: String = "aces"
const SPLITS_ORTHOGONAL: String = "orthogonal"
const SPLITS_TWO: String = "2_splits"
const SPLITS_FOUR: String = "4_splits"

## Folga vertical do ponto de nascimento, para o jogador não começar dentro do chão.
const SPAWN_CLEARANCE: float = 0.4

## Campo do vale gerado por último. Quem precisa da altura do relevo — o bench, para não
## enterrar a câmera na montanha; a prova, para medir — lê daqui em vez de refazer o ruído.
static var last_field: HeightField = null
## Traçado da última cidade gerada. `make city` mede daqui; a fase 10 vai ler os marcadores.
static var last_city: CityLayout = null
## Estatística da última geração. Vai para `docs/bench.json` e para o relatório da prova.
static var last_report: Dictionary = {}


## Constrói o vale inteiro sob `root`, substituindo o que já estiver lá.
## Devolve o nó raiz do estágio.
##
## `with_player` desligado dá o vale sem ninguém dentro — é o que as provas visuais
## querem: um jogador extra apareceria no meio do quadro.
static func build_stage(root: Node3D, with_player: bool = true) -> Node3D:
	var stage: Node3D = _fresh_stage(root)
	var environment: WorldEnvironment = build_environment()
	var sun: DirectionalLight3D = build_sun()
	stage.add_child(environment)
	stage.add_child(sun)

	var world_seed: int = current_seed()
	var started: int = Time.get_ticks_msec()

	var field: HeightField = TerrainGenerator.build_field(world_seed)
	# O sítio da cidade escolhe-se e terraplena-se **antes** da estrada. Ao contrário, o
	# platô desceria por cima de um leito já cravado e a estrada chegaria por um degrau.
	var layout: CityLayout = CityGenerator.plan(field, world_seed)
	var curve: Curve3D = RoadGenerator.carve(field, world_seed, layout)
	# E a muralha só depois da estrada: é o campo de distância dela que diz onde é o portão.
	CityGenerator.plan_streets(layout, curve, world_seed)
	last_field = field
	last_city = layout

	var problems: PackedStringArray = CityGenerator.validate(layout)
	for problem: String in problems:
		push_error("Cidade inválida (seed %d): %s" % [world_seed, problem])

	var terrain: Node3D = Node3D.new()
	terrain.name = TERRAIN_ROOT_NAME
	stage.add_child(terrain)
	var chunks: int = TerrainGenerator.build_chunks(field, terrain, layout)

	var scatter_root: Node3D = Node3D.new()
	scatter_root.name = SCATTER_ROOT_NAME
	stage.add_child(scatter_root)
	# A vegetação não entra na cidade: uma árvore no meio da praça não é acaso simpático,
	# é um espalhamento que não sabe que a cidade existe.
	var scatter: Dictionary = ScatterGenerator.scatter(
		field, scatter_root, world_seed, layout.center, Params.CITY_RADIUS + Params.CITY_WALL_MARGIN
	)

	var city: Dictionary = CityBuilder.build(layout, field, stage, world_seed)

	var region: NavigationRegion3D = build_navigation()
	stage.add_child(region)
	region.bake_navigation_mesh(true)

	# Vida por último, e nesta ordem: o ambiente não depende de ninguém, mas a população
	# depende do assado de navegação e o martelo depende do artesão existir.
	var ambient: Dictionary = AmbientGenerator.build(layout, field, stage, world_seed)
	var population: Dictionary = PopulationGenerator.populate(
		layout, stage, world_seed, null, ambient["node"]
	)

	# Céu, tempo e som depois da cidade: o ciclo precisa dos lampiões para acendê-los e a
	# paisagem sonora precisa dos interiores para saber quando abafar.
	var atmosphere: Dictionary = build_atmosphere(stage, sun, environment.environment, layout)

	last_report = {
		"seed": world_seed,
		"chunks": chunks,
		"scatter_instances": int(scatter["instances"]),
		"scatter_nodes": int(scatter["nodes"]),
		"road_slope": RoadGenerator.measure_slope(field, curve),
		"road_slope_limit": Params.ROAD_MAX_SLOPE,
		"terrain_span_m": field.span(),
		"city_problems": problems.size(),
		"city_instances": int(city["instances"]),
		"city_draw_nodes": int(city["draw_nodes"]),
		"city_occluders": int(city["occluders"]),
		"npcs": int(population["npcs"]),
		"npc_archetypes": population["archetypes"],
		"npc_active_ceiling": int(population["active_ceiling"]),
		"ambient_smoke": int(ambient["smoke"]),
		"ambient_birds": int(ambient["birds"]),
		"ambient_leaves": int(ambient["leaves"]),
		"lanterns": int(city["lanterns"]),
		"lantern_lights": (city["lantern_lights"] as Array).size(),
		"weather": atmosphere["weather"].current(),
		"build_ms": float(Time.get_ticks_msec() - started),
	}
	last_report.merge(layout.report)

	# A conversa por último: ela precisa da câmera e do sensor do jogador, e nas provas sem
	# jogador ela existe do mesmo jeito — a prova de diálogo abre uma árvore sem ninguém
	# apertar tecla nenhuma.
	var runner: DialogueRunner = DialogueRunner.new()
	runner.name = DIALOGUE_NODE_NAME
	stage.add_child(runner)
	var prompt: ContextPrompt = ContextPrompt.new()
	prompt.name = PROMPT_NODE_NAME
	stage.add_child(prompt)

	var cycle: DayNightCycle = atmosphere["cycle"]
	cycle.bind_lanterns(city["lantern_lights"], city["lantern_glow"])

	if with_player:
		var player: Node3D = build_player(field)
		if player != null:
			stage.add_child(player)
			_bind_dialogue(player, runner, prompt)
			# O ouvinte é o corpo do jogador, e não a câmera: a câmera fica três metros
			# atrás, e ao entrar pela porta da taverna ela ainda está do lado de fora.
			(atmosphere["soundscape"] as Soundscape).set_listener(player)
			(atmosphere["weather"] as WeatherSystem).set_focus(player)
	return stage


## Ciclo do dia, clima e paisagem sonora, sob o estágio.
##
## Os três juntos porque são um trio: o clima multiplica o que o ciclo decide, e a
## paisagem sonora lê os dois. Montá-los separados obrigaria quem chama a conhecer a ordem
## de ligação — e a ordem importa, porque o ciclo aplica a primeira iluminação no `bind`.
static func build_atmosphere(
	stage: Node3D, sun: DirectionalLight3D, environment: Environment, layout: CityLayout
) -> Dictionary:
	var weather: WeatherSystem = WeatherSystem.new()
	weather.name = WEATHER_NODE_NAME
	stage.add_child(weather)
	weather.seed_with(current_seed())

	var cycle: DayNightCycle = DayNightCycle.new()
	cycle.name = CYCLE_NODE_NAME
	stage.add_child(cycle)
	cycle.bind(sun, environment, weather)

	var soundscape: Soundscape = Soundscape.new()
	soundscape.name = SOUNDSCAPE_NODE_NAME
	stage.add_child(soundscape)
	soundscape.bind(layout, null, weather)

	return {"cycle": cycle, "weather": weather, "soundscape": soundscape}


## Liga a conversa ao jogador: a câmera que enquadra e o sensor que escolhe o alvo.
##
## Feito aqui e não dentro do runner porque o runner não procura o jogador na árvore — nas
## provas não há jogador nenhum, e um runner que dependesse de achar um ficaria mudo.
static func _bind_dialogue(player: Node3D, runner: DialogueRunner, prompt: ContextPrompt) -> void:
	var camera: ThirdPersonCamera = player.get_node_or_null(^"CameraArm") as ThirdPersonCamera
	var sensor: InteractionSensor = player.get_node_or_null(^"Sensor") as InteractionSensor
	runner.bind(camera, sensor)
	prompt.watch()


## Trava o céu numa hora e num tempo fixos. Para quem mede, não para quem joga.
##
## `make bench` percorre uma rota fixa justamente para que duas execuções sejam
## comparáveis — e o histórico é a coluna de números que mostra regressão. Com o relógio
## andando e o tempo virando por sorteio, uma execução pegaria meio-dia de sol e a seguinte
## um entardecer de chuva: a diferença de draw calls entre as duas seria clima, e ninguém
## saberia disso lendo o CSV. A captura de tela tem o mesmo problema pela mesma razão.
static func pin_sky(stage: Node3D, hour: float) -> void:
	var weather: WeatherSystem = stage.find_child("Weather", true, false) as WeatherSystem
	if weather != null:
		weather.set_auto(false)
		weather.set_weather(Params.WEATHER_START, true)

	var time: Node = stage.get_node_or_null(^"/root/TimeSystem")
	if time != null:
		time.set_time_of_day(hour)
		time.clock_paused = true

	var cycle: DayNightCycle = stage.find_child(String(CYCLE_NODE_NAME), true, false) as DayNightCycle
	if cycle != null:
		cycle.apply_now()


## Estágio plano: céu, sol e chão liso, sem vale.
##
## É o cenário das provas de movimento. `make anim` mede deslizamento de pé e `make
## playtest` mede velocidade e salto; num vale, as duas mediriam a encosta.
static func build_flat_stage(root: Node3D) -> Node3D:
	var stage: Node3D = _fresh_stage(root)
	stage.add_child(build_environment())
	stage.add_child(build_sun())
	stage.add_child(build_flat_ground())
	stage.add_child(build_camera())
	return stage


static func _fresh_stage(root: Node3D) -> Node3D:
	var previous: Node = root.get_node_or_null(NodePath(STAGE_ROOT_NAME))
	if previous != null:
		root.remove_child(previous)
		previous.queue_free()

	var stage: Node3D = Node3D.new()
	stage.name = STAGE_ROOT_NAME
	root.add_child(stage)
	return stage


## Seed do mundo, lida do manifesto gerado.
##
## É o que faz `make world SEED=123` alcançar o runtime sem recompilar nada: o Python
## escreve a seed no manifesto, o jogo lê. Sem manifesto — árvore recém-clonada —, vale a
## seed de fábrica de `params.py`.
static func current_seed() -> int:
	var file: FileAccess = FileAccess.open(
		Params.GENERATED_DIR + MANIFEST_PATH, FileAccess.READ
	)
	if file == null:
		return Params.WORLD_SEED
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return Params.WORLD_SEED
	return int((parsed as Dictionary).get("seed", Params.WORLD_SEED))


## Céu procedural e névoa, sem HDRI nem textura.
##
## SDFGI fica desligado de propósito, e não por esquecimento: num vale aberto ele custa
## caro e entrega quase nada, porque a iluminação indireta que ele resolve bem é a de
## interior — e interior é a fase 9.
static func build_environment() -> WorldEnvironment:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Params.color(&"sky_zenith")
	sky_material.sky_horizon_color = Params.color(&"sky_horizon")
	sky_material.sky_curve = Params.SKY_CURVE
	# O hemisfério inferior do céu é névoa, não chão. Ele só aparece **abaixo** da silhueta
	# do terreno — de um alto, olhando o vale, é a faixa entre a linha dos morros e a linha
	# do horizonte. Pintado de terra escura, essa faixa lia como um paredão de barro atrás
	# das montanhas; com a cor da névoa, lê como distância, que é o que ela é.
	sky_material.ground_bottom_color = Params.color(&"fog")
	sky_material.ground_horizon_color = Params.color(&"sky_horizon")
	sky_material.sun_angle_max = Params.SUN_ANGLE_MAX
	sky_material.sun_curve = Params.SUN_CURVE

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = Params.AMBIENT_SKY_CONTRIBUTION
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = _tonemap_from_name(Params.TONEMAP_MODE)
	environment.tonemap_white = Params.TONEMAP_WHITE
	environment.fog_enabled = true
	environment.fog_light_color = Params.color(&"fog")
	environment.fog_density = Params.FOG_DENSITY
	environment.fog_sky_affect = Params.FOG_SKY_AFFECT
	environment.sdfgi_enabled = false
	environment.ssao_enabled = false
	environment.ssil_enabled = false

	var node: WorldEnvironment = WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = environment
	return node


## Traduz o nome de tonemap de `Params` para a constante da engine. Guardar o índice
## numérico em `params.py` daria um `int` cru numa propriedade de enum — e um aviso.
static func _tonemap_from_name(name: String) -> Environment.ToneMapper:
	if name == TONEMAP_LINEAR:
		return Environment.TONE_MAPPER_LINEAR
	if name == TONEMAP_REINHARDT:
		return Environment.TONE_MAPPER_REINHARDT
	if name == TONEMAP_FILMIC:
		return Environment.TONE_MAPPER_FILMIC
	if name == TONEMAP_ACES:
		return Environment.TONE_MAPPER_ACES
	push_error("Tonemap desconhecido em params.py: %s" % name)
	return Environment.TONE_MAPPER_FILMIC


## Luz direcional única — o orçamento só permite uma sombra direcional.
static func build_sun() -> DirectionalLight3D:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Params.color(&"sun")
	sun.light_energy = Params.STAGE_SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = _splits_from_name(Params.SHADOW_DIRECTIONAL_SPLITS)
	sun.directional_shadow_max_distance = Params.SHADOW_MAX_DISTANCE
	sun.position = Vector3(0.0, Params.STAGE_SUN_HEIGHT, 0.0)
	sun.rotation = Vector3(
		deg_to_rad(Params.STAGE_SUN_PITCH_DEG),
		deg_to_rad(Params.STAGE_SUN_YAW_DEG),
		0.0
	)
	return sun


## Traduz o número de cascatas de `Params` para a constante da engine.
##
## Cada cascata redesenha todo caster dentro do alcance da sombra, então este é um botão de
## draw calls disfarçado de botão de qualidade.
static func _splits_from_name(name: String) -> DirectionalLight3D.ShadowMode:
	if name == SPLITS_ORTHOGONAL:
		return DirectionalLight3D.SHADOW_ORTHOGONAL
	if name == SPLITS_FOUR:
		return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if name != SPLITS_TWO:
		push_warning("Cascatas de sombra desconhecidas: %s. Usando %s." % [name, SPLITS_TWO])
	return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


## Região de navegação sobre o terreno já construído.
##
## O assado roda numa thread: 512 m de vale em célula de 1 m é trabalho de segundos, e
## fazê-lo no `_ready` congelaria a tela na primeira coisa que o jogador vê. A geometria
## vem do grupo `NAV_GROUP`, em que cada pedaço de terreno se inscreve — a vegetação, que
## não bloqueia caminho nenhum, fica de fora do assado e não o encarece.
static func build_navigation() -> NavigationRegion3D:
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.cell_size = Params.NAV_CELL_SIZE
	mesh.cell_height = Params.NAV_CELL_HEIGHT
	mesh.agent_radius = Params.NAV_AGENT_RADIUS
	mesh.agent_height = Params.NAV_AGENT_HEIGHT
	mesh.agent_max_climb = Params.NAV_AGENT_MAX_CLIMB
	mesh.agent_max_slope = Params.NAV_AGENT_MAX_SLOPE_DEG
	# Colisor, e não malha: o terreno já expõe a sua malha de colisão e os prédios expõem
	# uma caixa por prédio. Ler malha visível obrigaria a cidade a publicar cada telha para
	# o assador, e a navegação não tem nada a fazer com telha — o que ela precisa saber é
	# onde não se passa, que é exatamente o que a caixa diz.
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Params.LAYER_WORLD
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = Params.NAV_GROUP

	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.name = NAV_ROOT_NAME
	region.navigation_mesh = mesh
	return region


## Instancia o jogador gerado, apoiado na planície.
static func build_player(field: HeightField) -> Node3D:
	if not ResourceLoader.exists(Params.PLAYER_SCENE):
		push_warning(
			"Cena do jogador ausente (%s). Rode `make player`." % Params.PLAYER_SCENE
		)
		return null
	var packed: PackedScene = ResourceLoader.load(Params.PLAYER_SCENE) as PackedScene
	if packed == null:
		return null
	var player: Node3D = packed.instantiate() as Node3D
	player.name = PLAYER_NODE_NAME
	player.position = spawn_point(field)
	return player


## Onde o jogador nasce: o portão da cidade, apoiado no relevo.
##
## Era o centro da planície até a cidade existir. Nascer no portão põe a cidade inteira à
## frente na primeira vista, que é onde ela deve estar — nascer na praça entregaria o
## interior antes da silhueta.
static func spawn_point(field: HeightField) -> Vector3:
	if field == null:
		return Vector3.ZERO
	var spot: Vector2 = field.plain_center
	if last_city != null:
		spot = last_city.gate_point + last_city.gate_normal * Params.CITY_WALL_MARGIN
	return field.ground_point(spot.x, spot.y, SPAWN_CLEARANCE)


## Chão plano do estágio da fase 1, com colisão de plano infinito.
static func build_flat_ground() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Params.LAYER_WORLD
	body.collision_mask = 0

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "GroundMesh"
	mesh_instance.mesh = build_ground_mesh()
	mesh_instance.material_override = MaterialLibrary.get_material(GROUND_MATERIAL)
	body.add_child(mesh_instance)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "GroundCollision"
	collision.shape = WorldBoundaryShape3D.new()
	body.add_child(collision)
	return body


## Grade plana em XZ com leve variação de tom por célula.
static func build_ground_mesh() -> ArrayMesh:
	var builder: MeshBuilder = MeshBuilder.new()
	var base: Color = Params.color(&"ground_default")
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = Params.WORLD_SEED

	var tint: Callable = func(_column: int, _row: int) -> Color:
		var jitter: float = noise.randf_range(-Params.STAGE_GROUND_TONE_JITTER, Params.STAGE_GROUND_TONE_JITTER)
		return base.lightened(jitter) if jitter > 0.0 else base.darkened(-jitter)

	builder.add_color_grid(
		Vector3.ZERO,
		Params.STAGE_GROUND_SIZE,
		Params.STAGE_GROUND_CELLS,
		tint
	)
	return builder.commit(GROUND_MESH_CATEGORY)


## Câmera fixa do estágio plano. O vale não a usa: lá quem enquadra é o jogador.
static func build_camera() -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = Params.STAGE_CAMERA_FOV
	camera.far = Params.STAGE_CAMERA_FAR
	camera.position = Vector3(0.0, Params.STAGE_CAMERA_HEIGHT, Params.STAGE_CAMERA_DISTANCE)
	camera.rotation = Vector3(deg_to_rad(Params.STAGE_CAMERA_PITCH_DEG), 0.0, 0.0)
	camera.current = true
	return camera
