## Tiras de quadros da locomoção — os olhos da animação.
##
##     godot --script res://tools/anim_preview.gd
##
## Uma malha parada num catálogo não diz nada sobre movimento. Este script põe o
## personagem para andar, correr e pular num estágio de verdade, grava um quadro a cada
## poucos passos de simulação e monta as tiras em `docs/anim/`. Ler a tira da esquerda
## para a direita é ver o ciclo.
##
## **E ele mede, não só desenha.** O critério "o pé não desliza" vira número: enquanto um
## pé está apoiado, a sua posição de mundo não pode mudar. O script guarda essa posição a
## cada passo de física e reporta o maior desvio dentro de um mesmo apoio. Olhar a tira
## pega o deslizamento grosseiro; o número pega o de meio centímetro, e pega em CI.
##
## O segundo critério — "raças diferentes andam visivelmente diferente" — sai da tira
## comparativa: três posturas congeladas na mesma fase do ciclo, com o comprimento de
## passo e a altura de pé de cada uma impressos junto.
##
## Como as capturas do kit, isto **não** roda com `--headless`: sem renderizador o
## viewport devolve preto, e uma tira preta passaria despercebida por muito tempo.
extends SceneTree

const HEADLESS_DISPLAY: String = "headless"
const RESULT_PREFIX: String = "MEDIEV_ANIM "
const GAIT_SCRIPT: String = "res://scripts/gameplay/gait_profile.gd"
const CHARACTER_MANIFEST: String = "manifest.json"

## Margem entre quadros da tira, em pixels. Sem ela os corpos encostam e viram borrão.
const STRIP_GUTTER: int = 2
## Passos de física gastos antes de qualquer captura, para a marcha engatar.
const PHYSICS_SUBSTEPS: int = 1
## Teto de passos de simulação por corpo na tira comparativa. É só uma trava: o laço sai
## quando a fase alvo passa, e passa muito antes disso.
const COMPARISON_LIMIT: int = 400
## O nó cronometra em microssegundos; a tabela de orçamento fala em milissegundos.
const USEC_PER_MS: float = 1000.0

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _stage: Node3D = null
var _report: Dictionary = {}


func _initialize() -> void:
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		push_error(
			"Sem display: o renderizador nulo não produz imagem. "
			+ "Rode com xvfb-run ou numa sessão gráfica."
		)
		quit(1)
		return
	# A janela do sistema não desenha nada útil aqui — o quadro sai do SubViewport. Ela
	# continua sendo rasterizada a cada frame, e num contêiner sem GPU rasterizar 1080p à
	# toa custou mais que a simulação inteira: a primeira execução gastou dez minutos
	# para produzir uma tira. Encolher a janela é o que faz a prova caber num CI.
	DisplayServer.window_set_size(Vector2i(Params.ANIM_FRAME_WIDTH, Params.ANIM_FRAME_HEIGHT))
	_run.call_deferred()


func _run() -> void:
	_build_stage()

	var strips: Array[String] = []
	var slides: Dictionary = {}
	var costs: Dictionary = {}

	for take: Array in [
		[&"caminhada", Params.ANIM_WALK_SPEED, false],
		[&"corrida", Params.ANIM_RUN_SPEED, false],
		[&"salto", Params.ANIM_JUMP_SPEED, true],
	]:
		var label: String = String(take[0])
		var result: Dictionary = await _record_take(label, take[1], take[2])
		strips.append(label)
		slides[label] = result["slide"]
		costs[label] = result["physics_ms"]
		print("  %-11s %2d quadros  passo %.2f m  desliza %.4f m  pose %.3f ms" % [
			label, result["frames"], result["step"], result["slide"], result["physics_ms"]
		])

	strips.append(await _record_states())

	var comparison: Dictionary = await _record_comparison()
	strips.append(comparison["name"])

	_report = {
		"strips": strips,
		"dir": Params.ANIM_DIR,
		"slide": slides,
		"slide_limit": Params.ANIM_FOOT_SLIDE_LIMIT,
		"physics_ms": costs,
		"gaits": comparison["gaits"],
	}
	print(RESULT_PREFIX + JSON.stringify(_report))
	quit(0)


