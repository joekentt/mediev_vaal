"""Gera `resources/daycycle/ciclo.tres` e `resources/weather/*.tres`.

O dia inteiro é um `DayCycleProfile`: quatro `Gradient` de cor e seis `Curve` de número,
todos amostrados pela fração do dia. O clima são três `WeatherProfile` de multiplicadores.

Como `resources/gaits/` e `resources/dialogues/`, isto é **versionado**: é dado de design,
e o diff de uma curva de luz é exatamente o tipo de mudança que se quer ver numa revisão.
Continua gerado, e `make verify` reprova quem editar à mão.

Três auditorias, e todas nasceram de defeito possível:

1. **O laço tem de fechar.** A chave das 24h tem de repetir a das 0h em cor e em número.
   Sem isso há um degrau na virada da meia-noite — o único instante do ciclo em que
   ninguém está olhando a tela, e por isso o defeito mais fácil de deixar passar.
2. **O azimute tem de subir sempre.** É a única curva que não é interpolação de estado, é
   ângulo acumulado: se uma chave devolvesse o sol para trás, ele nasceria a oeste no meio
   da manhã.
3. **Toda cor é da paleta.** A tabela cita nome de cor, não hexadecimal, então uma cor
   inventada aqui morre na geração em vez de virar magenta na tela.
"""

from __future__ import annotations

from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, write_if_changed

CYCLE_OUTPUT = Path(P.DAY_CYCLE_DIR) / "ciclo.tres"
WEATHER_DIR = Path(P.WEATHER_DIR)
CYCLE_SCRIPT = "res://scripts/gameplay/day_cycle_profile.gd"
WEATHER_SCRIPT = "res://scripts/gameplay/weather_profile.gd"

# Curvas do perfil: (campo, chave em DAY_CYCLE_KEYS).
CURVES = (
    ("sun_energy", "sun_energy"),
    ("fog_scale", "fog_scale"),
    ("ambient", "ambient"),
    ("elevation", "elevation"),
    ("azimuth", "azimuth"),
    ("light", "light"),
)
# Gradientes do perfil: (campo, chave em DAY_CYCLE_KEYS).
GRADIENTS = (
    ("sky_zenith", "zenith"),
    ("sky_horizon", "horizon"),
    ("fog_color", "fog"),
    ("sun_color", "sun"),
)

# Modo de tangente do Godot que faz `Curve.sample()` interpolar em reta. Escrever 0
# (tangente livre) daria uma curva com ombro em cada chave — e um ombro na curva de energia
# do sol é justamente o salto de luz que esta fase existe para não ter.
TANGENT_LINEAR = 1
# Folga do domínio da curva. `Curve` corta pontos fora de [min_value, max_value] no momento
# em que os lê, então o domínio nasce um pouco maior que os dados.
CURVE_MARGIN = 0.05


def _fraction(hour: float) -> float:
    return hour / float(P.HOURS_PER_DAY)


def _gradient(name: str, key: str) -> str:
    offsets = ", ".join(P.num(_fraction(entry["hour"])) for entry in P.DAY_CYCLE_KEYS)
    channels: list[str] = []
    for entry in P.DAY_CYCLE_KEYS:
        red, green, blue = P.hex_to_rgb(P.PALETTE[entry[key]])
        channels += [P.num(red), P.num(green), P.num(blue), P.num(1.0)]
    return (
        f'[sub_resource type="Gradient" id="Gradient_{name}"]\n'
        f"offsets = PackedFloat32Array({offsets})\n"
        f"colors = PackedColorArray({', '.join(channels)})\n"
    )


def _curve(name: str, key: str) -> str:
    values = [float(entry[key]) for entry in P.DAY_CYCLE_KEYS]
    low = min(values) - CURVE_MARGIN
    high = max(values) + CURVE_MARGIN
    points: list[str] = []
    for entry, value in zip(P.DAY_CYCLE_KEYS, values):
        points.append(
            f"Vector2({P.num(_fraction(entry['hour']))}, {P.num(value)}), "
            f"0.0, 0.0, {TANGENT_LINEAR}, {TANGENT_LINEAR}"
        )
    # min_value e max_value **antes** de _data: o carregador aplica as propriedades na
    # ordem escrita, e um ponto fora do domínio vigente é cortado ao ser lido. Escrever o
    # domínio depois dos dados achatava a curva de azimute em 1,0 e o sol parava de girar.
    return (
        f'[sub_resource type="Curve" id="Curve_{name}"]\n'
        f"min_value = {P.num(low)}\n"
        f"max_value = {P.num(high)}\n"
        f"_data = [{', '.join(points)}]\n"
        f"point_count = {len(points)}\n"
    )


def _cycle_resource() -> str:
    blocks = [_gradient(name, key) for name, key in GRADIENTS]
    blocks += [_curve(name, key) for name, key in CURVES]
    fields = [f'{name} = SubResource("Gradient_{name}")' for name, _ in GRADIENTS]
    fields += [f'{name} = SubResource("Curve_{name}")' for name, _ in CURVES]
    steps = len(blocks) + 2  # os sub-recursos, o script e o próprio recurso
    return (
        f"{GENERATED_HEADER('tools/gen_daycycle.py', 'tools/params.py', ';')}\n"
        f'[gd_resource type="Resource" script_class="DayCycleProfile" '
        f'load_steps={steps} format=3]\n\n'
        f'[ext_resource type="Script" path="{CYCLE_SCRIPT}" id="1_cycle"]\n\n'
        + "\n".join(blocks)
        + '\n[resource]\nscript = ExtResource("1_cycle")\n'
        + "\n".join(fields)
        + "\n"
    )


