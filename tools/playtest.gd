## Dirige o jogador por uma sequência fixa e mede o que os critérios de aceite pedem.
##
##     godot --script res://tools/playtest.gd
##
## "Andar/correr/pular fluidos" e "a câmera nunca atravessa parede" são frases de olho, e
## este script as transforma em número. Ele constrói uma arena — chão, anel de paredes,
## uma plataforma com beirada —, instancia `player.tscn` e **aperta as teclas de verdade**
## via `Input.action_press`. Falsear a entrada num nível mais baixo testaria o código que
## eu escrevi contra si mesmo; passando pelo input map, o que se prova é o caminho que o
## jogador vai usar.
##
## O que sai medido:
##
## - velocidade estabilizada andando e correndo, contra o alvo de `params.py`;
## - tempo até 90% da velocidade — é a "sensação de peso" em segundos;
## - altura do salto, contra `PLAYER_JUMP_HEIGHT`;
## - coyote time: sai da beirada, espera metade da janela, pula. Tem de subir.
## - a folga da câmera: a cada frame, a distância do braço até a geometria mais próxima
##   na direção da lente. Zero ou negativo é a câmera dentro da parede.
##
## Como as demais provas visuais, **não** roda com `--headless`: sem renderizador não há
## captura, e o `SpringArm3D` precisa de um mundo físico de verdade para varrer.
extends SceneTree

const HEADLESS_DISPLAY: String = "headless"
const RESULT_PREFIX: String = "MEDIEV_PLAYTEST "
const WALL_PART: String = "wall"

## Ações apertadas pela prova. Repetidas aqui, e não lidas de `PlayerController`, por um
## motivo de ordem de carga: `--script` compila este arquivo **antes** de o SceneTree
## existir, e uma referência estática ao controlador arrastaria o script dele para essa
## compilação precoce — onde os autoloads (`GameState`, `EventBus`) ainda não foram
## registrados e o identificador não resolve. Instanciado depois, pela cena, ele compila
## normalmente. São os nomes do input map gerado; `make verify` cobra que existam.
const ACTION_FORWARD: StringName = &"move_forward"
const ACTION_BACK: StringName = &"move_back"
const ACTION_SPRINT: StringName = &"sprint"
const ACTION_JUMP: StringName = &"jump"

## Tempo de cada trecho da sequência, em segundos. Curto o bastante para a prova caber num
## CI e longo o bastante para a velocidade estabilizar — 1,2 s a 12 m/s² passa dos 6 m/s.
const SEGMENT_SECONDS: float = 1.4
## Amostras finais de cada trecho usadas para a média. As primeiras estão acelerando.
const STEADY_SAMPLES: int = 20
## Fração da janela de coyote esperada antes de apertar pulo no teste da beirada.
const COYOTE_FRACTION: float = 0.5
## Fração da velocidade alvo cujo tempo de chegada é reportado. Não é 100% de propósito:
## `move_toward` chega ao alvo exato, mas o último décimo leva um tempo desproporcional e
## diria mais sobre a curva de aproximação do que sobre a sensação de peso.
const SPEED_REACHED_FRACTION: float = 0.9
## Altura do muro da arena, em múltiplos do grid. O kit já dá a peça na medida certa.
const WALL_TIERS: int = 2
## Conversão de fração para porcentagem, só para o relatório.
const PERCENT: float = 100.0

var _stage: Node3D = null
var _player: CharacterBody3D = null
var _arm: SpringArm3D = null
var _camera: Camera3D = null
var _mirror: Camera3D = null
var _viewport: SubViewport = null
var _shots: Array[Image] = []
var _camera_clearance: float = 1e9
var _ledge: Vector3 = Vector3.ZERO


func _initialize() -> void:
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		push_error(
			"Sem display: sem renderizador não há captura, e a prova da câmera "
			+ "ficaria sem imagem. Rode com xvfb-run ou numa sessão gráfica."
		)
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(Params.ANIM_FRAME_WIDTH, Params.ANIM_FRAME_HEIGHT))
	_run.call_deferred()


func _run() -> void:
	_build_arena()
	await _spawn_player()

	var report: Dictionary = {}
	report["walk"] = await _drive(&"andando", false)
	report["run"] = await _drive(&"correndo", true)
	report["jump"] = await _measure_jump()
	report["coyote"] = await _measure_coyote()
	report["camera"] = await _measure_camera()

	report["walk_target"] = Params.PLAYER_WALK_SPEED
	report["run_target"] = Params.PLAYER_RUN_SPEED
	report["jump_target"] = Params.PLAYER_JUMP_HEIGHT
	report["camera_clearance"] = _camera_clearance
	report["tolerance"] = Params.PLAYTEST_TOLERANCE
	report["dir"] = Params.PLAYTEST_DIR

	_save_strip()
	print(RESULT_PREFIX + JSON.stringify(report))
	quit(0)