# --- Cena --------------------------------------------------------------------


func _build_stage() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	WorldGenerator.build_stage(_stage)
	# A câmera do estágio existe para a captura do mundo; aqui a tira tem a sua própria,
	# dentro de um SubViewport de tamanho fixo. Depender da janela do sistema faria o
	# tamanho do quadro mudar com a resolução de quem rodou.
	var stage_camera: Camera3D = _stage.get_node_or_null("Stage/Camera3D") as Camera3D
	if stage_camera != null:
		stage_camera.current = false

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(Params.ANIM_FRAME_WIDTH, Params.ANIM_FRAME_HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.world_3d = _stage.get_world_3d()
	_viewport.own_world_3d = false
	root.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = Params.ANIM_CAMERA_FOV
	_camera.far = Params.STAGE_CAMERA_FAR
	_viewport.add_child(_camera)
	_camera.make_current()


## Instancia um personagem gerado e pendura nele a locomoção. Nada aqui sabe *qual*
## personagem é: o perfil de marcha vem da postura que o manifesto declara.
func _spawn(character: String) -> Dictionary:
	var path: String = "%s/%s.glb" % [Params.CHARACTER_DIR, character]
	var packed: PackedScene = ResourceLoader.load(path) as PackedScene
	if packed == null:
		push_error("Personagem ausente: %s. Rode `make characters`." % path)
		quit(1)
		return {}

	var body: Node3D = packed.instantiate() as Node3D
	_stage.add_child(body)

	var legs: ProceduralLocomotion = ProceduralLocomotion.new()
	legs.name = "Locomotion"
	legs.profile = GaitProfile.load_for(_posture_of(character))
	body.add_child(legs)
	return {"body": body, "legs": legs}


## Postura declarada pelo corpo no manifesto — o parâmetro por povo, lido do dado e não
## escrito num `if` aqui. É o que sustenta "sem código específico" no critério de aceite.
func _posture_of(character: String) -> StringName:
	var path: String = "%s/%s" % [Params.CHARACTER_DIR, CHARACTER_MANIFEST]
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return &"ereto"
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return &"ereto"
	for entry: Dictionary in (parsed as Dictionary)["characters"]:
		if entry["name"] == character:
			return StringName(entry["posture"])
	return &"ereto"


# --- Gravação de uma tira -----------------------------------------------------


func _record_take(label: String, speed: float, jumping: bool) -> Dictionary:
	var spawned: Dictionary = _spawn(Params.ANIM_SUBJECT)
	var body: Node3D = spawned["body"]
	var legs: ProceduralLocomotion = spawned["legs"]

	var frames: Array[Image] = []
	var tracker: FootTracker = FootTracker.new()
	var travel: float = 0.0
	var jump_frame: int = -1
	var physics_ms: float = 0.0
	var samples: int = 0

	var captures: int = Params.ANIM_STRIP_COLUMNS
	for index: int in Params.ANIM_SETTLE_FRAMES + captures * Params.ANIM_STEP_FRAMES:
		travel += speed * _step_time()
		body.global_position = Vector3(0.0, 0.0, -travel)
		_aim_camera(body, speed)

		if jumping and index == Params.ANIM_SETTLE_FRAMES and jump_frame < 0:
			legs.request_jump()
			jump_frame = index
		# O salto aqui é só de pose: o corpo não sai do chão, porque a física do jogador
		# é a fase 6. A tira mostra agachar, impulso, pernas recolhidas e amortecimento —
		# que é o que este nó controla e o que precisa ser conferido.
		if jumping and jump_frame >= 0 and index == jump_frame + Params.ANIM_STEP_FRAMES * 2:
			legs.notify_landed()

		await physics_frame
		tracker.sample(legs)
		# Custo do nó onde ele de fato roda. `make bench` mede o estágio vazio e não veria
		# isto; sem medir aqui, o orçamento de 40 NPCs ativos seria um palpite.
		if index >= Params.ANIM_SETTLE_FRAMES:
			physics_ms += float(legs.pose_usec) / USEC_PER_MS
			samples += 1

		var settled: int = index - Params.ANIM_SETTLE_FRAMES
		if settled >= 0 and settled % Params.ANIM_STEP_FRAMES == 0:
			frames.append(await _grab())

	var image: Image = _compose(frames)
	_save(image, label)
	var slide: float = tracker.worst
	var step: float = legs.step_length()
	body.queue_free()
	await process_frame
	return {
		"frames": frames.size(),
		"slide": slide,
		"step": step,
		"physics_ms": physics_ms / maxf(float(samples), 1.0),
	}


## Os estados que não são locomoção, um quadro cada.
##
## Existem por um motivo simples: até aqui ninguém tinha *visto* sentar, carregar,
## interagir ou olhar. Os quatro são código que roda sem erro e sem prova — e código de
## pose que roda sem erro pode perfeitamente estar deixando o personagem em T-pose.
func _record_states() -> String:
	var spawned: Dictionary = _spawn(Params.ANIM_SUBJECT)
	var body: Node3D = spawned["body"]
	var legs: ProceduralLocomotion = spawned["legs"]
	body.global_position = Vector3.ZERO

	var frames: Array[Image] = []
	for state: StringName in [&"parado", &"olhando", &"interagindo", &"sentado", &"carregando"]:
		legs.clear_look()
		legs.set_sitting(false)
		legs.set_carrying(false)
		if state == &"olhando":
			legs.look_at_point(Params.ANIM_LOOK_AT)
		elif state == &"interagindo":
			legs.request_interact(body.global_position + Params.ANIM_INTERACT_REACH
				* legs.character_height())
		elif state == &"sentado":
			legs.set_sitting(true)
		elif state == &"carregando":
			legs.set_carrying(true)

		for index: int in Params.ANIM_STATE_FRAMES:
			_aim_camera(body, 0.0)
			await physics_frame
			# `interagir` tem ida, permanência e volta: o quadro tem de sair no meio, com o
			# braço estendido, e não no fim, quando ele já voltou para o lado do corpo.
			if state == &"interagindo" and index * 2 >= Params.ANIM_STATE_FRAMES:
				break
		frames.append(await _grab())
		print("  %-11s capturado" % String(state))

	_save(_compose(frames), "estados")
	body.queue_free()
	await process_frame
	return "estados"


## Três posturas andando lado a lado, congeladas na **mesma fase do ciclo**.
##
## É o teste do critério "raças diferentes andam visivelmente diferente": mesma
## velocidade, mesmo código, mesma fase — só o `GaitProfile` muda. Se as três silhuetas
## saírem iguais, o perfil não está chegando ao corpo.
##
## Esperar um número fixo de quadros seria a comparação errada, e por pouco: cadências
## diferentes põem cada corpo numa fase diferente do próprio ciclo, e a tira mostraria a
## diferença entre relógios em vez da diferença entre marchas. Aqui cada um anda até
## cruzar `ANIM_COMPARISON_PHASE`, e é aí que o quadro é tirado.
func _record_comparison() -> Dictionary:
	var columns: Array[Image] = []
	var gaits: Array[Dictionary] = []

	for character: String in Params.ANIM_GAIT_COMPARISON:
		var spawned: Dictionary = _spawn(character)
		var body: Node3D = spawned["body"]
		var legs: ProceduralLocomotion = spawned["legs"]

		var travel: float = 0.0
		var previous: float = legs.current_phase()
		for index: int in COMPARISON_LIMIT:
			travel += Params.ANIM_WALK_SPEED * _step_time()
			body.global_position = Vector3(0.0, 0.0, -travel)
			_aim_camera(body, Params.ANIM_WALK_SPEED)
			await physics_frame
			var now: float = legs.current_phase()
			if index > Params.ANIM_SETTLE_FRAMES and previous < Params.ANIM_COMPARISON_PHASE \
					and now >= Params.ANIM_COMPARISON_PHASE:
				break
			previous = now

		columns.append(await _grab())
		gaits.append({
			"character": character,
			"posture": String(legs.profile.posture),
			"stride_scale": legs.profile.stride_scale,
			"cadence_scale": legs.profile.cadence_scale,
			"foot_lift": legs.profile.foot_lift,
			"arm_swing_deg": legs.profile.arm_swing_deg,
			"phase": legs.current_phase(),
			"step_length": legs.step_length(),
			"foot_spread": legs.foot_position(0).distance_to(legs.foot_position(1)),
		})
		print("  %-11s postura %-8s fase %.2f  passo %.2f m  pé alto %.3f  vão %.3f m" % [
			character, gaits[-1]["posture"], gaits[-1]["phase"], gaits[-1]["step_length"],
			gaits[-1]["foot_lift"], gaits[-1]["foot_spread"]
		])
		body.queue_free()
		await process_frame

	_save(_compose(columns), "marchas")
	return {"name": "marchas", "gaits": gaits}


func _step_time() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second) * float(PHYSICS_SUBSTEPS)


