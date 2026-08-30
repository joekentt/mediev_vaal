## Escolhe com quem o jogador vai falar, entre tudo que está por perto.
##
## **Área, e não raio da câmera.** Raio pede mira, e num jogo de terceira pessoa com a
## câmera atrás do ombro, mirar um NPC a dois metros exige apontar para um ponto que o
## próprio corpo do jogador tapa. A área pega tudo dentro de `INTERACT_SENSE_RADIUS` e o
## desempate resolve o resto.
##
## **O desempate é por centralidade na tela**, não por distância. É o que o olho já está
## fazendo sem pensar: entre dois habitantes lado a lado, aquele que está mais perto do
## meio do quadro é aquele para quem o jogador está olhando. Distância entra como peso
## secundário, senão um NPC longe e perfeitamente centralizado ganharia de um encostado no
## ombro do jogador.
##
## A reavaliação é por temporizador. A doze vezes por segundo o prompt já troca antes de o
## jogador perceber que virou a câmera, e fazer isso por quadro seria uma projeção de tela
## por candidato a 60 Hz para uma resposta que muda a cada meio segundo.
class_name InteractionSensor
extends Area3D

const MIN_LENGTH: float = 0.001
## O `EventBus` é alcançado pelo caminho do autoload. Ver a nota em `npc_controller.gd`.
const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"

## Alvo escolhido agora, ou `null`.
var _target: Interactable = null
var _timer: float = 0.0
var _bus: Node = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = Params.LAYER_INTERACTABLE
	monitoring = true
	monitorable = false
	_bus = get_node_or_null(EVENT_BUS_PATH)

	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = Params.INTERACT_SENSE_RADIUS
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "SenseShape"
	collider.shape = shape
	add_child(collider)


## Alvo atual. O controlador do jogador lê daqui quando a tecla de interagir é apertada.
func target() -> Interactable:
	return _target


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / maxf(Params.INTERACT_REFRESH_HZ, MIN_LENGTH)
	_choose()


func _choose() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var best: Interactable = null
	var best_score: float = -INF

	for area: Area3D in get_overlapping_areas():
		if not area is Interactable:
			continue
		var candidate: Interactable = area as Interactable
		var score: float = _score(candidate, camera)
		if score > best_score:
			best_score = score
			best = candidate

	if best == _target:
		return
	_target = best
	if _bus != null:
		_bus.interactable_focused.emit(_target)


## Pontuação de um candidato: centralidade na tela, com a distância como desempate.
##
## A centralidade é medida como **ângulo até o eixo da câmera**, e não projetando o ponto
## na tela. As duas ordenam igual — quanto menor o ângulo, mais perto do meio do quadro —,
## mas o ângulo não tem o defeito da projeção: `unproject_position` devolve o centro da tela
## para um ponto **atrás** da câmera, e o prompt ofereceria conversa com quem ficou para
## trás. Aqui, quem passa de `INTERACT_MAX_ANGLE_DEG` sai com `-INF` e não disputa.
func _score(candidate: Interactable, camera: Camera3D) -> float:
	var spot: Vector3 = candidate.focus_point()
	var gap: float = global_position.distance_to(spot)
	if gap > Params.INTERACT_SENSE_RADIUS:
		return -INF
	if camera == null:
		# Sem câmera — cena de teste, prova headless — vale a distância pura.
		return -gap

	var forward: Vector3 = -camera.global_transform.basis.z
	var towards: Vector3 = spot - camera.global_position
	if towards.length() < MIN_LENGTH:
		return -INF
	var angle: float = rad_to_deg(forward.angle_to(towards.normalized()))
	if angle > Params.INTERACT_MAX_ANGLE_DEG:
		return -INF

	# Centralidade em 0..1: 1 no meio exato do quadro, 0 na borda do cone.
	var centrality: float = 1.0 - angle / maxf(Params.INTERACT_MAX_ANGLE_DEG, MIN_LENGTH)
	var closeness: float = 1.0 - gap / maxf(Params.INTERACT_SENSE_RADIUS, MIN_LENGTH)
	var bias: float = Params.INTERACT_CENTER_BIAS
	return centrality * bias + closeness * (1.0 - bias)


## Esquece o alvo. Chamado quando a conversa começa: durante uma conversa o prompt não tem
## o que oferecer, e mantê-lo faria a tecla abrir a mesma conversa por cima dela mesma.
func clear_target() -> void:
	if _target == null:
		return
	_target = null
	if _bus != null:
		_bus.interactable_focused.emit(null)
