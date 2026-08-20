extends Node

## Ponto único de reprodução de áudio, e dono das zonas sonoras.
##
## Pools fixos de players, criados uma vez no boot — nada de instanciar
## `AudioStreamPlayer` em tempo de execução. Música usa dois players alternando em
## crossfade, e a ambiência usa outros dois pelo mesmo motivo. Nenhum outro sistema deve
## criar player de áudio por conta própria.
##
## **A zona é a peça nova.** Floresta, cidade e interior têm cada uma o seu leito sonoro,
## e trocar de zona é um crossfade de `AUDIO_ZONE_CROSSFADE` segundos entre dois players.
## Quem decide a zona é `Soundscape`, olhando onde o ouvinte está; aqui só se sabe misturar.
##
## O crossfade é de **potência constante**, e é a única decisão de peso deste arquivo.
## Escrever `volume_db` de um subindo em reta enquanto o outro desce em reta é o que sai
## naturalmente — e afunda o volume percebido para 71% no meio da troca, que é o "corte"
## que o critério de aceite desta fase proíbe. Com seno e cosseno, a soma dos quadrados é
## 1 do começo ao fim: a paisagem sonora muda sem que o volume se mexa. `make soundscape`
## mede exatamente isso.
##
## Os barramentos (`Master`, `Music`, `SFX`, `Ambience`, `UI`) vêm do layout gerado por
## `make audio`, com um passa-baixa em `SFX` e em `Ambience` — é por ele que a chuva abafa
## o mundo e que o interior soa como interior.

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _sfx_cursor: int = 0
var _sfx_3d_cursor: int = 0

var _music_players: Array[AudioStreamPlayer] = []
var _music_active: int = 0
var _music_context: StringName = &""
var _ambience_player: AudioStreamPlayer = null
var _fade_tween: Tween = null

var _zone_players: Array[AudioStreamPlayer] = []
var _zone_active: int = 0
var _zone: StringName = &""
var _zone_blend: float = 1.0
var _zone_trim_db: float = 0.0
var _muffle_hz: float = Params.AUDIO_FILTER_MAX_HZ


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sfx_pool()
	_build_sfx_3d_pool()
	_build_music_players()
	_build_ambience_player()
	_build_zone_players()


## Efeito sem posição (UI, feedback direto do jogador).
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Efeito posicionado no mundo, com atenuação por distância.
func play_sfx_3d(
	stream: AudioStream,
	position: Vector3,
	volume_db: float = 0.0,
	pitch: float = 1.0
) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer3D = _sfx_3d_pool[_sfx_3d_cursor]
	_sfx_3d_cursor = (_sfx_3d_cursor + 1) % _sfx_3d_pool.size()
	player.global_position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Troca a trilha com crossfade. `null` silencia.
func play_music(stream: AudioStream, fade_time: float = Params.MUSIC_CROSSFADE_SEC) -> void:
	var outgoing: AudioStreamPlayer = _music_players[_music_active]
	_music_active = (_music_active + 1) % _music_players.size()
	var incoming: AudioStreamPlayer = _music_players[_music_active]

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	incoming.stream = stream
	incoming.volume_db = Params.SILENT_DB
	if stream != null:
		incoming.play()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(outgoing, "volume_db", Params.SILENT_DB, fade_time)
	if stream != null:
		_fade_tween.tween_property(incoming, "volume_db", 0.0, fade_time)
	_fade_tween.chain().tween_callback(outgoing.stop)


func stop_music(fade_time: float = Params.MUSIC_CROSSFADE_SEC) -> void:
	play_music(null, fade_time)


## Toca o tema de um contexto (`exterior`, `cidade`, `noite`), pelo nome.
##
## Sem registro e sem `match`: o nome é o caminho, como nas árvores de conversa. Repetir o
## contexto que já está tocando não faz nada — senão andar por cima da fronteira da cidade
## reiniciaria a música a cada passo.
func play_music_context(context: StringName) -> void:
	if context == _music_context:
		return
	_music_context = context
	if context == &"":
		stop_music()
		return
	play_music(_cached("musica/%s" % context))


func music_context() -> StringName:
	return _music_context


# --- Zonas sonoras ------------------------------------------------------------


