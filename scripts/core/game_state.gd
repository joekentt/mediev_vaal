extends Node

## Estado global e volátil da sessão. Stub da fase 1.
##
## Guarda só o que é de fato global: fase do jogo, pausa, preferências de entrada e
## flags de mundo. Nada de regra de gameplay aqui. Toda mudança relevante é anunciada
## pelo `EventBus`; ninguém consulta o `GameState` em `_process`.

enum Phase {
	BOOT, ## Autoloads subindo, nada gerado ainda.
	MAIN_MENU, ## Menu inicial.
	GENERATING, ## Mundo sendo construído por `generators/`.
	PLAYING, ## Jogo em andamento.
	PAUSED, ## Pausado pelo jogador.
	CUTSCENE, ## Controle tomado por uma cena roteirizada.
}

## Sensibilidade do mouse para a câmera, em graus por pixel.
var mouse_sensitivity: float = Params.MOUSE_SENSITIVITY

## Inverte o eixo vertical da câmera.
var invert_camera_y: bool = false

var _phase: int = Phase.BOOT
var _is_paused: bool = false
var _world_flags: Dictionary = {}
var _reputation: Dictionary = {}

## Povo do jogador. As condições de diálogo comparam contra isto; a fase 11 completa é
## quem vai deixar o jogador escolher.
var player_race: StringName = Params.PLAYER_BODY

## Voz procedural dos habitantes. Opção de jogador: quem acha a fala sintetizada
## irritante desliga e continua lendo o texto, que é onde a informação está de verdade.
var voice_enabled: bool = true

# --- Opções de vídeo e áudio -------------------------------------------------
# Ficam aqui porque preferência é estado global e este é o autoload de estado global.
# Quem as aplica no motor é `Settings`, e quem as escreve em disco também: este arquivo
# guarda o valor, não sabe o que ele faz.

## Preset de qualidade (ver `Params.QUALITY_PRESETS`). "media" é o alvo do projeto.
var quality: StringName = Params.QUALITY_DEFAULT
## Fator sobre o alcance de sombra e de LOD.
var render_distance: float = Params.RENDER_DISTANCE_DEFAULT
## Fator sobre `NPC_COUNT`. Vale na geração do mundo, não com o jogo aberto.
var npc_density: float = Params.NPC_DENSITY_DEFAULT
var vsync_enabled: bool = Params.VSYNC_DEFAULT
## Volume linear por barramento, como um slider espera.
var volumes: Dictionary = Params.VOLUME_DEFAULTS.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Fase atual do jogo (ver `Phase`).
func get_phase() -> int:
	return _phase


func set_phase(new_phase: int) -> void:
	if _phase == new_phase:
		return
	_phase = new_phase
	EventBus.game_phase_changed.emit(_phase)


func is_paused() -> bool:
	return _is_paused


## Pausa a árvore inteira. Autoloads seguem rodando (`PROCESS_MODE_ALWAYS`).
func set_paused(value: bool) -> void:
	if _is_paused == value:
		return
	_is_paused = value
	get_tree().paused = value
	set_phase(Phase.PAUSED if value else Phase.PLAYING)
	EventBus.game_paused_changed.emit(_is_paused)


func toggle_pause() -> void:
	set_paused(not _is_paused)


## Sensibilidade do mouse, presa a limites sãos (ver `Params`).
func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(
		value, Params.MOUSE_SENSITIVITY_MIN, Params.MOUSE_SENSITIVITY_MAX
	)


## Flags de mundo: fatos pequenos e persistentes ("portao_norte_aberto", ...).
func set_flag(key: StringName, value: Variant) -> void:
	_world_flags[key] = value


func get_flag(key: StringName, default_value: Variant = null) -> Variant:
	return _world_flags.get(key, default_value)


func has_flag(key: StringName) -> bool:
	return _world_flags.has(key)


func clear_flags() -> void:
	_world_flags.clear()


## Cópia das flags, para o save. Cópia e não a referência: quem salva não escreve no mundo.
func flags() -> Dictionary:
	return _world_flags.duplicate()


## Repõe as flags de um save. Substitui em vez de mesclar: carregar uma partida é entrar
## naquele mundo, não somar dois.
func load_flags(data: Dictionary) -> void:
	_world_flags = data.duplicate()


## Reputação com uma facção, presa aos limites de `Params`.
##
## Um inteiro por facção e nada mais. Diálogo lê e escreve; nada além dele depende disto
## ainda — comércio e consequência são de fases posteriores, e inventar estrutura para elas
## agora seria adivinhar o formato de um sistema que não existe.
func reputation(faction: StringName) -> int:
	return int(_reputation.get(faction, Params.REPUTATION_START))


func add_reputation(faction: StringName, delta: int) -> void:
	if not Params.FACTIONS.has(faction):
		push_warning("Facção desconhecida: %s. Ver FACTIONS em params.py." % faction)
		return
	var before: int = reputation(faction)
	var after: int = clampi(before + delta, Params.REPUTATION_MIN, Params.REPUTATION_MAX)
	if after == before:
		return
	_reputation[faction] = after
	EventBus.reputation_changed.emit(faction, after)


func clear_reputation() -> void:
	_reputation.clear()


## Cópia da reputação por facção, para o save.
func reputations() -> Dictionary:
	return _reputation.duplicate()


## Repõe a reputação de um save, ignorando facção que não existe mais nesta versão.
func load_reputations(data: Dictionary) -> void:
	_reputation.clear()
	for faction: Variant in data:
		var key: StringName = StringName(faction)
		if not Params.FACTIONS.has(key):
			push_warning("Save cita facção desconhecida: %s. Ignorando." % key)
			continue
		_reputation[key] = clampi(
			int(data[faction]), Params.REPUTATION_MIN, Params.REPUTATION_MAX
		)


## Contexto para as condições de diálogo.
##
## Montado aqui e passado por valor, porque `DialogueTree` não conhece — e não deve
## conhecer — o `GameState`: ela é um `Resource` avaliável fora do jogo, e a prova de
## diálogo depende disso para rodar uma árvore inteira sem abrir uma janela.
func dialogue_context() -> Dictionary:
	var by_faction: Dictionary = {}
	for faction: StringName in Params.FACTIONS:
		by_faction[faction] = reputation(faction)
	return {
		DialogueTree.CONTEXT_FLAGS: _world_flags.duplicate(),
		DialogueTree.CONTEXT_REPUTATION: by_faction,
		DialogueTree.CONTEXT_RACE: player_race,
	}
