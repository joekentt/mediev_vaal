## Qualquer coisa com que se possa interagir: NPC, porta, baú, placa.
##
## É a interface inteira, e é pequena de propósito: um texto de prompt e um verbo. Quem
## interage não sabe o que está do outro lado, e o que está do outro lado não sabe quem
## interagiu além do nó que recebe. Uma porta da fase 9 e um NPC da fase 10 entram pelo
## mesmo lugar sem que o sensor do jogador precise saber que existem os dois.
##
## É `Area3D` e não `Node3D` porque o sensor do jogador detecta por sobreposição de área.
## A alternativa seria o sensor varrer a cena atrás de nós de um tipo, o que custa uma
## busca por quadro para responder uma pergunta que o motor de física já responde de graça.
##
## `dialogue` é opcional: com árvore, interagir abre conversa; sem ela, o nó só anuncia
## `interacted` e quem quiser que reaja. É o que deixa um baú ser interagível sem inventar
## uma conversa de uma linha para ele.
class_name Interactable
extends Area3D

## Emitido quando alguém interage e não há conversa para abrir.
signal interacted(actor: Node3D)

## Verbo que o prompt mostra. Curto: o que informa é o verbo, o resto é ruído sobre o
## cenário.
@export var prompt_text: String = "Interagir"

## Conversa a abrir, quando houver.
@export var dialogue: DialogueTree = null

## Altura acima da origem para onde a câmera de conversa olha. Zero usa a própria origem.
@export var focus_height: float = 0.0

## Nó a que este interagível pertence — o NPC, a porta. Vazio usa o pai.
@export var owner_path: NodePath = NodePath("..")


func _ready() -> void:
	# Camada de interagível e máscara nenhuma: quem procura é o sensor do jogador. Uma área
	# que também monitora gastaria um teste por par para nada.
	collision_layer = Params.LAYER_INTERACTABLE
	collision_mask = 0
	monitoring = false
	monitorable = true


## Nó dono deste interagível. É ele que o diálogo pausa, e é dele que a voz sai.
func subject() -> Node3D:
	var found: Node = get_node_or_null(owner_path)
	if found is Node3D:
		return found as Node3D
	return self


## Ponto para onde a câmera de conversa olha — a cabeça, não os pés.
func focus_point() -> Vector3:
	return subject().global_position + Vector3.UP * focus_height


## O verbo acontece. Com árvore, pede conversa; sem ela, só avisa.
##
## Pedir por sinal, e não chamar o runner, é o que permite o interagível existir num mundo
## sem sistema de diálogo nenhum — a fase 9 vai instanciar portas antes de a fase 11
## existir na árvore de cena.
func interact(actor: Node3D) -> void:
	if dialogue != null:
		var bus: Node = get_node_or_null(EVENT_BUS_PATH)
		if bus != null:
			bus.dialogue_requested.emit(dialogue.id, self)
		return
	interacted.emit(actor)


## O `EventBus` é alcançado pelo caminho do autoload. Ver a nota em `npc_controller.gd`:
## identificador de autoload não existe quando um script de ferramenta compila, e este
## arquivo entra na cadeia estática de `WorldGenerator`.
const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"
