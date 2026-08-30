## A conversa, medida. Prova os dois critérios de aceite da fase em número.
##
##     godot --headless --script res://tools/dialogue.gd
##
## **Sem renderizador de propósito**, pelo mesmo motivo de `population.gd`: os dois
## critérios são de estado, não de pixel. O que a conversa tem de visual — o painel, o
## fade, o ombro da câmera — é do `make preview`, que enxerga; aqui se mede o que uma
## captura de tela não responderia.
##
## Critério 1 — **"falar com um NPC e sair não quebra a rotina dele"**. Não basta ele
## voltar a andar: tem de voltar ao *mesmo* estado, com o *mesmo* destino, e de fato sair
## do lugar depois. A prova grava os três antes de abrir a conversa, segura o habitante
## parado enquanto se fala com ele — parado é medido, não suposto —, e compara na saída.
##
## Critério 2 — **"adicionar conversa nova não exige tocar em código"**. A prova abre
## `guarda_portao`, que é a árvore que *nenhum* caminho de código referencia:
## `DIALOGUE_BY_ARCHETYPE` não a menciona, nenhum `.tscn` a aponta, nenhum `match` a
## conhece. Ela existe como `.tres` e é carregada pelo nome. Se um registro tivesse
## aparecido em algum lugar do projeto, esta árvore seria a que ficaria mudo.
##
## De quebra a prova percorre a máquina de condições inteira, na ordem em que uma partida
## a percorreria: uma escolha trancada por flag abre depois que outra conversa acende a
## flag, e uma escolha trancada por reputação abre depois que a escolha do ferreiro paga
## os pontos. É a diferença entre "a condição avalia" e "a condição avalia contra o estado
## que o jogo de fato acumulou".
extends SceneTree

const RESULT_PREFIX: String = "MEDIEV_DIALOGUE "
## Teto de espera pelo assado da navegação, em quadros de física.
const BAKE_TIMEOUT_FRAMES: int = 2400
## Quadros de assentamento antes de medir: os habitantes precisam de caminho.
const SETTLE_FRAMES: int = 90

## A árvore que nenhum código referencia. É o critério 2 em forma de arquivo.
const UNREFERENCED_TREE: StringName = &"guarda_portao"
## A árvore cuja escolha acende uma flag, e a que cobra reputação.
const FLAG_TREE: StringName = &"aldeao_saudacao"
const REPUTATION_TREE: StringName = &"ferreiro_encomenda"
const FLAG_KEY: StringName = &"ouviu_do_silencio"
const REPUTATION_FACTION: StringName = &"vilarejo"

## Texto qualquer, só para a síntese ter comprimento. O conteúdo não importa: a voz lê o
## comprimento, não as letras.
const VOICE_LINE: String = "Uma linha de prova, comprida o bastante para render sílabas."
const VOICE_ID_A: StringName = &"habitante_um"
const VOICE_ID_B: StringName = &"habitante_dois"
const VOICE_POSTURE: StringName = &"ereto"
const BYTES_PER_SAMPLE: int = 2

var _stage: Node3D = null
var _npcs: Array[NPCController] = []
var _director: NPCDirector = null
var _runner: DialogueRunner = null
var _prompt: ContextPrompt = null
var _bus: Node = null
var _state: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_bus = root.get_node_or_null(^"/root/EventBus")
	_state = root.get_node_or_null(^"/root/GameState")

	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	# O estágio é o nó que `build_stage` devolve, e não o que se passa a ele: o runner e o
	# prompt nascem lá dentro, e procurá-los no invólucro devolveria nulo.
	_stage = WorldGenerator.build_stage(holder, false)

	var layout: CityLayout = WorldGenerator.last_city
	await _wait_for_bake(_find_region(_stage))
	_collect()
	_watch_from_plaza(layout)

	for _frame: int in SETTLE_FRAMES:
		await physics_frame

	var npc: NPCController = _pick()
	if npc == null:
		print(RESULT_PREFIX + JSON.stringify({"npcs": _npcs.size(), "chosen": ""}))
		quit(0)
		return

	var partner: Interactable = npc.get_node_or_null(^"Talk") as Interactable
	var routine: Dictionary = await _routine_survives(npc, partner)
	var conditions: Dictionary = await _conditions_walk(partner)

	print(RESULT_PREFIX + JSON.stringify({
		"npcs": _npcs.size(),
		"chosen": npc.name,
		"trees": _catalog(),
		"unreferenced_tree": String(UNREFERENCED_TREE),
		"routine": routine,
		"conditions": conditions,
		"voice": _voice_report(),
		"tolerance": Params.DIALOGUE_PROOF_TOLERANCE,
		"window_seconds": Params.DIALOGUE_PROOF_SECONDS,
		"stuck": npc.stuck_events(),
	}))
	quit(0)


