## Três minutos de praça, medidos. Prova que a cidade tem vida e que ninguém quebra nada.
##
##     godot --headless --script res://tools/population.gd
##
## **Sem renderizador de propósito.** Os três critérios da fase são de movimento, não de
## pixel: gente andando, ninguém entalado, ninguém dentro de parede. Medir isso com
## renderizador custaria trinta minutos de llvmpipe para responder a uma pergunta que a
## física responde sozinha. O critério de desenho — 60 FPS com vinte NPCs à vista — é do
## `make bench`, que já tem contador de draw call e a cidade inteira em cena.
##
## O tempo é acelerado pelo relógio do jogo, não por um `Engine.time_scale`: um dia do
## mundo dura `SECONDS_PER_GAME_DAY`, então três minutos de praça atravessam várias
## viradas de hora e várias trocas de bloco de agenda. É isso que se quer provar — que a
## rotina muda sozinha —, e não que vinte corpos conseguem ficar de pé por três minutos.
##
## Três medidas, uma por critério:
##
## - **Movimento contínuo e não repetitivo**: em cada janela de `POPULATION_WINDOW`
##   segundos, que fração dos habitantes de fato saiu do lugar; e quanto do percurso de
##   cada um cai em terreno onde ele ainda não esteve. Movimento contínuo sem novidade é um
##   NPC andando de um lado para o outro na mesma linha: passa no primeiro teste e reprova
##   no olho.
## - **Sem entalo**: cada NPC conta as próprias vezes em que precisou ser destravado.
## - **Sem atravessar parede**: a posição de cada NPC é testada contra as caixas de colisão
##   dos prédios. É a única checagem que precisa da cidade e não da população.
extends SceneTree

const RESULT_PREFIX: String = "MEDIEV_POPULATION "
## Teto de espera pelo assado da navegação, em quadros de física.
const BAKE_TIMEOUT_FRAMES: int = 2400
## Quadros de assentamento antes de começar a medir: os NPCs precisam de caminho.
const SETTLE_FRAMES: int = 90
const HALF: float = 0.5
## Folga na checagem de parede. A cápsula tem raio, e um habitante encostado numa fachada
## tem o centro a menos de meio metro dela sem estar dentro de nada.
const CLIP_MARGIN: float = 0.35

var _stage: Node3D = null
var _npcs: Array[NPCController] = []
var _director: NPCDirector = null
var _boxes: Array[Dictionary] = []

## Rastro de cada NPC: uma posição por amostra.
var _tracks: Array[PackedVector3Array] = []
var _clip_events: int = 0
var _state_seen: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	WorldGenerator.build_stage(_stage, false)

	var layout: CityLayout = WorldGenerator.last_city
	var report: Dictionary = WorldGenerator.last_report.duplicate()
	await _wait_for_bake(_find_region(_stage))
	_collect()
	_collect_boxes()

	# O diretor mira a praça: é de lá que o critério fala, e sem jogador ele não teria
	# observador nenhum.
	if _director != null and layout != null:
		var eye: Node3D = Node3D.new()
		eye.name = "PlazaEye"
		_stage.add_child(eye)
		eye.global_position = layout.markers[&"praca"]
		_director.observer = eye

	for _frame: int in SETTLE_FRAMES:
		await physics_frame

	var measured: Dictionary = await _watch()

	print(RESULT_PREFIX + JSON.stringify({
		"npcs": _npcs.size(),
		"expected": Params.NPC_COUNT,
		"archetypes": report.get("npc_archetypes", {}),
		"active_ceiling": int(report.get("npc_active_ceiling", 0)),
		"active_peak": int(measured["active_peak"]),
		"seconds": Params.POPULATION_SECONDS,
		"windows": measured["windows"],
		"worst_window_movers": measured["worst_movers"],
		"min_movers": Params.POPULATION_MIN_MOVERS,
		"novelty": measured["novelty"],
		"min_novelty": Params.POPULATION_MIN_NOVELTY,
		"stuck": measured["stuck"],
		"max_stuck": Params.POPULATION_MAX_STUCK,
		"clipping": _clip_events,
		"max_clipping": Params.POPULATION_MAX_CLIPPING,
		"states_seen": _state_seen.keys(),
		"smoke": int(report.get("ambient_smoke", 0)),
		"birds": int(report.get("ambient_birds", 0)),
		"leaves": int(report.get("ambient_leaves", 0)),
	}))
	quit(0)


# --- Coleta -------------------------------------------------------------------


func _collect() -> void:
	_walk(_stage)
	_tracks.resize(_npcs.size())
	for index: int in _npcs.size():
		_tracks[index] = PackedVector3Array()


func _walk(node: Node) -> void:
	if node is NPCController:
		_npcs.append(node as NPCController)
	elif node is NPCDirector:
		_director = node as NPCDirector
	for child: Node in node.get_children():
		_walk(child)


