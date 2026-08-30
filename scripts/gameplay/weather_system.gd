## O tempo que faz: ensolarado, nublado e chuva.
##
## O clima não escreve iluminação. Ele publica multiplicadores, e quem os aplica é o
## `DayNightCycle` — é o que faz "nublado" continuar tendo hora do dia dentro. As três
## únicas coisas que este nó mexe sozinho são as que o ciclo não tem: a chuva que cai, o
## corte do passa-baixa dos barramentos e o volume do leito de ambiência.
##
## **A chuva acompanha a câmera e não o mundo.** Uma caixa de 26 m em volta de quem olha,
## com novecentas gotas, é chuva em toda a tela; chover no vale inteiro seria simular
## milhões de gotas para que 99,99% delas caíssem onde ninguém está. É o mesmo truque que
## todo jogo de mundo aberto usa, e o motivo de ele funcionar é que gota nenhuma é
## identificável individualmente.
##
## **A virada leva `WEATHER_BLEND_SECONDS`.** Doze segundos é lento de propósito: o céu de
## verdade não pisca, e o defeito que se vê num clima procedural mal feito não é a chuva —
## é a chuva *começando* de uma vez.
class_name WeatherSystem
extends Node3D

const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"
const AUDIO_MANAGER_PATH: NodePath = ^"/root/AudioManager"
const HALF: float = 0.5

var _profiles: Dictionary = {}
var _from: WeatherProfile = null
var _to: WeatherProfile = null
var _blend: float = 1.0
var _modifiers: Dictionary = {}

var _rain: GPUParticles3D = null
var _focus: Node3D = null
var _audio: Node = null
var _muffle: float = Params.AUDIO_FILTER_MAX_HZ
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_audio = get_node_or_null(AUDIO_MANAGER_PATH)
	_load_profiles()
	_build_rain()

	_to = _profiles.get(Params.WEATHER_START)
	_from = _to
	_blend = 1.0
	_modifiers = WeatherProfile.blend(_from, _to, 1.0)
	_apply(0.0)

	var bus: Node = get_node_or_null(EVENT_BUS_PATH)
	if bus != null:
		# O sorteio do tempo pendura-se na hora anunciada, e não num temporizador próprio:
		# um clima que virasse a cada tantos segundos ignoraria que o jogo tem relógio.
		bus.hour_changed.connect(_on_hour_changed)


func seed_with(world_seed: int) -> void:
	_rng.seed = world_seed + SEED_OFFSET


const SEED_OFFSET: int = 60413


func _load_profiles() -> void:
	for id: StringName in Params.WEATHER_IDS:
		var path: String = "%s/%s.tres" % [Params.WEATHER_DIR, id]
		if not ResourceLoader.exists(path):
			push_warning("Clima ausente: %s. Rode `make daycycle`." % path)
			continue
		var profile: WeatherProfile = ResourceLoader.load(path) as WeatherProfile
		if profile != null:
			_profiles[id] = profile


# --- Estado -------------------------------------------------------------------


## Multiplicadores do clima agora, já misturados se houver virada em curso.
func modifiers() -> Dictionary:
	return _modifiers


func is_blending() -> bool:
	return _blend < 1.0


func current() -> StringName:
	return _to.id if _to != null else &""


func previous() -> StringName:
	return _from.id if _from != null else &""


## Quanto da virada já andou, de 0 a 1. A prova lê daqui.
func blend_progress() -> float:
	return _blend


## Corte do passa-baixa agora, em Hz. É o "abafado" em número.
func muffle_hz() -> float:
	return _muffle


## Quem a chuva acompanha quando não há câmera — as provas rodam sem renderizador.
func set_focus(node: Node3D) -> void:
	_focus = node


# --- Virada -------------------------------------------------------------------


## Troca o tempo. `immediate` corta a transição, e serve à prova, não ao jogo.
func set_weather(id: StringName, immediate: bool = false) -> void:
	if not _profiles.has(id):
		push_warning("Clima inexistente: %s" % id)
		return
	if _to != null and _to.id == id and not is_blending():
		return
	# O ponto de partida é o **estado misturado atual**, não o clima anterior inteiro:
	# virar o tempo no meio de uma virada tem de continuar de onde a tela está.
	_from = _to
	_to = _profiles[id]
	_blend = 1.0 if immediate else 0.0
	if immediate:
		_modifiers = _to.as_dictionary()
		_apply(0.0)
	var bus: Node = get_node_or_null(EVENT_BUS_PATH)
	if bus != null:
		bus.weather_changed.emit(_to.id, _to.label)


## Liga e desliga o sorteio de tempo por hora. A prova do ciclo desliga para medir a luz
## do dia sem que uma nuvem entre no meio da medida — o clima tem prova própria.
func set_auto(enabled: bool) -> void:
	_auto = enabled


var _auto: bool = true


func _on_hour_changed(_hour: int) -> void:
	if not _auto or _rng.randf() >= Params.WEATHER_CHANGE_CHANCE:
		return
	set_weather(_roll())


## Sorteio com peso. O clima novo pode ser o mesmo de agora — e quando é, `set_weather`
## devolve sem fazer nada, que é o comportamento certo: o tempo continua como estava.
func _roll() -> StringName:
	var total: float = 0.0
	for id: StringName in Params.WEATHER_IDS:
		total += float(Params.WEATHER_WEIGHTS.get(id, 0.0))
	if total <= 0.0:
		return current()
	var pick: float = _rng.randf() * total
	for id: StringName in Params.WEATHER_IDS:
		pick -= float(Params.WEATHER_WEIGHTS.get(id, 0.0))
		if pick <= 0.0:
			return id
	return Params.WEATHER_IDS[Params.WEATHER_IDS.size() - 1]