# --- Critério 1: a rotina sobrevive ------------------------------------------


## Abre a conversa como o jogo abre — tecla, sinal, runner — e mede o que sobra depois.
##
## A conversa é aberta por `Interactable.interact()`, e não chamando o runner: o caminho da
## tecla passa pelo `EventBus`, pelo carregamento por nome e pelo prompt que se cala. Testar
## o runner direto pularia justamente os três lugares onde um erro de fiação moraria.
func _routine_survives(npc: NPCController, partner: Interactable) -> Dictionary:
	# A árvore que ninguém referencia entra aqui: se o carregamento por nome não funcionasse,
	# o critério 1 morreria junto, e é bom que os dois falhem no mesmo lugar.
	partner.dialogue = DialogueRunner.load_tree(UNREFERENCED_TREE)
	_prompt.watch()

	var before_spot: Vector3 = npc.global_position
	await _advance(Params.DIALOGUE_PROOF_SECONDS)
	var moved_before: float = npc.global_position.distance_to(before_spot)

	var state_before: int = npc.state()
	var goal_before: Vector3 = npc.goal()

	_bus.interactable_focused.emit(partner)
	var prompt_before: bool = _prompt.is_showing()

	partner.interact(npc)
	var opened: bool = _runner.is_talking()
	# O prompt tem de calar durante a conversa: a tecla que o abriria abriria a mesma
	# conversa por cima dela mesma. O foco é reemitido para a mudez ser medida e não suposta.
	_bus.interactable_focused.emit(partner)
	var prompt_during: bool = _prompt.is_showing()
	# `paused` sozinho sombrearia a propriedade do `SceneTree`, que é o que este script
	# estende.
	var routine_paused: bool = npc.is_paused()

	var pause_spot: Vector3 = npc.global_position
	await _advance(Params.DIALOGUE_PROOF_SECONDS)
	var moved_during: float = npc.global_position.distance_to(pause_spot)

	_runner.finish()
	var state_after: int = npc.state()
	var goal_after: Vector3 = npc.goal()

	var resume_spot: Vector3 = npc.global_position
	await _advance(Params.DIALOGUE_PROOF_SECONDS)
	var moved_after: float = npc.global_position.distance_to(resume_spot)

	return {
		"opened": opened,
		"tree": String(partner.dialogue.id),
		"paused": routine_paused,
		"prompt_before": prompt_before,
		"prompt_during": prompt_during,
		"prompt_after": _prompt_awake(partner),
		"state_before": _state_name(state_before),
		"state_after": _state_name(state_after),
		"goal_shift": goal_before.distance_to(goal_after),
		"moved_before": moved_before,
		"moved_during": moved_during,
		"moved_after": moved_after,
		"min_move": Params.NPC_STUCK_PROGRESS,
	}


## O prompt voltou a poder aparecer depois da conversa?
##
## Perguntado emitindo o foco de novo, e não lendo uma variável: o que interessa é o
## comportamento — se a mudez da conversa vazou para depois dela, é aqui que aparece, e o
## jogador nunca mais veria um prompt na vida daquela partida.
func _prompt_awake(partner: Interactable) -> bool:
	_bus.interactable_focused.emit(partner)
	return _prompt.is_showing()


# --- Critério 2: condição, efeito e árvore sem código ------------------------


