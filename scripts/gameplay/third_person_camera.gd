## Câmera de terceira pessoa: braço com colisão, atraso posicional e tranco de pouso.
##
## **Por que a câmera nunca atravessa parede.** O nó *é* um `SpringArm3D`, que varre do
## alvo até onde a câmera deveria estar e encurta o braço no primeiro obstáculo. O detalhe
## que não dá para pular: a varredura precisa ser de **forma**, e por isso o `_ready`
## atribui uma esfera ao `shape`. Com `shape` nulo o nó cai num raycast, e nesse caminho a
## propriedade `margin` é simplesmente ignorada — foi medido: a lente parava a 14 mm da
## parede, ou seja, exatamente em cima dela, com o near plane já dentro da pedra. O que
## mantém a câmera afastada é o raio da esfera, não a margem.
##
## **Por que o braço é `top_level`.** Preso ao corpo, a câmera herda cada tranco do
## personagem e o mundo inteiro treme junto com a passada. Solto, ele persegue o alvo com
## mola: o corpo se move *dentro* do quadro, que é o que dá peso ao movimento. O preço é
## que a posição vira responsabilidade deste nó, e é o que `_physics_process` faz.
##
## O tranco de pouso e o balanço de corrida entram como deslocamento do alvo, não como
## rotação: sacudir a direção do olhar embrulha o estômago em dois minutos.
class_name ThirdPersonCamera
extends SpringArm3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _target: Node3D = null
var _target_height: float = 0.0
var _camera: Camera3D = null
var _locomotion: ProceduralLocomotion = null
var _shake: float = 0.0
var _shake_time: float = 0.0
var _distance: float = 0.0
var _has_anchor: bool = false

@export_group("Enquadramento")
## Comprimento de repouso do braço, em metros.
@export var distance: float = Params.CAMERA_DISTANCE
@export var distance_min: float = Params.CAMERA_DISTANCE_MIN
@export var distance_max: float = Params.CAMERA_DISTANCE_MAX
## Metros por clique da roda do mouse.
@export var zoom_step: float = Params.CAMERA_ZOOM_STEP
## Onde o braço se prende, em fração da altura do corpo. 0,86 fica no pescoço.
@export var target_height: float = Params.CAMERA_TARGET_HEIGHT

@export_group("Rotação")
@export var pitch_min_deg: float = Params.CAMERA_PITCH_MIN_DEG
@export var pitch_max_deg: float = Params.CAMERA_PITCH_MAX_DEG
@export var start_pitch_deg: float = Params.CAMERA_START_PITCH_DEG

@export_group("Seguimento")
## Quão rápido a plataforma alcança o alvo, em 1/s. Alto gruda, baixo arrasta.
@export var follow_lag: float = Params.CAMERA_FOLLOW_LAG
@export var fov: float = Params.CAMERA_FOV
## Graus somados ao FOV na velocidade máxima. É a leitura de "está mais rápido".
@export var fov_run_bonus: float = Params.CAMERA_FOV_RUN_BONUS
@export var fov_lerp: float = Params.CAMERA_FOV_LERP

@export_group("Tranco de aterrissagem")
@export var shake_amplitude: float = Params.CAMERA_SHAKE_AMPLITUDE
@export var shake_decay: float = Params.CAMERA_SHAKE_DECAY
@export var shake_frequency: float = Params.CAMERA_SHAKE_FREQUENCY
## Queda abaixo desta velocidade não sacode nada — pular no lugar não é um baque.
@export var shake_min_fall: float = Params.CAMERA_SHAKE_MIN_FALL
## Queda onde o tranco satura. Acima disso não piora, para não virar epilepsia.
@export var shake_max_fall: float = Params.CAMERA_SHAKE_MAX_FALL


## Enquadramento de conversa: para onde olhar, e se está ativo.
var _conversation_focus: Vector3 = Vector3.ZERO
var _in_conversation: bool = false


func _ready() -> void:
	# Sem isto o braço herda a rotação do corpo, e o personagem girar arrastaria a câmera
	# junto: mira e movimento deixariam de ser independentes.
	top_level = true
	_distance = distance
	spring_length = distance
	margin = Params.CAMERA_SPRING_MARGIN
	collision_mask = Params.LAYER_WORLD
	var probe: SphereShape3D = SphereShape3D.new()
	probe.radius = Params.CAMERA_PROBE_RADIUS
	shape = probe
	_pitch = deg_to_rad(start_pitch_deg)

	for child: Node in get_children():
		if child is Camera3D:
			_camera = child as Camera3D
	if _camera != null:
		_camera.fov = fov