## Entra numa zona (`floresta`, `cidade`, `interior`) com crossfade de potência constante.
func set_zone(zone_id: StringName) -> void:
	if zone_id == _zone:
		return
	_zone = zone_id

	var stream: AudioStream = _zone_stream(zone_id)
	_zone_active = (_zone_active + 1) % _zone_players.size()
	var incoming: AudioStreamPlayer = _zone_players[_zone_active]
	incoming.stream = stream
	if stream != null:
		incoming.play()
	# Se a troca pega uma anterior pela metade, o novo leito parte do zero e o antigo
	# continua de onde estava. Não é aproximação: são dois players, e o terceiro leito
	# simplesmente reaproveita o que estava saindo.
	_zone_blend = 0.0
	_write_zone_volumes()

	var bus: Node = get_node_or_null(EVENT_BUS_PATH)
	if bus != null:
		bus.audio_zone_changed.emit(zone_id)


const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"


func zone() -> StringName:
	return _zone


## Ganho linear de cada leito agora, e o total **em potência** — que é o que o ouvido
## escuta como volume, e o que `make soundscape` cobra que não afunde no meio da troca.
##
## Lido dos players, e não da conta que os alimenta. É a diferença entre medir o que se
## pretendia e medir o que sai: um leito cujo .wav não foi gerado tem `playing` falso e
## entra na conta como zero, então a medida acusa o buraco em vez de reportar o seno que
## teria tocado se o arquivo existisse.
func zone_mix() -> Dictionary:
	var incoming: float = 0.0
	var outgoing: float = 0.0
	for index: int in _zone_players.size():
		var player: AudioStreamPlayer = _zone_players[index]
		var gain: float = db_to_linear(player.volume_db) if player.playing else 0.0
		if index == _zone_active:
			incoming += gain
		else:
			outgoing += gain
	return {
		&"incoming": incoming,
		&"outgoing": outgoing,
		&"total": sqrt(incoming * incoming + outgoing * outgoing),
		&"blend": _zone_blend,
	}


const HALF: float = 0.5


## As duas rampas do crossfade de potência constante, para um dado avanço.
func _gains(blend: float) -> Vector2:
	return Vector2(sin(blend * PI * HALF), cos(blend * PI * HALF))


func _process(delta: float) -> void:
	if _zone_blend >= 1.0:
		return
	if Params.AUDIO_ZONE_CROSSFADE <= 0.0:
		_zone_blend = 1.0
	else:
		_zone_blend = minf(_zone_blend + delta / Params.AUDIO_ZONE_CROSSFADE, 1.0)
	_write_zone_volumes()


func _write_zone_volumes() -> void:
	var gains: Vector2 = _gains(_zone_blend)
	for index: int in _zone_players.size():
		var player: AudioStreamPlayer = _zone_players[index]
		var gain: float = gains.x if index == _zone_active else gains.y
		if gain <= 0.0:
			player.volume_db = Params.SILENT_DB
			if index != _zone_active:
				player.stop()
			continue
		player.volume_db = maxf(linear_to_db(gain), Params.SILENT_DB) + _zone_trim_db


func _zone_stream(zone_id: StringName) -> AudioStream:
	return _cached("ambiencia/%s" % zone_id)