## Percorre as condições na ordem de uma partida: flag apagada, flag acesa, reputação paga.
func _conditions_walk(partner: Interactable) -> Dictionary:
	var context: Dictionary = _state.dialogue_context()
	var locked_tree: DialogueTree = DialogueRunner.load_tree(UNREFERENCED_TREE)
	var guard_locked: int = _visible_count(locked_tree, context)

	var smith_tree: DialogueTree = DialogueRunner.load_tree(REPUTATION_TREE)
	var smith_locked: int = _visible_count(smith_tree, _state.dialogue_context())

	# 1) A conversa do aldeão acende a flag, por efeito de nó.
	var villager_tree: DialogueTree = DialogueRunner.load_tree(FLAG_TREE)
	partner.dialogue = villager_tree
	partner.interact(null)
	_runner.choose(_choice_into_flag(villager_tree, _state.dialogue_context()))
	var flag_set: bool = bool(_state.get_flag(FLAG_KEY, false))
	_runner.finish()
	await _advance(Params.DIALOGUE_PROOF_SECONDS * SHORT_FRACTION)

	var smith_unlocked: int = _visible_count(smith_tree, _state.dialogue_context())

	# 2) A escolha do ferreiro paga a reputação, por efeito de escolha.
	var reputation_before: int = _state.reputation(REPUTATION_FACTION)
	partner.dialogue = smith_tree
	partner.interact(null)
	var paying: int = _paying_choice(smith_tree, _state.dialogue_context())
	_runner.choose(paying)
	var reputation_after: int = _state.reputation(REPUTATION_FACTION)
	_runner.finish()
	await _advance(Params.DIALOGUE_PROOF_SECONDS * SHORT_FRACTION)

	# 3) E a fala do guarda que a reputação destranca abre sozinha.
	var guard_unlocked: int = _visible_count(locked_tree, _state.dialogue_context())

	return {
		"guard_locked": guard_locked,
		"guard_unlocked": guard_unlocked,
		"smith_locked": smith_locked,
		"smith_unlocked": smith_unlocked,
		"flag_key": String(FLAG_KEY),
		"flag_set": flag_set,
		"faction": String(REPUTATION_FACTION),
		"reputation_before": reputation_before,
		"reputation_after": reputation_after,
		"cap": Params.DIALOGUE_MAX_CHOICES,
		"talking_after": _runner.is_talking(),
	}


## Fração da janela usada nas pausas entre conversas: só o suficiente para a tela fechar.
const SHORT_FRACTION: float = 0.5


## Quantas escolhas do nó inicial passam pelas condições, com este contexto.
func _visible_count(tree: DialogueTree, context: Dictionary) -> int:
	if tree == null:
		return -1
	return tree.choices_for(tree.opening(context), context).size()


## Índice da escolha que paga reputação, procurado e não decorado: um número fixo aqui
## viraria mentira na primeira vez que alguém reordenasse as falas em `params.py`.
func _paying_choice(tree: DialogueTree, context: Dictionary) -> int:
	var choices: Array[Dictionary] = tree.choices_for(tree.opening(context), context)
	for index: int in choices.size():
		if _has_effect(choices[index], DialogueTree.TYPE_REPUTATION):
			return index
	return -1


## Índice da escolha que leva a um nó com efeito de flag. Mesma ideia: a prova procura o
## caminho pelo que ele faz, não pela posição em que está escrito.
func _choice_into_flag(tree: DialogueTree, context: Dictionary) -> int:
	var choices: Array[Dictionary] = tree.choices_for(tree.opening(context), context)
	for index: int in choices.size():
		var goto: StringName = StringName(choices[index].get("goto", &""))
		if goto != &"" and _has_effect(tree.node(goto), DialogueTree.TYPE_FLAG):
			return index
	return -1


static func _has_effect(entry: Dictionary, kind: StringName) -> bool:
	for effect: Dictionary in DialogueTree.effects_of(entry):
		if StringName(effect["type"]) == kind:
			return true
	return false