## Quem a câmera segue, e quão alto é. Chame de novo se o corpo mudar de tamanho.
func set_target(node: Node3D, height: float) -> void:
	_target = node
	_target_height = height
	if not _has_anchor:
		_snap()


## Nó de locomoção cujo `camera_offset` a câmera soma. Opcional: sem ele, sem balanço.
func set_locomotion(legs: ProceduralLocomotion) -> void:
	_locomotion = legs


## Guinada atual em radianos. O controlador move o corpo em relação a isto — é o que faz
## "para a frente" significar "para onde a câmera olha".
func yaw() -> float:
	return _yaw


## Sacode a câmera na proporção de um impacto. `fall_speed` em m/s.
func land(fall_speed: float) -> void:
	if fall_speed <= shake_min_fall:
		return
	var span: float = maxf(shake_max_fall - shake_min_fall, 1.0)
	_shake = clampf((fall_speed - shake_min_fall) / span, 0.0, 1.0)
	_shake_time = 0.0


## Gira a câmera. Em radianos, já com a inversão de eixo aplicada por quem chama.
func orbit(delta_yaw: float, delta_pitch: float) -> void:
	_yaw = wrapf(_yaw + delta_yaw, -PI, PI)
	_pitch = clampf(
		_pitch + delta_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg)
	)


## Aproxima ou afasta. `steps` positivo aproxima.
func zoom(steps: float) -> void:
	distance = clampf(distance - steps * zoom_step, distance_min, distance_max)


## Reposiciona o braço. **Quem chama é o corpo**, do `_physics_process` dele, e não um
## `_physics_process` próprio deste nó.
##
## A ordem é o motivo. O `SpringArm3D` faz a varredura no próprio processamento interno,
## que acontece *antes* do script do mesmo nó — então um braço que se movesse no próprio
## `_physics_process` varreria sempre com a rotação do frame anterior. Numa girada rápida
## de mouse isso põe a lente dentro da parede por um quadro. Chamado pelo corpo, que é o
## nó **pai**, a transformação já está nova quando a varredura roda.
## Enquadra uma conversa: a câmera desliza para trás do ombro do jogador, olhando para a
## cabeça do interlocutor.
##
## Desliza, não corta. Corte seco em jogo de terceira pessoa custa a orientação espacial
## que o jogador levou a caminhada inteira para construir — ele perde onde está e, ao sair
## da conversa, anda para o lado errado.
func frame_conversation(focus: Vector3) -> void:
	_conversation_focus = focus
	_in_conversation = true


func release_conversation() -> void:
	_in_conversation = false


func is_framing_conversation() -> bool:
	return _in_conversation


func follow(delta: float) -> void:
	if _target == null:
		return

	var anchor: Vector3 = _target.global_position + Vector3.UP * target_height * _target_height
	if _locomotion != null:
		anchor += _locomotion.camera_offset

	if _in_conversation:
		_follow_conversation(anchor, delta)
		return

	_tick_wake(delta)
	global_position = global_position.lerp(anchor, _smoothing(follow_lag, delta))
	rotation = Vector3(_pitch, _yaw, 0.0)

	_distance = lerpf(_distance, distance, _smoothing(follow_lag, delta))
	spring_length = _distance + _shake_offset(delta)
	_update_fov(delta)


## Abre os olhos: a câmera parte do chão e sobe até a linha do horizonte.
##
## É a abertura do jogo, e é tudo o que ela é — não há corte, não há letreiro, não há texto.
## Começar olhando para o chão e terminar olhando para a estrada é o que transforma
## "apareci num vale" em "acordei aqui", e custa uma interpolação de pitch.
func wake(seconds: float) -> void:
	_wake_left = maxf(seconds, 0.0)
	_wake_total = _wake_left
	_pitch = deg_to_rad(pitch_min_deg)


var _wake_left: float = 0.0
var _wake_total: float = 0.0


## Ainda abrindo os olhos? A prova lê daqui.
func is_waking() -> bool:
	return _wake_left > 0.0


func _tick_wake(delta: float) -> void:
	if _wake_left <= 0.0:
		return
	_wake_left = maxf(_wake_left - delta, 0.0)
	# Ease-out: o olhar sobe depressa e desacelera ao chegar na linha do horizonte, que é
	# como uma cabeça que se levanta se comporta. Linear parece elevador.
	var travelled: float = 1.0 - _wake_left / maxf(_wake_total, MIN_TIME)
	var eased: float = 1.0 - pow(1.0 - travelled, WAKE_EASE)
	_pitch = lerpf(deg_to_rad(pitch_min_deg), deg_to_rad(start_pitch_deg), eased)