func _process(delta: float) -> void:
	# O avanço da virada tem teto por quadro, e isso foi aprendido medindo. Um quadro longo
	# — um carregamento, o assado da navegação terminando, a janela voltando do alt-tab —
	# chega com `delta` de vários segundos, e sem teto ele completa a transição inteira de
	# uma vez: o céu salta de ensolarado para chuva num quadro. `make daynight` mediu isso
	# como 0,78 de energia de sol e 0,18 de cor num quadro só.
	var step: float = minf(delta, Params.WEATHER_BLEND_MAX_STEP)
	if _blend < 1.0 and Params.WEATHER_BLEND_SECONDS > 0.0:
		_blend = minf(_blend + step / Params.WEATHER_BLEND_SECONDS, 1.0)
		_modifiers = WeatherProfile.blend(_from, _to, _blend)
	_apply(step)


func _apply(delta: float) -> void:
	if _modifiers.is_empty():
		return
	_follow_focus()

	var wanted: float = float(_modifiers.get(&"rain", 0.0))
	if _rain != null:
		_rain.amount_ratio = clampf(wanted, 0.0, 1.0)
		_rain.emitting = wanted > 0.0

	# O corte do filtro persegue o alvo em vez de saltar: um passa-baixa que fecha de uma
	# vez soa como alguém tapando o microfone, não como chuva chegando.
	var target: float = float(_modifiers.get(&"muffle_hz", Params.AUDIO_FILTER_MAX_HZ))
	var step: float = clampf(delta * Params.AUDIO_MUFFLE_LERP, 0.0, 1.0)
	_muffle = lerpf(_muffle, target, step) if delta > 0.0 else target
	if _audio != null:
		_audio.set_muffle(_muffle)
		_audio.set_ambience_trim(float(_modifiers.get(&"ambience_db", 0.0)))


func _follow_focus() -> void:
	if _rain == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var spot: Vector3 = Vector3.ZERO
	if camera != null:
		spot = camera.global_position
	elif _focus != null:
		spot = _focus.global_position
	else:
		return
	# Só a posição acompanha, nunca a rotação: uma caixa de chuva que gira com a câmera faz
	# as gotas girarem junto, e o efeito entrega o truque no primeiro movimento de mouse.
	global_position = spot


# --- Chuva --------------------------------------------------------------------


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = Params.WEATHER_RAIN_PARTICLES
	_rain.amount_ratio = 0.0
	_rain.emitting = false
	_rain.lifetime = Params.WEATHER_RAIN_HEIGHT / Params.WEATHER_RAIN_SPEED
	# A gota nasce no teto da caixa e cai até a altura de quem olha.
	_rain.position = Vector3(0.0, Params.WEATHER_RAIN_HEIGHT, 0.0)
	# Coordenadas de mundo, e não locais: com locais, a chuva já caída viaja junto com a
	# câmera e as gotas ficam paradas em relação a quem anda — o oposto de chover.
	_rain.local_coords = false
	_rain.draw_pass_1 = _drop_mesh()
	_rain.process_material = _rain_material()
	_rain.material_override = _rain_surface()
	# Gota não projeta sombra, não recebe sombra e não entra em oclusão. Novecentas gotas
	# com sombra seriam novecentos casters por cascata para escurecer nada.
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


func _rain_material() -> ParticleProcessMaterial:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var half: float = Params.WEATHER_RAIN_BOX * HALF
	process.emission_box_extents = Vector3(half, 0.0, half)
	process.direction = Vector3.DOWN
	process.spread = 0.0
	process.initial_velocity_min = Params.WEATHER_RAIN_SPEED
	process.initial_velocity_max = Params.WEATHER_RAIN_SPEED
	process.gravity = Vector3(Params.WEATHER_RAIN_SLANT, 0.0, 0.0)
	process.scale_min = 1.0
	process.scale_max = 1.0
	return process


func _rain_surface() -> StandardMaterial3D:
	var material: StandardMaterial3D = MaterialLibrary.get_material(Params.RAIN_MATERIAL)
	# A chuva é o único emissivo que não obedece à hora: gota tem de ser visível na
	# tempestade das duas da tarde e na das duas da manhã.
	material.emission_energy_multiplier = Params.RAIN_ENERGY
	return material


## O risco de uma gota: uma caixa fina e comprida. Duas faces bastariam, mas uma caixa é
## o que o construtor de malha já sabe fazer e custa doze triângulos que nunca serão vistos
## de perto.
func _drop_mesh() -> Mesh:
	var builder: MeshBuilder = MeshBuilder.new()
	builder.add_box(
		Vector3.ZERO,
		Vector3(
			Params.WEATHER_RAIN_WIDTH, Params.WEATHER_RAIN_LENGTH, Params.WEATHER_RAIN_WIDTH
		),
		Params.color(&"rain")
	)
	return builder.commit(&"prop")


## Quantas gotas estão no ar agora. A prova lê daqui — "está chovendo" é um número.
func rain_amount() -> float:
	return _rain.amount_ratio if _rain != null else 0.0
