## Locomoção sem um único clipe de animação: tudo sai de IK e de senos, em runtime.
##
## Não é economia, é escolha estética. Uma malha de 470 triângulos com silhueta dura não
## pede a sutileza de uma curva capturada; pede leitura clara a 10 m. E o que se ganha em
## troca é grande: a passada responde à velocidade de verdade, o pé encontra o degrau que
## o terreno procedural acabou de gerar, e um povo novo anda diferente porque tem outro
## `GaitProfile` — não porque alguém exportou outro `.glb`.
##
## **A ideia que faz o resto funcionar: o pé não é animado, é pregado.** Durante o apoio,
## o pé fica numa posição *de mundo* fixa e o corpo passa por ela; só no balanço ele viaja
## até o próximo apoio. Deslizamento não é um defeito que se combate com tuning — aqui ele
## é impossível por construção, e `tools/anim_preview.gd` mede isso para provar. A
## cadência é derivada da velocidade (`cadência = velocidade / 2·passo`), e não de um
## relógio próprio: um ciclo com relógio patina no chão assim que o personagem acelera.
##
## Camadas, na ordem em que se somam — cada uma lê o esqueleto já modificado pela anterior:
##
##   quadril → coluna → pernas (IK) → braços → cabeça → aditivas (respiração, olhar)
##
## Uso mínimo: pendure o nó como filho do personagem e dê a ele um perfil. Ele descobre o
## `Skeleton3D` sozinho e mede a própria velocidade pelo deslocamento real.
##
##     var legs: ProceduralLocomotion = ProceduralLocomotion.new()
##     legs.profile = GaitProfile.load_for(&"agil")
##     character.add_child(legs)
class_name ProceduralLocomotion
extends Node3D

## Estado do corpo. `LOCOMOTING` cobre parado, andando e correndo — a diferença entre os
## três é contínua e sai da velocidade, não de um `if`.
enum State { LOCOMOTING, JUMPING, SITTING }

## Fases do salto. Sem a de agachar o pulo lê como teletransporte.
enum JumpPhase { CROUCH, LAUNCH, AIRBORNE, LAND }

const BONE_HIPS: StringName = &"Hips"
const BONE_SPINE: StringName = &"Spine"
const BONE_CHEST: StringName = &"Chest"
const BONE_NECK: StringName = &"Neck"
const BONE_HEAD: StringName = &"Head"

## Lados na ordem em que os arrays internos os guardam: 0 é a esquerda.
const SIDE_PREFIX: Array[StringName] = [&"Left", &"Right"]
## Sinal lateral de cada lado. +X é a direita do personagem no espaço do Godot.
const SIDE_SIGN: Array[float] = [-1.0, 1.0]
## Meio ciclo separa um pé do outro — e o braço do seu contra-lateral.
const OPPOSITE_PHASE: float = 0.5

const SUFFIX_UPLEG: StringName = &"UpLeg"
const SUFFIX_LEG: StringName = &"Leg"
const SUFFIX_FOOT: StringName = &"Foot"
const SUFFIX_TOE: StringName = &"Toe"
const SUFFIX_ARM: StringName = &"Arm"
const SUFFIX_FOREARM: StringName = &"ForeArm"
const SUFFIX_HAND: StringName = &"Hand"

const NO_BONE: int = -1
## Comprimento mínimo de segmento aceito no rig. Abaixo disso o osso é degenerado e a IK
## não teria triângulo para resolver.
const MIN_SEGMENT: float = 0.001
## Metade — usado onde "meio passo" e "meio ciclo" aparecem como conceito, não como ajuste.
const HALF: float = 0.5

var _skeleton: Skeleton3D = null
var _bones: Dictionary = {}
var _ready_to_pose: bool = false

## Comprimentos medidos do rest, uma vez. São a fonte da IK e da escala do personagem.
var _thigh_length: float = 0.0
var _shin_length: float = 0.0
var _foot_length: float = 0.0
var _upper_arm_length: float = 0.0
var _forearm_length: float = 0.0
var _hip_height: float = 0.0
var _stance_half_width: float = 0.0
var _character_height: float = 0.0

var _phase: float = 0.0
var _speed: float = 0.0
var _locomotion_weight: float = 0.0
var _breath_time: float = 0.0
var _previous_origin: Vector3 = Vector3.ZERO
var _has_previous: bool = false
var _drive_velocity: Vector3 = Vector3.ZERO
var _use_drive_velocity: bool = false

var _state: State = State.LOCOMOTING
var _jump_phase: JumpPhase = JumpPhase.CROUCH
var _jump_time: float = 0.0
var _sit_blend: float = 0.0
var _carry_blend: float = 0.0
var _interact_time: float = 0.0
var _interact_active: bool = false
var _interact_target: Vector3 = Vector3.ZERO
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _look_active: bool = false
var _look_target: Vector3 = Vector3.ZERO

## Posição de apoio de cada pé, em coordenadas de **mundo**. É o que não desliza.
var _plant: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _next_plant: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _in_stance: Array[bool] = [true, true]
## Se o pé está de fato sendo *segurado* no chão pela máquina de apoio. Sentado e no ar
## a resposta é não, mesmo com `_in_stance` guardando o último apoio para a aterrissagem.
var _grounded: Array[bool] = [true, true]
var _foot_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

## Deslocamento que uma câmera de primeira ou terceira pessoa pode somar à própria
## posição. O nó não mexe em câmera nenhuma: quem quiser o bob lê isto.
var camera_offset: Vector3 = Vector3.ZERO