# --- Arena --------------------------------------------------------------------


## Chão, anel de muros e uma plataforma com beirada.
##
## O anel existe para a câmera ter em que bater: num plano vazio, "a câmera não atravessa
## parede" é verdade por falta de parede. A plataforma existe para o coyote time ter uma
## beirada de onde cair.
func _build_arena() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	WorldGenerator.build_flat_stage(_stage)
	var stage_camera: Camera3D = _stage.get_node_or_null("Stage/Camera3D") as Camera3D
	if stage_camera != null:
		stage_camera.current = false

	var wall: PackedScene = ResourceLoader.load(
		"%s/%s.glb" % [Params.KIT_DIR, WALL_PART]
	) as PackedScene
	# Contagem derivada do raio, e não fixada: o anel **tem** de fechar. Com um número
	# solto em params.py, aumentar o raio abriria vãos por onde a câmera passaria sem
	# tocar em nada — e a prova diria "não atravessa parede" por falta de parede.
	var count: int = int(ceil(TAU * Params.PLAYTEST_ARENA_RADIUS / Params.GRID_SIZE))
	for index: int in count:
		var angle: float = TAU * float(index) / float(count)
		var spot: Vector3 = Vector3(
			cos(angle) * Params.PLAYTEST_ARENA_RADIUS,
			0.0,
			sin(angle) * Params.PLAYTEST_ARENA_RADIUS
		)
		for tier: int in WALL_TIERS:
			_add_block(spot + Vector3.UP * Params.WALL_HEIGHT * float(tier), angle, wall)

	_ledge = Vector3(
		Params.PLAYTEST_LEDGE_OFFSET.x * Params.GRID_SIZE,
		0.0,
		Params.PLAYTEST_LEDGE_OFFSET.y * Params.GRID_SIZE
	)
	_add_platform(_ledge)


## Um bloco de muro com colisão. A malha é a peça do kit quando ela existe; a colisão é
## sempre uma caixa, porque é ela que o `SpringArm3D` e o corpo consultam.
func _add_block(position: Vector3, yaw: float, mesh_scene: PackedScene) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = Params.LAYER_WORLD
	body.collision_mask = 0
	body.position = position
	# Tangente ao círculo, e não radial: a caixa tem 2 m no eixo X local, e girar só por
	# `-yaw` a deixava apontada para o centro. O anel virava um conjunto de raios com vãos
	# largos entre eles, e a câmera passava no meio sem tocar em parede nenhuma — a prova
	# teria dado "não atravessa" por falta do que atravessar.
	body.rotation = Vector3(0.0, -yaw - PI * 0.5, 0.0)
	_stage.add_child(body)

	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(Params.GRID_SIZE, Params.WALL_HEIGHT, Params.WALL_THICKNESS)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, Params.WALL_HEIGHT * 0.5, 0.0)
	body.add_child(shape)

	if mesh_scene != null:
		var visual: Node3D = mesh_scene.instantiate() as Node3D
		visual.position = Vector3(-Params.GRID_SIZE * 0.5, 0.0, 0.0)
		body.add_child(visual)