## Câmera de perfil: o passo se lê de lado, não de frente. De frente, um pé que desliza
## meio metro parece exatamente igual a um pé que não desliza.
func _aim_camera(body: Node3D, speed: float) -> void:
	var legs: ProceduralLocomotion = body.get_node_or_null("Locomotion") as ProceduralLocomotion
	var stature: float = Params.PREVIEW_FIGURE_HEIGHT_FALLBACK
	if legs != null:
		stature = legs.character_height()
	var focus: Vector3 = body.global_position + Vector3.UP * Params.ANIM_CAMERA_HEIGHT * stature
	var yaw: float = deg_to_rad(Params.ANIM_CAMERA_YAW_DEG)
	var offset: Vector3 = Vector3(
		cos(yaw) * Params.ANIM_CAMERA_DISTANCE,
		0.0,
		sin(yaw) * Params.ANIM_CAMERA_DISTANCE
	)
	# O bob de câmera entra aqui, e não dentro do nó: quem move a câmera é quem tem uma.
	if legs != null and speed > 0.0:
		offset += legs.camera_offset
	_camera.global_position = focus + offset
	_camera.look_at(focus, Vector3.UP)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = _viewport.get_texture()
	return texture.get_image()


## Junta os quadros numa tira, na ordem em que foram gravados.
func _compose(frames: Array[Image]) -> Image:
	if frames.is_empty():
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

	var width: int = frames[0].get_width()
	var height: int = frames[0].get_height()
	var total: int = width * frames.size() + STRIP_GUTTER * (frames.size() - 1)
	var strip: Image = Image.create_empty(total, height, false, frames[0].get_format())
	strip.fill(Params.color(&"stone_dark"))

	for index: int in frames.size():
		strip.blit_rect(
			frames[index],
			Rect2i(Vector2i.ZERO, Vector2i(width, height)),
			Vector2i(index * (width + STRIP_GUTTER), 0)
		)
	return strip


