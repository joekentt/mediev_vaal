## Veste um corpo: monta a malha rigada, escolhe a marcha e ajusta o colisor.
##
## É o único lugar do jogo que sabe que existe um `.glb` por povo. O controlador do
## jogador não sabe; a locomoção não sabe. Trocar `body` de `aldeao` para `prova_alto`
## troca a malha, a postura, a passada **e** a cápsula de colisão — sem tocar em nenhum
## dos dois.
##
## Por que o colisor entra aqui: o elenco vai de 1,45 m a 2,05 m. Uma cápsula fixa na
## cena faria o corpo baixo flutuar e o alto enfiar a cabeça no teto, e o erro só
## apareceria quando alguém trocasse de povo — muito longe daqui. A dimensão física é
## parte do que "ser deste povo" significa, então nasce junto com a malha.
##
## Hoje o dado vem do manifesto de `make characters`, que já carrega postura e altura de
## cada corpo. Na fase 11, quando existir um `Resource` de raça, é ele que este nó vai
## ler — a interface (`apply()`) não muda.
## Precisa ser `Node3D`, e não `Node`: a malha montada é filha deste nó, e a propagação de
## transformação do Godot sobe pela cadeia de `Node3D`. Um `Node` cru aqui deixaria o
## personagem parado na origem enquanto o corpo anda.
class_name RaceApplier
extends Node3D

## Emitido quando um corpo termina de ser montado. Quem depende das medidas do corpo
## (câmera, colisor, IA) escuta isto em vez de adivinhar quando o `.glb` chegou.
signal body_applied(body: StringName, height: float)

const MANIFEST_FILE: String = "manifest.json"
const MOUNT_NAME: StringName = &"Body"
const DEFAULT_POSTURE: StringName = &"ereto"

var _height: float = 0.0
var _posture: StringName = DEFAULT_POSTURE
var _mounted: Node3D = null

@export_group("Povo")
## Nome do corpo no elenco de `Params.CHARACTER_ROSTER`.
@export var body: StringName = Params.PLAYER_BODY
## Aplica sozinho ao entrar na árvore. Desligue para montar na hora que quiser.
@export var apply_on_ready: bool = true

@export_group("Nós afetados")
## Locomoção a religar depois de montar. Vazio faz o nó procurar entre os irmãos.
@export var locomotion_path: NodePath = NodePath()
## Cápsula a redimensionar pela altura do corpo. Vazio, ninguém é redimensionado.
@export var collider_path: NodePath = NodePath()


func _ready() -> void:
	if apply_on_ready:
		apply(body)


## Altura do corpo montado, em metros. Zero antes de montar.
func body_height() -> float:
	return _height


## Postura declarada pelo corpo — é ela que escolhe o `GaitProfile`.
func posture() -> StringName:
	return _posture


## Monta o corpo `who` e devolve se deu certo.
##
## Idempotente: chamar de novo troca o corpo, descartando o anterior. É o caminho para
## troca de aparência em runtime sem recriar o jogador inteiro.
func apply(who: StringName) -> bool:
	var path: String = "%s/%s.glb" % [Params.CHARACTER_DIR, who]
	var packed: PackedScene = ResourceLoader.load(path) as PackedScene
	if packed == null:
		push_error(
			"RaceApplier: corpo %s ausente em %s. Rode `make characters`." % [who, path]
		)
		return false

	if _mounted != null:
		_mounted.queue_free()
		remove_child(_mounted)

	body = who
	_mounted = packed.instantiate() as Node3D
	_mounted.name = MOUNT_NAME
	add_child(_mounted)
	_share_material(_mounted)

	var record: Dictionary = _manifest_entry(who)
	_height = float(record.get("height", 0.0))
	_posture = StringName(record.get("posture", DEFAULT_POSTURE))

	_fit_collider()
	_tune_locomotion()
	body_applied.emit(body, _height)
	return true


## Faz o corpo desenhar com o material compartilhado do kit.
##
## Cada `.glb` de personagem chega com o próprio `character_flat`, e a auditoria mediu
## cinco recursos idênticos em cena — um por corpo carregado. São todos brancos com vertex
## color, exatamente como o material do kit, então compartilhar não muda um pixel e devolve
## quatro entradas do orçamento de materiais únicos.
static func _share_material(node: Node) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.material_override = MaterialLibrary.get_material(Params.KIT_MATERIAL)
	for child: Node in node.get_children():
		_share_material(child)


## Dados do corpo no manifesto de `make characters`.
func _manifest_entry(who: StringName) -> Dictionary:
	var path: String = "%s/%s" % [Params.CHARACTER_DIR, MANIFEST_FILE]
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RaceApplier: %s ausente. Rode `make characters`." % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("RaceApplier: %s não é um manifesto válido." % path)
		return {}

	for entry: Dictionary in (parsed as Dictionary)["characters"]:
		if StringName(entry["name"]) == who:
			return entry
	push_error("RaceApplier: %s não está no manifesto de personagens." % who)
	return {}


## Cápsula da altura do corpo, com o pé no chão.
##
## `CapsuleShape3D.height` no Godot é a altura **total**, calotas incluídas, então o
## centro fica na metade. Errar isso enterra metade do personagem no chão, e o sintoma
## que aparece é o pé afundando — que se confunde com defeito de locomoção.
func _fit_collider() -> void:
	if collider_path.is_empty() or _height <= 0.0:
		return
	var collider: CollisionShape3D = get_node_or_null(collider_path) as CollisionShape3D
	if collider == null:
		return
	var capsule: CapsuleShape3D = collider.shape as CapsuleShape3D
	if capsule == null:
		return
	capsule.radius = Params.PLAYER_CAPSULE_RADIUS
	capsule.height = maxf(_height, Params.PLAYER_CAPSULE_RADIUS * 2.0)
	collider.position = Vector3(0.0, capsule.height * 0.5, 0.0)


## Dá à locomoção a marcha do povo e a religa ao esqueleto recém-montado.
func _tune_locomotion() -> void:
	var legs: ProceduralLocomotion = _find_locomotion()
	if legs == null:
		return
	legs.profile = GaitProfile.load_for(_posture)
	legs.bind()


func _find_locomotion() -> ProceduralLocomotion:
	if not locomotion_path.is_empty():
		return get_node_or_null(locomotion_path) as ProceduralLocomotion
	var parent: Node = get_parent()
	if parent == null:
		return null
	for sibling: Node in parent.get_children():
		if sibling is ProceduralLocomotion:
			return sibling as ProceduralLocomotion
	return null