func _add_platform(spot: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = Params.LAYER_WORLD
	body.collision_mask = 0
	body.position = spot
	_stage.add_child(body)

	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(Params.GRID_SIZE * 2.0, Params.PLAYTEST_LEDGE_HEIGHT, Params.GRID_SIZE * 2.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, Params.PLAYTEST_LEDGE_HEIGHT * 0.5, 0.0)
	body.add_child(shape)


func _spawn_player() -> void:
	var packed: PackedScene = ResourceLoader.load(Params.PLAYER_SCENE) as PackedScene
	if packed == null:
		push_error("Cena do jogador ausente: %s. Rode `make player`." % Params.PLAYER_SCENE)
		quit(1)
		return

	_player = packed.instantiate() as CharacterBody3D
	_stage.add_child(_player)
	_player.global_position = Vector3.ZERO

	_arm = _player.get_node_or_null("CameraArm") as SpringArm3D
	_camera = _arm.get_node_or_null("Camera3D") as Camera3D

	# A lente de verdade **fica** onde está: filha do braço de mola, porque é o braço que
	# move os próprios filhos ao encontrar geometria. Movê-la para outro viewport — a
	# primeira tentativa — desligaria justamente o mecanismo que esta prova verifica.
	#
	# A captura sai de uma câmera-espelho num SubViewport, que copia a transformação da
	# lente a cada quadro. A janela do sistema não serve: sob renderizador de software ela
	# entrega uma imagem de vários quadros atrás, e a tira saía mostrando o jogador longe
	# do lugar onde o relatório dizia que ele estava.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(Params.ANIM_FRAME_WIDTH, Params.ANIM_FRAME_HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_3d = _stage.get_world_3d()
	_viewport.own_world_3d = false
	root.add_child(_viewport)

	_mirror = Camera3D.new()
	_mirror.fov = Params.CAMERA_FOV
	_mirror.far = Params.STAGE_CAMERA_FAR
	_viewport.add_child(_mirror)
	_mirror.make_current()

	for _frame: int in Params.PLAYTEST_SETTLE_FRAMES:
		await physics_frame
	_shots.append(await _grab())


# --- Trechos da sequência ------------------------------------------------------


## Segura para a frente (e opcionalmente correr) e mede o que sai.
func _drive(label: StringName, sprint: bool) -> Dictionary:
	var samples: Array[float] = []
	var reached: float = -1.0
	var elapsed: float = 0.0
	var target: float = Params.PLAYER_RUN_SPEED if sprint else Params.PLAYER_WALK_SPEED

	Input.action_press(ACTION_FORWARD)
	if sprint:
		Input.action_press(ACTION_SPRINT)

	var steps: int = int(SEGMENT_SECONDS * float(Engine.physics_ticks_per_second))
	for index: int in steps:
		await physics_frame
		elapsed += 1.0 / float(Engine.physics_ticks_per_second)
		_track_camera()
		# Velocidade lida do corpo, e não do controlador. A prova fica caixa-preta: se o
		# `planar_speed()` dele mentisse, este teste concordaria com a mentira.
		var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		if reached < 0.0 and speed >= target * SPEED_REACHED_FRACTION:
			reached = elapsed
		if index >= steps - STEADY_SAMPLES:
			samples.append(speed)

	_shots.append(await _grab())
	Input.action_release(ACTION_FORWARD)
	if sprint:
		Input.action_release(ACTION_SPRINT)
	await _rest()

	var total: float = 0.0
	for value: float in samples:
		total += value
	print("  %-10s velocidade %.2f m/s (alvo %.2f)  %.0f%% do alvo em %.2f s" % [
		String(label), total / float(samples.size()), target,
		SPEED_REACHED_FRACTION * PERCENT, reached
	])
	return {
		"speed": total / float(samples.size()),
		"target": target,
		"time_to_90": reached,
	}


func _measure_jump() -> Dictionary:
	var start: float = _player.global_position.y
	var peak: float = start
	Input.action_press(ACTION_JUMP)
	await physics_frame
	Input.action_release(ACTION_JUMP)

	var steps: int = int(SEGMENT_SECONDS * float(Engine.physics_ticks_per_second))
	for index: int in steps:
		await physics_frame
		_track_camera()
		peak = maxf(peak, _player.global_position.y)
		if index * 2 == steps:
			_shots.append(await _grab())
	await _rest()

	var height: float = peak - start
	print("  %-10s altura %.2f m (alvo %.2f)" % ["salto", height, Params.PLAYER_JUMP_HEIGHT])
	return {"height": height, "target": Params.PLAYER_JUMP_HEIGHT}


## Coyote time: anda para fora da plataforma e pula **depois** de já estar no ar.
##
## É o teste que separa "tem a variável" de "a variável funciona". Sem coyote, o pulo
## apertado meio quadro depois da beirada simplesmente não acontece, e o jogador jura que
## apertou — porque apertou.
func _measure_coyote() -> Dictionary:
	_player.global_position = _ledge + Vector3.UP * Params.PLAYTEST_LEDGE_HEIGHT
	_player.velocity = Vector3.ZERO
	for _frame: int in Params.PLAYTEST_SETTLE_FRAMES:
		await physics_frame

	# Anda até sair da plataforma.
	Input.action_press(ACTION_BACK)
	var airborne: bool = false
	var steps: int = int(SEGMENT_SECONDS * float(Engine.physics_ticks_per_second))
	for _index: int in steps:
		await physics_frame
		_track_camera()
		if not _player.is_on_floor():
			airborne = true
			break
	Input.action_release(ACTION_BACK)

	if not airborne:
		print("  %-10s o corpo não saiu da plataforma — teste inconclusivo" % "coyote")
		return {"jumped": false, "waited": 0.0, "reason": "sem beirada"}

	# Espera metade da janela e só então aperta pulo.
	var waited: float = 0.0
	var window: float = Params.PLAYER_COYOTE_TIME * COYOTE_FRACTION
	while waited < window:
		await physics_frame
		waited += 1.0 / float(Engine.physics_ticks_per_second)
		_track_camera()

	var before: float = _player.velocity.y
	Input.action_press(ACTION_JUMP)
	# Dois quadros, e não um: o sinal `physics_frame` do SceneTree é emitido **antes** dos
	# `_physics_process` do mesmo tique, então logo depois do primeiro `await` o
	# controlador ainda não viu a tecla. Medir ali dava "não pulou" com o pulo correto.
	await physics_frame
	await physics_frame
	Input.action_release(ACTION_JUMP)
	var jumped: bool = _player.velocity.y > before and _player.velocity.y > 0.0

	for _index: int in Params.PLAYTEST_SETTLE_FRAMES:
		await physics_frame
		_track_camera()
	await _rest()

	print("  %-10s pulou %s depois de %.3f s no ar (janela %.2f s)" % [
		"coyote", "sim" if jumped else "NÃO", waited, Params.PLAYER_COYOTE_TIME
	])
	return {"jumped": jumped, "waited": waited, "window": Params.PLAYER_COYOTE_TIME}


## Encosta o jogador no muro e gira a câmera em volta, procurando o pior enquadramento.
##
## Girar é o ponto: parado de frente para a parede a câmera está atrás do jogador, longe
## de tudo. É ao girar para o lado do muro que o braço tem de encurtar, e é aí que uma
## implementação de raio (em vez de forma) deixa a lente entrar na pedra.
func _measure_camera() -> Dictionary:
	_player.global_position = Vector3(
		0.0, 0.0, -(Params.PLAYTEST_ARENA_RADIUS - Params.GRID_SIZE)
	)
	_player.velocity = Vector3.ZERO
	for _frame: int in Params.PLAYTEST_SETTLE_FRAMES:
		await physics_frame

	var worst: float = 1e9
	var worst_yaw: float = 0.0
	var arm: ThirdPersonCamera = _arm as ThirdPersonCamera
	var turns: int = int(SEGMENT_SECONDS * float(Engine.physics_ticks_per_second)) * 2
	for index: int in turns:
		arm.orbit(TAU / float(turns), 0.0)
		await physics_frame
		var clearance: float = _camera_gap()
		if clearance < worst:
			worst = clearance
			worst_yaw = arm.yaw()
		_track_camera()
		if index * 2 == turns:
			_shots.append(await _grab())

	print("  %-10s folga mínima %.3f m (margem do braço %.2f m)" % [
		"câmera", worst, Params.CAMERA_SPRING_MARGIN
	])
	return {"clearance": worst, "worst_yaw_deg": rad_to_deg(worst_yaw)}


func _rest() -> void:
	for _frame: int in Params.PLAYTEST_SETTLE_FRAMES:
		await physics_frame
		_track_camera()


# --- Medida da câmera ----------------------------------------------------------


## Distância entre a lente e a geometria no caminho do braço.
##
## Positiva: a câmera está aquém do obstáculo, como deve. Zero ou negativa: a lente está
## dentro da parede, e o quadro mostraria o interior do muro. Medir isto todo frame, e não
## só nas poses fotografadas, é o que faz a prova cobrir a órbita inteira.
func _camera_gap() -> float:
	if _arm == null or _camera == null:
		return 1e9
	var origin: Vector3 = _arm.global_position
	var lens: Vector3 = _camera.global_position

	var space: PhysicsDirectSpaceState3D = _stage.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, lens)
	query.collision_mask = Params.LAYER_WORLD
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return origin.distance_to(lens)
	# Há geometria entre o alvo e a lente: a folga é negativa, e o tamanho diz o quanto a
	# lente passou da parede.
	return origin.distance_to(hit["position"]) - origin.distance_to(lens)


func _track_camera() -> void:
	_camera_clearance = minf(_camera_clearance, _camera_gap())


# --- Captura -------------------------------------------------------------------


func _grab() -> Image:
	_mirror.global_transform = _camera.global_transform
	_mirror.fov = _camera.fov
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


func _save_strip() -> void:
	if _shots.is_empty():
		return
	var width: int = _shots[0].get_width()
	var height: int = _shots[0].get_height()
	var strip: Image = Image.create_empty(
		width * _shots.size(), height, false, _shots[0].get_format()
	)
	for index: int in _shots.size():
		strip.blit_rect(
			_shots[index],
			Rect2i(Vector2i.ZERO, Vector2i(width, height)),
			Vector2i(index * width, 0)
		)
	DirAccess.make_dir_recursive_absolute(Params.PLAYTEST_DIR)
	var path: String = "%s/controle.png" % Params.PLAYTEST_DIR
	if strip.save_png(path) == OK:
		print("  tira -> %s" % path)
