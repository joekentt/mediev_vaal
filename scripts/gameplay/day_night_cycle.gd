## Move o sol, o céu, a névoa e a luz de dentro das casas conforme a hora.
##
## É o único nó do projeto que escreve em `DirectionalLight3D`, em `Environment` e no
## material emissivo. Quem decide **o quê** é o `DayCycleProfile` gerado; quem decide
## **quando** é o `TimeSystem`; este arquivo só faz a ponte e trata dos dois detalhes que
## nenhum dos dois pode saber: que existe clima por cima, e que a cidade tem lampiões.
##
## Três coisas que valem estar escritas aqui, porque as três são decisão e não acaso:
##
## - **Não se aplica nada por quadro.** O ciclo só reescreve luz e cor quando a fração do
##   dia andou mais que `DAY_CYCLE_MIN_STEP`. Na velocidade normal isso é uma vez a cada
##   ~29 quadros; entre elas, o custo do nó é uma subtração. O degrau que essa economia
##   introduz é o **único** degrau possível no ciclo inteiro — e é exatamente ele que
##   `make daynight` mede. Durante uma virada de tempo o ciclo volta a aplicar todo quadro,
##   porque aí quem está andando é o clima e não o relógio.
## - **O sol nunca se apaga.** À noite ele é a lua: continua alto, com cor fria e um décimo
##   da energia. Apagar a única luz direcional do orçamento deixaria a cidade sem sombra
##   nenhuma, e sem sombra a noite lê como cinza chapado em cima de tudo.
## - **A noite acende um material, não mil janelas.** Toda carta de interior falso da
##   cidade divide um `StandardMaterial3D` só. Subir a emissão dele acende a cidade inteira
##   numa atribuição — e o mesmo material serve o vidro dos lampiões.
class_name DayNightCycle
extends Node

const TIME_SYSTEM_PATH: NodePath = ^"/root/TimeSystem"
## Meia volta em fração de dia. Usada para medir quanto o relógio andou sem que a virada
## da meia-noite conte como um dia inteiro de deslocamento.
const HALF_TURN: float = 0.5

var _profile: DayCycleProfile = null
var _sun: DirectionalLight3D = null
var _environment: Environment = null
var _sky: ProceduralSkyMaterial = null
var _glow: StandardMaterial3D = null
var _weather: WeatherSystem = null
var _time: Node = null

var _lanterns: Array[OmniLight3D] = []
var _lantern_glow: Node3D = null

var _last_fraction: float = -1.0
var _applied: Dictionary = {}
var _updates: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_time = get_node_or_null(TIME_SYSTEM_PATH)
	if _profile == null:
		_profile = load_profile()


## Carrega o perfil gerado. Pelo nome, como toda árvore de conversa: sem registro.
static func load_profile() -> DayCycleProfile:
	var path: String = "%s/ciclo.tres" % Params.DAY_CYCLE_DIR
	if not ResourceLoader.exists(path):
		push_warning("Ciclo do dia ausente: %s. Rode `make daycycle`." % path)
		return null
	var profile: DayCycleProfile = ResourceLoader.load(path) as DayCycleProfile
	if profile != null and not profile.is_complete():
		push_error("Ciclo do dia incompleto em %s: falta gradiente ou curva." % path)
	return profile


## Liga o ciclo ao que ele move. Chamado por `WorldGenerator`, que é quem tem os nós.
##
## Feito por injeção e não por busca na árvore pelo mesmo motivo do runner de diálogo: nas
## provas há cena sem céu e cena sem cidade, e um nó que dependesse de encontrar os dois
## ficaria mudo em metade delas.
func bind(sun: DirectionalLight3D, environment: Environment, weather: WeatherSystem) -> void:
	_sun = sun
	_environment = environment
	_weather = weather
	if environment != null and environment.sky != null:
		_sky = environment.sky.sky_material as ProceduralSkyMaterial
	_glow = MaterialLibrary.get_material(Params.GLOW_MATERIAL)
	_last_fraction = -1.0
	apply_now()


## Entrega os lampiões da cidade ao ciclo: as luzes pontuais e a malha do vidro aceso.
func bind_lanterns(lights: Array[OmniLight3D], glow: Node3D) -> void:
	_lanterns = lights
	_lantern_glow = glow
	_last_fraction = -1.0
	apply_now()


func _process(_delta: float) -> void:
	if _time == null:
		return
	var fraction: float = _time.get_day_fraction()
	var moved: float = absf(fposmod(fraction - _last_fraction + HALF_TURN, 1.0) - HALF_TURN)
	# O clima anda por conta própria: enquanto ele estiver virando, o ciclo acompanha todo
	# quadro. Fora disso, só quando o relógio andou o suficiente para a tela notar.
	var blending: bool = _weather != null and _weather.is_blending()
	if moved < Params.DAY_CYCLE_MIN_STEP and not blending:
		return
	_last_fraction = fraction
	_apply(fraction)


