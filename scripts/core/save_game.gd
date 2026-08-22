## Salvar e carregar: um JSON com o mínimo que descreve uma partida.
##
## O que se guarda é a **semente do mundo e o que o jogador fez nele** — nunca o mundo.
## Um vale de 512 m, uma cidade de 40 prédios e vinte habitantes com rotina saem de um
## número e de `tools/params.py`, e serializá-los seria gravar em disco o que o gerador
## produz de graça. É a regra inegociável levada ao save: se está no jogo porque um script
## o criou, um script o cria de novo.
##
## Guardamos, então: a seed, onde o jogador estava, que horas eram, as flags de mundo e a
## reputação por facção. Tudo o mais é derivado disso.
##
## JSON e não `ConfigFile` nem binário: um save que se abre num editor de texto é um save
## que se depura sem ferramenta, e o formato foi pedido assim.
class_name SaveGame
extends RefCounted

const KEY_VERSION: StringName = &"version"
const KEY_SEED: StringName = &"seed"
const KEY_HOUR: StringName = &"hour"
const KEY_DAY: StringName = &"day"
const KEY_POSITION: StringName = &"position"
const KEY_FACING: StringName = &"facing"
const KEY_FLAGS: StringName = &"flags"
const KEY_REPUTATION: StringName = &"reputation"
const KEY_STAMP: StringName = &"stamp"

const VECTOR_FIELDS: int = 3


## Existe partida salva?
static func exists() -> bool:
	return FileAccess.file_exists(Params.SAVE_PATH)


## Monta o save a partir do estado vivo. Não escreve nada — quem escreve é `write`.
##
## Separado de propósito: a prova monta um save, mexe no mundo e o restaura sem tocar em
## disco, e o menu de pausa usa o mesmo caminho que ela.
static func capture(player: Node3D) -> Dictionary:
	var time: Node = Engine.get_main_loop().root.get_node_or_null(^"/root/TimeSystem")
	var state: Node = Engine.get_main_loop().root.get_node_or_null(^"/root/GameState")
	var spot: Vector3 = player.global_position if player != null else Vector3.ZERO
	var facing: float = player.rotation.y if player != null else 0.0
	return {
		KEY_VERSION: Params.SAVE_VERSION,
		KEY_SEED: WorldGenerator.current_seed(),
		KEY_HOUR: time.get_time_of_day() if time != null else Params.START_HOUR,
		KEY_DAY: time.get_day() if time != null else 1,
		KEY_POSITION: [spot.x, spot.y, spot.z],
		KEY_FACING: facing,
		KEY_FLAGS: state.flags() if state != null else {},
		KEY_REPUTATION: state.reputations() if state != null else {},
		KEY_STAMP: Time.get_datetime_string_from_system(true),
	}


static func write(data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(Params.SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Não consegui escrever %s" % Params.SAVE_PATH)
		return false
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	return true


## Lê o save. Devolve vazio quando não há um, quando está corrompido, ou quando é de uma
## versão que este build não entende — e avisa alto em vez de tentar adivinhar.
static func read() -> Dictionary:
	if not exists():
		return {}
	var file: FileAccess = FileAccess.open(Params.SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("Save ilegível em %s. Ignorando." % Params.SAVE_PATH)
		return {}

	var data: Dictionary = parsed as Dictionary
	var version: int = int(data.get(KEY_VERSION, 0))
	if version != Params.SAVE_VERSION:
		push_warning(
			"Save da versão %d; este build lê a %d. Ignorando."
			% [version, Params.SAVE_VERSION]
		)
		return {}
	return data


static func erase() -> void:
	if exists():
		DirAccess.remove_absolute(Params.SAVE_PATH)


## Devolve o mundo ao estado salvo: relógio, flags, reputação e o corpo do jogador.
##
## A seed **não** é aplicada aqui: ela precisa valer antes de o mundo existir, e quem a
## aplica é `WorldGenerator.override_seed` antes da geração. Restaurar posição num mundo
## gerado com outra seed poria o jogador dentro de uma montanha que não estava lá.
static func restore(data: Dictionary, player: Node3D) -> void:
	if data.is_empty():
		return
	var root_node: Node = Engine.get_main_loop().root
	var time: Node = root_node.get_node_or_null(^"/root/TimeSystem")
	if time != null:
		time.set_time_of_day(float(data.get(KEY_HOUR, Params.START_HOUR)))

	var state: Node = root_node.get_node_or_null(^"/root/GameState")
	if state != null:
		state.load_flags(data.get(KEY_FLAGS, {}))
		state.load_reputations(data.get(KEY_REPUTATION, {}))

	if player != null:
		player.global_position = position_of(data)
		player.rotation.y = float(data.get(KEY_FACING, 0.0))


## Posição salva como `Vector3`. O JSON guarda três números porque um `Vector3` serializado
## pelo Godot vira uma string que só o Godot lê de volta — e o formato tinha de ser legível.
static func position_of(data: Dictionary) -> Vector3:
	var raw: Array = data.get(KEY_POSITION, [])
	if raw.size() < VECTOR_FIELDS:
		return Vector3.ZERO
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


static func seed_of(data: Dictionary) -> int:
	return int(data.get(KEY_SEED, Params.WORLD_SEED))
