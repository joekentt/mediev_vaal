extends Node

## Ponto único de reprodução de áudio. Stub da fase 1.
##
## Pools fixos de players, criados uma vez no boot — nada de instanciar
## `AudioStreamPlayer` em tempo de execução. Música usa dois players alternando em
## crossfade. Nenhum outro sistema deve criar player de áudio por conta própria.
##
## Os barramentos (`Master`, `Music`, `SFX`, `Ambience`, `UI`) vêm do layout gerado por
## `make audio`. Todo som do jogo será sintetizado por `tools/gen_audio.py`.

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _sfx_cursor: int = 0
var _sfx_3d_cursor: int = 0

var _music_players: Array[AudioStreamPlayer] = []
var _music_active: int = 0
var _ambience_player: AudioStreamPlayer = null
var _fade_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sfx_pool()
	_build_sfx_3d_pool()
	_build_music_players()
	_build_ambience_player()


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