const WAKE_EASE: float = 3.0
const MIN_TIME: float = 0.001


## Enquadramento de ombro: o braço encolhe, escorrega para o lado e aponta para a cabeça
## do interlocutor.
##
## O lado escolhido é o **oposto** ao interlocutor. Pôr a câmera do mesmo lado deixaria o
## corpo do jogador entre a lente e o rosto de quem fala, que é exatamente o que um
## enquadramento de conversa existe para evitar.
func _follow_conversation(anchor: Vector3, delta: float) -> void:
	var towards: Vector2 = Vector2(
		_conversation_focus.x - anchor.x, _conversation_focus.z - anchor.z
	)
	if towards.length() < CONVERSATION_MIN_GAP:
		return
	var facing: float = atan2(towards.x, towards.y)
	var blend: float = _smoothing(Params.DIALOGUE_CAMERA_BLEND, delta)

	var side: Vector3 = Basis(Vector3.UP, facing) * Vector3.RIGHT
	var spot: Vector3 = (
		anchor
		+ side * Params.DIALOGUE_CAMERA_SIDE
		+ Vector3.UP * Params.DIALOGUE_CAMERA_RISE
	)
	global_position = global_position.lerp(spot, blend)

	# O braço encolhe para a distância de conversa e a mola continua colidindo: o
	# enquadramento não é desculpa para a lente atravessar a parede atrás do jogador.
	spring_length = lerpf(spring_length, Params.DIALOGUE_CAMERA_BACK, blend)

	var wanted_yaw: float = facing
	var height: float = _conversation_focus.y - global_position.y
	var reach: float = maxf(towards.length(), CONVERSATION_MIN_GAP)
	var wanted_pitch: float = atan2(height, reach)
	_yaw = lerp_angle(_yaw, wanted_yaw, blend)
	_pitch = lerp_angle(_pitch, wanted_pitch, blend)
	rotation = Vector3(_pitch, _yaw, 0.0)

	if _camera != null:
		_camera.fov = lerpf(_camera.fov, Params.DIALOGUE_CAMERA_FOV, blend)


## Piso da distância ao interlocutor. Abaixo disto a direção é ruído e o enquadramento
## giraria sozinho.
const CONVERSATION_MIN_GAP: float = 0.2


## Distância livre entre o alvo e a lente, em metros. Negativa significa que a lente
## atravessou geometria — é o critério de aceite da fase medido de dentro do nó.
func clearance() -> float:
	if _camera == null:
		return spring_length
	return global_position.distance_to(_camera.global_position)


## Fração de interpolação para este frame, independente da taxa de quadros.
##
## `1 - e^(-k·delta)` e não `k·delta`: interpolação crua muda de comportamento quando o
## frame varia, e o mesmo valor de ajuste dá seguimentos diferentes em 30 e em 144 Hz.
func _smoothing(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


## Tranco de pouso, aplicado ao **comprimento** do braço e não à direção do olhar.
##
## Empurrar e puxar a câmera ao longo do próprio braço lê como impacto e não desestabiliza
## o horizonte. Rodar o olhar leria como perder o equilíbrio, que é outra coisa.
func _shake_offset(delta: float) -> float:
	if _shake <= 0.0:
		return 0.0
	_shake_time += delta
	_shake = maxf(0.0, _shake - shake_decay * delta * _shake)
	return sin(_shake_time * TAU * shake_frequency) * shake_amplitude * _shake


func _update_fov(delta: float) -> void:
	if _camera == null:
		return
	var running: float = 0.0
	if _locomotion != null:
		running = clampf(
			_locomotion.current_speed() / maxf(Params.PLAYER_RUN_SPEED, 1.0), 0.0, 1.0
		)
	_camera.fov = lerpf(
		_camera.fov, fov + fov_run_bonus * running, _smoothing(fov_lerp, delta)
	)


## Põe a câmera no lugar sem interpolar. Usado no primeiro frame, para o jogo não começar
## com a câmera vindo da origem do mundo até o jogador.
func _snap() -> void:
	if _target == null:
		return
	_has_anchor = true
	global_position = _target.global_position + Vector3.UP * target_height * _target_height
	rotation = Vector3(_pitch, _yaw, 0.0)
