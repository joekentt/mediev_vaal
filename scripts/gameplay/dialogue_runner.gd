## Conduz uma conversa: carrega a árvore, pausa o NPC, enquadra a câmera, aplica efeitos.
##
## Este é o único arquivo do projeto que conhece todas as peças da fase ao mesmo tempo, e é
## de propósito que ele seja o único: a `DialogueTree` não conhece o `GameState`, a tela
## não conhece condição, o `Interactable` não conhece o runner e o NPC não conhece diálogo
## nenhum. Cada um faz uma coisa e este arquivo as costura.
##
## **A rotina do NPC é devolvida exatamente onde parou.** Não é "ele volta a andar": é o
## mesmo estado, o mesmo destino e o mesmo posto que ele tinha no instante em que a
## conversa começou. `NPCController.pause_routine()` guarda os três e
## `resume_routine()` os devolve — nada é recalculado, porque recalcular a agenda na saída
## faria um habitante que estava a meio caminho da taverna recomeçar da casa dele.
##
## Carregar a árvore **pelo nome** é o que faz o critério "acrescentar conversa não exige
## tocar em código" ser verdade: o runner monta `DIALOGUE_DIR/<id>.tres` e carrega. Não há
## registro, não há `match`, não há lista para atualizar.
class_name DialogueRunner
extends Node

const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"
const GAME_STATE_PATH: NodePath = ^"/root/GameState"
## Ações de escolha, de 1 a `DIALOGUE_MAX_CHOICES`. Nascem do input map gerado.
const CHOICE_ACTION_PREFIX: String = "dialogue_choice_"
const ACTION_ADVANCE: StringName = &"interact"
const ACTION_LEAVE: StringName = &"pause"

var _screen: DialogueScreen = null
var _bus: Node = null
var _state: Node = null

var _tree: DialogueTree = null
var _node: Dictionary = {}
var _visible_choices: Array[Dictionary] = []
var _partner: Interactable = null
var _camera: ThirdPersonCamera = null
var _sensor: InteractionSensor = null
var _voice: AudioStreamPlayer3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus = get_node_or_null(EVENT_BUS_PATH)
	_state = get_node_or_null(GAME_STATE_PATH)

	_screen = DialogueScreen.new()
	_screen.name = "DialogueScreen"
	add_child(_screen)
	_screen.chosen.connect(_on_chosen)

	_voice = AudioStreamPlayer3D.new()
	_voice.name = "Voice"
	_voice.bus = Params.BUS_SFX
	_voice.volume_db = Params.VOICE_VOLUME_DB
	add_child(_voice)

	if _bus != null:
		_bus.dialogue_requested.connect(_on_requested)


## Liga o runner à câmera e ao sensor do jogador. Chamado por quem monta a cena — o runner
## não procura o jogador na árvore, porque nas provas não há jogador nenhum.
func bind(camera: ThirdPersonCamera, sensor: InteractionSensor) -> void:
	_camera = camera
	_sensor = sensor


func is_talking() -> bool:
	return _tree != null


## Árvore em curso. A prova lê daqui.
func current_tree() -> DialogueTree:
	return _tree


func current_node_id() -> StringName:
	return StringName(_node.get("id", &""))


# --- Abrir e fechar -----------------------------------------------------------


func _on_requested(dialogue_id: StringName, speaker: Node3D) -> void:
	if _tree != null:
		return
	var tree: DialogueTree = load_tree(dialogue_id)
	if tree == null:
		return
	_partner = speaker as Interactable
	begin(tree, _partner)


## Carrega uma árvore pelo identificador. Sem registro e sem tabela: o nome é o caminho.
static func load_tree(dialogue_id: StringName) -> DialogueTree:
	var path: String = "%s/%s.tres" % [Params.DIALOGUE_DIR, dialogue_id]
	if not ResourceLoader.exists(path):
		push_warning("Conversa ausente: %s. Rode `make dialogues`." % path)
		return null
	return ResourceLoader.load(path) as DialogueTree


## Abre a conversa. Público para a prova poder abrir sem passar pelo sinal.
func begin(tree: DialogueTree, partner: Interactable) -> void:
	_tree = tree
	_partner = partner

	if _sensor != null:
		_sensor.clear_target()
	if partner != null:
		var subject: Node3D = partner.subject()
		if subject is NPCController:
			(subject as NPCController).pause_routine()
		if _camera != null:
			_camera.frame_conversation(partner.focus_point())

	_show(tree.opening(_context()))


