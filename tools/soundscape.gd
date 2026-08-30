## Entrar e sair da cidade, medindo o volume quadro a quadro.
##
##     godot --headless --audio-driver Dummy --script res://tools/soundscape.gd
##
## O critério da fase é "o som muda ao entrar e sair da cidade sem corte perceptível", e
## corte é uma coisa medível: é o volume caindo no meio da troca. O ouvinte atravessa a
## muralha nos dois sentidos e, a cada amostra, se registra o ganho de cada leito e a soma
## **em potência** dos dois — que é o que o ouvido escuta como volume.
##
## Duas coisas reprovam:
##
## - **O buraco**: a potência somada cair abaixo de `SOUNDSCAPE_MIN_TOTAL` em qualquer
##   amostra. Um crossfade linear em amplitude — o que se escreve sem pensar — afunda para
##   0,707 no meio; um de potência constante fica em 1,0. O teto está entre os dois.
## - **O salto**: a potência mudar mais que `SOUNDSCAPE_MAX_STEP` de uma amostra para a
##   seguinte. É o que pega um "para o leito antigo e começa o novo" disfarçado de fade.
##
## Sem renderizador e com driver de áudio mudo: o que se mede são os ganhos que o
## `AudioManager` escreve nos players, e eles são os mesmos com ou sem placa de som. De
## quebra, todo arquivo do manifesto é carregado — é a prova de que `make audio` produziu
## um banco que o Godot de fato importa, e não quarenta arquivos que só existem no disco.
extends SceneTree

const RESULT_PREFIX: String = "MEDIEV_SOUNDSCAPE "
const BAKE_TIMEOUT_FRAMES: int = 2400
const MS_PER_SECOND: float = 1000.0
const HALF: float = 0.5

var _stage: Node3D = null
var _soundscape: Soundscape = null
var _audio: Node = null
var _listener: Node3D = null
var _layout: CityLayout = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	WorldGenerator.build_stage(_stage, false)

	_audio = root.get_node_or_null(^"AudioManager")
	_soundscape = _stage.find_child("Soundscape", true, false) as Soundscape
	_layout = WorldGenerator.last_city
	if _audio == null or _soundscape == null or _layout == null:
		printerr("Paisagem sonora ausente na cena montada.")
		quit(1)
		return

	_listener = Node3D.new()
	_listener.name = "Ouvinte"
	_stage.add_child(_listener)
	_soundscape.set_listener(_listener)

	await _wait_for_bake(_find_region(_stage))

	var outside: Vector3 = _outside()
	var plaza: Vector3 = _layout.markers[&"praca"]

	_listener.global_position = outside
	_soundscape.poll_now()
	await _settle()

	var going: Dictionary = await _travel(outside, plaza)
	await _settle()
	var coming: Dictionary = await _travel(plaza, outside)
	await _settle()
	var inside: Dictionary = await _interior()

	print(RESULT_PREFIX + JSON.stringify({
		"crossfade_target": Params.AUDIO_ZONE_CROSSFADE,
		"min_total": Params.SOUNDSCAPE_MIN_TOTAL,
		"max_step": Params.SOUNDSCAPE_MAX_STEP,
		"tolerance": Params.SOUNDSCAPE_CROSSFADE_TOLERANCE,
		"entering": going,
		"leaving": coming,
		"interior": inside,
		"bank": _bank(),
	}))
	quit(0)


## Um ponto claramente fora da cidade, na direção do portão. Longe o bastante para a
## histerese não ter dúvida, perto o bastante para a travessia caber em seis segundos.
func _outside() -> Vector3:
	var reach: float = Params.CITY_RADIUS + Params.CITY_WALL_MARGIN \
		+ Params.AUDIO_ZONE_HYSTERESIS * 2.0
	var spot: Vector2 = _layout.center + _layout.gate_normal * reach
	return Vector3(spot.x, _layout.ground_y, spot.y)


# --- A travessia --------------------------------------------------------------


