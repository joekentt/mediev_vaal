@tool
## Povoa a cidade: combina corpo, arquétipo, rotina e seed de variação.
##
## O que esta etapa realmente faz é **resolver nomes**. A fase 8 entregou `Marker3D`
## chamados `praca`, `poco`, `taverna`, `portao`, `mercado_01..05` e `casa_01..15`; as
## agendas da fase 10 falam em `casa`, `trabalho`, `praca`. Aqui os dois se encontram: cada
## habitante recebe uma tabela de lugares em que `casa` já é a casa dele e `trabalho` já é
## o posto dele, e a agenda passa a funcionar sem saber onde a cidade caiu desta vez.
##
## A coerência entre casa e trabalho não é decoração: um comerciante mora numa casa e
## trabalha numa banca; um artesão mora numa casa e trabalha na ferraria. Sortear os dois
## independentemente daria a metade da cidade caminhadas de 100 m atravessando a praça oito
## vezes por dia — movimento que parece vida por dez segundos e ruído depois disso.
##
## Determinismo: a mesma seed dá a mesma população. A semente de cada habitante é derivada
## do índice dele, então acrescentar um vigésimo primeiro NPC não muda os vinte primeiros.
class_name PopulationGenerator
extends RefCounted

const POPULATION_ROOT_NAME: StringName = &"Population"
const DIRECTOR_NAME: StringName = &"Director"
const HALF: float = 0.5
## Passo entre sementes de habitantes. Primo, para dois NPCs vizinhos não compartilharem
## sequência de sorteio.
const SEED_STRIDE: int = 7919
## Arquétipo que comanda o martelo da ferraria.
const SMITH_ARCHETYPE: StringName = &"artesao"


## Cria a população sob `parent`. Devolve estatística para o relatório e para a prova.
static func populate(
	layout: CityLayout,
	parent: Node3D,
	world_seed: int,
	observer: Node3D = null,
	ambient: AmbientLife = null
) -> Dictionary:
	if layout == null or layout.markers.is_empty():
		return _empty_report()

	var packed: PackedScene = ResourceLoader.load(Params.NPC_SCENE) as PackedScene
	if packed == null:
		push_warning("Cena de NPC ausente (%s). Rode `make npc`." % Params.NPC_SCENE)
		return _empty_report()

	var root: Node3D = Node3D.new()
	root.name = POPULATION_ROOT_NAME
	parent.add_child(root)

	var director: NPCDirector = NPCDirector.new()
	director.name = String(DIRECTOR_NAME)
	director.observer = observer
	root.add_child(director)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + Params.NPC_SEED_OFFSET

	var homes: Array[StringName] = _markers_named(layout, &"casa_")
	var stalls: Array[StringName] = _markers_named(layout, &"mercado_")
	var schedules: Dictionary = _load_schedules()
	var roster: Dictionary = _bodies_by_name()

	var counts: Dictionary = {}
	var spawned: int = 0
	for index: int in Params.NPC_COUNT:
		var spec: Dictionary = _pick_archetype(rng)
		var npc: NPCController = packed.instantiate() as NPCController
		if npc == null:
			continue

		var name_key: StringName = spec["name"]
		npc.name = "NPC_%02d_%s" % [index + 1, name_key]
		npc.archetype = name_key
		npc.variation_seed = world_seed + Params.NPC_SEED_OFFSET + index * SEED_STRIDE
		npc.schedule = schedules.get(spec["schedule"], null)
		npc.places = _places_for(layout, spec, homes, stalls, index)

		# A conversa vem do arquétipo, por nome, e o runner carrega pelo nome. É isto que
		# faz "acrescentar conversa não exige tocar em código" ser verdade: um `.tres` novo
		# e uma linha em DIALOGUE_BY_ARCHETYPE bastam.
		var talk: Interactable = npc.get_node_or_null(^"Talk") as Interactable
		if talk != null and Params.DIALOGUE_BY_ARCHETYPE.has(name_key):
			talk.dialogue = DialogueRunner.load_tree(Params.DIALOGUE_BY_ARCHETYPE[name_key])

		var body: StringName = _pick_body(spec, roster, rng)
		var race: RaceApplier = npc.get_node(npc.race_path) as RaceApplier
		if race != null:
			race.body = body

		# Nasce na porta de casa: é onde a agenda vai mandá-lo dormir de qualquer forma, e
		# um habitante que nasce no meio da praça às 3 da manhã entrega o truque.
		npc.position = Vector3(npc.places[NPCController.MARKER_HOME])
		root.add_child(npc)
		director.enroll(npc)

		# O martelo da ferraria bate no compasso de quem está de pé na frente dela. O
		# primeiro artesão criado é quem o comanda — sincronizar com "algum" artesão daria
		# bigorna batendo enquanto o ferreiro almoça na taverna.
		if ambient != null and name_key == SMITH_ARCHETYPE and not counts.has(name_key):
			ambient.bind_smith(npc)

		counts[name_key] = int(counts.get(name_key, 0)) + 1
		spawned += 1

	return {
		"npcs": spawned,
		"archetypes": counts,
		"homes": homes.size(),
		"stalls": stalls.size(),
		"active_ceiling": Params.budget(&"active_npcs"),
	}


