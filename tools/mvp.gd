## O MVP em número: salvar, fechar, reabrir, continuar — e a pausa que não quebra o relógio.
##
##     godot --headless --script res://tools/mvp.gd
##
## O critério de aceite da fase é uma frase — "salvar, fechar, reabrir e continuar
## funciona" — e ela só é verificável de um jeito: **em dois processos**. Salvar e carregar
## na mesma sessão prova pouco, porque o mundo já está na memória e a seed já está aplicada.
## Por isso este script tem três modos:
##
##     --script res://tools/mvp.gd -- fluxo      abre a cena principal e joga por ela
##     --script res://tools/mvp.gd -- salvar     gera um mundo, anda, salva, imprime o estado
##     --script res://tools/mvp.gd -- carregar   abre o save num processo novo e compara
##
## Nenhum deles cita um identificador de autoload. `GameState` e `TimeSystem` são resolvidos
## por `/root/...` e as fases vêm de `Params.Phase`: identificador de autoload não existe
## quando `--script` compila, e citá-lo derruba a compilação do arquivo inteiro — foi o que
## aconteceu na primeira versão deste modo de fluxo.
##
## Entre os dois, tudo morre: a árvore de cena, os autoloads, o `WorldGenerator` e as suas
## variáveis estáticas. O que atravessa é o arquivo JSON, que é exatamente o que o jogador
## tem quando fecha o jogo e volta no dia seguinte.
##
## A pausa é medida no primeiro modo: pausa-se, deixam-se passar quadros reais, despausa-se
## e cobra-se que o relógio do mundo **não tenha andado** e que o céu não tenha saltado.
## Não é purismo — é o que separa "pausei" de "o mundo continuou sem mim".
extends SceneTree

const RESULT_PREFIX: String = "MEDIEV_MVP "
const MODE_SAVE: String = "salvar"
const MODE_LOAD: String = "carregar"
const MODE_FLOW: String = "fluxo"
const MAIN_SCENE: String = "res://scenes/world/main.tscn"
const BAKE_TIMEOUT_FRAMES: int = 2400
## Quanto o jogador anda antes de salvar, para a posição salva não ser a de nascimento.
const WALK_SECONDS: float = 2.0
## Quadros reais de pausa. Suficientes para o relógio andar visivelmente se ele andasse.
const PAUSE_FRAMES: int = 60

var _stage: Node3D = null
var _time: Node = null
var _state: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_time = root.get_node_or_null(^"/root/TimeSystem")
	_state = root.get_node_or_null(^"/root/GameState")
	match _mode():
		MODE_SAVE:
			await _save_side()
		MODE_LOAD:
			await _load_side()
		MODE_FLOW:
			await _flow_side()
		_:
			printerr("Modo desconhecido. Use `salvar`, `carregar` ou `fluxo`.")
			quit(1)


func _mode() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	return args[0] if args.size() > 0 else MODE_SAVE


# --- Lado do salvar -----------------------------------------------------------


func _save_side() -> void:
	# Sem save antigo por perto: senão a prova poderia estar lendo o de uma execução
	# anterior e passando por acidente.
	SaveGame.erase()
	WorldGenerator.clear_seed_override()

	_stage = await _build()
	var player: Node3D = _stage.get_node_or_null(^"Player")
	if player == null:
		printerr("Jogador ausente no estágio.")
		quit(1)
		return

	var opening: Dictionary = WorldGenerator.begin_opening(_stage, player)
	var woke_at: Vector3 = player.global_position
	await _wait(WALK_SECONDS)

	# Estado inventado de propósito antes de salvar: um save que só guarda posição passaria
	# num teste que não olha para flags nem reputação.
	_state.set_flag(&"prova_do_mvp", true)
	_state.add_reputation(&"vilarejo", REPUTATION_MARK)
	_time.set_time_of_day(SAVE_HOUR)

	var pause: Dictionary = await _pause_check()

	var data: Dictionary = SaveGame.capture(player)
	var wrote: bool = SaveGame.write(data)

	print(RESULT_PREFIX + JSON.stringify({
		"mode": MODE_SAVE,
		"wrote": wrote,
		"path": Params.SAVE_PATH,
		"seed": int(data[SaveGame.KEY_SEED]),
		"hour": float(data[SaveGame.KEY_HOUR]),
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"flags": data[SaveGame.KEY_FLAGS].size(),
		"reputation": data[SaveGame.KEY_REPUTATION],
		"opening": {
			"built": not opening.is_empty(),
			"lanterns": int(opening.get("lanterns", 0)),
			"woke_at": [woke_at.x, woke_at.y, woke_at.z],
			"camp_gap_m": woke_at.distance_to(opening.get("camp", woke_at)),
			"road_gap_m": _road_gap(woke_at),
			"gate_gap_m": _gate_gap(woke_at),
		},
		"pause": pause,
	}))
	quit(0)


const REPUTATION_MARK: int = 7
const SAVE_HOUR: float = 15.25


## A pausa não pode mexer no relógio do mundo.
##
## Pausa-se, deixam-se passar `PAUSE_FRAMES` quadros **reais** e despausa-se. O relógio é
## `PROCESS_MODE_PAUSABLE`, então ele para junto: a hora depois tem de ser a mesma de
## antes. Se ela andar, o jogador que abre o menu por três minutos volta com o sol noutro
## lugar — e é isso que "a pausa não quebra o TimeSystem" quer dizer.
func _pause_check() -> Dictionary:
	var before: float = _time.get_time_of_day()
	_state.set_paused(true)
	for _frame: int in PAUSE_FRAMES:
		await process_frame
	var during: float = _time.get_time_of_day()
	_state.set_paused(false)
	await process_frame
	await process_frame
	return {
		"frames": PAUSE_FRAMES,
		"hour_before": before,
		"hour_during": during,
		"drift_hours": absf(during - before),
		"running_after": not _state.is_paused(),
	}


