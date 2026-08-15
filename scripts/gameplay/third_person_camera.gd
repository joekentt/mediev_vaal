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
func follow(delta: float) -> void:
	if _target == null:
		return

	var anchor: Vector3 = _target.global_position + Vector3.UP * target_height * _target_height
	if _locomotion != null:
		anchor += _locomotion.camera_offset

	global_position = global_position.lerp(anchor, _smoothing(follow_lag, delta))
	rotation = Vector3(_pitch, _yaw, 0.0)

	_distance = lerpf(_distance, distance, _smoothing(follow_lag, delta))
	spring_length = _distance + _shake_offset(delta)
	_update_fov(delta)


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