## Caixas de colisão dos prédios, em espaço de mundo, para a checagem de parede.
##
## Lidas da cena e não do traçado: o que interessa é onde a colisão de fato está, e um erro
## entre o traçado e a construção é exatamente o que esta checagem deveria pegar.
func _collect_boxes() -> void:
	var city: Node = _stage.find_child("City", true, false)
	if city == null:
		return
	for child: Node in city.get_children():
		if not child is StaticBody3D:
			continue
		# A muralha fica de fora: o portão é um vão na peça, não na caixa, e um habitante
		# atravessando o portão contaria como atravessando a muralha.
		if child.name == "WallCollision":
			continue
		for shape_node: Node in child.get_children():
			if not shape_node is CollisionShape3D:
				continue
			var collider: CollisionShape3D = shape_node as CollisionShape3D
			if not collider.shape is BoxShape3D:
				continue
			_boxes.append({
				"inverse": collider.global_transform.affine_inverse(),
				"half": (collider.shape as BoxShape3D).size * HALF,
			})


func _find_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node as NavigationRegion3D
	for child: Node in node.get_children():
		var found: NavigationRegion3D = _find_region(child)
		if found != null:
			return found
	return null


func _wait_for_bake(region: NavigationRegion3D) -> void:
	if region == null:
		return
	var waited: int = 0
	while region.is_baking() and waited < BAKE_TIMEOUT_FRAMES:
		await physics_frame
		waited += 1
	await physics_frame
	await physics_frame


# --- Medição ------------------------------------------------------------------


func _watch() -> Dictionary:
	var sample_period: float = 1.0 / maxf(Params.POPULATION_SAMPLE_HZ, MIN_RATE)
	var samples: int = int(round(Params.POPULATION_SECONDS / sample_period))
	var per_window: int = maxi(int(round(Params.POPULATION_WINDOW / sample_period)), 1)
	var active_peak: int = 0

	for _sample: int in samples:
		var waited: float = 0.0
		while waited < sample_period:
			waited += await _step()
		_record()
		if _director != null:
			active_peak = maxi(active_peak, _director.active_count())

	return {
		"active_peak": active_peak,
		"windows": int(floor(float(samples) / float(per_window))),
		"worst_movers": _worst_window(per_window),
		"novelty": _novelty(),
		"stuck": _stuck_total(),
	}


const MIN_RATE: float = 0.01


func _step() -> float:
	await physics_frame
	return 1.0 / float(Params.PHYSICS_TICKS_PER_SECOND)


func _record() -> void:
	for index: int in _npcs.size():
		var npc: NPCController = _npcs[index]
		if not is_instance_valid(npc):
			continue
		_tracks[index].append(npc.global_position)
		_state_seen[_state_name(npc.state())] = true
		if _inside_wall(npc.global_position):
			_clip_events += 1


static func _state_name(state: int) -> String:
	return NPCController.State.keys()[state]


## O centro do habitante está dentro de alguma caixa de prédio?
##
## Testado no espaço local da caixa, e não por AABB de mundo: os prédios são girados pela
## malha da cidade, e um AABB de mundo de um prédio a 40° declararia parede onde há rua.
func _inside_wall(spot: Vector3) -> bool:
	for box: Dictionary in _boxes:
		var local: Vector3 = Transform3D(box["inverse"]) * spot
		var half: Vector3 = box["half"]
		if (
			absf(local.x) < half.x - CLIP_MARGIN
			and absf(local.z) < half.z - CLIP_MARGIN
			and absf(local.y) < half.y
		):
			return true
	return false


## Pior janela: a fração mínima de habitantes que se moveu em alguma janela da prova.
##
## Mínima, e não média: uma cidade que para por vinte segundos e depois compensa daria uma
## média aceitável, e o critério fala de movimento **contínuo**.
func _worst_window(per_window: int) -> float:
	var worst: float = 1.0
	var total: int = _npcs.size()
	if total == 0 or _tracks.is_empty():
		return 0.0

	var samples: int = _tracks[0].size()
	var start: int = 0
	while start + per_window < samples:
		var movers: int = 0
		for track: PackedVector3Array in _tracks:
			if track[start].distance_to(track[start + per_window]) > Params.NPC_STUCK_PROGRESS:
				movers += 1
		worst = minf(worst, float(movers) / float(total))
		start += per_window
	return worst


## Novidade do percurso: fração das amostras que caíram num lugar onde aquele habitante
## ainda não tinha estado.
##
## A primeira versão media **dispersão** — distância média ao centro do próprio rastro — e
## media a coisa errada. Dispersão é migração: ela pune um comerciante que passa a manhã
## inteira na banca dele, que é exatamente o que um comerciante deve fazer, e não distingue
## isso de vinte NPCs andando de um lado para o outro numa linha de três metros. Os dois
## dão dispersão baixa; só um deles é o defeito de que o critério fala.
##
## Novidade separa os dois. Quem anda para a frente pisa em célula nova o tempo todo; quem
## repete o mesmo trecho satura depois das primeiras voltas e para de gerar novidade,
## mesmo sem nunca parar de se mexer.
func _novelty() -> float:
	if _tracks.is_empty():
		return 0.0
	var cell: float = maxf(Params.GRID_SIZE, MIN_RATE)
	var fresh: int = 0
	var total: int = 0
	for track: PackedVector3Array in _tracks:
		var seen: Dictionary = {}
		for spot: Vector3 in track:
			var key: Vector2i = Vector2i(int(floor(spot.x / cell)), int(floor(spot.z / cell)))
			if not seen.has(key):
				seen[key] = true
				fresh += 1
			total += 1
	return float(fresh) / float(maxi(total, 1))


func _stuck_total() -> int:
	var total: int = 0
	for npc: NPCController in _npcs:
		if is_instance_valid(npc):
			total += npc.stuck_events()
	return total
