extends Node3D

## Raiz da cena principal, e o único lugar que sabe a ordem das coisas.
##
## A cena em disco tem só este nó. Todo o resto — céu, sol, relevo, estrada, cidade,
## habitantes, menus — é construído por script quando isto roda. Se algo aqui só existisse
## por ter sido arrastado no editor, estaria errado.
##
## O fluxo é curto e é o de qualquer jogo: menu → carregamento → mundo. O que este arquivo
## faz de próprio é **a ordem**, e ela importa em três pontos:
##
## 1. As opções são lidas e aplicadas **antes** do mundo nascer. A densidade de habitantes
##    vale na geração, e aplicá-la depois seria apagar gente recém-criada.
## 2. A cortina de carregamento sobe **antes** da geração, e sem fade. Gerar o vale bloqueia
##    a thread principal por cerca de um segundo, e um fade de um terço de segundo começaria
##    depois de a tela já ter travado.
## 3. O save é restaurado **depois** de o mundo existir e **antes** de a abertura rodar:
##    quem continua uma partida não acorda no acampamento de novo.

const WORLD_ID: StringName = &"stage"
const USEC_PER_MS: float = 1000.0
const PLAYER_NAME: StringName = &"Player"
## Quadros entre subir a cortina e começar a gerar. Dois, e não um: o primeiro põe o nó na
## árvore, o segundo o desenha. Com um só, a cortina existe e ninguém a vê.
const CURTAIN_FRAMES: int = 2

var _stage: Node3D = null
var _menu: MainMenu = null
var _pause: PauseScreen = null
var _options: OptionsScreen = null
var _loading: LoadingScreen = null
var _fps: FPSCounter = null


func _ready() -> void:
	Settings.load_into(GameState)
	Settings.apply_global(GameState)
	_build_screens()

	GameState.set_phase(Params.Phase.MAIN_MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu.open()


func _build_screens() -> void:
	_loading = LoadingScreen.new()
	_loading.name = "Loading"
	add_child(_loading)

	_options = OptionsScreen.new()
	_options.name = "Options"
	_options.closed.connect(_on_options_closed)
	add_child(_options)

	_pause = PauseScreen.new()
	_pause.name = "Pause"
	_pause.options_requested.connect(_options.open)
	_pause.save_requested.connect(_save)
	_pause.menu_requested.connect(_to_menu)
	add_child(_pause)
	_pause.process_mode = Node.PROCESS_MODE_DISABLED

	_menu = MainMenu.new()
	_menu.name = "MainMenu"
	_menu.start_requested.connect(_start)
	_menu.options_requested.connect(_options.open)
	_menu.quit_requested.connect(_quit)
	add_child(_menu)

	_fps = FPSCounter.new()
	_fps.name = "FPS"
	add_child(_fps)


# --- Começar ------------------------------------------------------------------


## Gera o mundo e entrega o controle. `from_save` decide entre continuar e recomeçar.
func _start(from_save: bool) -> void:
	var save: Dictionary = SaveGame.read() if from_save else {}
	_menu.close()
	_loading.open("gerando o vale…")
	for _frame: int in CURTAIN_FRAMES:
		await get_tree().process_frame

	GameState.set_phase(Params.Phase.GENERATING)
	if save.is_empty():
		WorldGenerator.clear_seed_override()
		GameState.clear_flags()
		GameState.clear_reputation()
	else:
		WorldGenerator.override_seed(SaveGame.seed_of(save))

	var started_usec: int = Time.get_ticks_usec()
	_stage = WorldGenerator.build_stage(self)
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / USEC_PER_MS

	_loading.step("assentando a cidade…")
	await get_tree().process_frame
	Settings.apply_world(GameState, _stage)
	# As opções passam a alcançar o mundo agora que ele existe: sol, LOD e vegetação só
	# existem depois daqui, e sem esta linha mexer na qualidade durante o jogo mudaria
	# apenas o que é global (janela, áudio, V-Sync).
	_options.bind(_stage)

	var player: Node3D = _stage.get_node_or_null(NodePath(PLAYER_NAME))
	if save.is_empty():
		WorldGenerator.begin_opening(_stage, player)
	else:
		SaveGame.restore(save, player)

	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.set_phase(Params.Phase.PLAYING)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_loading.close()

	EventBus.world_generated.emit(WORLD_ID, {
		"nodes": _stage.get_child_count(),
		"build_ms": elapsed_ms,
	})
	print("Estágio gerado em %.2f ms." % elapsed_ms)


# --- Sair, salvar, voltar -----------------------------------------------------


func _save() -> void:
	var player: Node3D = _stage.get_node_or_null(NodePath(PLAYER_NAME)) if _stage != null else null
	if SaveGame.write(SaveGame.capture(player)):
		EventBus.toast_requested.emit("Partida salva.")


## Volta ao menu principal, descartando o mundo.
##
## Descartar e reconstruir, em vez de guardar o mundo escondido: um vale de 512 m com
## cidade e vinte habitantes ocupa memória e continua custando física, e "voltar ao menu"
## é justamente o momento em que ninguém está olhando para ele.
func _to_menu() -> void:
	_pause.close()
	_pause.process_mode = Node.PROCESS_MODE_DISABLED
	if _stage != null:
		remove_child(_stage)
		_stage.queue_free()
		_stage = null
	_options.bind(null)
	GameState.set_phase(Params.Phase.MAIN_MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu.open()


func _on_options_closed() -> void:
	# As opções são chamadas de dois lugares e voltam para quem as chamou: do menu, para o
	# menu; da pausa, para a pausa. Sem isto, fechar as opções durante o jogo devolveria o
	# controle com a pausa ainda ligada e o mouse solto.
	if GameState.get_phase() == Params.Phase.MAIN_MENU:
		_menu.open()


func _quit() -> void:
	Settings.save_from(GameState)
	get_tree().quit()