## Microssegundos gastos na última passada de pose.
##
## Existe porque o orçamento de 40 NPCs ativos depende deste número e nada mais o mede:
## `make bench` percorre o estágio vazio e não veria um corpo animado. Medir por fora,
## pelo monitor de física do Godot, foi tentado e mentiu — num contêiner sem GPU os
## tiques de física se agrupam dentro de um frame de render e o monitor soma o grupo
## inteiro, reportando 125 ms para um personagem só. Cronometrar a própria passada é
## independente do ritmo de renderização.
var pose_usec: int = 0

@export_group("Rig")
## Esqueleto a animar. Vazio faz o nó procurar o primeiro `Skeleton3D` abaixo do pai.
@export var skeleton_path: NodePath = NodePath()
## Perfil do povo. Trocar isto é a única coisa que separa a marcha de um povo da de outro.
@export var profile: GaitProfile = null

@export_group("Ganhos globais")
## Multiplica toda amplitude de uma vez. 0 congela o corpo em rest; útil para depurar.
@export_range(0.0, 2.0, 0.01) var amplitude: float = 1.0
## Multiplica a cadência sem mexer no comprimento do passo. Acima de 1 o pé **desliza**:
## existe para ver o defeito acontecer, não para usar em produção.
@export_range(0.1, 3.0, 0.01) var frequency_scale: float = 1.0
## Deslocamento inicial do ciclo. Dois NPCs lado a lado com o mesmo offset marcham juntos
## como um pelotão, o que entrega o truque na hora.
@export_range(0.0, 1.0, 0.01) var phase_offset: float = 0.0

@export_group("Camadas")
@export var enable_locomotion: bool = true
@export var enable_arms: bool = true
@export var enable_breathing: bool = true
@export var enable_look: bool = true
@export var enable_camera_bob: bool = true
## Raycast para apoiar o pé no relevo. Desligado, o pé assume o plano do personagem.
@export var enable_foot_planting: bool = true
## Camadas de física em que o pé procura chão.
@export_flags_3d_physics var ground_mask: int = Params.LAYER_WORLD


func _ready() -> void:
	# Silêncio quando não há esqueleto ainda, e não é desleixo: um `RaceApplier` monta o
	# corpo em `_ready`, e não há ordem de irmãos que garanta que ele venha antes deste
	# nó. Quem monta chama `bind()` depois — e é `bind()` que reclama alto se falhar.
	if _resolve_skeleton() != null:
		bind()


## Prende o nó ao esqueleto que estiver abaixo do pai e mede o rig.
##
## Chame depois de trocar o corpo. Devolve `false` e reclama alto quando não há esqueleto
## ou quando faltam ossos do padrão Mixamo — os dois casos deixariam o personagem em
## T-pose, que é o tipo de defeito que se atribui a "a animação ainda não está pronta".
func bind() -> bool:
	_skeleton = _resolve_skeleton()
	if _skeleton == null:
		push_error("ProceduralLocomotion: nenhum Skeleton3D encontrado sob %s." % get_path())
		_ready_to_pose = false
		set_physics_process(false)
		return false

	if profile == null:
		profile = GaitProfile.from_posture(GaitProfile.DEFAULT_POSTURE)
	_ready_to_pose = _measure_rig()
	set_physics_process(_ready_to_pose)
	if not _ready_to_pose:
		return false

	_phase = phase_offset
	_reset_plants()
	if _state == State.SITTING:
		_seat_feet()
	return true


## Velocidade imposta por um controlador que já a conhece (um `CharacterBody3D`, por
## exemplo). Sem isto, o nó mede o próprio deslocamento — que é o caso geral e funciona
## para NPC movido por navegação ou por script de teste.
func set_drive_velocity(velocity: Vector3) -> void:
	_drive_velocity = velocity
	_use_drive_velocity = true


## Volta a medir a velocidade pelo deslocamento real.
func clear_drive_velocity() -> void:
	_use_drive_velocity = false


## Começa um salto. Ignorado se já houver um no ar.
func request_jump() -> void:
	if _state == State.JUMPING:
		return
	_state = State.JUMPING
	_jump_phase = JumpPhase.CROUCH
	_jump_time = 0.0


## Avisa que o corpo tocou o chão. O salto só sai da fase aérea quando quem simula a
## física diz que chegou — adivinhar pelo tempo daria pouso antes ou depois do impacto.
func notify_landed() -> void:
	if _state == State.JUMPING and _jump_phase == JumpPhase.AIRBORNE:
		_jump_phase = JumpPhase.LAND
		_jump_time = 0.0
		# O apoio se refaz **aqui**, no toque, e não quando o amortecimento acaba. Deixar
		# para depois devolvia os pés às marcas de antes do salto: o corpo tinha andado
		# 68 cm no ar e os pés voltavam a ficar cravados lá atrás, esticando as pernas
		# por um quarto de segundo. A prova de deslizamento pegou exatamente isso.
		_reset_plants()


## Estica um braço até um ponto do mundo e recolhe. O braço é escolhido pelo lado do alvo.
func request_interact(target: Vector3) -> void:
	_interact_target = target
	_interact_active = true
	_interact_time = 0.0