static func _empty_report() -> Dictionary:
	return {"npcs": 0, "archetypes": {}, "homes": 0, "stalls": 0, "active_ceiling": 0}


## Tabela de lugares deste habitante: a cidade inteira, mais `casa` e `trabalho` resolvidos.
static func _places_for(
	layout: CityLayout,
	spec: Dictionary,
	homes: Array[StringName],
	stalls: Array[StringName],
	index: int
) -> Dictionary:
	var places: Dictionary = layout.markers.duplicate()

	# Casa por rodízio, e não por sorteio: com quinze casas e vinte habitantes, sortear
	# deixaria casas vazias e outras com quatro moradores. O rodízio distribui parelho.
	if not homes.is_empty():
		places[NPCController.MARKER_HOME] = layout.markers[homes[index % homes.size()]]
	else:
		places[NPCController.MARKER_HOME] = layout.markers[&"praca"]

	var work: StringName = spec["work"]
	if work == &"mercado" and not stalls.is_empty():
		places[NPCController.MARKER_WORK] = layout.markers[stalls[index % stalls.size()]]
	elif layout.markers.has(work):
		places[NPCController.MARKER_WORK] = layout.markers[work]
	else:
		places[NPCController.MARKER_WORK] = places[NPCController.MARKER_HOME]
	return places


## Marcadores cujo nome começa com um prefixo, em ordem estável.
static func _markers_named(layout: CityLayout, prefix: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	var names: Array = layout.markers.keys()
	names.sort()
	for key: StringName in names:
		if String(key).begins_with(String(prefix)):
			found.append(key)
	return found


static func _pick_archetype(rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for spec: Dictionary in Params.NPC_ARCHETYPES:
		total += float(spec["share"])
	var roll: float = rng.randf() * total
	for spec: Dictionary in Params.NPC_ARCHETYPES:
		roll -= float(spec["share"])
		if roll <= 0.0:
			return spec
	return Params.NPC_ARCHETYPES[0]


## Corpo do habitante, entre os que o arquétipo aceita e que o elenco de fato produziu.
static func _pick_body(
	spec: Dictionary, roster: Dictionary, rng: RandomNumberGenerator
) -> StringName:
	var allowed: Array = spec["bodies"]
	var usable: Array[StringName] = []
	for body: Variant in allowed:
		if roster.has(body):
			usable.append(StringName(body))
	if usable.is_empty():
		push_warning(
			"Arquétipo %s: nenhum dos corpos %s existe no elenco. Rode `make characters`."
			% [spec["name"], str(allowed)]
		)
		return Params.PLAYER_BODY
	return usable[rng.randi_range(0, usable.size() - 1)]


static func _bodies_by_name() -> Dictionary:
	var names: Dictionary = {}
	for entry: StringName in Params.CHARACTER_BODIES:
		names[entry] = true
	return names


static func _load_schedules() -> Dictionary:
	var loaded: Dictionary = {}
	for spec: Dictionary in Params.NPC_ARCHETYPES:
		var key: StringName = spec["schedule"]
		if loaded.has(key):
			continue
		var path: String = "%s/%s.tres" % [Params.NPC_DIR, key]
		var resource: NPCSchedule = ResourceLoader.load(path) as NPCSchedule
		if resource == null:
			push_warning("Agenda ausente: %s. Rode `make schedules`." % path)
			continue
		loaded[key] = resource
	return loaded
