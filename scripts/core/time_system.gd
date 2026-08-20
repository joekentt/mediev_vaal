extends Node

## Relógio do mundo: faz a hora andar e anuncia as viradas pelo `EventBus`.
##
## Um dia dura `seconds_per_day` segundos reais — 24 minutos de fábrica — e a duração é
## exportada, não constante, porque é o primeiro número que se quer mexer com o jogo
## rodando. O valor de fábrica continua vindo de `Params`: o inspetor ajusta, mas quem
## manda no que nasce é o gerador.
##
## `time_scale` é a mesma ideia levada ao extremo: multiplica a passagem do tempo sem
## mexer na duração do dia. É por ele que `make daynight` percorre 24 horas em quatro
## segundos e mede se a cor deu algum salto no caminho — e é por ele que se olha um pôr do
## sol inteiro sem esperar por ele.
##
## **Nada aqui sabe o que é sol, céu ou névoa.** Este nó publica hora, dia e período;
## `DayNightCycle` é quem escuta e move a luz. Rotinas de NPC escutam
## `EventBus.hour_changed` e nunca leem o relógio por quadro — vinte habitantes
## perguntando as horas a 60 Hz seriam 1200 consultas por segundo para a mesma resposta.

## Congela o relógio sem pausar o resto do jogo (útil em cutscene).
var clock_paused: bool = false

## Segundos reais por dia de jogo. De fábrica: `Params.SECONDS_PER_GAME_DAY`.
@export var seconds_per_day: float = Params.SECONDS_PER_GAME_DAY
## Multiplicador da passagem do tempo. 1 é o jogo.
@export var time_scale: float = Params.TIME_SCALE_DEFAULT

var _time_of_day: float = Params.START_HOUR
var _day: int = 1
var _last_hour: int = -1
var _last_period: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_last_hour = get_hour()
	_last_period = get_period()


func _process(delta: float) -> void:
	if clock_paused or seconds_per_day <= 0.0 or time_scale <= 0.0:
		return

	var hours_per_second: float = float(Params.HOURS_PER_DAY) / seconds_per_day
	_time_of_day += delta * hours_per_second * clampf(time_scale, 0.0, Params.TIME_SCALE_MAX)

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
## O primeiro período — a madrugada — é o que vale enquanto nenhum limite de
## `PERIOD_START_HOURS` tiver sido ultrapassado. Cada limite ultrapassado avança um.
func get_period() -> int:
	var hour: int = get_hour()
	var period: int = 0
	for index: int in Params.PERIOD_START_HOURS.size():
		if hour >= Params.PERIOD_START_HOURS[index]:
			period = index + 1
	return period


## Nome do período atual, em português. Para relatório e prova, não para lógica: quem
## compara período compara o enum.
func get_period_name() -> StringName:
	var period: int = get_period()
	if period < 0 or period >= Params.PERIOD_NAMES.size():
		return &""
	return Params.PERIOD_NAMES[period]


## Fração do dia (0.0 = meia-noite, 0.5 = meio-dia). É por aqui que o ciclo amostra as
## curvas e os gradientes do `DayCycleProfile`.
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