## Senta ou levanta. A transição é contínua: o quadril desce e os joelhos dobram sozinhos,
## porque o pé continua pregado no chão e a IK resolve o resto.
func set_sitting(sitting: bool) -> void:
	if sitting == (_state == State.SITTING):
		return
	if sitting:
		_state = State.SITTING
		if _ready_to_pose:
			_seat_feet()
		return
	_state = State.LOCOMOTING
	if _ready_to_pose:
		_reset_plants()


## Liga ou desliga a pose de carregar: braços à frente, tronco compensando o peso.
func set_carrying(carrying: bool) -> void:
	_carry_blend = 1.0 if carrying else 0.0


## Ponto do mundo para onde a cabeça olha. O tronco só entra quando o pescoço não alcança.
func look_at_point(target: Vector3) -> void:
	_look_target = target
	_look_active = true


## Solta o olhar; a cabeça volta para a frente do corpo suavemente.
func clear_look() -> void:
	_look_active = false


## Velocidade escalar considerada pela marcha, já suavizada. Para HUD e depuração.
func current_speed() -> float:
	return _speed


## Fase do ciclo em [0, 1). 0 é o instante em que o pé esquerdo toca o chão.
func current_phase() -> float:
	return _phase


## Comprimento do passo em metros, na velocidade atual. É o número que a tira de
## quadros ilustra: a distância entre dois apoios consecutivos de pés opostos.
func step_length() -> float:
	return _step_length()


## Altura do corpo em metros, medida da malha no rest. Enquadrar a câmera por um valor
## fixo funcionaria só para um personagem; o elenco vai de 1,45 m a 2,05 m.
func character_height() -> float:
	return _character_height


## Posição de mundo do pé, como a locomoção a definiu neste frame. Existe para que
## `tools/anim_preview.gd` possa **medir** o deslizamento em vez de julgá-lo pelo olho.
func foot_position(side: int) -> Vector3:
	return _foot_world[side]


## Se o pé está apoiado agora. Durante o apoio, `foot_position` não pode mudar — é
## exatamente esse invariante que `make anim` mede.
func is_foot_planted(side: int) -> bool:
	return _in_stance[side] and _grounded[side]


func _physics_process(delta: float) -> void:
	if not _ready_to_pose:
		return

	_track_velocity(delta)
	_advance_state(delta)
	_advance_phase(delta)

	var started: int = Time.get_ticks_usec()
	_pose()
	pose_usec = Time.get_ticks_usec() - started


# --- Descoberta e medida do rig ----------------------------------------------


func _resolve_skeleton() -> Skeleton3D:
	if not skeleton_path.is_empty():
		return get_node_or_null(skeleton_path) as Skeleton3D
	var from: Node = get_parent()
	if from == null:
		from = self
	return _find_skeleton(from)


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


## Lê do rest tudo que a IK precisa. Medir em vez de parametrizar é o que faz o mesmo nó
## servir a um corpo de 1,45 m e a um de 2,05 m sem uma constante por personagem.
func _measure_rig() -> bool:
	var required: Array[StringName] = [BONE_HIPS, BONE_SPINE, BONE_CHEST, BONE_NECK, BONE_HEAD]
	for prefix: StringName in SIDE_PREFIX:
		for suffix: StringName in [
			SUFFIX_UPLEG, SUFFIX_LEG, SUFFIX_FOOT, SUFFIX_TOE,
			SUFFIX_ARM, SUFFIX_FOREARM, SUFFIX_HAND
		]:
			required.append(_joint(prefix, suffix))

	var missing: Array[String] = []
	for required_name: StringName in required:
		var index: int = _skeleton.find_bone(String(required_name))
		if index == NO_BONE:
			missing.append(String(required_name))
		_bones[required_name] = index

	if not missing.is_empty():
		push_error(
			"ProceduralLocomotion: o esqueleto não tem %s. Os nomes são contrato com "
			% ", ".join(missing)
			+ "o padrão Mixamo que tools/gen_characters.py produz."
		)
		return false

	var hip: Vector3 = _rest_origin(_joint(SIDE_PREFIX[0], SUFFIX_UPLEG))
	var knee: Vector3 = _rest_origin(_joint(SIDE_PREFIX[0], SUFFIX_LEG))
	var ankle: Vector3 = _rest_origin(_joint(SIDE_PREFIX[0], SUFFIX_FOOT))
	var toe: Vector3 = _rest_origin(_joint(SIDE_PREFIX[0], SUFFIX_TOE))
	var shoulder: Vector3 = _rest_origin(_joint(SIDE_PREFIX[0], SUFFIX_ARM))
	var elbow: Vector3 = _rest_origin(_joint(SIDE_PREFIX[0], SUFFIX_FOREARM))
	var wrist: Vector3 = _rest_origin(_joint(SIDE_PREFIX[0], SUFFIX_HAND))

	_thigh_length = hip.distance_to(knee)
	_shin_length = knee.distance_to(ankle)
	_foot_length = ankle.distance_to(toe)
	_upper_arm_length = shoulder.distance_to(elbow)
	_forearm_length = elbow.distance_to(wrist)
	_hip_height = _rest_origin(BONE_HIPS).y
	_stance_half_width = absf(hip.x)
	_character_height = _measure_height()

	for length: float in [_thigh_length, _shin_length, _upper_arm_length, _forearm_length]:
		if length < MIN_SEGMENT:
			push_error("ProceduralLocomotion: segmento degenerado no rest do esqueleto.")
			return false
	return true


