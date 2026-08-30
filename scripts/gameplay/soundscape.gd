## Decide em que zona sonora o ouvinte está, e que tema toca.
##
## A divisão de trabalho é a de sempre: o `AudioManager` sabe misturar dois leitos e não
## sabe onde ninguém está; este nó sabe onde o ouvinte está e não sabe misturar nada.
##
## **A zona não é lida por quadro.** Um temporizador a `AUDIO_ZONE_POLL_HZ` basta para uma
## fronteira que se atravessa andando a 3 m/s — quatro decisões por segundo dão no máximo
## 75 cm de atraso, e o crossfade que vem depois leva dois segundos. Testar a cada quadro
## seria 60 vezes o trabalho para adiantar a decisão em 15 centésimos.
##
## **A fronteira tem histerese.** Sem ela, parar em cima da linha da muralha alterna leito
## sonoro quatro vezes por segundo — e o crossfade de dois segundos nunca chega ao fim,
## então o que se ouve é um pêndulo. Com `AUDIO_ZONE_HYSTERESIS`, sair custa seis metros a
## mais do que entrar.
##
## O interior é medido contra a caixa dos prédios que **têm** interior de verdade. Os
## outros são fachada com carta escura atrás da janela: entrar neles é impossível, e
## abafar o som ao encostar num deles seria abafar por causa de um cômodo que não existe.
class_name Soundscape
extends Node

const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"
const AUDIO_MANAGER_PATH: NodePath = ^"/root/AudioManager"
const TIME_SYSTEM_PATH: NodePath = ^"/root/TimeSystem"
const ZONE_FOREST: StringName = &"floresta"
const ZONE_CITY: StringName = &"cidade"
const ZONE_INTERIOR: StringName = &"interior"
const HALF: float = 0.5

var _layout: CityLayout = null
var _listener: Node3D = null
var _audio: Node = null
var _time: Node = null
var _weather: WeatherSystem = null
var _timer: Timer = null
var _zone: StringName = &""
var _interiors: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_audio = get_node_or_null(AUDIO_MANAGER_PATH)
	_time = get_node_or_null(TIME_SYSTEM_PATH)

	_timer = Timer.new()
	_timer.name = "Poll"
	_timer.wait_time = 1.0 / Params.AUDIO_ZONE_POLL_HZ
	_timer.timeout.connect(_poll)
	add_child(_timer)
	_timer.start()

	var bus: Node = get_node_or_null(EVENT_BUS_PATH)
	if bus != null:
		# O tema muda com o período, e o período chega por sinal: perguntar a hora a cada
		# volta do temporizador seria perguntar quatro vezes por segundo o que muda de hora
		# em hora.
		bus.day_period_changed.connect(_on_period_changed)

	# Os nomes das zonas são o caminho dos leitos gerados (`ambiencia/<zona>.wav`). Se um
	# deles não estiver em `AUDIO_ZONES`, `make audio` não gerou leito para ele e a zona
	# entraria muda — falha silenciosa, que é a pior espécie.
	for zone_id: StringName in [ZONE_FOREST, ZONE_CITY, ZONE_INTERIOR]:
		if not Params.AUDIO_ZONES.has(zone_id):
			push_error("Zona sonora sem leito gerado: %s. Confira AUDIO_ZONES." % zone_id)


## Liga a paisagem sonora ao mundo. Sem cidade, tudo é floresta — que é o certo para o
## estágio plano das provas de locomoção.
func bind(layout: CityLayout, listener: Node3D, weather: WeatherSystem) -> void:
	_layout = layout
	_listener = listener
	_weather = weather
	_interiors.clear()
	if layout != null:
		for building: Dictionary in layout.buildings:
			if Params.CITY_INTERIOR_TYPES.has(StringName(building["type"])):
				_interiors.append(building)
	_poll()


## Quem a paisagem escuta. Nas provas não há jogador, e o ouvinte é um nó qualquer.
func set_listener(node: Node3D) -> void:
	_listener = node
	_poll()


func zone() -> StringName:
	return _zone


## Força uma decisão agora, sem esperar o temporizador. A prova usa ao teleportar.
func poll_now() -> void:
	_poll()


func _poll() -> void:
	var wanted: StringName = _decide()
	if wanted == _zone:
		return
	_zone = wanted
	if _audio != null:
		_audio.set_zone(wanted)
	_refresh_music()


func _decide() -> StringName:
	if _listener == null or not _listener.is_inside_tree():
		return Params.AUDIO_ZONE_START
	var spot: Vector3 = _listener.global_position
	if _inside_interior(spot):
		return ZONE_INTERIOR
	if _layout == null:
		return ZONE_FOREST

	var reach: float = Params.CITY_RADIUS + Params.CITY_WALL_MARGIN
	# Sair custa mais que entrar: é a histerese, e é o que impede o pêndulo na muralha.
	if _zone == ZONE_CITY or _zone == ZONE_INTERIOR:
		reach += Params.AUDIO_ZONE_HYSTERESIS
	var flat: Vector2 = Vector2(spot.x, spot.z)
	return ZONE_CITY if flat.distance_to(_layout.center) <= reach else ZONE_FOREST


func _inside_interior(spot: Vector3) -> bool:
	if _layout == null or _interiors.is_empty():
		return false
	var local: Vector2 = _layout.to_local(Vector2(spot.x, spot.z))
	for building: Dictionary in _interiors:
		var rect: Rect2 = building["rect"]
		if not rect.has_point(local):
			continue
		# A altura também conta: de cima do telhado não se está dentro da taverna.
		var top: float = _layout.ground_y + float(building["floors"]) * Params.CITY_FLOOR_HEIGHT
		if spot.y <= top and spot.y >= _layout.ground_y - Params.NAV_AGENT_HEIGHT:
			return true
	return false


func _on_period_changed(_period: int) -> void:
	_refresh_music()


func _refresh_music() -> void:
	if _audio != null:
		_audio.play_music_context(music_context())


## Que tema toca agora. A noite vence a cidade: uma praça vazia às três da manhã não pede
## o tema de praça cheia, e é a mesma razão pela qual a madrugada é um período separado.
func music_context() -> StringName:
	if _time != null and Params.MUSIC_NIGHT_PERIODS.has(_time.get_period_name()):
		return Params.MUSIC_CONTEXTS[2]
	if _zone == ZONE_CITY or _zone == ZONE_INTERIOR:
		return Params.MUSIC_CONTEXTS[1]
	return Params.MUSIC_CONTEXTS[0]


## Estado inteiro, para o relatório da prova.
func state() -> Dictionary:
	var mix: Dictionary = _audio.zone_mix() if _audio != null else {}
	return {
		&"zone": _zone,
		&"music": _audio.music_context() if _audio != null else &"",
		&"muffle_hz": _audio.muffle_hz() if _audio != null else 0.0,
		&"weather": _weather.current() if _weather != null else &"",
		&"mix": mix,
	}