## Reaplica agora, ignorando o passo mínimo. Para quem acabou de saltar a hora.
func apply_now() -> void:
	if _time == null:
		_time = get_node_or_null(TIME_SYSTEM_PATH)
	if _time == null:
		return
	_last_fraction = _time.get_day_fraction()
	_apply(_last_fraction)


func _apply(fraction: float) -> void:
	if _profile == null:
		return
	var key: Dictionary = _profile.sample(fraction)
	var sky_state: Dictionary = {}
	if _weather != null:
		sky_state = _weather.modifiers()

	var sun_scale: float = float(sky_state.get(&"sun_scale", 1.0))
	var ambient_scale: float = float(sky_state.get(&"ambient_scale", 1.0))
	var fog_weather: float = float(sky_state.get(&"fog_scale", 1.0))
	var gray: float = float(sky_state.get(&"sky_gray", 0.0))
	var tint: Color = sky_state.get(&"fog_tint", Color.WHITE)
	var tint_amount: float = float(sky_state.get(&"fog_tint_amount", 0.0))

	var sun_color: Color = key[&"sun_color"]
	var sun_energy: float = float(key[&"sun_energy"]) * sun_scale
	if _sun != null:
		_sun.light_color = sun_color
		_sun.light_energy = sun_energy
		_sun.rotation = Vector3(
			-deg_to_rad(float(key[&"elevation"])), deg_to_rad(float(key[&"azimuth"])), 0.0
		)

	var zenith: Color = _desaturate(key[&"sky_zenith"], gray)
	var horizon: Color = _desaturate(key[&"sky_horizon"], gray)
	var fog: Color = (key[&"fog_color"] as Color).lerp(tint, tint_amount)
	if _sky != null:
		_sky.sky_top_color = zenith
		_sky.sky_horizon_color = horizon
		# O hemisfério de baixo do céu é névoa, não chão: é a faixa entre a linha dos
		# morros e o horizonte. Pintá-la com a cor da névoa da hora é o que faz a distância
		# escurecer junto com o resto em vez de continuar clara depois do pôr do sol.
		_sky.ground_bottom_color = fog
		_sky.ground_horizon_color = horizon

	if _environment != null:
		_environment.fog_light_color = fog
		_environment.fog_density = Params.FOG_DENSITY * float(key[&"fog_scale"]) * fog_weather
		_environment.ambient_light_energy = float(key[&"ambient"]) * ambient_scale

	var lit: float = lamp_level(float(key[&"light"]))
	_light_lamps(lit)

	_updates += 1
	_applied = {
		&"fraction": fraction,
		&"sun_color": sun_color,
		&"sun_energy": sun_energy,
		&"sky_zenith": zenith,
		&"sky_horizon": horizon,
		&"fog_color": fog,
		&"fog_density": Params.FOG_DENSITY * float(key[&"fog_scale"]) * fog_weather,
		&"ambient": float(key[&"ambient"]) * ambient_scale,
		&"elevation": float(key[&"elevation"]),
		&"lamps": lit,
	}


## Quanto os lampiões estão acesos, de 0 a 1, para um dado nível de luz do dia.
##
## Estático e público porque é a definição de "é noite" do projeto inteiro, e mais de um
## sistema pergunta isso. `smoothstep` e não um `if`: um limiar seco acenderia a cidade
## inteira num quadro, e a cidade inteira acendendo num quadro é o salto que a fase toda
## existe para não ter.
static func lamp_level(light: float) -> float:
	var on: float = Params.DAY_CYCLE_LIGHT_ON
	var fade: float = Params.DAY_CYCLE_LIGHT_FADE
	return 1.0 - smoothstep(on - fade, on + fade, light)


func _light_lamps(level: float) -> void:
	if _glow != null:
		_glow.emission_energy_multiplier = Params.GLOW_ENERGY * level
	for lamp: OmniLight3D in _lanterns:
		# Luz pontual apagada continua custando: o renderizador ainda a considera na lista
		# de luzes do agrupamento. Escondê-la a tira da conta.
		lamp.visible = level > 0.0
		lamp.light_energy = Params.DAY_CYCLE_LANTERN_ENERGY * level
	if _lantern_glow != null:
		_lantern_glow.visible = level > 0.0


static func _desaturate(color: Color, amount: float) -> Color:
	if amount <= 0.0:
		return color
	var flat: float = color.get_luminance()
	return color.lerp(Color(flat, flat, flat, color.a), amount)


## O último estado aplicado. É daqui que `make daynight` lê o que o jogador veria.
func state() -> Dictionary:
	return _applied


## Quantas vezes o ciclo reescreveu a iluminação. A prova compara com o número de quadros
## para mostrar que "sem custo por quadro" é afirmação medida, e não promessa.
func update_count() -> int:
	return _updates