## Altura real do corpo, tirada da malha e não estimada de um osso.
##
## A caixa da malha é a única medida honesta aqui: o osso da cabeça marca a base do
## crânio, não o topo dele, e derivar a altura dali erra por uma cabeça inteira — o que
## em amplitude de passo é a diferença entre andar e marchar.
func _measure_height() -> float:
	for child: Node in _skeleton.get_children():
		if child is MeshInstance3D:
			var mesh: MeshInstance3D = child as MeshInstance3D
			if mesh.mesh != null:
				return mesh.get_aabb().size.y
	return _rest_origin(BONE_HEAD).y


static func _joint(prefix: StringName, suffix: StringName) -> StringName:
	return StringName(String(prefix) + String(suffix))


func _bone(bone_name: StringName) -> int:
	return int(_bones[bone_name])


func _rest_origin(bone_name: StringName) -> Vector3:
	return _skeleton.get_bone_global_rest(_bone(bone_name)).origin


# --- Velocidade, estado e fase -----------------------------------------------


func _track_velocity(delta: float) -> void:
	var origin: Vector3 = global_position
	var velocity: Vector3 = _drive_velocity
	if not _use_drive_velocity:
		velocity = Vector3.ZERO
		if _has_previous and delta > 0.0:
			velocity = (origin - _previous_origin) / delta
	_previous_origin = origin
	_has_previous = true

	# Só o plano interessa: subir uma rampa não é andar mais rápido.
	var planar: float = Vector2(velocity.x, velocity.z).length()
	var smoothing: float = clampf(Params.GAIT_SPEED_SMOOTHING * delta, 0.0, 1.0)
	_speed = lerpf(_speed, planar, smoothing)

	var wants_locomotion: bool = _speed > Params.GAIT_MOVE_THRESHOLD and _state == State.LOCOMOTING
	var target_weight: float = 1.0 if wants_locomotion else 0.0
	_locomotion_weight = move_toward(
		_locomotion_weight, target_weight, Params.GAIT_BLEND_SPEED * delta
	)
	_breath_time += delta


func _advance_state(delta: float) -> void:
	_sit_blend = move_toward(
		_sit_blend,
		1.0 if _state == State.SITTING else 0.0,
		delta / maxf(Params.SIT_HIP_TIME, MIN_SEGMENT)
	)

	if _interact_active:
		_interact_time += delta
		var total: float = (
			Params.INTERACT_REACH_TIME + Params.INTERACT_HOLD_TIME + Params.INTERACT_RETURN_TIME
		)
		if _interact_time >= total:
			_interact_active = false

	if _state != State.JUMPING:
		return

	_jump_time += delta
	if _jump_phase == JumpPhase.CROUCH and _jump_time >= Params.JUMP_CROUCH_TIME:
		_jump_phase = JumpPhase.LAUNCH
		_jump_time = 0.0
	elif _jump_phase == JumpPhase.LAUNCH and _jump_time >= Params.JUMP_LAUNCH_TIME:
		_jump_phase = JumpPhase.AIRBORNE
		_jump_time = 0.0
	elif _jump_phase == JumpPhase.LAND and _jump_time >= Params.JUMP_LAND_TIME:
		_state = State.LOCOMOTING


## Avança o ciclo. `cadência = velocidade / (2 · passo)` — a igualdade que impede o pé de
## deslizar: o corpo anda exatamente dois passos por ciclo, então o pé pousado nunca
## precisa se corrigir.
func _advance_phase(delta: float) -> void:
	if not enable_locomotion:
		return
	if _locomotion_weight <= 0.0 and _speed <= Params.GAIT_MOVE_THRESHOLD:
		return
	var step: float = _step_length()
	var cadence: float = _speed / (2.0 * step) * frequency_scale
	_phase = fposmod(_phase + cadence * delta, 1.0)


func _step_length() -> float:
	var base: float = (
		_hip_height * Params.GAIT_STRIDE_HIP_FACTOR
		+ _speed * Params.GAIT_STRIDE_SPEED_FACTOR
	)
	var scaled: float = base * profile.stride_scale / maxf(profile.cadence_scale, MIN_SEGMENT)
	return clampf(scaled, Params.GAIT_STRIDE_MIN, Params.GAIT_STRIDE_MAX)


func _run_blend() -> float:
	return clampf(_speed / maxf(Params.GAIT_RUN_SPEED, MIN_SEGMENT), 0.0, 1.0)


func _duty() -> float:
	return lerpf(Params.GAIT_DUTY_WALK, Params.GAIT_DUTY_RUN, _run_blend())


# --- Aplicação da pose --------------------------------------------------------


func _pose() -> void:
	_skeleton.reset_bone_poses()

	var frame: Basis = _model_basis()
	var forward: Vector3 = frame * Vector3.FORWARD
	var right: Vector3 = frame * Vector3.RIGHT
	var up: Vector3 = frame * Vector3.UP

	_pose_hips(forward, up)
	_pose_spine(right, up)
	if enable_locomotion:
		_pose_legs(forward, up)
	if enable_arms:
		_pose_arms(forward, right, up)
	_pose_head(right, up)
	_update_camera_offset(up, right)


## Base que leva vetores do espaço do personagem para o espaço do esqueleto.
##
## Não é decorativo: o `.glb` traz o esqueleto sob um nó `Armature` com rotação própria,
## e assumir que o modelo compartilha os eixos do personagem faria a marcha sair de lado
## em qualquer corpo importado com hierarquia diferente.
func _model_basis() -> Basis:
	return _skeleton.global_transform.basis.inverse() * global_transform.basis


