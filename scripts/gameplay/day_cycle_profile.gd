## O dia inteiro como dado: quatro gradientes de cor e seis curvas de número.
##
## É `Resource` pelo mesmo motivo que a marcha e a conversa são: **mudar como o dia parece
## não pode exigir código**. O `.tres` sai de `tools/gen_daycycle.py`, e `DayNightCycle`
## só sabe pedir a hora e aplicar o que veio.
##
## Por que gradiente e curva, e não uma tabela de estados por período: um estado por
## período obriga alguém a escrever a transição entre eles, e transição escrita à mão é
## exatamente onde nasce o salto de cor. Aqui não há transição para escrever — **só existe**
## a interpolação. Às 6h32 ninguém decidiu nada: o gradiente foi amostrado em 0,2722 do dia
## e devolveu a cor que estava lá.
##
## Todas as curvas são amostradas pela **fração do dia** (0 = meia-noite, 0,5 = meio-dia),
## e a chave das 24h repete a das 0h — o gerador reprova se não repetir, porque a virada da
## meia-noite é a única emenda do laço e é a que ninguém está olhando quando quebra.
class_name DayCycleProfile
extends Resource

@export var sky_zenith: Gradient = null
@export var sky_horizon: Gradient = null
@export var fog_color: Gradient = null
@export var sun_color: Gradient = null

@export var sun_energy: Curve = null
@export var fog_scale: Curve = null
@export var ambient: Curve = null
## Elevação do sol em graus acima do horizonte. Nunca negativa: à noite esta luz é a lua.
@export var elevation: Curve = null
## Azimute em graus. Passa de 360 na última chave de propósito — a curva tem de subir
## sempre, senão o sol volta para trás na virada do dia em vez de completar a volta.
@export var azimuth: Curve = null
## Quanto de dia existe, de 0 a 1. É o que acende janela e lampião.
@export var light: Curve = null


## Tudo de uma vez, para quem aplica não amostrar dez vezes espalhado pelo código.
func sample(fraction: float) -> Dictionary:
	var t: float = fposmod(fraction, 1.0)
	return {
		&"sky_zenith": _color(sky_zenith, t),
		&"sky_horizon": _color(sky_horizon, t),
		&"fog_color": _color(fog_color, t),
		&"sun_color": _color(sun_color, t),
		&"sun_energy": _value(sun_energy, t),
		&"fog_scale": _value(fog_scale, t),
		&"ambient": _value(ambient, t),
		&"elevation": _value(elevation, t),
		&"azimuth": _value(azimuth, t),
		&"light": _value(light, t),
	}


## Está completo? Um perfil pela metade produz um vale preto, e é melhor dizer isso alto.
func is_complete() -> bool:
	for part: Variant in [
		sky_zenith, sky_horizon, fog_color, sun_color,
		sun_energy, fog_scale, ambient, elevation, azimuth, light,
	]:
		if part == null:
			return false
	return true


static func _color(gradient: Gradient, t: float) -> Color:
	if gradient == null:
		return Params.color(&"debug_magenta")
	return gradient.sample(t)


static func _value(curve: Curve, t: float) -> float:
	if curve == null:
		return 0.0
	return curve.sample(t)