# --- Lado do fluxo ------------------------------------------------------------


## Abre a cena principal de verdade e joga por ela: menu → carregamento → mundo → pausa.
##
## As outras duas provas chamam `WorldGenerator.build_stage` direto, que é o certo para
## medir mundo — mas deixa `main.gd` sem uma única execução. A peça mais visível do MVP, o
## caminho que todo jogador percorre, seria verificada só pelo compilador. Aqui a cena é
## instanciada como o jogo a instancia, e o botão é apertado pelo sinal que o botão emite.
func _flow_side() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE) as PackedScene
	if packed == null:
		printerr("Não consegui carregar %s" % MAIN_SCENE)
		quit(1)
		return

	var main: Node3D = packed.instantiate() as Node3D
	root.add_child(main)
	await process_frame

	var menu: MainMenu = main.get_node_or_null(^"MainMenu") as MainMenu
	var pause: PauseScreen = main.get_node_or_null(^"Pause") as PauseScreen
	var options: OptionsScreen = main.get_node_or_null(^"Options") as OptionsScreen
	var fps: FPSCounter = main.get_node_or_null(^"FPS") as FPSCounter
	var at_menu: bool = _state.get_phase() == Params.Phase.MAIN_MENU

	# "Novo vale", pelo sinal que o botão emite. Clicar num `Button` sem renderizador não é
	# possível; emitir o sinal dele percorre exatamente o mesmo código.
	menu.start_requested.emit(false)
	var waited: int = 0
	while _state.get_phase() != Params.Phase.PLAYING and waited < FLOW_TIMEOUT_FRAMES:
		await process_frame
		waited += 1

	var stage: Node3D = main.get_node_or_null(^"Stage")
	var player: Node3D = stage.get_node_or_null(^"Player") if stage != null else null

	# A pausa, pelo mesmo caminho do jogador: abre, congela, fecha.
	pause.open()
	await process_frame
	var paused_ok: bool = _state.is_paused() and pause.is_open()
	pause.close()
	await process_frame

	options.open()
	await process_frame
	options.close()
	await process_frame

	print(RESULT_PREFIX + JSON.stringify({
		"mode": MODE_FLOW,
		"started_at_menu": at_menu,
		"reached_playing": _state.get_phase() == Params.Phase.PLAYING,
		"frames_to_world": waited,
		"has_stage": stage != null,
		"has_player": player != null,
		"has_fps_counter": fps != null,
		"paused_ok": paused_ok,
		"running_after": not _state.is_paused(),
		"npcs": int(WorldGenerator.last_report.get("npcs", 0)),
	}))
	quit(0)


const FLOW_TIMEOUT_FRAMES: int = 3000


# --- Lado do carregar ---------------------------------------------------------


func _load_side() -> void:
	var data: Dictionary = SaveGame.read()
	if data.is_empty():
		printerr("Save ausente ou ilegível em %s." % Params.SAVE_PATH)
		quit(1)
		return

	# A seed **antes** do mundo: é ela que decide o relevo, e restaurar a posição num vale
	# gerado com outra seed poria o jogador dentro de uma montanha que não estava lá.
	WorldGenerator.override_seed(SaveGame.seed_of(data))
	_stage = await _build()
	var player: Node3D = _stage.get_node_or_null(^"Player")
	SaveGame.restore(data, player)
	await process_frame

	var wanted: Vector3 = SaveGame.position_of(data)
	var landed: Vector3 = player.global_position if player != null else Vector3.ZERO
	print(RESULT_PREFIX + JSON.stringify({
		"mode": MODE_LOAD,
		"seed_saved": SaveGame.seed_of(data),
		"seed_world": WorldGenerator.current_seed(),
		"hour_saved": float(data[SaveGame.KEY_HOUR]),
		"hour_world": _time.get_time_of_day(),
		"position_gap_m": wanted.distance_to(landed),
		"ground_gap_m": _ground_gap(landed),
		"flags": _state.flags(),
		"reputation": _state.reputations(),
		"npcs": int(WorldGenerator.last_report.get("npcs", 0)),
	}))
	quit(0)


# --- Utilidades ---------------------------------------------------------------


func _build() -> Node3D:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var stage: Node3D = WorldGenerator.build_stage(holder)
	await _wait_for_bake(_find_region(stage))
	return stage


## Distância do ponto ao leito da estrada, em planta. A abertura acampa **ao lado** dela.
func _road_gap(spot: Vector3) -> float:
	var curve: Curve3D = WorldGenerator.last_curve
	if curve == null:
		return -1.0
	var near: Vector3 = curve.get_closest_point(spot)
	return Vector2(spot.x, spot.z).distance_to(Vector2(near.x, near.z))


func _gate_gap(spot: Vector3) -> float:
	var layout: CityLayout = WorldGenerator.last_city
	if layout == null:
		return -1.0
	var gate: Vector3 = layout.markers.get(&"portao", Vector3.ZERO)
	return Vector2(spot.x, spot.z).distance_to(Vector2(gate.x, gate.z))


## Quanto o corpo restaurado está acima do relevo. Negativo é dentro do chão.
func _ground_gap(spot: Vector3) -> float:
	var field: HeightField = WorldGenerator.last_field
	if field == null:
		return 0.0
	return spot.y - field.height_at(spot.x, spot.z)


func _wait(seconds: float) -> void:
	var frames: int = int(seconds * float(Params.PHYSICS_TICKS_PER_SECOND))
	for _frame: int in frames:
		await physics_frame


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