func _to_model(world_point: Vector3) -> Vector3:
	return _skeleton.global_transform.affine_inverse() * world_point


func _to_world(model_point: Vector3) -> Vector3:
	return _skeleton.global_transform * model_point


# --- Quadril e coluna ---------------------------------------------------------


func _pose_hips(forward: Vector3, up: Vector3) -> void:
	var hips: int = _bone(BONE_HIPS)
	var rest: Transform3D = _skeleton.get_bone_rest(hips)
	var weight: float = _locomotion_weight * amplitude
	var cycle: float = _phase * TAU

	# Duas subidas por ciclo: o quadril sobe a cada pé que passa pelo apoio.
	var bounce: float = sin(cycle * 2.0) * profile.hip_bounce * _character_height * weight
	var offset: Vector3 = up * (bounce + _vertical_offset())

	var sway: float = sin(cycle) * deg_to_rad(profile.hip_sway_deg) * weight
	var drop: float = sin(cycle) * deg_to_rad(profile.hip_drop_deg) * weight
	var delta: Basis = Basis(up, sway) * Basis(forward, drop)

	_skeleton.set_bone_pose_position(hips, rest.origin + offset)
	_skeleton.set_bone_pose_rotation(
		hips, (delta * rest.basis).get_rotation_quaternion()
	)


## Quanto o quadril desce ou sobe por causa de salto e de sentar, em metros.
func _vertical_offset() -> float:
	var offset: float = -_sit_blend * Params.SIT_HIP_DROP * _character_height
	if _state != State.JUMPING:
		return offset

	var phase_ratio: float = 0.0
	if _jump_phase == JumpPhase.CROUCH:
		phase_ratio = clampf(_jump_time / maxf(Params.JUMP_CROUCH_TIME, MIN_SEGMENT), 0.0, 1.0)
		offset -= Params.JUMP_CROUCH_DEPTH * _character_height * phase_ratio
	elif _jump_phase == JumpPhase.LAUNCH:
		phase_ratio = clampf(_jump_time / maxf(Params.JUMP_LAUNCH_TIME, MIN_SEGMENT), 0.0, 1.0)
		offset += lerpf(
			-Params.JUMP_CROUCH_DEPTH, Params.JUMP_LAUNCH_RISE, phase_ratio
		) * _character_height
	elif _jump_phase == JumpPhase.AIRBORNE:
		offset += Params.JUMP_LAUNCH_RISE * _character_height
	elif _jump_phase == JumpPhase.LAND:
		# Amortecimento: afunda no impacto e volta. Uma curva só, sem mola nem oscilação —
		# oscilar depois de aterrissar parece bêbado, não elástico.
		phase_ratio = clampf(_jump_time / maxf(Params.JUMP_LAND_TIME, MIN_SEGMENT), 0.0, 1.0)
		offset -= Params.JUMP_LAND_DEPTH * _character_height * sin(phase_ratio * PI)
	return offset


func _pose_spine(right: Vector3, up: Vector3) -> void:
	var weight: float = _locomotion_weight * amplitude
	var lean: float = deg_to_rad(profile.torso_lean_deg) * (HALF + HALF * _run_blend())
	lean += deg_to_rad(Params.CARRY_TORSO_LEAN_DEG) * _carry_blend
	lean += deg_to_rad(Params.SIT_TORSO_DEG) * _sit_blend
	var twist: float = sin(_phase * TAU) * deg_to_rad(profile.torso_twist_deg) * weight

	# O tronco torce **contra** o quadril: é o que impede o corpo de parecer um bloco só.
	_rotate_in_model(_bone(BONE_SPINE), Basis(right, lean) * Basis(up, -twist))
	_rotate_in_model(_bone(BONE_CHEST), Basis(up, -twist * HALF))
	if enable_breathing:
		_apply_breathing(right, up)


func _apply_breathing(right: Vector3, up: Vector3) -> void:
	# Respiração some quando o corpo anda: quem anda já sobe e desce, e somar as duas
	# coisas dá um peito que infla no ritmo errado.
	var idle: float = (1.0 - _locomotion_weight) * amplitude
	if idle <= 0.0:
		return
	var wave: float = sin(_breath_time * TAU * Params.BREATH_FREQUENCY)
	_rotate_in_model(_bone(BONE_CHEST), Basis(right, -wave * deg_to_rad(Params.BREATH_CHEST_DEG) * idle))
	var hips: int = _bone(BONE_HIPS)
	var rise: Vector3 = up * wave * Params.BREATH_RISE * _character_height * idle
	_skeleton.set_bone_pose_position(hips, _skeleton.get_bone_pose_position(hips) + rise)


# --- Pernas -------------------------------------------------------------------


func _pose_legs(forward: Vector3, up: Vector3) -> void:
	for side: int in SIDE_PREFIX.size():
		var target: Vector3 = _foot_target(side)
		_foot_world[side] = target
		_solve_leg(side, _to_model(target), forward, up)