## Um leito ou tema, carregado uma vez e guardado para sempre.
##
## O cache não é economia de disco: é **posse**. Com só dois players de ambiência, o leito
## que sai de cena a cada troca perde a última referência e é descarregado — e o próximo
## `load` traz uma cópia nova do disco, sem a marca de laço que este arquivo tinha posto
## nele. Andar para dentro e para fora da cidade três vezes deixava o primeiro leito sem
## repetir, e foi assim que `make soundscape` encontrou isto.
##
## De quebra, tira a leitura de disco do meio da travessia: entrar na cidade não é o
## momento de descomprimir 20 s de áudio.
func _cached(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path: String = "%s/%s.wav" % [Params.AUDIO_DIR, name]
	if not ResourceLoader.exists(path):
		push_warning("Som ausente: %s. Rode `make audio`." % path)
		return null
	var stream: AudioStream = _looping(ResourceLoader.load(path) as AudioStream)
	_streams[name] = stream
	return stream


var _streams: Dictionary = {}


## Marca um .wav para tocar em laço.
##
## Leito e trilha **têm** de repetir: um leito de 22 s que toca uma vez deixa a floresta em
## silêncio no vigésimo terceiro segundo, que é o defeito mais fácil de não notar num teste
## curto e o mais óbvio de notar jogando. O laço é marcado aqui e não no import porque o
## mesmo importador serve as sílabas e os passos, que não podem repetir — um passo em laço
## é um pé arrastando para sempre.
##
## `make audio` fecha a costura somando a cauda de cada leito de volta no começo, então a
## volta não tem emenda audível; aqui só se liga a repetição.
static func _looping(stream: AudioStream) -> AudioStream:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav == null or wav.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		return stream
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	# Em quadros, não em bytes: 16 bits mono são dois bytes por quadro.
	@warning_ignore("integer_division")
	var frames: int = wav.data.size() / BYTES_PER_FRAME
	wav.loop_end = frames
	return stream


## Bytes por quadro de um .wav mono de 16 bits. Estrutural: é o formato que `make audio`
## escreve e que `WAV_IMPORT` manda o Godot preservar.
const BYTES_PER_FRAME: int = 2


## Corte do passa-baixa dos barramentos de mundo, em Hz. Quem chama é o clima.
##
## Escreve no efeito do barramento e não em cada player: um filtro por som seria um filtro
## por voz simultânea, e o ponto de ter barramento é justamente esse.
func set_muffle(hz: float) -> void:
	if is_equal_approx(hz, _muffle_hz):
		return
	_muffle_hz = hz
	for bus_name: StringName in [Params.BUS_SFX, Params.BUS_AMBIENCE]:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index < 0 or AudioServer.get_bus_effect_count(index) == 0:
			continue
		var effect: AudioEffectFilter = AudioServer.get_bus_effect(index, 0) as AudioEffectFilter
		if effect != null:
			effect.cutoff_hz = hz


func muffle_hz() -> float:
	return _muffle_hz


## Correção de volume do leito de ambiência, em dB. O clima usa para abaixar a floresta
## quando o que se ouve é chuva.
func set_ambience_trim(db: float) -> void:
	if is_equal_approx(db, _zone_trim_db):
		return
	_zone_trim_db = db
	_write_zone_volumes()


## Leito sonoro contínuo (floresta, praça, caverna).
func play_ambience(stream: AudioStream) -> void:
	if _ambience_player.stream == stream:
		return
	_ambience_player.stream = stream
	if stream == null:
		_ambience_player.stop()
	else:
		_ambience_player.play()


## Volume de um barramento em escala linear (0..1), como um slider espera.
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		push_warning("Barramento inexistente: %s. Rode `make audio`." % bus_name)
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)))


func get_bus_volume(bus_name: StringName) -> float:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


## Confere se o layout gerado foi de fato carregado. Usado por `make bench`.
func has_generated_buses() -> bool:
	return AudioServer.get_bus_index(Params.BUS_MUSIC) >= 0


func _build_sfx_pool() -> void:
	for index: int in Params.SFX_POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Sfx%02d" % index
		player.bus = Params.BUS_SFX
		add_child(player)
		_sfx_pool.append(player)


func _build_sfx_3d_pool() -> void:
	for index: int in Params.SFX_3D_POOL_SIZE:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "Sfx3D%02d" % index
		player.bus = Params.BUS_SFX
		player.max_distance = Params.SFX_3D_MAX_DISTANCE
		player.unit_size = Params.SFX_3D_UNIT_SIZE
		add_child(player)
		_sfx_3d_pool.append(player)


func _build_music_players() -> void:
	for index: int in Params.MUSIC_PLAYER_COUNT:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Music%d" % index
		player.bus = Params.BUS_MUSIC
		player.volume_db = Params.SILENT_DB
		add_child(player)
		_music_players.append(player)


func _build_ambience_player() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "Ambience"
	_ambience_player.bus = Params.BUS_AMBIENCE
	add_child(_ambience_player)


func _build_zone_players() -> void:
	for index: int in Params.AUDIO_AMBIENCE_PLAYERS:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Zone%d" % index
		player.bus = Params.BUS_AMBIENCE
		player.volume_db = Params.SILENT_DB
		add_child(player)
		_zone_players.append(player)
