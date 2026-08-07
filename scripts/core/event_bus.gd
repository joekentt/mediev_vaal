extends Node

## Barramento global de sinais.
##
## Regra do projeto: nenhum sistema alcança outro por caminho de nó
## (`get_node("../../Algo")`). Emissores e ouvintes se encontram aqui.
##
##     EventBus.interaction_requested.emit(target)
##     EventBus.hour_changed.connect(_on_hour_changed)
##
## Nomes: `<sujeito>_<verbo_no_passado>` para fato consumado (`npc_died`) e sufixo
## `_requested` para pedido (`dialogue_requested`). O EventBus só declara sinais —
## estado global vive no `GameState`.

# --- Ciclo de jogo -----------------------------------------------------------

## A fase do jogo mudou (ver `GameState.Phase`).
@warning_ignore("unused_signal")
signal game_phase_changed(phase: int)

## O jogo foi pausado ou despausado.
@warning_ignore("unused_signal")
signal game_paused_changed(is_paused: bool)

## Uma área de mundo terminou de ser gerada e está pronta para uso.
@warning_ignore("unused_signal")
signal world_generated(world_id: StringName, stats: Dictionary)

# --- Jogador -----------------------------------------------------------------

## O foco de interação mudou. `null` quando nada está ao alcance.
@warning_ignore("unused_signal")
signal interactable_focused(interactable: Node3D)

## O jogador acionou a interação sobre um alvo.
@warning_ignore("unused_signal")
signal interaction_requested(interactable: Node3D)

## O jogador cruzou a fronteira de uma célula de streaming.
@warning_ignore("unused_signal")
signal player_moved_to_cell(cell: Vector2i)

# --- NPCs e IA ---------------------------------------------------------------

## Um NPC entrou na simulação detalhada (dentro do teto de NPCs ativos).
@warning_ignore("unused_signal")
signal npc_activated(npc: Node3D)

## Um NPC saiu da simulação detalhada e voltou a ser simulado de forma abstrata.
@warning_ignore("unused_signal")
signal npc_deactivated(npc: Node3D)

## Um NPC trocou de tarefa na rotina diária.
@warning_ignore("unused_signal")
signal npc_schedule_changed(npc: Node3D, task_id: StringName)

# --- Diálogo -----------------------------------------------------------------

## Algo pediu para abrir um diálogo.
@warning_ignore("unused_signal")
signal dialogue_requested(dialogue_id: StringName, speaker: Node3D)

## O diálogo em curso terminou.
@warning_ignore("unused_signal")
signal dialogue_finished(dialogue_id: StringName)

# --- Tempo -------------------------------------------------------------------

## A hora do dia virou (0..23).
@warning_ignore("unused_signal")
signal hour_changed(hour: int)

## Um novo dia começou.
@warning_ignore("unused_signal")
signal day_changed(day: int)

## O período do dia mudou (ver `Params.Period`).
@warning_ignore("unused_signal")
signal day_period_changed(period: int)

# --- Interface ---------------------------------------------------------------

## Pedido para mostrar uma mensagem curta na tela.
@warning_ignore("unused_signal")
signal toast_requested(text: String)

## Pedido para abrir ou fechar um painel de UI.
@warning_ignore("unused_signal")
signal ui_screen_requested(screen_id: StringName, open: bool)

# --- Áudio -------------------------------------------------------------------

## Pedido de troca de trilha musical.
@warning_ignore("unused_signal")
signal music_requested(track_id: StringName)

## Pedido de troca de leito sonoro ambiente.
@warning_ignore("unused_signal")
signal ambience_requested(ambience_id: StringName)

# --- Depuração ---------------------------------------------------------------

## Uma amostra de métricas ficou pronta (ver `Metrics.sample`). Alimenta `make bench`.
@warning_ignore("unused_signal")
signal metrics_sampled(sample: Dictionary)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
