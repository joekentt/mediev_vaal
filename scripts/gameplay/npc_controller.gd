## Um habitante: máquina de estados, agenda, navegação e reação barata.
##
## O NPC não sabe o que é uma cidade. Ele recebe um dicionário de lugares por nome —
## `praca`, `poco`, `casa`, `trabalho` — e uma `NPCSchedule` que diz a que horas ir a cada
## um. Quem resolve os nomes contra os `Marker3D` da fase 8 é `population_gen.gd`. É essa
## indireção que faz a mesma rotina servir a qualquer seed de cidade.
##
## **A hora chega por sinal, não por leitura.** `EventBus.hour_changed` dispara 24 vezes
## por dia; vinte NPCs perguntando as horas a 60 Hz seriam 1200 consultas por segundo para
## responder a uma pergunta que muda 24 vezes por dia. O mesmo princípio vale para a
## percepção: uma `Area3D` avisa quem entrou, ninguém varre a cena atrás de vizinhos.
##
## **O corpo é o da fase 6 inteiro.** `RaceApplier` veste a malha e dimensiona a cápsula,
## `ProceduralLocomotion` move as pernas por IK a partir da velocidade real. Este arquivo
## não anima nada: ele decide para onde andar e entrega a velocidade.
class_name NPCController
extends CharacterBody3D

## Estados da rotina. `REACT` é o único que não vem da agenda — ele interrompe o que
## estiver acontecendo e devolve o NPC ao estado anterior quando acaba.
enum State { IDLE, WALK_TO, WORK, SOCIALIZE, SLEEP, REACT }

## Nomes de marcador resolvidos por NPC. Ver `population_gen.gd`.
const MARKER_HOME: StringName = &"casa"
const MARKER_WORK: StringName = &"trabalho"

## Fração do passo em que o gesto de trabalho vai e volta. Estrutural: um seno completo.
const WORK_CYCLE: float = 1.0
## Piso de comprimento para não normalizar um vetor nulo.
const MIN_LENGTH: float = 0.001
const HALF: float = 0.5

@export_group("Identidade")
## Arquétipo, para escolher a fala e para o relatório da prova.
@export var archetype: StringName = &"comerciante"
## Semente de variação. Dois NPCs com a mesma agenda e sementes diferentes não andam
## em bloco — é o que impede a praça de virar um formigueiro sincronizado.
@export var variation_seed: int = 0

@export_group("Movimento")
@export var walk_speed: float = Params.NPC_WALK_SPEED
@export var hurry_speed: float = Params.NPC_HURRY_SPEED
@export var turn_rate: float = Params.NPC_TURN_RATE
@export var arrive_radius: float = Params.NPC_ARRIVE_RADIUS

@export_group("Ócio")
@export var idle_min: float = Params.NPC_IDLE_MIN
@export var idle_max: float = Params.NPC_IDLE_MAX
@export var wander_chance: float = Params.NPC_WANDER_CHANCE
@export var wander_radius: float = Params.NPC_WANDER_RADIUS

@export_group("Nós")
@export var agent_path: NodePath = NodePath("Agent")
@export var locomotion_path: NodePath = NodePath("Locomotion")
@export var race_path: NodePath = NodePath("Race")
@export var sense_path: NodePath = NodePath("Sense")
@export var speech_path: NodePath = NodePath("Speech")

## Agenda do arquétipo, carregada por `population_gen.gd`.
var schedule: NPCSchedule = null
## Lugares por nome, já resolvidos em coordenadas de mundo.
var places: Dictionary = {}

var _state: State = State.IDLE
## Estado a que o NPC volta quando termina de andar ou de reagir.
var _task_state: State = State.IDLE
var _goal: Vector3 = Vector3.ZERO
## Onde é o posto deste bloco de agenda. O passeio curto parte daqui, e não do alvo
## corrente: partir do alvo fazia cada volta somar à anterior, e em três minutos o
## habitante tinha derivado para longe do próprio posto sem nunca ter recebido essa ordem.
var _post_position: Vector3 = Vector3.ZERO
## Deslocamento fixo em torno do marcador. Sorteado uma vez: vinte NPCs mirando o mesmo
## ponto se empilhariam nele.
var _spread: Vector3 = Vector3.ZERO
var _idle_timer: float = 0.0
var _repath_timer: float = 0.0
var _react_timer: float = 0.0
var _speak_cooldown: float = 0.0
var _look_timer: float = 0.0
var _look_target: Vector3 = Vector3.ZERO
var _work_phase: float = 0.0

