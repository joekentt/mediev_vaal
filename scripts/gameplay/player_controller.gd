## O jogador: máquina de estados, sensação de peso e a cola entre corpo, marcha e câmera.
##
## **Sensação de peso é o assunto.** Um corpo que atinge a velocidade máxima no primeiro
## frame e para no seguinte é preciso de controlar e não convence ninguém. Aqui acelerar e
## desacelerar são números separados, e desacelerar é mais rápido — soltar o comando
## precisa ser nítido, senão o personagem patina toda vez que se quer parar numa marca. O
## corpo também não vira instantaneamente: `lerp_angle` gasta alguns frames girando, e é
## nesses frames que o peso aparece.
##
## **Coyote time e buffer são a mesma ideia, espelhada.** Pular *depois* de sair da beirada
## continua valendo por um sexto de segundo, e apertar pulo *antes* de tocar o chão fica
## guardado pelo mesmo tempo. Sem os dois, o jogador culpa o controle — e tem razão: ele
## apertou no instante em que quis, e o instante em que o jogo aceita é mais estreito do
## que o olho percebe.
##
## O que este nó **não** faz: animar. Ele entrega a velocidade a `ProceduralLocomotion` e
## avisa dos eventos (pulou, pousou, interagiu); a pose é assunto de lá. E não sabe qual
## povo veste: quem monta corpo, marcha e colisor é o `RaceApplier`.
class_name PlayerController
extends CharacterBody3D

## Estados do jogador. A ordem da resolução é a de precedência, não a de declaração:
## interagir vence, depois o ar, e só então a velocidade no chão decide.
enum State { IDLE, WALK, RUN, JUMP, FALL, INTERACT }

## Nomes das ações, do input map gerado. StringName para não alocar por frame.
const ACTION_LEFT: StringName = &"move_left"
const ACTION_RIGHT: StringName = &"move_right"
const ACTION_FORWARD: StringName = &"move_forward"
const ACTION_BACK: StringName = &"move_back"
const ACTION_SPRINT: StringName = &"sprint"
const ACTION_JUMP: StringName = &"jump"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_CAPTURE: StringName = &"camera_toggle_capture"
const ACTION_ZOOM_IN: StringName = &"camera_zoom_in"
const ACTION_ZOOM_OUT: StringName = &"camera_zoom_out"

var _state: State = State.IDLE
var _coyote: float = 0.0
var _buffer: float = 0.0
var _interact_left: float = 0.0
var _was_on_floor: bool = true
var _planar_speed: float = 0.0

var _legs: ProceduralLocomotion = null
var _camera: ThirdPersonCamera = null
var _race: RaceApplier = null

@export_group("Nós")
@export var locomotion_path: NodePath = NodePath()
@export var camera_path: NodePath = NodePath()
@export var race_path: NodePath = NodePath()
## O sensor que escolhe o alvo de interação. Nó, e não busca: quem monta a cena é o
## gerador, e um controlador que procurasse o sensor na árvore acharia o do NPC ao lado.
@export var sensor_path: NodePath = NodePath()

@export_group("Velocidade")
@export var walk_speed: float = Params.PLAYER_WALK_SPEED
@export var run_speed: float = Params.PLAYER_RUN_SPEED
## Abaixo disto o corpo conta como parado, e a marcha desliga.
@export var idle_speed: float = Params.GAIT_MOVE_THRESHOLD

@export_group("Peso")
## Ganho de velocidade por segundo com o comando pressionado.
@export var acceleration: float = Params.PLAYER_ACCELERATION
## Perda de velocidade por segundo com o comando solto. Maior que a aceleração de
## propósito: parar tem de ser mais nítido do que arrancar.
@export var deceleration: float = Params.PLAYER_DECELERATION
## Fração da aceleração que vale no ar. 1,0 daria controle de nave espacial.
@export var air_control: float = Params.PLAYER_AIR_CONTROL
## Velocidade do `lerp_angle` que gira o corpo para a direção do movimento, em 1/s.
@export var turn_speed: float = Params.PLAYER_TURN_SPEED

@export_group("Salto")
## Altura do salto em metros — mais fácil de conferir contra um degrau do que m/s.
@export var jump_height: float = Params.PLAYER_JUMP_HEIGHT
## Bem acima dos 9,8 reais. Gravidade realista dá salto lento e boiado.
@export var gravity: float = Params.PLAYER_GRAVITY
## Multiplica a gravidade na descida. Cair mais rápido que subir tira a flutuação no topo.
@export var fall_gravity_scale: float = Params.PLAYER_FALL_GRAVITY_SCALE
@export var terminal_velocity: float = Params.PLAYER_TERMINAL_VELOCITY
## Janela em que ainda se pode pular depois de sair da beirada.
@export var coyote_time: float = Params.PLAYER_COYOTE_TIME
## Janela em que um pulo apertado cedo demais continua valendo ao tocar o chão.
@export var jump_buffer: float = Params.PLAYER_JUMP_BUFFER

