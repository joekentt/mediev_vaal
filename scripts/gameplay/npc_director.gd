## Decide quem custa física e quem custa quase nada.
##
## O orçamento do projeto tem um teto de NPCs ativos (`BUDGET["active_npcs"]`), e a fase 8
## encheu a cidade de prédios que já consomem draw call. Este nó é o que mantém as duas
## coisas compatíveis: perto da câmera o habitante é um `CharacterBody3D` com navegação e
## malha; longe dela ele é uma posição avançando sobre a rota que já tinha.
##
## Três decisões que parecem detalhe e não são:
##
## 1. **A reavaliação é por temporizador, não por quadro.** Quatro vezes por segundo é
##    mais que suficiente para uma fronteira de 60 m — a câmera precisaria voar a 240 m/s
##    para atravessá-la entre duas avaliações. Fazer isso por quadro seria vinte medições
##    de distância a 60 Hz para uma decisão que muda uma vez a cada vários segundos.
## 2. **A fronteira tem histerese.** Sem ela, um NPC parado exatamente a 60 m entraria e
##    sairia da simulação cara a cada avaliação, e o custo do liga-desliga é maior que o
##    da própria física.
## 3. **O teto vence o raio.** Se mais habitantes couberem no raio do que o orçamento
##    permite, ficam os mais próximos. É o que garante que o número de corpos ativos seja
##    um teto de verdade e não uma expectativa.
class_name NPCDirector
extends Node

## Quem observa: o jogador quando existe, a câmera ativa quando não. As provas rodam sem
## jogador, e um diretor que só soubesse olhar para o jogador desligaria a cidade inteira.
var observer: Node3D = null

var _npcs: Array[NPCController] = []
var _timer: float = 0.0
var _active_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Registra um habitante. Chamado por `population_gen.gd` na criação.
func enroll(npc: NPCController) -> void:
	_npcs.append(npc)


func population() -> int:
	return _npcs.size()


func active_count() -> int:
	return _active_count


func _physics_process(delta: float) -> void:
	# Os abstratos avançam todo quadro, porque avançar é uma interpolação e custa menos que
	# decidir se vale a pena avançar.
	for npc: NPCController in _npcs:
		if is_instance_valid(npc) and not npc.is_active():
			npc.advance_abstract(delta)

	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / maxf(Params.NPC_DIRECTOR_HZ, MIN_RATE)
	_reassign()


func _reassign() -> void:
	var eye: Vector3 = _observer_position()
	var ceiling: int = Params.budget(&"active_npcs")

	# Ordena por distância e liga de dentro para fora até o teto. Uma passada só: a lista
	# tem vinte entradas, e um particionamento sofisticado custaria mais que a ordenação.
	var ranked: Array[NPCController] = []
	for npc: NPCController in _npcs:
		if is_instance_valid(npc):
			ranked.append(npc)
	ranked.sort_custom(func(a: NPCController, b: NPCController) -> bool:
		return (
			a.global_position.distance_squared_to(eye)
			< b.global_position.distance_squared_to(eye)
		)
	)

	_active_count = 0
	for index: int in ranked.size():
		var npc: NPCController = ranked[index]
		var gap: float = npc.global_position.distance_to(eye)
		# Histerese: quem já está ativo só sai depois da folga; quem está fora só entra
		# antes dela. A fronteira deixa de piscar por um NPC parado em cima dela.
		var threshold: float = Params.NPC_ACTIVE_RADIUS
		if npc.is_active():
			threshold += Params.NPC_ACTIVE_HYSTERESIS
		var wanted: bool = gap <= threshold and _active_count < ceiling
		npc.set_simulated(wanted)
		npc.set_shadow_casting(wanted and gap <= Params.NPC_SHADOW_RADIUS)
		if wanted:
			_active_count += 1


func _observer_position() -> Vector3:
	if observer != null and is_instance_valid(observer):
		return observer.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	return Vector3.ZERO


## Piso da frequência de reavaliação, para uma taxa zerada em params.py não dividir por 0.
const MIN_RATE: float = 0.01