## Onde o pé deste lado está **no mundo**, neste instante.
##
## É o coração do não-deslizamento: no apoio a resposta é literalmente a mesma posição do
## frame anterior. Nada de "quase parado", nada de correção por atrito: o pé não se mexe
## porque ninguém o move.
func _foot_target(side: int) -> Vector3:
	if _state == State.JUMPING and _jump_phase == JumpPhase.AIRBORNE:
		_grounded[side] = false
		return _tucked_foot(side)
	if _state == State.SITTING:
		_grounded[side] = false
		return _seated_foot(side)

	var leg_phase: float = fposmod(_phase + (OPPOSITE_PHASE if side == 1 else 0.0), 1.0)
	var duty: float = _duty()

	if leg_phase < duty:
		if not _in_stance[side]:
			_in_stance[side] = true
			_plant[side] = _next_plant[side]
		_grounded[side] = true
		return _plant[side]

	_grounded[side] = false
	if _in_stance[side]:
		_in_stance[side] = false
		_next_plant[side] = _predict_plant(side, duty)

	var swing: float = (leg_phase - duty) / maxf(1.0 - duty, MIN_SEGMENT)
	# Suavização nas pontas: o pé sai e chega devagar, e cruza o meio rápido. Interpolação
	# linear aqui dá o passo de robô, com velocidade constante e parada seca.
	var eased: float = smoothstep(0.0, 1.0, swing)
	var lift_height: float = lerpf(profile.foot_lift, profile.foot_lift_run, _run_blend())
	var arc: float = sin(swing * PI) * lift_height * _character_height * amplitude
	return _plant[side].lerp(_next_plant[side], eased) + Vector3.UP * arc


## Onde este pé vai pousar, previsto para o instante do toque.
func _predict_plant(side: int, duty: float) -> Vector3:
	var step: float = _step_length()
	var cadence: float = maxf(_speed / (2.0 * step), MIN_SEGMENT)
	var swing_time: float = (1.0 - duty) / cadence
	var heading: Vector3 = global_transform.basis * Vector3.FORWARD
	var lateral: Vector3 = global_transform.basis * Vector3.RIGHT

	var future_body: Vector3 = global_position + _planar_velocity() * swing_time
	var landing: Vector3 = (
		future_body
		+ lateral * SIDE_SIGN[side] * _stance_half_width
		+ heading * step * duty
	)
	return _ground_at(landing)


func _planar_velocity() -> Vector3:
	var heading: Vector3 = global_transform.basis * Vector3.FORWARD
	return heading * _speed


## Apoia um ponto no relevo. Sem raycast — ou sem chão sob o ponto — assume o plano do
## personagem, que é o comportamento certo num estágio plano e num corpo em queda.
func _ground_at(point: Vector3) -> Vector3:
	var ankle: float = Params.GAIT_ANKLE_HEIGHT * _character_height
	if not enable_foot_planting:
		return Vector3(point.x, global_position.y + ankle, point.z)

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = point + Vector3.UP * Params.GAIT_GROUND_PROBE_UP
	var to: Vector3 = point - Vector3.UP * Params.GAIT_GROUND_PROBE_DOWN
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ground_mask
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return Vector3(point.x, global_position.y + ankle, point.z)
	var contact: Vector3 = hit["position"]
	return Vector3(point.x, contact.y + ankle, point.z)


func _tucked_foot(side: int) -> Vector3:
	var hip: Vector3 = _to_world(_skeleton.get_bone_global_pose(
		_bone(_joint(SIDE_PREFIX[side], SUFFIX_UPLEG))
	).origin)
	var leg: float = (_thigh_length + _shin_length) * Params.JUMP_TUCK_LEG_FACTOR
	var tuck: Vector3 = Vector3.DOWN.rotated(
		(global_transform.basis * Vector3.RIGHT).normalized(),
		deg_to_rad(Params.JUMP_TUCK_DEG)
	)
	return hip + tuck * leg


## Onde os pés ficam ao sentar. Calculado **uma vez**, quando o corpo senta.
##
## Recalcular por frame custaria dois raycasts por NPC sentado — com o teto de 40 ativos,
## oitenta consultas de física por frame para achar um chão que não mudou. E, pior, um
## empurrão no corpo arrastaria os pés junto: sentado, o pé fica onde foi posto.
func _seat_feet() -> void:
	var heading: Vector3 = global_transform.basis * Vector3.FORWARD
	var lateral: Vector3 = global_transform.basis * Vector3.RIGHT
	for side: int in SIDE_PREFIX.size():
		_plant[side] = _ground_at(
			global_position
			+ heading * Params.SIT_FOOT_FORWARD * _character_height
			+ lateral * SIDE_SIGN[side] * _stance_half_width
		)
		_foot_world[side] = _plant[side]


func _seated_foot(side: int) -> Vector3:
	return _plant[side]


## IK de duas juntas na perna, com o joelho apontando para a frente do corpo.
func _solve_leg(side: int, target: Vector3, forward: Vector3, up: Vector3) -> void:
	var upleg: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_UPLEG))
	var leg: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_LEG))
	var foot: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_FOOT))
	var toe: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_TOE))

	var root: Vector3 = _skeleton.get_bone_global_pose(upleg).origin
	var knee: Vector3 = TwoBoneIK.solve(
		root, target, _thigh_length, _shin_length, forward * profile.knee_forward
	)
	_aim(upleg, leg, knee)
	_aim(leg, foot, target)

	# O pé fica nivelado: aponta para a frente do corpo, não para onde a canela apontar.
	# Sem isto o personagem anda na ponta dos pés no balanço e de calcanhar no apoio.
	var leg_phase: float = fposmod(_phase + (OPPOSITE_PHASE if side == 1 else 0.0), 1.0)
	var swinging: float = 0.0 if leg_phase < _duty() else 1.0
	var tilt: float = deg_to_rad(Params.FOOT_SWING_TILT_DEG) * swinging * _locomotion_weight
	var direction: Vector3 = forward.rotated(
		_orthogonal(forward, up), -tilt
	).normalized()
	_aim(foot, toe, target + direction * _foot_length)


