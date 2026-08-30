## Movimento sem IA: pássaros, cachorro e o martelo da ferraria.
##
## Nada aqui decide nada. Não há caminho calculado, não há percepção, não há estado que
## sobreviva a um quadro — é tudo função do relógio e de uma rota fixa. É de propósito: a
## cidade precisa de movimento contínuo no campo de visão o tempo todo, e movimento que
## custa uma decisão por quadro não escala para "o tempo todo".
##
## Os pássaros são um `MultiMesh` por bando, e não um nó por pássaro. Dez pássaros seriam
## dez draw calls para dez triângulos cada; num `MultiMesh` são dois draw calls e a volta
## de cada um é uma fase somada à do bando.
##
## O martelo é o único que lê alguma coisa do mundo, e lê uma só: a fase de trabalho do
## artesão. Sincronizar o som visual da bigorna com quem está de pé na frente dela é o tipo
## de coincidência que o olho registra sem saber por quê — e desincronizar é o tipo que
## entrega o cenário na primeira olhada.
class_name AmbientLife
extends Node3D

const HALF: float = 0.5
const MIN_LENGTH: float = 0.001

## Bandos: `{"node": MultiMeshInstance3D, "center": Vector3, "radius": float,
## "phase": float, "offsets": PackedVector3Array}`.
var _flocks: Array[Dictionary] = []

## Ronda do cachorro: pontos de mundo, em ordem.
var _dog_route: PackedVector3Array = PackedVector3Array()
var _dog: Node3D = null
var _dog_index: int = 0
var _dog_pause: float = 0.0

## Martelo da ferraria e o artesão que o comanda.
var _hammer: Node3D = null
var _hammer_rest: float = 0.0
var _smith: NPCController = null
var _hammer_clock: float = 0.0

var _clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func add_flock(node: MultiMeshInstance3D, center: Vector3, radius: float, offsets: PackedVector3Array) -> void:
	_flocks.append({
		"node": node,
		"center": center,
		"radius": radius,
		"phase": float(_flocks.size()) / float(maxi(Params.AMBIENT_BIRD_FLOCKS, 1)),
		"offsets": offsets,
	})


func set_dog(node: Node3D, route: PackedVector3Array) -> void:
	_dog = node
	_dog_route = route
	if route.size() > 0:
		_dog.global_position = route[0]


func set_hammer(node: Node3D, smith: NPCController) -> void:
	_hammer = node
	_smith = smith
	_hammer_rest = node.position.y


## O artesão só existe depois de a população ser criada; o ambiente é montado antes.
func bind_smith(smith: NPCController) -> void:
	_smith = smith


func _process(delta: float) -> void:
	_clock += delta
	_fly(delta)
	_walk_dog(delta)
	_strike(delta)


# --- Pássaros -----------------------------------------------------------------


## Cada bando percorre um círculo inclinado; cada pássaro é o bando mais um deslocamento
## fixo e uma defasagem. Some-se a isso o bater de asas, que é o próprio giro do corpo.
func _fly(delta: float) -> void:
	var turn: float = delta / maxf(Params.AMBIENT_BIRD_SECONDS, MIN_LENGTH)
	for flock: Dictionary in _flocks:
		flock["phase"] = fmod(float(flock["phase"]) + turn, 1.0)
		var node: MultiMeshInstance3D = flock["node"]
		var multi: MultiMesh = node.multimesh
		var center: Vector3 = flock["center"]
		var radius: float = flock["radius"]
		var offsets: PackedVector3Array = flock["offsets"]

		for index: int in multi.instance_count:
			var lag: float = float(index) / float(maxi(multi.instance_count, 1))
			var angle: float = (float(flock["phase"]) + lag * BIRD_LAG) * TAU
			var spot: Vector3 = center + Vector3(cos(angle), 0.0, sin(angle)) * radius
			spot += offsets[index]
			# O bando sobe e desce junto, como uma revoada de verdade.
			spot.y += sin(angle * BIRD_CLIMB_TURNS) * Params.AMBIENT_BIRD_SPREAD * HALF
			# O corpo aponta para a tangente do círculo, que é para onde ele está indo.
			var heading: float = angle + PI * HALF
			multi.set_instance_transform(
				index, Transform3D(Basis(Vector3.UP, -heading), spot)
			)


## Defasagem máxima entre o primeiro e o último pássaro do bando, em voltas.
const BIRD_LAG: float = 0.06
## Subidas e descidas por volta.
const BIRD_CLIMB_TURNS: float = 3.0


# --- Cachorro -----------------------------------------------------------------


## Ronda: anda até o próximo ponto, para um instante, segue. Sem navmesh e sem física — a
## rota já foi traçada sobre a malha de navegação quando o ambiente foi montado.
func _walk_dog(delta: float) -> void:
	if _dog == null or _dog_route.size() < 2:
		return
	if _dog_pause > 0.0:
		_dog_pause -= delta
		return

	var target: Vector3 = _dog_route[_dog_index]
	var step: Vector3 = target - _dog.global_position
	step.y = 0.0
	var gap: float = step.length()
	if gap < Params.AMBIENT_DOG_SPEED * delta:
		_dog.global_position = Vector3(target.x, _dog.global_position.y, target.z)
		_dog_index = (_dog_index + 1) % _dog_route.size()
		_dog_pause = Params.AMBIENT_DOG_PAUSE
		return

	var direction: Vector3 = step / gap
	_dog.global_position += direction * Params.AMBIENT_DOG_SPEED * delta
	_dog.global_position.y = target.y
	_dog.rotation.y = lerp_angle(
		_dog.rotation.y, atan2(direction.x, direction.z), minf(delta * DOG_TURN_RATE, 1.0)
	)
	# Trote: o corpo sobe e desce no ritmo do passo, e é isso que o separa de uma caixa
	# deslizando pelo chão.
	_dog.position.y = target.y + absf(sin(_clock * DOG_TROT_HZ)) * DOG_TROT_LIFT


const DOG_TURN_RATE: float = 6.0
const DOG_TROT_HZ: float = 9.0
const DOG_TROT_LIFT: float = 0.06


# --- Martelo ------------------------------------------------------------------


## O martelo sobe e desce no compasso do artesão. Sem artesão por perto — dormindo, longe,
## ou simulado de forma abstrata — a bigorna fica quieta, que é o correto: uma ferraria que
## martela sozinha de madrugada é pior que uma ferraria muda.
func _strike(_delta: float) -> void:
	if _hammer == null:
		return
	var working: bool = (
		_smith != null
		and is_instance_valid(_smith)
		and _smith.is_active()
		and _smith.state() == NPCController.State.WORK
	)
	if not working:
		_hammer.position.y = _hammer_rest
		return

	_hammer_clock = _smith.work_phase()
	# Uma pancada por ciclo: sobe devagar na primeira metade, desce de uma vez na segunda.
	var lift: float = 1.0 - absf(_hammer_clock * 2.0 - 1.0)
	_hammer.position.y = _hammer_rest + pow(lift, HAMMER_EASE) * Params.AMBIENT_HAMMER_LIFT
	_hammer.rotation.x = -lift * Params.AMBIENT_HAMMER_LIFT


## Expoente da subida do martelo. Maior que 1 concentra o movimento no alto do arco.
const HAMMER_EASE: float = 2.0