func _show(entry: Dictionary) -> void:
	if entry.is_empty():
		finish()
		return
	_node = entry
	_apply(DialogueTree.effects_of(entry))

	_visible_choices = _tree.choices_for(entry, _context())
	var lines: PackedStringArray = PackedStringArray()
	for choice: Dictionary in _visible_choices:
		lines.append(String(choice["text"]))

	_screen.present(_tree.speaker, String(entry["text"]), lines)
	_speak(String(entry["text"]))


## Encerra e devolve tudo ao que era.
##
## A ordem importa: a rotina volta antes de a câmera soltar, senão há um quadro em que o
## habitante já está andando e a câmera ainda está no ombro dele — e o corte fica visível.
func finish() -> void:
	if _tree == null:
		return
	var closing: StringName = _tree.id
	_tree = null
	_node = {}
	_visible_choices.clear()

	if _partner != null:
		var subject: Node3D = _partner.subject()
		if subject is NPCController:
			(subject as NPCController).resume_routine()
	_partner = null

	if _camera != null:
		_camera.release_conversation()
	_screen.close()
	if _voice.playing:
		_voice.stop()
	if _bus != null:
		_bus.dialogue_finished.emit(closing)


# --- Escolha e efeitos --------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if _tree == null:
		return
	if event.is_action_pressed(ACTION_LEAVE):
		finish()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_ADVANCE) and not _screen.is_revealed():
		# A primeira tecla completa a linha em vez de avançar: quem lê rápido não espera, e
		# quem apertou sem querer não perde a fala.
		_screen.reveal_all()
		get_viewport().set_input_as_handled()
		return
	for index: int in _visible_choices.size():
		if event.is_action_pressed(StringName(CHOICE_ACTION_PREFIX + str(index + 1))):
			_screen.choose(index)
			get_viewport().set_input_as_handled()
			return


func _on_chosen(index: int) -> void:
	if index < 0 or index >= _visible_choices.size():
		return
	var choice: Dictionary = _visible_choices[index]
	_apply(DialogueTree.effects_of(choice))

	var goto: StringName = StringName(choice.get("goto", &""))
	if goto == &"":
		finish()
		return
	_show(_tree.node(goto))


## Escolhe pela posição, para a prova não precisar sintetizar evento de input.
func choose(index: int) -> void:
	_on_chosen(index)


## Quantas escolhas estão visíveis agora.
func choice_count() -> int:
	return _visible_choices.size()


func _apply(effects: Array) -> void:
	if _state == null:
		return
	for effect: Dictionary in effects:
		var kind: StringName = StringName(effect["type"])
		if kind == DialogueTree.TYPE_FLAG:
			_state.set_flag(StringName(effect["key"]), effect["value"])
			continue
		if kind == DialogueTree.TYPE_REPUTATION:
			_state.add_reputation(StringName(effect["key"]), int(effect["value"]))
			continue
		push_warning("Efeito de diálogo com tipo desconhecido: %s" % kind)


func _context() -> Dictionary:
	if _state == null:
		return {}
	return _state.dialogue_context()


# --- Voz ----------------------------------------------------------------------


## A fala sai da boca de quem fala, em 3D, com o pitch daquele habitante.
##
## Silenciável pela opção do jogador. Quando desligada não se sintetiza nada — o custo cai
## a zero, e não a "um som mudo", que é o erro fácil de cometer aqui.
func _speak(text: String) -> void:
	if _state == null or not _state.voice_enabled or _partner == null:
		return
	var subject: Node3D = _partner.subject()
	var posture: StringName = _posture_of(subject)
	var speaker_id: StringName = StringName(subject.name)

	var line: AudioStreamWAV = ProceduralVoice.line_for(text, speaker_id, posture)
	if line == null:
		# Banco de voz ausente — `make audio` não rodou. A conversa continua muda em vez de
		# derrubar a fala inteira: quem lê o texto não perde nada, e quem gerou o projeto já
		# recebeu o aviso do carregador.
		return
	_voice.global_position = _partner.focus_point()
	_voice.stream = line
	_voice.pitch_scale = ProceduralVoice.pitch_for(speaker_id, posture)
	_voice.play()


## Postura do corpo de quem fala. É a mesma chave que a marcha usa: um corpo novo herda
## voz sem tabela nova, do mesmo jeito que herda passada.
static func _posture_of(subject: Node3D) -> StringName:
	var race: Node = subject.get_node_or_null(^"Race")
	if race is RaceApplier:
		return (race as RaceApplier).posture()
	return DEFAULT_POSTURE


const DEFAULT_POSTURE: StringName = &"ereto"