static func _orthogonal(forward: Vector3, up: Vector3) -> Vector3:
	var axis: Vector3 = forward.cross(up)
	if axis.length() < TwoBoneIK.PARALLEL_EPSILON:
		return Vector3.RIGHT
	return axis.normalized()


# --- Braços -------------------------------------------------------------------


func _pose_arms(forward: Vector3, right: Vector3, up: Vector3) -> void:
	for side: int in SIDE_PREFIX.size():
		if _interact_active and _interact_side() == side:
			_solve_interact_arm(side, forward, up)
			continue
		_swing_arm(side, forward, right, up)


## Balanço contra-lateral: o braço direito acompanha a perna esquerda. É o detalhe que
## faz o corpo parecer que anda em vez de desfilar — braços em fase com as pernas do
## mesmo lado é exatamente como uma pessoa nervosa anda, e o olho percebe na hora.
func _swing_arm(side: int, forward: Vector3, right: Vector3, up: Vector3) -> void:
	var arm: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_ARM))
	var forearm: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_FOREARM))
	var hand: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_HAND))

	var opposite: float = OPPOSITE_PHASE if side == 0 else 0.0
	var wave: float = sin(fposmod(_phase + opposite, 1.0) * TAU)
	var amount: float = _locomotion_weight * amplitude * (HALF + HALF * _run_blend())

	var swing: float = wave * deg_to_rad(profile.arm_swing_deg) * amount
	var bias: float = deg_to_rad(profile.arm_bias_deg)
	bias += deg_to_rad(Params.CARRY_ARM_DEG) * _carry_blend
	var elbow: float = deg_to_rad(profile.elbow_bend_deg)
	elbow += deg_to_rad(Params.CARRY_ELBOW_DEG) * _carry_blend
	elbow += deg_to_rad(profile.elbow_bend_deg) * absf(wave) * amount

	# Sai da T-pose para o braço ao longo do corpo, depois abre um pouco e então balança.
	var lateral: Vector3 = right * SIDE_SIGN[side]
	var direction: Vector3 = lateral.rotated(_orthogonal(lateral, up), -deg_to_rad(Params.ARM_REST_DROP_DEG))
	direction = direction.rotated(forward, -deg_to_rad(Params.ARM_OUTWARD_DEG) * SIDE_SIGN[side])
	direction = direction.rotated(right, swing + bias)

	_aim_direction(arm, forearm, direction)
	_aim_direction(forearm, hand, direction.rotated(right, elbow))


func _interact_side() -> int:
	var local: Vector3 = global_transform.affine_inverse() * _interact_target
	return 1 if local.x >= 0.0 else 0


## O braço vai até o alvo por IK e volta. Três tempos — ir, segurar, voltar — porque um
## braço que chega e some no mesmo frame não lê como ter tocado em nada.
func _solve_interact_arm(side: int, forward: Vector3, up: Vector3) -> void:
	var arm: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_ARM))
	var forearm: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_FOREARM))
	var hand: int = _bone(_joint(SIDE_PREFIX[side], SUFFIX_HAND))

	var reach: float = 0.0
	if _interact_time < Params.INTERACT_REACH_TIME:
		reach = _interact_time / maxf(Params.INTERACT_REACH_TIME, MIN_SEGMENT)
	elif _interact_time < Params.INTERACT_REACH_TIME + Params.INTERACT_HOLD_TIME:
		reach = 1.0
	else:
		var back: float = _interact_time - Params.INTERACT_REACH_TIME - Params.INTERACT_HOLD_TIME
		reach = 1.0 - back / maxf(Params.INTERACT_RETURN_TIME, MIN_SEGMENT)
	reach = clampf(smoothstep(0.0, 1.0, reach), 0.0, 1.0)

	var shoulder: Vector3 = _skeleton.get_bone_global_pose(arm).origin
	var resting: Vector3 = shoulder - Vector3.UP * (_upper_arm_length + _forearm_length)
	var target: Vector3 = resting.lerp(_to_model(_interact_target), reach)
	var elbow: Vector3 = TwoBoneIK.solve(
		shoulder, target, _upper_arm_length, _forearm_length, -forward - up
	)
	_aim(arm, forearm, elbow)
	_aim(forearm, hand, target)


# --- Cabeça e câmera ----------------------------------------------------------


func _pose_head(right: Vector3, up: Vector3) -> void:
	var head: int = _bone(BONE_HEAD)
	var bob: float = sin(_phase * TAU * 2.0) * profile.head_bob * _character_height
	bob *= _locomotion_weight * amplitude
	_offset_bone(head, up * bob)
	if enable_look:
		_apply_look(right, up)


