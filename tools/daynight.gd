## O dia inteiro em quatro segundos, medido quadro a quadro.
##
##     godot --headless --script res://tools/daynight.gd
##
## **Sem renderizador de propósito.** O critério da fase — "acelerar o tempo mostra
## transição contínua sem salto de cor" — é sobre os valores que alimentam o renderizador,
## não sobre os pixels que saem dele. Cor de céu, cor e energia do sol, cor e densidade da
## névoa são números escritos em `Environment` e em `DirectionalLight3D`, e um salto neles
## é um salto na tela. Medir com renderizador custaria meia hora de llvmpipe para
## responder a mesma pergunta com menos precisão.
##
## Seis medidas, e cada uma responde uma frase do enunciado:
##
## 1. **A varredura fina** amostra o dia em `DAYNIGHT_SAMPLES` pontos, reaplicando a cada
##    um, e mede a **velocidade** de mudança em cor por hora de jogo. Velocidade e não
##    degrau: o número tem de ser o mesmo com qualquer número de amostras. Um degrau de
##    verdade aparece como uma velocidade absurda, inclusive na virada da meia-noite, que é
##    a única emenda do laço.
## 2. **A corrida acelerada** roda o relógio a `DAYNIGHT_PROOF_SCALE` com passo fixo de
##    60 quadros por segundo e compara cada quadro com a interpolação ideal daquele mesmo
##    intervalo. O que se cobra é o **excesso**: a 360x a paleta do amanhecer tem de passar
##    em fração de segundo, e cobrar degrau por quadro seria cobrar que o amanhecer demore.
## 3. **O custo em repouso**: quantas vezes o ciclo reescreve a iluminação em 240 quadros
##    na velocidade do jogo. É "sem custo por quadro" medido, e não prometido.
## 4. **A noite acesa**: a emissão do material das janelas e o número de lampiões ligados
##    à 1h e ao meio-dia. "Acende à noite" vira dois números e a diferença entre eles.
## 5. **A praça vazia**: quantos habitantes estão na praça ao meio-dia e quantos à 1h,
##    depois de `DAYNIGHT_SETTLE_SECONDS` de simulação em cada hora. Sem a simulação a
##    medida seria de onde a agenda diz que eles deveriam estar, e não de onde eles estão.
## 6. **Os três climas**, um a um, com névoa, chuva e abafamento — a prova de que
##    "nublado" e "chuva" são estados diferentes de "ensolarado" em número, e não três
##    nomes na mesma tabela. Mais a virada num quadro só, que é um defeito que esta prova
##    encontrou e que agora ela vigia.
extends SceneTree

const RESULT_PREFIX: String = "MEDIEV_DAYNIGHT "
const BAKE_TIMEOUT_FRAMES: int = 2400

var _stage: Node3D = null
var _cycle: DayNightCycle = null
var _weather: WeatherSystem = null
var _time: Node = null
var _npcs: Array[NPCController] = []
var _plaza: Vector3 = Vector3.ZERO
var _profile: DayCycleProfile = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	WorldGenerator.build_stage(_stage, false)

	_time = root.get_node_or_null(^"TimeSystem")
	_cycle = _find(_stage, "DayNight") as DayNightCycle
	_weather = _find(_stage, "Weather") as WeatherSystem
	if _time == null or _cycle == null:
		printerr("Ciclo do dia ausente na cena montada.")
		quit(1)
		return

	var layout: CityLayout = WorldGenerator.last_city
	if layout != null:
		_plaza = layout.markers[&"praca"]
	await _wait_for_bake(_find_region(_stage))
	_collect(_stage)

	_profile = DayNightCycle.load_profile()
	var sweep: Dictionary = _sweep()
	var accelerated: Dictionary = await _accelerate()
	var idle: Dictionary = await _idle_cost()
	var lights: Dictionary = await _lights()
	var plaza: Dictionary = await _plaza_watch()
	var weather: Array = await _weathers()
	var hitch: Dictionary = await _hitch()

	print(RESULT_PREFIX + JSON.stringify({
		"seconds_per_day": _time.seconds_per_day,
		"periods": Params.PERIOD_NAMES,
		"keys": Params.DAY_CYCLE_KEYS.size(),
		"sweep": sweep,
		"run": accelerated,
		"idle": idle,
		"lights": lights,
		"plaza": plaza,
		"weather": weather,
		"hitch": hitch,
		"max_color_rate": Params.DAYNIGHT_MAX_COLOR_RATE,
		"max_energy_rate": Params.DAYNIGHT_MAX_ENERGY_RATE,
		"max_color_step": Params.DAYNIGHT_MAX_COLOR_STEP,
		"max_energy_step": Params.DAYNIGHT_MAX_ENERGY_STEP,
		"max_night_plaza": Params.DAYNIGHT_MAX_NIGHT_PLAZA,
	}))
	quit(0)