@export_group("Interação")
## Até onde a mão vai quando não há alvo nenhum. Quem escolhe alvo é o `InteractionSensor`,
## e a máscara de camada mora nele — este arquivo deixou de ter opinião sobre onde procurar
## no dia em que a busca deixou de ser um raio.
@export var interact_range: float = Params.PLAYER_INTERACT_RANGE


func _ready() -> void:
	floor_max_angle = deg_to_rad(Params.PLAYER_FLOOR_MAX_ANGLE_DEG)
	floor_snap_length = Params.PLAYER_FLOOR_SNAP
	collision_layer = Params.LAYER_PLAYER
	collision_mask = Params.LAYER_WORLD

	_legs = get_node_or_null(locomotion_path) as ProceduralLocomotion
	_camera = get_node_or_null(camera_path) as ThirdPersonCamera
	_race = get_node_or_null(race_path) as RaceApplier

	if _race != null:
		_race.body_applied.connect(_on_body_applied)
	if _camera != null:
		_camera.set_locomotion(_legs)
		_camera.set_target(self, _body_height())


## Estado atual. Existe para HUD e depuração — o estado não é lido por mais ninguém aqui.
func current_state() -> State:
	return _state


## Velocidade horizontal em m/s, já sem a componente vertical.
func planar_speed() -> float:
	return _planar_speed


func _on_body_applied(_body: StringName, height: float) -> void:
	if _camera != null:
		_camera.set_target(self, height)


func _body_height() -> float:
	if _race != null and _race.body_height() > 0.0:
		return _race.body_height()
	return Params.PREVIEW_FIGURE_HEIGHT_FALLBACK


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var sensitivity: float = deg_to_rad(GameState.mouse_sensitivity)
		var vertical: float = -motion.relative.y
		if GameState.invert_camera_y:
			vertical = -vertical
		_camera.orbit(-motion.relative.x * sensitivity, vertical * sensitivity)
		return

	if event.is_action_pressed(ACTION_CAPTURE):
		var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION_ZOOM_IN):
		_camera.zoom(1.0)
	elif event.is_action_pressed(ACTION_ZOOM_OUT):
		_camera.zoom(-1.0)


func _physics_process(delta: float) -> void:
	_read_timers(delta)
	var wish: Vector3 = _wish_direction()
	_apply_horizontal(wish, delta)
	_apply_vertical(delta)
	_face_movement(wish, delta)

	var before: float = velocity.y
	move_and_slide()
	_detect_landing(before)

	_planar_speed = Vector2(velocity.x, velocity.z).length()
	_set_state(_resolve_state(wish))
	if _legs != null:
		_legs.set_drive_velocity(velocity)
	# A câmera é atualizada **daqui**, e não do `_physics_process` dela: ver `follow()`.
	# Depois de `move_and_slide`, para o braço mirar onde o corpo está agora.
	if _camera != null:
		_camera.follow(delta)


func _read_timers(delta: float) -> void:
	_coyote = coyote_time if is_on_floor() else maxf(0.0, _coyote - delta)
	_buffer = maxf(0.0, _buffer - delta)
	_interact_left = maxf(0.0, _interact_left - delta)

	if Input.is_action_just_pressed(ACTION_JUMP):
		_buffer = jump_buffer
	if Input.is_action_just_pressed(ACTION_INTERACT):
		_begin_interact()


## Direção desejada, em espaço de mundo, já relativa à câmera.
##
## Relativa à câmera e não ao corpo: "para a frente" tem de significar "para onde estou
## olhando". Com direção relativa ao corpo, girar a câmera não muda nada e o personagem
## anda de costas para o jogador sem que ele consiga corrigir.
func _wish_direction() -> Vector3:
	var input: Vector2 = Input.get_vector(
		ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACK
	)
	if input.length_squared() <= 0.0:
		return Vector3.ZERO
	var yaw: float = 0.0 if _camera == null else _camera.yaw()
	var frame: Basis = Basis(Vector3.UP, yaw)
	return (frame * Vector3(input.x, 0.0, input.y)).normalized()