## Anti-travamento: onde o NPC estava quando a janela começou, e há quanto tempo.
var _progress_anchor: Vector3 = Vector3.ZERO
var _progress_timer: float = 0.0
var _stuck_events: int = 0

## Simulação barata. Quando falso, o NPC não tem física nem navegação: quem o move é
## `NPCDirector`, interpolando a rota que ele já tinha.
var _active: bool = true
var _shadows_on: bool = true
var _mesh_cache: Array[MeshInstance3D] = []
var _abstract_path: PackedVector3Array = PackedVector3Array()
var _abstract_index: int = 0

@onready var _agent: NavigationAgent3D = get_node(agent_path)
@onready var _locomotion: ProceduralLocomotion = get_node(locomotion_path)
@onready var _sense: Area3D = get_node(sense_path)
@onready var _speech: Label3D = get_node(speech_path)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## O `EventBus` é alcançado pelo caminho do autoload, e não pelo identificador global.
##
## Não é preferência de estilo: o identificador de um autoload só existe depois que o
## projeto registra os autoloads, e um script rodado com `--script` compila antes disso.
## Como `tools/bench.gd`, `tools/city.gd` e `tools/population.gd` referenciam
## `WorldGenerator` — que agora alcança o habitante — o identificador global aqui
## quebrava a compilação de **toda** a medição do projeto com "Identifier not found:
## EventBus". A cena do jogador escapa disso por ser carregada em runtime; o habitante
## não escapa, porque o gerador de população o nomeia.
const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"
const TIME_SYSTEM_PATH: NodePath = ^"/root/TimeSystem"
var _bus: Node = null
var _clock: Node = null


func _ready() -> void:
	_rng.seed = variation_seed
	_spread = _random_offset(Params.NPC_TARGET_SPREAD)
	_idle_timer = _rng.randf_range(idle_min, idle_max)
	_progress_anchor = global_position

	_agent.path_desired_distance = arrive_radius * HALF
	_agent.target_desired_distance = arrive_radius
	_agent.radius = Params.NAV_AGENT_RADIUS
	_agent.height = Params.NAV_AGENT_HEIGHT

	_speech.visible = false
	_sense.body_entered.connect(_on_sensed)
	_bus = get_node_or_null(EVENT_BUS_PATH)
	_clock = get_node_or_null(TIME_SYSTEM_PATH)
	if _bus != null:
		_bus.hour_changed.connect(_on_hour_changed)
	# A agenda é aplicada já, e não só na próxima virada de hora: um NPC que nasce às 8h05
	# esperaria até as 9h para saber o que fazer.
	apply_schedule()


## Liga ou desliga a projeção de sombra deste corpo.
##
## Chamado pelo diretor por distância. Não é economia de última hora: com duas cascatas,
## um corpo custa três draw calls — um de cor e um por cascata — e vinte corpos custam
## sessenta. A sombra de uma pessoa a 30 m é um punhado de pixels, e a malha do corpo
## continua desenhada: o que some é só a mancha no chão.
func set_shadow_casting(enabled: bool) -> void:
	if _shadows_on == enabled:
		return
	_shadows_on = enabled
	var setting: GeometryInstance3D.ShadowCastingSetting = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for node: MeshInstance3D in _meshes():
		node.cast_shadow = setting


## Malhas do corpo, achadas uma vez. O `RaceApplier` as cria no `_ready`, então procurar
## antes disso devolveria uma lista vazia que nunca mais seria refeita.
func _meshes() -> Array[MeshInstance3D]:
	if _mesh_cache.is_empty():
		_gather_meshes(self)
	return _mesh_cache


func _gather_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_cache.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_gather_meshes(child)


## Estado atual. A prova lê isto para saber quem está andando e quem está dormindo.
func state() -> State:
	return _state


func is_active() -> bool:
	return _active


func stuck_events() -> int:
	return _stuck_events


# --- Agenda -------------------------------------------------------------------


func _on_hour_changed(_hour: int) -> void:
	apply_schedule()