## Cada árvore gerada, carregada pelo nome, com o tamanho que tem.
func _catalog() -> Array:
	var out: Array = []
	for id: String in Params.DIALOGUE_IDS:
		var tree: DialogueTree = DialogueRunner.load_tree(StringName(id))
		out.append({
			"id": id,
			"loaded": tree != null,
			"nodes": 0 if tree == null else tree.nodes.size(),
			"speaker": "" if tree == null else tree.speaker,
		})
	return out


# --- Voz ----------------------------------------------------------------------


## A voz em três números: estável para o mesmo habitante, diferente entre habitantes, e com
## amostra de verdade dentro.
##
## Estabilidade é o critério escrito ("pitch randomizado por NPC de forma estável, derivado
## do id"), e é o único dos três que um ouvido não pegaria: um pitch que sorteia por fala
## soa aleatório, não soa errado.
func _voice_report() -> Dictionary:
	var first: float = ProceduralVoice.pitch_for(VOICE_ID_A, VOICE_POSTURE)
	var again: float = ProceduralVoice.pitch_for(VOICE_ID_A, VOICE_POSTURE)
	var other: float = ProceduralVoice.pitch_for(VOICE_ID_B, VOICE_POSTURE)
	var stream: AudioStreamWAV = ProceduralVoice.line_for(VOICE_LINE, VOICE_ID_A, VOICE_POSTURE)
	# Divisão inteira de propósito: a amostra é s16, dois bytes, e o que se quer é a
	# contagem de amostras.
	@warning_ignore("integer_division")
	var frames: int = 0 if stream == null else stream.data.size() / BYTES_PER_SAMPLE
	return {
		"pitch": first,
		"stable": is_equal_approx(first, again),
		"distinct": not is_equal_approx(first, other),
		"frames": frames,
		"rate": Params.VOICE_SAMPLE_RATE,
		"profiles": Params.VOICE_PROFILES.size(),
	}


# --- Coleta e passagem do tempo ----------------------------------------------


func _collect() -> void:
	_walk(_stage)
	_runner = _stage.get_node_or_null(NodePath(WorldGenerator.DIALOGUE_NODE_NAME)) as DialogueRunner
	_prompt = _stage.get_node_or_null(NodePath(WorldGenerator.PROMPT_NODE_NAME)) as ContextPrompt


func _walk(node: Node) -> void:
	if node is NPCController:
		_npcs.append(node as NPCController)
	elif node is NPCDirector:
		_director = node as NPCDirector
	for child: Node in node.get_children():
		_walk(child)


## O diretor precisa de um observador; sem jogador, a praça faz esse papel — é de onde o
## critério da fase 10 já olhava.
func _watch_from_plaza(layout: CityLayout) -> void:
	if _director == null or layout == null:
		return
	var eye: Node3D = Node3D.new()
	eye.name = "PlazaEye"
	_stage.add_child(eye)
	eye.global_position = layout.markers[&"praca"]
	_director.observer = eye


## Com quem conversar: alguém a caminho de algum lugar, e perto da praça.
##
## A caminho porque uma rotina que sobrevive à conversa só se prova em quem tinha rotina em
## curso: pausar quem está parado e devolvê-lo parado não prova nada. Perto da praça porque
## é lá que está o observador — um habitante longe cai na simulação barata no meio da
## conversa, e aí quem o move é o diretor, não a rotina.
func _pick() -> NPCController:
	var eye: Vector3 = Vector3.ZERO
	if _director != null and _director.observer != null:
		eye = _director.observer.global_position
	var best: NPCController = null
	var best_gap: float = INF
	for npc: NPCController in _npcs:
		if not is_instance_valid(npc) or not npc.is_active():
			continue
		if npc.state() != NPCController.State.WALK_TO:
			continue
		var gap: float = npc.global_position.distance_to(eye)
		if gap < best_gap:
			best_gap = gap
			best = npc
	return best


func _advance(seconds: float) -> void:
	var step: float = 1.0 / float(Params.PHYSICS_TICKS_PER_SECOND)
	var waited: float = 0.0
	while waited < seconds:
		await physics_frame
		waited += step


static func _state_name(state: int) -> String:
	return NPCController.State.keys()[state]


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