func _save(image: Image, label: String) -> void:
	DirAccess.make_dir_recursive_absolute(Params.ANIM_DIR)
	var path: String = "%s/%s.png" % [Params.ANIM_DIR, label]
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Falha ao salvar %s (erro %d)" % [path, error])
		return
	print("  %s -> %s" % [label, path])


## Guarda a posição de mundo de cada pé enquanto ele está apoiado.
##
## O apoio é a única janela em que a resposta certa é "não mudou nada". Comparar contra a
## primeira amostra do apoio, e não contra a amostra anterior, é de propósito: erro que
## cresce um décimo de milímetro por frame soma meio centímetro num passo, e a diferença
## entre frames consecutivos nunca acusaria.
class FootTracker extends RefCounted:
	const SIDES: int = 2

	var worst: float = 0.0
	var _anchor: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var _tracking: Array[bool] = [false, false]

	func sample(legs: ProceduralLocomotion) -> void:
		for side: int in SIDES:
			var planted: bool = legs.is_foot_planted(side)
			var position: Vector3 = legs.foot_position(side)
			if not planted:
				_tracking[side] = false
				continue
			if not _tracking[side]:
				_tracking[side] = true
				_anchor[side] = position
				continue
			worst = maxf(worst, _anchor[side].distance_to(position))