## A virada do tempo num quadro longo.
##
## Este teste existe por um defeito que esta prova encontrou: sem teto no avanço por
## quadro, um único quadro com `delta` grande — e um quadro grande acontece, basta um
## carregamento — completava os doze segundos da transição de uma vez, e o céu saltava de
## ensolarado para chuva instantaneamente. Aqui a transição é pedida e um quadro só é
## rodado: se ela terminar nesse quadro, o teto não está fazendo o trabalho dele.
func _hitch() -> Dictionary:
	if _weather == null:
		return {"checked": false}
	_weather.set_auto(false)
	_weather.set_weather(Params.WEATHER_START, true)
	await process_frame

	var other: StringName = Params.WEATHER_IDS[Params.WEATHER_IDS.size() - 1]
	_weather.set_weather(other)
	await process_frame
	var after_one: float = _weather.blend_progress()
	_weather.set_weather(Params.WEATHER_START, true)
	_weather.set_auto(true)
	return {
		"checked": true,
		"to": String(other),
		"after_one_frame": after_one,
		"seconds": Params.WEATHER_BLEND_SECONDS,
		"max_step": Params.WEATHER_BLEND_MAX_STEP,
	}


# --- 1. Varredura fina do dado ------------------------------------------------


func _sweep() -> Dictionary:
	var samples: int = Params.DAYNIGHT_SAMPLES
	var hours_per_sample: float = float(Params.HOURS_PER_DAY) / float(samples)
	var states: Array[Dictionary] = []
	for index: int in samples:
		_time.set_time_of_day(float(index) * hours_per_sample)
		_cycle.apply_now()
		states.append(_cycle.state().duplicate())

	var worst_color: float = 0.0
	var worst_energy: float = 0.0
	var worst_hour: float = 0.0
	for index: int in samples:
		# O último ponto compara com o primeiro: a virada da meia-noite é uma emenda como
		# qualquer outra, e é a que ninguém está olhando quando quebra.
		var step: Dictionary = _difference(states[index], states[(index + 1) % samples])
		# Dividido pelo intervalo: o que se mede é velocidade de mudança, em cor por hora
		# de jogo. Sem dividir, o número dependeria de quantas amostras se tirou.
		var rate: float = float(step["color"]) / hours_per_sample
		if rate > worst_color:
			worst_color = rate
			worst_hour = float(index) * hours_per_sample
		worst_energy = maxf(worst_energy, float(step["energy"]) / hours_per_sample)

	var midnight: Dictionary = _difference(states[samples - 1], states[0])
	return {
		"samples": samples,
		"max_color_rate": worst_color,
		"max_energy_rate": worst_energy,
		"worst_at_hour": worst_hour,
		"midnight_color": midnight["color"],
		"midnight_energy": midnight["energy"],
		"strip": _strip(states),
	}


## A varredura em forma de tira, para `daynight.py` desenhar `docs/daynight/dia.png`.
##
## A fase mede sem renderizador, e mesmo assim precisa de olhos: a tira é desenhada com os
## mesmos valores medidos aqui. Um salto de cor vira uma listra visível antes de virar um
## número reprovado — e listra é o que se vê sem ler nada.
static func _strip(states: Array[Dictionary]) -> Dictionary:
	var zenith: PackedStringArray = PackedStringArray()
	var horizon: PackedStringArray = PackedStringArray()
	var fog: PackedStringArray = PackedStringArray()
	var sun: PackedStringArray = PackedStringArray()
	var energy: PackedFloat32Array = PackedFloat32Array()
	var lamps: PackedFloat32Array = PackedFloat32Array()
	for state: Dictionary in states:
		zenith.append((state[&"sky_zenith"] as Color).to_html(false))
		horizon.append((state[&"sky_horizon"] as Color).to_html(false))
		fog.append((state[&"fog_color"] as Color).to_html(false))
		sun.append((state[&"sun_color"] as Color).to_html(false))
		energy.append(float(state[&"sun_energy"]))
		lamps.append(float(state[&"lamps"]))
	return {
		"zenith": zenith, "horizon": horizon, "fog": fog, "sun": sun,
		"energy": energy, "lamps": lamps,
	}


## Maior diferença por canal entre dois estados, e a diferença de energia do sol.
##
## Por canal e não em distância: o olho vê banda num canal só, e uma média de três canais
## esconderia um degrau de azul dentro de dois canais parados.
static func _difference(before: Dictionary, after: Dictionary) -> Dictionary:
	if before.is_empty() or after.is_empty():
		return {"color": 0.0, "energy": 0.0}
	var worst: float = 0.0
	for key: StringName in [&"sun_color", &"sky_zenith", &"sky_horizon", &"fog_color"]:
		var a: Color = before[key]
		var b: Color = after[key]
		worst = maxf(worst, absf(a.r - b.r))
		worst = maxf(worst, absf(a.g - b.g))
		worst = maxf(worst, absf(a.b - b.b))
	return {
		"color": worst,
		"energy": absf(float(before[&"sun_energy"]) - float(after[&"sun_energy"])),
	}