## Lê o bloco que vale agora e põe o NPC a caminho dele.
func apply_schedule() -> void:
	if schedule == null:
		return
	var block: Dictionary = schedule.block_for(_hour_now())
	if block.is_empty():
		return

	var marker: StringName = block["marker"]
	if not places.has(marker):
		push_warning("NPC %s: marcador '%s' não existe nesta cidade." % [name, marker])
		return

	_task_state = _state_from_name(block["state"])
	_post_position = _reachable(Vector3(places[marker]) + _spread)
	_goal = _post_position
	if _bus != null:
		_bus.npc_schedule_changed.emit(self, marker)

	if _flat_distance(global_position, _goal) > arrive_radius:
		_enter(State.WALK_TO)
		return
	_enter(_task_state)


## Hora do mundo. Sem relógio — cena de teste sem autoloads — vale a hora de partida, que
## é o que faz o habitante ao menos escolher um bloco em vez de ficar sem ordem nenhuma.
func _hour_now() -> float:
	if _clock == null:
		return Params.START_HOUR
	return float(_clock.get_time_of_day())


static func _state_from_name(text: StringName) -> State:
	if text == &"WALK_TO":
		return State.WALK_TO
	if text == &"WORK":
		return State.WORK
	if text == &"SOCIALIZE":
		return State.SOCIALIZE
	if text == &"SLEEP":
		return State.SLEEP
	if text == &"REACT":
		return State.REACT
	return State.IDLE


func _enter(next: State) -> void:
	if _state == next:
		return
	_state = next

	# Dormir é o único estado que apaga o NPC do mundo: sem malha, sem colisão, sem
	# navegação. Uma casa do kit não tem interior, e deixar o corpo de pé atrás da porta
	# custaria física e desenho por nada.
	var sleeping: bool = next == State.SLEEP
	visible = not sleeping
	set_collision_layer_value(NPC_LAYER_BIT, not sleeping)

	if next == State.WALK_TO:
		_repath_timer = 0.0
		_progress_anchor = global_position
		_progress_timer = 0.0
		return
	velocity = Vector3.ZERO
	_locomotion.clear_drive_velocity()
	if next != State.REACT:
		_idle_timer = _rng.randf_range(idle_min, idle_max)


## Bit da camada de NPC. `set_collision_layer_value` conta bits a partir de 1.
const NPC_LAYER_BIT: int = 3


## Leva um ponto para o polígono navegável mais próximo.
##
## Todo alvo passa por aqui, e não só os suspeitos. O deslocamento que espalha vinte NPCs
## em torno do mesmo marcador tem até `NPC_TARGET_SPREAD` metros e não sabe onde estão as
## paredes: parte deles caía dentro de um prédio, o habitante andava até o ponto mais perto
## que conseguia, nunca "chegava", e o anti-travamento disparava. Foram 8 destravamentos em
## três minutos — todos com o mesmo motivo, e nenhum deles um problema de navegação.
func _reachable(point: Vector3) -> Vector3:
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid():
		return point

	var snapped_point: Vector3 = NavigationServer3D.map_get_closest_point(map, point)
	# Navegável não é o mesmo que alcançável. A malha da cidade tem ilhas — o chão dentro
	# da taverna é uma delas, ligada ao resto por uma porta de 1,2 m que o raio de agente de
	# 0,5 m nem sempre atravessa. Um alvo numa ilha faz o habitante andar até o ponto mais
	# perto que consegue e nunca chegar, e o anti-travamento dispara sem que haja travamento
	# nenhum. Terminar o alvo no fim do caminho possível resolve na origem.
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		map, global_position, snapped_point, true
	)
	if path.is_empty():
		return snapped_point
	var reached: Vector3 = path[path.size() - 1]
	if _flat_distance(reached, snapped_point) > arrive_radius:
		return reached
	return snapped_point


# --- Passo --------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if not _active:
		return

	_speak_cooldown = maxf(_speak_cooldown - delta, 0.0)
	_tick_look(delta)

	match _state:
		State.WALK_TO:
			_step_walk(delta)
		State.WORK:
			_step_task(delta, true)
		State.SOCIALIZE:
			_step_task(delta, false)
		State.REACT:
			_step_react(delta)
		State.SLEEP:
			pass
		_:
			_step_task(delta, false)