## Anda de `from` a `to` em `SOUNDSCAPE_TRAVEL_SECONDS`, amostrando o tempo todo.
func _travel(from: Vector3, to: Vector3) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var period: float = 1.0 / maxf(Params.SOUNDSCAPE_SAMPLE_HZ, 1.0)
	var zone_before: StringName = _soundscape.zone()
	var zone_seen: StringName = zone_before
	var switched_at: float = -1.0
	var finished_at: float = -1.0

	var min_total: float = 1.0
	var max_step: float = 0.0
	var previous: float = -1.0
	var samples: int = 0
	var zones: Dictionary = {}
	var music: Dictionary = {}
	# O maior intervalo entre duas observações. Nenhum instante medido aqui pode ser mais
	# preciso que isto — e neste contêiner, sem GPU, um quadro da cidade leva frações de
	# segundo, bem mais que o período de amostragem pedido.
	var worst_gap: float = 0.0
	var previous_at: float = 0.0

	# A medida não acaba com a caminhada: acaba com o crossfade. Saindo da cidade a
	# fronteira só é cruzada perto do fim do trajeto — a histerese empurra a saída seis
	# metros para fora —, e parar de amostrar na chegada cortaria a troca no meio e mediria
	# um crossfade que não terminou como se fosse um crossfade quebrado.
	var deadline: float = Params.SOUNDSCAPE_TRAVEL_SECONDS + Params.AUDIO_ZONE_CROSSFADE * 2.0
	var elapsed: float = 0.0
	var next_sample: float = 0.0
	while elapsed < Params.SOUNDSCAPE_TRAVEL_SECONDS \
			or (switched_at >= 0.0 and finished_at < 0.0 and elapsed < deadline):
		await process_frame
		elapsed = float(Time.get_ticks_msec() - started) / MS_PER_SECOND
		_listener.global_position = from.lerp(
			to, clampf(elapsed / Params.SOUNDSCAPE_TRAVEL_SECONDS, 0.0, 1.0)
		)
		if elapsed < next_sample:
			continue
		next_sample += period
		if samples > 0:
			worst_gap = maxf(worst_gap, elapsed - previous_at)
		previous_at = elapsed

		var mix: Dictionary = _audio.zone_mix()
		var total: float = float(mix[&"total"])
		samples += 1
		zones[String(_soundscape.zone())] = true
		music[String(_audio.music_context())] = true
		min_total = minf(min_total, total)
		if previous >= 0.0:
			max_step = maxf(max_step, absf(total - previous))
		previous = total

		# A medida do crossfade recomeça a cada troca de zona, e o que se reporta é a
		# **última**. A travessia não tem só uma: saindo da praça em linha reta o ouvinte
		# raspa a taverna, e a perna inteira contém cidade → interior → cidade → floresta.
		# Cronometrar da primeira troca até o último fade completo media três crossfades
		# somados e acusava 2,50 s onde cada um leva 2,00.
		if _soundscape.zone() != zone_seen:
			zone_seen = _soundscape.zone()
			switched_at = elapsed
			finished_at = -1.0
		if switched_at >= 0.0 and finished_at < 0.0 and float(mix[&"blend"]) >= 1.0:
			finished_at = elapsed

	return {
		"from": String(zone_before),
		"to": String(_soundscape.zone()),
		"samples": samples,
		"min_total": min_total,
		"max_step": max_step,
		"crossfade_seconds": maxf(finished_at - switched_at, 0.0) if finished_at >= 0.0 else -1.0,
		"worst_gap": worst_gap,
		"zones": zones.keys(),
		"music": music.keys(),
	}


## Dentro da taverna: a zona vira interior e o passa-baixa fecha.
func _interior() -> Dictionary:
	var spot: Vector3 = Vector3.ZERO
	for building: Dictionary in _layout.buildings:
		if Params.CITY_INTERIOR_TYPES.has(StringName(building["type"])):
			var center: Vector2 = building["center"]
			spot = Vector3(center.x, _layout.ground_y + Params.NAV_AGENT_HEIGHT * HALF, center.y)
			break
	if spot == Vector3.ZERO:
		return {"reached": false}

	_listener.global_position = spot
	_soundscape.poll_now()
	await _settle()
	return {
		"reached": _soundscape.zone() == &"interior",
		"zone": String(_soundscape.zone()),
		"music": String(_audio.music_context()),
		"total": float(_audio.zone_mix()[&"total"]),
	}


# --- O banco ------------------------------------------------------------------


## Carrega tudo o que `make audio` escreveu no manifesto. Existir em disco não é o mesmo
## que o Godot conseguir importar: um .wav com cabeçalho torto passa na primeira prova e
## reprova na segunda, que é a que o jogo faz.
func _bank() -> Dictionary:
	var path: String = "%s/manifest.json" % Params.AUDIO_DIR
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"listed": 0, "loaded": 0, "missing": ["manifest.json"]}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"listed": 0, "loaded": 0, "missing": ["manifest.json"]}

	var files: Dictionary = (parsed as Dictionary).get("files", {})
	var loaded: int = 0
	var seconds: float = 0.0
	var missing: Array[String] = []
	var compressed: Array[String] = []
	var beds_looping: int = 0
	for name: String in files:
		var full: String = "%s/%s" % [Params.AUDIO_DIR, name]
		var stream: AudioStream = ResourceLoader.load(full) as AudioStream
		if stream == null:
			missing.append(name)
			continue
		loaded += 1
		seconds += stream.get_length()

		var wav: AudioStreamWAV = stream as AudioStreamWAV
		if wav == null:
			continue
		# O importador do Godot 4.3+ recomprime .wav em QOA, que é com perda — e bytes de
		# QOA não se concatenam, que é como a voz monta uma fala. `WAV_IMPORT` manda
		# preservar PCM de 16 bits; esta contagem é o que garante que a ordem chegou.
		if wav.format != AudioStreamWAV.FORMAT_16_BITS:
			compressed.append(name)
		# Leito que não repete deixa a zona muda depois de 22 s. As três zonas foram
		# visitadas antes desta contagem, então as três têm de estar marcadas.
		if name.begins_with("ambiencia/") and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			beds_looping += 1
	return {
		"listed": files.size(),
		"loaded": loaded,
		"seconds": seconds,
		"missing": missing,
		"compressed": compressed,
		"beds_looping": beds_looping,
		"beds": Params.AUDIO_ZONES.size(),
		"themes": (parsed as Dictionary).get("themes", {}).keys(),
	}


# --- Utilidades ---------------------------------------------------------------


func _settle() -> void:
	var started: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - started) / MS_PER_SECOND < Params.SOUNDSCAPE_SETTLE_SECONDS:
		await process_frame


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