# --- 2. O dia acelerado, como o jogador o veria -------------------------------


## O dia inteiro acelerado, comparado quadro a quadro com a interpolação ideal.
##
## O que se mede não é quanto a cor andou — a 360x ela **tem** de andar depressa, e cobrar
## o contrário seria cobrar que o amanhecer demore. O que se mede é quanto ela andou
## **além** do que a interpolação pedia naquele mesmo intervalo. Esse excesso é o salto que
## o sistema introduz, e é a única coisa que o jogador leria como corte.
##
## O clima fica travado durante a medida: ele multiplica a luz e tem prova própria logo
## abaixo. Uma nuvem entrando no meio da varredura mediria as duas coisas juntas e não
## diria qual delas saltou.
func _accelerate() -> Dictionary:
	if _weather != null:
		_weather.set_auto(false)
		_weather.set_weather(Params.WEATHER_START, true)

	# O relógio é movido à mão, com passo fixo de um quadro de 60 Hz. Deixá-lo correr
	# sozinho mediria a velocidade deste contêiner: sem renderizador o Godot roda a
	# centenas de quadros por segundo, e o passo de tempo entre eles não é o de um jogo.
	_time.clock_paused = true
	_time.set_time_of_day(0.0)
	_cycle.apply_now()

	var per_frame: float = float(Params.HOURS_PER_DAY) * Params.DAYNIGHT_PROOF_SCALE \
		/ (float(Params.PHYSICS_TICKS_PER_SECOND) * _time.seconds_per_day)
	var frames: int = int(ceil(float(Params.HOURS_PER_DAY) / per_frame))

	var previous: Dictionary = _cycle.state().duplicate()
	var previous_hour: float = 0.0
	var before_updates: int = _cycle.update_count()
	var worst_excess: float = 0.0
	var worst_energy: float = 0.0
	var worst_hour: float = 0.0
	var worst_step: float = 0.0

	for frame: int in frames:
		var hour: float = float(frame) * per_frame
		_time.set_time_of_day(hour)
		await process_frame
		var now: Dictionary = _cycle.state()
		var applied: Dictionary = _difference(previous, now)
		var ideal: Dictionary = _ideal(previous_hour, hour)

		var excess: float = float(applied["color"]) - float(ideal["color"])
		if excess > worst_excess:
			worst_excess = excess
			worst_hour = hour
		worst_energy = maxf(worst_energy, float(applied["energy"]) - float(ideal["energy"]))
		worst_step = maxf(worst_step, float(applied["color"]))
		previous = now.duplicate()
		previous_hour = hour

	var updates: int = _cycle.update_count() - before_updates
	_time.clock_paused = false
	if _weather != null:
		_weather.set_auto(true)
	return {
		"scale": Params.DAYNIGHT_PROOF_SCALE,
		"frames": frames,
		"updates": updates,
		"max_excess": worst_excess,
		"max_energy_excess": worst_energy,
		"max_step": worst_step,
		"worst_at_hour": worst_hour,
		"real_seconds": _time.seconds_per_day / Params.DAYNIGHT_PROOF_SCALE,
	}


## O que a interpolação pediria entre duas horas, lido direto do perfil gerado.
##
## É a régua da medida acima: sem ela não há como separar "a paleta anda depressa porque o
## tempo está acelerado" de "o sistema deu um pulo".
func _ideal(from_hour: float, to_hour: float) -> Dictionary:
	if _profile == null:
		return {"color": 0.0, "energy": 0.0}
	var day: float = float(Params.HOURS_PER_DAY)
	var before: Dictionary = _profile.sample(from_hour / day)
	var after: Dictionary = _profile.sample(to_hour / day)
	return _difference(before, after)


## O ciclo em velocidade normal: quantas vezes ele reescreve a iluminação em N quadros.
##
## É a medida de "sem custo por quadro além da interpolação". Na velocidade do jogo, o dia
## anda tão devagar que reaplicar toda vez seria trabalho para uma diferença que não cabe
## em oito bits de cor.
func _idle_cost() -> Dictionary:
	_time.clock_paused = true
	_time.set_time_of_day(Params.DAYNIGHT_DAY_HOUR)
	_cycle.apply_now()

	var per_frame: float = float(Params.HOURS_PER_DAY) \
		/ (float(Params.PHYSICS_TICKS_PER_SECOND) * _time.seconds_per_day)
	var before: int = _cycle.update_count()
	for frame: int in Params.DAYNIGHT_IDLE_FRAMES:
		_time.set_time_of_day(Params.DAYNIGHT_DAY_HOUR + float(frame) * per_frame)
		await process_frame
	_time.clock_paused = false
	var updates: int = _cycle.update_count() - before
	return {
		"frames": Params.DAYNIGHT_IDLE_FRAMES,
		"updates": updates,
		"frames_per_update": float(Params.DAYNIGHT_IDLE_FRAMES) / float(maxi(updates, 1)),
	}