func _step_walk(delta: float) -> void:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_agent.target_position = _goal
		_repath_timer = Params.NPC_REPATH_SECONDS

	if _flat_distance(global_position, _goal) <= arrive_radius or _agent.is_navigation_finished():
		_enter(_task_state)
		return

	var step: Vector3 = _next_step()
	if step.length() < MIN_LENGTH:
		# Sem caminho ainda. O assado da navegação roda numa thread e pode não ter
		# terminado quando o habitante nasce; tratar isso como chegada poria vinte NPCs a
		# "trabalhar" em cima da própria casa e lá ficariam até a virada de hora.
		return

	var direction: Vector3 = step.normalized()
	var speed: float = walk_speed
	velocity = Vector3(direction.x * speed, velocity.y, direction.z * speed)
	if not is_on_floor():
		velocity.y -= Params.PLAYER_GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	_face(direction, delta)
	_locomotion.set_drive_velocity(Vector3(velocity.x, 0.0, velocity.z))
	_watch_progress(delta)


## Próximo passo em planta, lido do caminho e não de `get_next_path_position()`.
##
## A malha de navegação **flutua sobre o chão** — o Recast rasteriza em células de
## `NAV_CELL_HEIGHT` e o polígono fica alguns decímetros acima do relevo. Medido: 0,7 m.
## O `NavigationAgent3D` decide que chegou a um ponto do caminho por distância em três
## dimensões, então o primeiro ponto, que fica exatamente em cima do agente e 0,7 m mais
## alto, nunca é considerado alcançado: o agente devolve esse mesmo ponto para sempre e o
## habitante fica parado tentando andar. Foi assim que os vinte primeiros NPCs desta fase
## passaram três minutos imóveis, em `WALK_TO`, acumulando destravamentos.
##
## Ler o caminho e avançar o índice **por distância horizontal** resolve na origem: a
## altura deixa de participar de uma decisão que é de planta.
func _next_step() -> Vector3:
	var path: PackedVector3Array = _agent.get_current_navigation_path()
	if path.is_empty():
		return Vector3.ZERO

	var index: int = _agent.get_current_navigation_path_index()
	while index < path.size() - 1 and _flat_distance(global_position, path[index]) < arrive_radius * HALF:
		index += 1
	if index >= path.size():
		return Vector3.ZERO

	var step: Vector3 = path[index] - global_position
	step.y = 0.0
	return step


## Anti-travamento. Um NPC que não avança meio metro em seis segundos está preso numa
## quina de porta, e insistir no mesmo caminho não o solta.
##
## O destravamento **não teleporta**: ele pede ao servidor de navegação o ponto navegável
## mais próximo e recomeça dali. Teleportar seria a correção fácil e é exatamente como um
## habitante atravessa uma parede na frente do jogador.
func _watch_progress(delta: float) -> void:
	_progress_timer += delta
	if _progress_timer < Params.NPC_STUCK_SECONDS:
		return
	if _flat_distance(global_position, _progress_anchor) >= Params.NPC_STUCK_PROGRESS:
		_progress_anchor = global_position
		_progress_timer = 0.0
		return

	_stuck_events += 1
	global_position = NavigationServer3D.map_get_closest_point(
		_agent.get_navigation_map(), global_position
	)
	_progress_anchor = global_position
	_progress_timer = 0.0
	_repath_timer = 0.0


## Parado no posto: gesto de trabalho, olhada em volta e, de vez em quando, uma volta curta.
func _step_task(delta: float, working: bool) -> void:
	velocity = Vector3.ZERO
	_locomotion.clear_drive_velocity()

	if working:
		# O gesto é publicado como fase, não como animação: quem move o braço é a
		# locomoção, e quem lê a fase para bater o martelo é a vida ambiente.
		_work_phase = fmod(_work_phase + delta / maxf(Params.AMBIENT_HAMMER_PERIOD, MIN_LENGTH), WORK_CYCLE)

	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	_idle_timer = _rng.randf_range(idle_min, idle_max)

	if _rng.randf() < wander_chance:
		_goal = _reachable(_post_position + _random_offset(wander_radius))
		_enter(State.WALK_TO)
		return
	# Sem passeio, o NPC ao menos vira a cabeça — parado e imóvel lê como estátua.
	_look_at_for(_post_position + _random_offset(wander_radius), Params.NPC_LOOK_SECONDS)


## Fase do gesto de trabalho, 0..1. A ferraria bate o martelo em cima disto.
func work_phase() -> float:
	return _work_phase


func _step_react(delta: float) -> void:
	velocity = Vector3.ZERO
	_locomotion.clear_drive_velocity()
	_react_timer -= delta
	if _react_timer <= 0.0:
		_enter(_task_state)


