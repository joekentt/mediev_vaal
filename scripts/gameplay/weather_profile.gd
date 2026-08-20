## Um clima como dado: multiplicadores sobre o que o ciclo do dia já decidiu.
##
## Tudo aqui é **fator**, nunca valor absoluto, e essa é a decisão de projeto da peça.
## Um clima que escrevesse "a cor do céu é cinza" apagaria o ciclo: começaria a chover e o
## dia pararia de andar até parar de chover. Multiplicando, nublado ao meio-dia continua
## sendo meio-dia — com um terço menos de sol e o dobro de névoa —, e o pôr do sol embaixo
## de chuva continua sendo um pôr do sol.
##
## Os dois campos que não são fator dizem respeito a coisas que o ciclo não tem: quanta
## chuva cai e quanto o som fica abafado.
class_name WeatherProfile
extends Resource

@export var id: StringName = &""
@export var label: String = ""

@export var sun_scale: float = 1.0
@export var ambient_scale: float = 1.0
@export var fog_scale: float = 1.0
## Cor para onde a névoa é puxada, e quanto dela é puxada. Nublado não troca a cor da
## névoa: mistura-a com o cinza da nuvem, e é por isso que o amanhecer nublado ainda tem
## laranja dentro do cinza.
@export var fog_tint: Color = Color.WHITE
@export var fog_tint_amount: float = 0.0
## Quanto o céu perde de saturação. Nuvem não escurece o céu, tira a cor dele.
@export var sky_gray: float = 0.0

@export var rain: float = 0.0
@export var wind_scale: float = 1.0
## Corte do passa-baixa dos barramentos de mundo, em Hz. É o "abafado" em número.
@export var muffle_hz: float = Params.AUDIO_FILTER_MAX_HZ
@export var ambience_db: float = 0.0


## Mistura de dois climas, para a virada do tempo não ser um corte.
##
## Devolve um dicionário e não um `WeatherProfile` de propósito: um recurso novo por
## quadro de transição seria alocação para nada, e ninguém precisa guardar o meio-termo.
static func blend(from: WeatherProfile, to: WeatherProfile, t: float) -> Dictionary:
	if from == null or to == null:
		var only: WeatherProfile = to if to != null else from
		if only == null:
			return {}
		return only.as_dictionary()
	var k: float = clampf(t, 0.0, 1.0)
	return {
		&"sun_scale": lerpf(from.sun_scale, to.sun_scale, k),
		&"ambient_scale": lerpf(from.ambient_scale, to.ambient_scale, k),
		&"fog_scale": lerpf(from.fog_scale, to.fog_scale, k),
		&"fog_tint": from.fog_tint.lerp(to.fog_tint, k),
		&"fog_tint_amount": lerpf(from.fog_tint_amount, to.fog_tint_amount, k),
		&"sky_gray": lerpf(from.sky_gray, to.sky_gray, k),
		&"rain": lerpf(from.rain, to.rain, k),
		&"wind_scale": lerpf(from.wind_scale, to.wind_scale, k),
		&"muffle_hz": lerpf(from.muffle_hz, to.muffle_hz, k),
		&"ambience_db": lerpf(from.ambience_db, to.ambience_db, k),
	}


func as_dictionary() -> Dictionary:
	return {
		&"sun_scale": sun_scale,
		&"ambient_scale": ambient_scale,
		&"fog_scale": fog_scale,
		&"fog_tint": fog_tint,
		&"fog_tint_amount": fog_tint_amount,
		&"sky_gray": sky_gray,
		&"rain": rain,
		&"wind_scale": wind_scale,
		&"muffle_hz": muffle_hz,
		&"ambience_db": ambience_db,
	}