# --- 3. A noite acesa ---------------------------------------------------------


func _lights() -> Dictionary:
	var day: Dictionary = await _lights_at(Params.DAYNIGHT_DAY_HOUR)
	var night: Dictionary = await _lights_at(Params.DAYNIGHT_NIGHT_HOUR)
	return {"day": day, "night": night}


func _lights_at(hour: float) -> Dictionary:
	_time.set_time_of_day(hour)
	_cycle.apply_now()
	await process_frame
	var glow: StandardMaterial3D = MaterialLibrary.get_material(Params.GLOW_MATERIAL)
	var lit: int = 0
	for lamp: Node in _lamps():
		if (lamp as OmniLight3D).visible:
			lit += 1
	return {
		"hour": hour,
		"emission": glow.emission_energy_multiplier if glow != null else 0.0,
		"lamps_on": lit,
		"lamps_total": _lamps().size(),
		"sun_energy": float(_cycle.state().get(&"sun_energy", 0.0)),
		"period": String(_time.get_period_name()),
	}


func _lamps() -> Array[Node]:
	var found: Array[Node] = []
	var city: Node = _stage.find_child("City", true, false)
	if city == null:
		return found
	for child: Node in city.get_children():
		if child is OmniLight3D:
			found.append(child)
	return found


# --- 4. A praça ---------------------------------------------------------------


func _plaza_watch() -> Dictionary:
	var day: int = await _plaza_count(Params.DAYNIGHT_DAY_HOUR)
	var night: int = await _plaza_count(Params.DAYNIGHT_NIGHT_HOUR)
	return {
		"npcs": _npcs.size(),
		"at_noon": day,
		"at_night": night,
		"night_fraction": float(night) / float(maxi(_npcs.size(), 1)),
		"settle_seconds": Params.DAYNIGHT_SETTLE_SECONDS,
	}


## Quantos habitantes estão na praça depois de a cidade responder à hora.
##
## O relógio fica parado durante o assentamento de propósito: com ele andando, setenta
## segundos reais são mais de uma hora de jogo e metade da população trocaria de bloco de
## agenda no meio da medida — o que se mediria então seria a travessia, não o destino.
func _plaza_count(hour: float) -> int:
	_time.clock_paused = true
	_time.set_time_of_day(hour)
	_cycle.apply_now()

	var frames: int = int(Params.DAYNIGHT_SETTLE_SECONDS * float(Params.PHYSICS_TICKS_PER_SECOND))
	for _frame: int in frames:
		await physics_frame

	var reach: float = Params.CITY_PLAZA_RADIUS + Params.NPC_TARGET_SPREAD
	var inside: int = 0
	for npc: NPCController in _npcs:
		var spot: Vector3 = npc.global_position
		if Vector2(spot.x, spot.z).distance_to(Vector2(_plaza.x, _plaza.z)) <= reach:
			inside += 1
	_time.clock_paused = false
	return inside


# --- 5. Os três climas --------------------------------------------------------


func _weathers() -> Array:
	var out: Array = []
	if _weather == null:
		return out
	var environment: Environment = _environment()
	_time.set_time_of_day(Params.DAYNIGHT_DAY_HOUR)
	for id: StringName in Params.WEATHER_IDS:
		_weather.set_weather(id, true)
		_cycle.apply_now()
		await process_frame
		out.append({
			"id": String(id),
			"fog_density": environment.fog_density if environment != null else 0.0,
			"sun_energy": float(_cycle.state().get(&"sun_energy", 0.0)),
			"rain": _weather.rain_amount(),
			"muffle_hz": _weather.muffle_hz(),
		})
	_weather.set_weather(Params.WEATHER_START, true)
	return out


func _environment() -> Environment:
	var node: Node = _stage.find_child("WorldEnvironment", true, false)
	return (node as WorldEnvironment).environment if node is WorldEnvironment else null


# --- Utilidades ---------------------------------------------------------------


func _collect(node: Node) -> void:
	if node is NPCController:
		_npcs.append(node as NPCController)
	for child: Node in node.get_children():
		_collect(child)


static func _find(node: Node, wanted: String) -> Node:
	return node.find_child(wanted, true, false)


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
	await physics_frame