func _face(direction: Vector3, delta: float) -> void:
	var wanted: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, wanted, minf(turn_rate * delta, 1.0))


func _tick_look(delta: float) -> void:
	if _look_timer <= 0.0:
		return
	_look_timer -= delta
	if _look_timer <= 0.0:
		_locomotion.clear_look()
		return
	_locomotion.look_at_point(_look_target)


func _look_at_for(target: Vector3, seconds: float) -> void:
	_look_target = target
	_look_timer = seconds


func _random_offset(reach: float) -> Vector3:
	var angle: float = _rng.randf_range(0.0, TAU)
	var distance: float = sqrt(_rng.randf()) * reach
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Percepção e fala ---------------------------------------------------------


## Alguém entrou no raio de percepção.
##
## Reagir é olhar e, às vezes, falar. Não há perseguição, nem caminho recalculado, nem
## estado guardado sobre quem passou: o custo de uma reação é um `look_at` e um texto.
func _on_sensed(body: Node3D) -> void:
	if body == self or _state == State.SLEEP:
		return
	_look_at_for(body.global_position + Vector3.UP * _eye_height(), Params.NPC_LOOK_SECONDS)

	if _speak_cooldown > 0.0 or _rng.randf() > Params.NPC_SPEAK_CHANCE:
		return
	_speak(_pick_line())
	if _state == State.WORK or _state == State.SOCIALIZE or _state == State.IDLE:
		_react_timer = Params.NPC_REACT_SECONDS
		_task_state = _state
		_enter(State.REACT)


func _pick_line() -> String:
	var lines: Array = Params.NPC_LINES.get(archetype, [])
	if lines.is_empty():
		return ""
	return String(lines[_rng.randi_range(0, lines.size() - 1)])


func _speak(text: String) -> void:
	if text.is_empty():
		return
	_speech.text = text
	_speech.visible = true
	_speak_cooldown = Params.NPC_SPEAK_COOLDOWN
	get_tree().create_timer(Params.NPC_SPEAK_SECONDS).timeout.connect(_hush)


func _hush() -> void:
	if is_instance_valid(_speech):
		_speech.visible = false


func _eye_height() -> float:
	var height: float = _locomotion.character_height()
	return height if height > 0.0 else Params.NAV_AGENT_HEIGHT


# --- Simulação barata ---------------------------------------------------------


## Liga ou desliga a simulação cara deste NPC.
##
## Desligado, ele perde física, navegação e malha, e passa a avançar sobre a **rota que já
## tinha** — interpolação pura, sem custo de caminho. É por isso que a rota é congelada
## aqui e não recalculada: recalcular caminho para quem está a 80 m e invisível é
## exatamente o gasto que o teto de ativos existe para evitar.
func set_simulated(active: bool) -> void:
	if _active == active:
		return
	_active = active
	set_physics_process(active)

	if active:
		# Voltar ao mundo caro exige voltar ao chão navegável: o avanço abstrato anda sobre
		# a rota, mas a rota é uma polilinha e o terreno tem relevo.
		global_position = NavigationServer3D.map_get_closest_point(
			_agent.get_navigation_map(), global_position
		)
		visible = _state != State.SLEEP
		_abstract_path = PackedVector3Array()
		_repath_timer = 0.0
		if _bus != null:
			_bus.npc_activated.emit(self)
		return

	visible = false
	velocity = Vector3.ZERO
	_locomotion.clear_drive_velocity()
	_abstract_path = NavigationServer3D.map_get_path(
		_agent.get_navigation_map(), global_position, _goal, true
	)
	_abstract_index = 0
	if _bus != null:
		_bus.npc_deactivated.emit(self)


## Um passo da simulação barata. Chamado pelo diretor, não pelo motor.
func advance_abstract(delta: float) -> void:
	if _state == State.SLEEP or _abstract_path.size() <= 1:
		return
	var budget: float = Params.NPC_ABSTRACT_SPEED * delta
	while budget > 0.0 and _abstract_index < _abstract_path.size() - 1:
		var target: Vector3 = _abstract_path[_abstract_index + 1]
		var gap: float = global_position.distance_to(target)
		if gap <= budget:
			global_position = target
			budget -= gap
			_abstract_index += 1
			continue
		global_position += (target - global_position).normalized() * budget
		budget = 0.0
