## Como um povo anda. Um `Resource` por postura, gerado em `resources/gaits/`.
##
## É aqui que mora o critério de aceite "raças diferentes andam visivelmente diferente
## sem código específico": `ProceduralLocomotion` não sabe o que é um guarda nem o que é
## um batedor. Ele lê amplitude, cadência e viés de um perfil, e o perfil vem do corpo.
## Trocar o `.tres` troca a marcha; não existe um `if raca == ...` em lugar nenhum.
##
## Todo campo é `@export` de propósito: dá para arrastar o slider no inspetor com o jogo
## rodando e ver a passada mudar. O valor de fábrica de cada um sai de `Params`, que sai
## de `tools/params.py` — o inspetor tuna, mas quem manda no que nasce é o gerador.
class_name GaitProfile
extends Resource

## Postura usada quando ninguém disse qual. É a marcha de referência do projeto.
const DEFAULT_POSTURE: StringName = &"ereto"

## Nome da postura de `Params.GAIT_PROFILES` que gerou este perfil.
@export var posture: StringName = DEFAULT_POSTURE

@export_group("Passada")
## Multiplicador do comprimento do passo. Abaixo de 1 encurta e parece cauteloso.
@export_range(0.4, 2.0, 0.01) var stride_scale: float = 0.0
## Multiplicador da cadência. Passo curto com cadência alta lê como pressa.
@export_range(0.4, 2.0, 0.01) var cadence_scale: float = 0.0
## Altura do pé no meio do balanço, em fração da altura do personagem.
@export_range(0.0, 0.4, 0.001) var foot_lift: float = 0.0
## Idem, em corrida. A diferença entre os dois é metade da leitura de "está correndo".
@export_range(0.0, 0.5, 0.001) var foot_lift_run: float = 0.0
## Para onde o joelho aponta, como multiplicador da frente do corpo.
@export_range(0.2, 2.0, 0.01) var knee_forward: float = 0.0

@export_group("Quadril e tronco")
## Sobe-e-desce do quadril por passo, em fração da altura.
@export_range(0.0, 0.08, 0.001) var hip_bounce: float = 0.0
## Rotação do quadril em torno do eixo vertical, em graus.
@export_range(0.0, 20.0, 0.1) var hip_sway_deg: float = 0.0
## Queda do quadril do lado do pé no ar, em graus. É o gingado.
@export_range(0.0, 20.0, 0.1) var hip_drop_deg: float = 0.0
## Inclinação do tronco para a frente, em graus.
@export_range(-20.0, 30.0, 0.1) var torso_lean_deg: float = 0.0
## Torção do tronco contra o quadril, em graus.
@export_range(0.0, 25.0, 0.1) var torso_twist_deg: float = 0.0

@export_group("Braços")
## Amplitude do balanço contra-lateral, em graus, no pico da velocidade.
@export_range(0.0, 80.0, 0.5) var arm_swing_deg: float = 0.0
## Deslocamento constante do braço, em graus. Positivo = à frente do corpo.
@export_range(-30.0, 45.0, 0.5) var arm_bias_deg: float = 0.0
## Dobra fixa do cotovelo, em graus.
@export_range(0.0, 90.0, 0.5) var elbow_bend_deg: float = 0.0

@export_group("Cabeça")
## Oscilação vertical da cabeça, em fração da altura.
@export_range(0.0, 0.05, 0.001) var head_bob: float = 0.0


## Um perfil recém-criado já nasce com a marcha de referência.
##
## Os campos declaram `0.0` porque a regra do projeto é que número com significado mora
## em `tools/params.py`, e um literal no `= ` de cada `@export` seria exatamente a cópia
## que a regra existe para impedir. Quem preenche é isto aqui, uma vez, na construção —
## e o `.tres` gerado sobrescreve depois, porque o Godot roda `_init` antes de aplicar as
## propriedades salvas.
func _init() -> void:
	_apply(DEFAULT_POSTURE)


## Monta um perfil a partir de uma entrada de `Params.GAIT_PROFILES`.
##
## Existe para o caso em runtime — um NPC nascido de dados, sem `.tres` carregado. O
## caminho normal é carregar o recurso gerado, que é o que o inspetor sabe editar.
static func from_posture(name: StringName) -> GaitProfile:
	var profile: GaitProfile = GaitProfile.new()
	profile._apply(name)
	return profile


## Copia uma entrada de `Params.GAIT_PROFILES` para os campos exportados.
func _apply(name: StringName) -> void:
	posture = name
	if not Params.GAIT_PROFILES.has(name):
		push_error("Postura sem perfil de marcha: %s" % name)
		return

	var values: Dictionary = Params.GAIT_PROFILES[name]
	stride_scale = values[&"stride_scale"]
	cadence_scale = values[&"cadence_scale"]
	foot_lift = values[&"foot_lift"]
	foot_lift_run = values[&"foot_lift_run"]
	knee_forward = values[&"knee_forward"]
	hip_bounce = values[&"hip_bounce"]
	hip_sway_deg = values[&"hip_sway_deg"]
	hip_drop_deg = values[&"hip_drop_deg"]
	torso_lean_deg = values[&"torso_lean_deg"]
	torso_twist_deg = values[&"torso_twist_deg"]
	arm_swing_deg = values[&"arm_swing_deg"]
	arm_bias_deg = values[&"arm_bias_deg"]
	elbow_bend_deg = values[&"elbow_bend_deg"]
	head_bob = values[&"head_bob"]


## Carrega o `.tres` gerado da postura, caindo para os valores de `Params` se faltar.
static func load_for(name: StringName) -> GaitProfile:
	var path: String = "%s/%s.tres" % [Params.GAIT_DIR, name]
	if ResourceLoader.exists(path):
		var loaded: GaitProfile = ResourceLoader.load(path) as GaitProfile
		if loaded != null:
			return loaded
	return from_posture(name)