func _apply_horizontal(wish: Vector3, delta: float) -> void:
	var target_speed: float = 0.0
	if wish.length_squared() > 0.0:
		target_speed = run_speed if Input.is_action_pressed(ACTION_SPRINT) else walk_speed
		if _interact_left > 0.0:
			# Interagir não trava o corpo, mas tira a corrida: esticar o braço para uma
			# maçaneta em disparada lê como bug, não como pressa.
			target_speed = minf(target_speed, walk_speed)

	var planar: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var wanted: Vector3 = wish * target_speed
	var rate: float = acceleration if target_speed > 0.0 else deceleration
	if not is_on_floor():
		rate *= air_control

	planar = planar.move_toward(wanted, rate * delta)
	velocity.x = planar.x
	velocity.z = planar.z


func _apply_vertical(delta: float) -> void:
	if _can_jump():
		_jump()
		return

	if is_on_floor():
		velocity.y = 0.0
		return

	var pull: float = fall_gravity_scale if velocity.y < 0.0 else 1.0
	velocity.y = maxf(velocity.y - gravity * pull * delta, -terminal_velocity)


func _can_jump() -> bool:
	return _buffer > 0.0 and _coyote > 0.0


func _jump() -> void:
	# `v = sqrt(2·g·h)`: a altura é o parâmetro porque é o que dá para conferir olhando.
	velocity.y = sqrt(2.0 * gravity * jump_height)
	_buffer = 0.0
	_coyote = 0.0
	if _legs != null:
		_legs.request_jump()


## Gira o corpo para a direção do movimento. Nunca instantâneo.
func _face_movement(wish: Vector3, delta: float) -> void:
	if wish.length_squared() <= 0.0:
		return
	# `-Z` é a frente no Godot, e a malha gerada nasce olhando para lá — daí os sinais.
	var target: float = atan2(-wish.x, -wish.z)
	# `1 - e^(-k·delta)` e não `k·delta`: interpolação crua muda de comportamento com a
	# taxa de quadros, e o mesmo ajuste giraria diferente em 30 e em 144 Hz.
	rotation.y = lerp_angle(rotation.y, target, 1.0 - exp(-turn_speed * delta))


## Detecta o toque no chão e reparte a notícia: a locomoção amortece, a câmera treme.
func _detect_landing(previous_vertical: float) -> void:
	var grounded: bool = is_on_floor()
	if grounded and not _was_on_floor:
		var impact: float = absf(previous_vertical)
		if _legs != null:
			_legs.notify_landed()
		if _camera != null:
			_camera.land(impact)
	_was_on_floor = grounded


## Aperta o verbo no alvo que o sensor escolheu.
##
## O alvo **não** é decidido aqui, e não é decidido por raio. Raio pede mira, e num jogo de
## terceira pessoa mirar um NPC a dois metros exige apontar para um ponto que o próprio
## corpo do jogador tapa — ver `InteractionSensor`, que escolhe por centralidade na tela.
func _begin_interact() -> void:
	_interact_left = (
		Params.INTERACT_REACH_TIME + Params.INTERACT_HOLD_TIME + Params.INTERACT_RETURN_TIME
	)
	var origin: Vector3 = global_position + Vector3.UP * _body_height() * Params.CAMERA_TARGET_HEIGHT
	var point: Vector3 = origin + (global_transform.basis * Vector3.FORWARD) * interact_range

	var sensor: InteractionSensor = get_node_or_null(sensor_path) as InteractionSensor
	var target: Interactable = sensor.target() if sensor != null else null
	if target != null:
		point = target.focus_point()
		target.interact(self)
		EventBus.interaction_requested.emit(target)

	if _legs != null:
		_legs.request_interact(point)


## Troca de estado, anunciando pelo `EventBus`. Ninguém aqui reage à mudança: HUD, áudio
## e IA são de outras fases, e é justamente por isso que o anúncio é um sinal global e
## não uma chamada — quem precisar se conecta sem que este arquivo saiba que existe.
func _set_state(next: State) -> void:
	if next == _state:
		return
	_state = next
	EventBus.player_state_changed.emit(int(_state))


## Precedência: interagir, depois o ar, e só então a velocidade no chão.
func _resolve_state(wish: Vector3) -> State:
	if _interact_left > 0.0 and is_on_floor():
		return State.INTERACT
	if not is_on_floor():
		return State.JUMP if velocity.y > 0.0 else State.FALL
	if _planar_speed <= idle_speed or wish.length_squared() <= 0.0:
		return State.IDLE
	return State.RUN if Input.is_action_pressed(ACTION_SPRINT) else State.WALK