## Olhar com limite de ângulo e virada de tronco no excesso.
##
## O pescoço humano não gira 180°, e um NPC que faz isso vira o momento em que o jogador
## para de acreditar na cena. Aqui o que passa do limite vira rotação de tronco — que é o
## que uma pessoa faz de verdade quando alguém a chama por trás.
func _apply_look(right: Vector3, up: Vector3) -> void:
	var wanted_yaw: float = 0.0
	var wanted_pitch: float = 0.0
	if _look_active:
		var local: Vector3 = global_transform.affine_inverse() * _look_target
		wanted_yaw = atan2(-local.x, -local.z)
		wanted_pitch = atan2(local.y, Vector2(local.x, local.z).length())

	var blend: float = clampf(Params.LOOK_SMOOTHING * get_physics_process_delta_time(), 0.0, 1.0)
	_look_yaw = lerp_angle(_look_yaw, wanted_yaw, blend)
	_look_pitch = lerpf(_look_pitch, wanted_pitch, blend)

	var yaw_limit: float = deg_to_rad(Params.LOOK_MAX_HEAD_YAW_DEG)
	var pitch_limit: float = deg_to_rad(Params.LOOK_MAX_HEAD_PITCH_DEG)
	var head_yaw: float = clampf(_look_yaw, -yaw_limit, yaw_limit)
	var excess: float = (_look_yaw - head_yaw) * Params.LOOK_TORSO_SHARE
	if absf(excess) > 0.0:
		_rotate_in_model(_bone(BONE_SPINE), Basis(up, excess))

	var head: int = _bone(BONE_HEAD)
	_rotate_in_model(_bone(BONE_NECK), Basis(up, head_yaw * HALF))
	_rotate_in_model(head, Basis(up, head_yaw * HALF) * Basis(right, -clampf(
		_look_pitch, -pitch_limit, pitch_limit
	)))


## Bob de câmera: só na corrida, e em dois eixos. Vertical no dobro da cadência (uma
## subida por pé) e lateral na cadência. Amarrado à mesma fase do passo, então a câmera
## sobe quando o corpo sobe — que é a diferença entre "vivo" e "enjoativo".
func _update_camera_offset(up: Vector3, right: Vector3) -> void:
	if not enable_camera_bob:
		camera_offset = Vector3.ZERO
		return
	var strength: float = _run_blend() * _locomotion_weight * amplitude
	var cycle: float = _phase * TAU
	camera_offset = (
		up * sin(cycle * Params.CAMERA_BOB_HARMONIC) * Params.CAMERA_BOB_AMPLITUDE * strength
		+ right * sin(cycle) * Params.CAMERA_BOB_SIDE * strength
	)


# --- Utilitários de esqueleto -------------------------------------------------


## Gira `bone` para que a direção até `child` aponte para `target`, tudo em espaço de
## modelo. É o passo que transforma a resposta geométrica da IK em pose de osso, sem
## supor nada sobre a orientação do rest — que no `.glb` do Blender não é a mesma para
## coxa, braço e pé.
func _aim(bone: int, child: int, target: Vector3) -> void:
	var origin: Vector3 = _skeleton.get_bone_global_pose(bone).origin
	var current: Vector3 = _skeleton.get_bone_global_pose(child).origin - origin
	_rotate_in_model(bone, Basis(TwoBoneIK.swing(current, target - origin)))


func _aim_direction(bone: int, child: int, direction: Vector3) -> void:
	var origin: Vector3 = _skeleton.get_bone_global_pose(bone).origin
	_aim(bone, child, origin + direction.normalized())


## Compõe uma rotação **no espaço do modelo** sobre a pose atual do osso.
##
## O `set_bone_pose_rotation` fala em espaço local do pai, e as camadas aqui pensam em
## eixos do personagem — "incline para a frente", "torça em torno do eixo vertical". A
## conversão fica neste único lugar em vez de espalhada por cada camada.
## Desloca um osso por um vetor pensado em eixos do **modelo**.
##
## `set_bone_pose_position` fala no espaço do pai, e o rest que sai do Blender não tem os
## eixos do personagem: o Y local do pescoço não é "para cima". Somar `Vector3.UP` cru ali
## manda a cabeça para o lado em vez de para cima, e o erro só aparece em corpos com
## postura inclinada.
func _offset_bone(bone: int, model_offset: Vector3) -> void:
	var parent: int = _skeleton.get_bone_parent(bone)
	var offset: Vector3 = model_offset
	if parent != NO_BONE:
		offset = _skeleton.get_bone_global_pose(parent).basis.inverse() * model_offset
	_skeleton.set_bone_pose_position(bone, _skeleton.get_bone_pose_position(bone) + offset)


func _rotate_in_model(bone: int, delta: Basis) -> void:
	var parent: int = _skeleton.get_bone_parent(bone)
	var parent_basis: Basis = Basis.IDENTITY
	if parent != NO_BONE:
		parent_basis = _skeleton.get_bone_global_pose(parent).basis
	var wanted: Basis = delta * _skeleton.get_bone_global_pose(bone).basis
	var local: Basis = parent_basis.inverse() * wanted
	_skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


func _reset_plants() -> void:
	var forward: Vector3 = global_transform.basis * Vector3.FORWARD
	var lateral: Vector3 = global_transform.basis * Vector3.RIGHT
	for side: int in SIDE_PREFIX.size():
		var point: Vector3 = global_position + lateral * SIDE_SIGN[side] * _stance_half_width
		_plant[side] = _ground_at(point)
		_next_plant[side] = _plant[side] + forward * _step_length()
		_in_stance[side] = true
		_grounded[side] = true
		# `_foot_world` tem de nascer no apoio, e não em zero. Quem lê de fora pode
		# amostrar antes do primeiro `_pose()` — o sinal `physics_frame` do SceneTree é
		# emitido *antes* dos `_physics_process` do mesmo tique — e leria uma posição que
		# o nó nunca calculou. Foi assim que a prova de deslizamento acusou 12 cm de
		# patinação num pé que não tinha se mexido um milímetro.
		_foot_world[side] = _plant[side]
