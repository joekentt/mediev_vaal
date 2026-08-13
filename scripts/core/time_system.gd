extends Node

## Relógio do mundo. Stub da fase 1.
##
## Faz a hora andar e anuncia as viradas pelo `EventBus`. Ainda não move o sol nem troca
## a iluminação — isso entra com o ciclo dia/noite na fase 3, dentro de `generators/`.
##
## Rotinas de NPC devem escutar `EventBus.hour_changed`, nunca ler o relógio por frame.

## Congela o relógio sem pausar o resto do jogo (útil em cutscene).
var clock_paused: bool = false

var _time_of_day: float = Params.START_HOUR
var _day: int = 1
var _last_hour: int = -1
var _last_period: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_last_hour = get_hour()
	_last_period = get_period()


func _process(delta: float) -> void:
	if clock_paused or Params.SECONDS_PER_GAME_DAY <= 0.0:
		return

	var hours_per_second: float = float(Params.HOURS_PER_DAY) / Params.SECONDS_PER_GAME_DAY
	_time_of_day += delta * hours_per_second

	while _time_of_day >= float(Params.HOURS_PER_DAY):
		_time_of_day -= float(Params.HOURS_PER_DAY)
		_day += 1
		EventBus.day_changed.emit(_day)

	_announce_transitions()


## Hora contínua do dia, de 0.0 a 24.0.
func get_time_of_day() -> float:
	return _time_of_day


## Hora cheia atual (0 a 23).
func get_hour() -> int:
	return int(_time_of_day) % Params.HOURS_PER_DAY


func get_minute() -> int:
	return int(fmod(_time_of_day, 1.0) * float(Params.MINUTES_PER_HOUR))


func get_day() -> int:
	return _day


## Período do dia atual (ver `Params.Period`).
##
## `PERIOD_START_HOURS` e `Period` saem da mesma tabela em `params.py`, deslocados de um:
## o dia começa em NIGHT (0) e cada limite ultrapassado avança um período. O último
## limite (o anoitecer) transborda o enum e fecha o ciclo de volta na noite.
func get_period() -> int:
	var hour: int = get_hour()
	var period: int = Params.Period.NIGHT
	for index: int in Params.PERIOD_START_HOURS.size():
		if hour >= Params.PERIOD_START_HOURS[index]:
			period = index + 1
	if period > Params.Period.DUSK:
		period = Params.Period.NIGHT
	return period


## Fração do dia (0.0 = meia-noite, 0.5 = meio-dia). Base do futuro ciclo solar.
func get_day_fraction() -> float:
	return _time_of_day / float(Params.HOURS_PER_DAY)


## Salta para uma hora específica, disparando as viradas correspondentes.
func set_time_of_day(hour: float) -> void:
	_time_of_day = fposmod(hour, float(Params.HOURS_PER_DAY))
	_announce_transitions()


## "08:35" — para HUD e depuração.
func format_clock() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


func _announce_transitions() -> void:
	var hour: int = get_hour()
	if hour != _last_hour:
		_last_hour = hour
		EventBus.hour_changed.emit(hour)

	var period: int = get_period()
	if period != _last_period:
		_last_period = period
		EventBus.day_period_changed.emit(period)