def _weather_resource(name: str, spec: dict) -> str:
    red, green, blue = P.hex_to_rgb(P.PALETTE[spec["fog_tint"]])
    return f"""{GENERATED_HEADER('tools/gen_daycycle.py', 'tools/params.py', ';')}
[gd_resource type="Resource" script_class="WeatherProfile" load_steps=2 format=3]

[ext_resource type="Script" path="{WEATHER_SCRIPT}" id="1_weather"]

[resource]
script = ExtResource("1_weather")
id = &"{name}"
label = "{spec['label']}"
sun_scale = {P.num(spec['sun_scale'])}
ambient_scale = {P.num(spec['ambient_scale'])}
fog_scale = {P.num(spec['fog_scale'])}
fog_tint = Color({P.num(red)}, {P.num(green)}, {P.num(blue)}, 1.0)
fog_tint_amount = {P.num(spec['fog_tint_amount'])}
sky_gray = {P.num(spec['sky_gray'])}
rain = {P.num(spec['rain'])}
wind_scale = {P.num(spec['wind_scale'])}
muffle_hz = {P.num(spec['muffle_hz'])}
ambience_db = {P.num(spec['ambience_db'])}
"""


def _audit() -> None:
    keys = P.DAY_CYCLE_KEYS
    if not keys:
        raise SystemExit("tools/params.py: DAY_CYCLE_KEYS está vazio.")

    hours = [entry["hour"] for entry in keys]
    if hours[0] != 0.0 or hours[-1] != float(P.HOURS_PER_DAY):
        raise SystemExit(
            f"tools/params.py: DAY_CYCLE_KEYS tem de começar em 0h e terminar em "
            f"{P.HOURS_PER_DAY}h — vai de {hours[0]}h a {hours[-1]}h."
        )
    for previous, current in zip(hours, hours[1:]):
        if current <= previous:
            raise SystemExit(
                f"tools/params.py: DAY_CYCLE_KEYS fora de ordem: {previous}h vem antes de "
                f"{current}h. As chaves são pontos de gradiente, e gradiente não anda para trás."
            )

    # 1. O laço tem de fechar: meia-noite é a única emenda do ciclo.
    first, last = keys[0], keys[-1]
    for _, key in GRADIENTS:
        if first[key] != last[key]:
            raise SystemExit(
                f"tools/params.py: a chave das {P.HOURS_PER_DAY}h tem {key}={last[key]!r} e a "
                f"das 0h tem {first[key]!r}. A cor daria um salto na virada da meia-noite."
            )
    for _, key in CURVES:
        if key == "azimuth":
            continue  # o azimute é ângulo acumulado; ver a auditoria 2.
        if float(first[key]) != float(last[key]):
            raise SystemExit(
                f"tools/params.py: a chave das {P.HOURS_PER_DAY}h tem {key}={last[key]} e a das "
                f"0h tem {first[key]}. O valor daria um salto na virada da meia-noite."
            )
    turn = float(last["azimuth"]) - float(first["azimuth"])
    if abs(turn - 360.0) > 1.0:
        raise SystemExit(
            f"tools/params.py: o sol gira {turn:g}° num dia. Tem de girar 360° — a volta "
            f"tem de fechar para o nascente de amanhã ser o mesmo de hoje."
        )

    # 2. O azimute tem de subir sempre.
    azimuths = [float(entry["azimuth"]) for entry in keys]
    for previous, current in zip(azimuths, azimuths[1:]):
        if current <= previous:
            raise SystemExit(
                f"tools/params.py: o azimute do sol volta de {previous}° para {current}°. "
                f"O sol nasceria duas vezes no mesmo dia."
            )

    # 3. Toda cor citada existe na paleta.
    for entry in keys:
        for _, key in GRADIENTS:
            if entry[key] not in P.PALETTE:
                raise KeyError(
                    f"DAY_CYCLE_KEYS ({entry['hour']}h) cita a cor {entry[key]!r}, que não "
                    f"existe na paleta."
                )
    for name, spec in P.WEATHER_PROFILES.items():
        if spec["fog_tint"] not in P.PALETTE:
            raise KeyError(
                f"Clima {name!r} cita a cor {spec['fog_tint']!r}, que não existe na paleta."
            )
    if P.WEATHER_START not in P.WEATHER_PROFILES:
        raise SystemExit(
            f"tools/params.py: WEATHER_START é {P.WEATHER_START!r} e não há perfil com esse nome."
        )

    # A elevação nunca desce abaixo do horizonte: à noite esta luz é a lua, e apagar a
    # única direcional do orçamento deixaria a cidade sem sombra nenhuma.
    for entry in keys:
        if float(entry["elevation"]) <= 0.0:
            raise SystemExit(
                f"tools/params.py: a chave das {entry['hour']}h põe o sol a "
                f"{entry['elevation']}° — no horizonte ou abaixo dele. À noite esta luz é a "
                f"lua e continua acesa; ver o comentário em DAY_CYCLE_KEYS."
            )


def main() -> list[Path]:
    _audit()

    written = write_if_changed(CYCLE_OUTPUT, _cycle_resource())
    for name, spec in P.WEATHER_PROFILES.items():
        written += write_if_changed(WEATHER_DIR / f"{name}.tres", _weather_resource(name, spec))

    span = P.DAY_CYCLE_KEYS[-1]["azimuth"] - P.DAY_CYCLE_KEYS[0]["azimuth"]
    print(
        f"  ciclo: {len(P.DAY_CYCLE_KEYS)} chaves, {len(GRADIENTS)} gradientes e "
        f"{len(CURVES)} curvas em {CYCLE_OUTPUT} (sol gira {span:g}°)"
    )
    print(f"  clima: {len(P.WEATHER_PROFILES)} perfis em {WEATHER_DIR}/")
    return written


if __name__ == "__main__":
    main()
