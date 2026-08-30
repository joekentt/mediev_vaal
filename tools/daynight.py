"""`make daynight` — roda `tools/daynight.gd` e cobra o aceite do ciclo dia/noite.

O critério da fase é uma frase — "acelerar o tempo mostra transição contínua sem salto de
cor" — e aqui ela vira quatro números:

- o maior degrau de cor por canal entre dois quadros consecutivos com o tempo acelerado
  360 vezes, contra `DAYNIGHT_MAX_COLOR_STEP`;
- o mesmo degrau na varredura fina do dado, que separa "o gradiente tem um degrau" de "a
  economia de reaplicação tem um degrau" — são defeitos diferentes e se corrigem em
  lugares diferentes;
- o degrau na virada da meia-noite, que é a emenda do laço;
- a emissão das janelas e o número de lampiões acesos de dia e de noite, mais quantos
  habitantes restam na praça à 1h.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import params as P  # noqa: E402
from tools.imagelib import Canvas, hex_to_bytes, scale  # noqa: E402
from tools.util import GodotMissing, GodotTimeout, ensure_imported, fail, run_godot  # noqa: E402

DAYNIGHT_SCRIPT = "res://tools/daynight.gd"
RESULT_PREFIX = "MEDIEV_DAYNIGHT "
STRIP_OUTPUT = Path(P.DAYNIGHT_DIR) / "dia.png"

# Altura de cada faixa da tira, de cima para baixo.
BANDS = (
    ("zenith", 70, "zênite do céu"),
    ("horizon", 50, "horizonte"),
    ("fog", 40, "névoa"),
    ("sun", 45, "sol, escurecido pela energia"),
    ("lamps", 30, "janelas e lampiões"),
)
TICK_HEIGHT = 12
TICK_EVERY_HOURS = 3
BACKGROUND = (18, 18, 20)
TICK_COLOR = (150, 150, 150)
MIDNIGHT_COLOR = (220, 90, 60)


def _draw_strip(report: dict) -> Path:
    """A tira do dia: uma coluna por amostra, uma faixa por coisa que o ciclo move."""
    strip = report["sweep"]["strip"]
    width = len(strip["zenith"])
    height = sum(band[1] for band in BANDS) + TICK_HEIGHT
    canvas = Canvas(width, height, BACKGROUND)

    top = 0
    for key, band_height, _label in BANDS:
        for column in range(width):
            if key == "lamps":
                # A faixa dos lampiões é a única que não é uma cor do ciclo: é o quanto
                # eles estão acesos, do apagado ao aceso, na cor da luz de dentro de casa.
                color = scale(hex_to_bytes(P.PALETTE["window_light"]), strip["lamps"][column])
            elif key == "sun":
                # O sol é mostrado escurecido pela própria energia: a cor da luz do meio-dia
                # e a da lua são parecidas em matiz e diferentes em quanto iluminam.
                color = scale(hex_to_bytes(strip["sun"][column]), strip["energy"][column])
            else:
                color = hex_to_bytes(strip[key][column])
            canvas.column(column, top, band_height, color)
        top += band_height

    per_hour = width / float(P.HOURS_PER_DAY)
    for hour in range(0, P.HOURS_PER_DAY, TICK_EVERY_HOURS):
        canvas.column(int(hour * per_hour), top, TICK_HEIGHT, TICK_COLOR)
    # A meia-noite ganha marca própria nas duas pontas: é a emenda do laço, e é lá que um
    # degrau apareceria como um corte vertical entre a última coluna e a primeira.
    canvas.column(0, top, TICK_HEIGHT, MIDNIGHT_COLOR)
    canvas.column(width - 1, top, TICK_HEIGHT, MIDNIGHT_COLOR)
    return canvas.save(STRIP_OUTPUT)


def _extract(stdout: str) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    return None


def _audit(report: dict) -> list[str]:
    problems: list[str] = []
    run = report["run"]
    sweep = report["sweep"]
    lights = report["lights"]
    plaza = report["plaza"]

    if run["max_excess"] > report["max_color_step"]:
        problems.append(
            f"com o tempo {run['scale']:g}x, a cor andou {run['max_excess']:.4f} além do "
            f"que a interpolação pedia, às {run['worst_at_hour']:.2f}h — acima do teto de "
            f"{report['max_color_step']:.4f}. É salto introduzido pelo sistema, não é a "
            f"paleta andando depressa."
        )
    if run["max_energy_excess"] > report["max_energy_step"]:
        problems.append(
            f"a energia do sol andou {run['max_energy_excess']:.4f} além da interpolação, "
            f"acima do teto de {report['max_energy_step']:.4f}."
        )
    if sweep["max_color_rate"] > report["max_color_rate"]:
        problems.append(
            f"o gradiente muda a {sweep['max_color_rate']:.2f} de cor por hora às "
            f"{sweep['worst_at_hour']:.2f}h, acima do teto de "
            f"{report['max_color_rate']:.2f}. Não é a economia de reaplicação: são duas "
            f"chaves de DAY_CYCLE_KEYS distantes demais uma da outra."
        )
    if sweep["max_energy_rate"] > report["max_energy_rate"]:
        problems.append(
            f"a energia do sol muda a {sweep['max_energy_rate']:.2f} por hora, acima do "
            f"teto de {report['max_energy_rate']:.2f}."
        )
    if sweep["midnight_color"] > report["max_color_step"]:
        problems.append(
            f"a virada da meia-noite salta {sweep['midnight_color']:.4f} em cor. A chave "
            f"das 24h não fecha com a das 0h."
        )
    if report["idle"]["updates"] >= report["idle"]["frames"]:
        problems.append(
            f"na velocidade normal o ciclo reaplicou a iluminação "
            f"{report['idle']['updates']} vezes em {report['idle']['frames']} quadros. "
            f"A economia de DAY_CYCLE_MIN_STEP não está funcionando, e o ciclo custa por "
            f"quadro."
        )
    hitch = report["hitch"]
    if hitch.get("checked") and hitch["after_one_frame"] >= 1.0:
        problems.append(
            f"a virada do tempo para {hitch['to']} terminou num quadro só. O teto de "
            f"{hitch['max_step']:g}s por quadro não está segurando, e um quadro longo faz "
            f"o céu saltar."
        )

    if lights["night"]["emission"] <= lights["day"]["emission"]:
        problems.append(
            f"as janelas emitem {lights['night']['emission']:.2f} à noite e "
            f"{lights['day']['emission']:.2f} de dia. A noite não acende nada."
        )
    if lights["day"]["emission"] > 0.0:
        problems.append(
            f"as janelas emitem {lights['day']['emission']:.2f} ao meio-dia. Casa acesa em "
            f"pleno sol lê como erro de material, não como casa habitada."
        )
    if lights["night"]["lamps_on"] <= 0 < lights["night"]["lamps_total"]:
        problems.append("nenhum lampião acendeu à noite.")
    if lights["day"]["lamps_on"] > 0:
        problems.append(f"{lights['day']['lamps_on']} lampião(ões) aceso(s) ao meio-dia.")

    if plaza["night_fraction"] > report["max_night_plaza"]:
        problems.append(
            f"à {P.DAYNIGHT_NIGHT_HOUR:g}h ainda há {plaza['night_fraction']:.0%} dos "
            f"habitantes na praça, acima do teto de {report['max_night_plaza']:.0%}. "
            f"A praça não esvazia."
        )
    if plaza["at_noon"] <= plaza["at_night"]:
        problems.append(
            f"a praça tem {plaza['at_noon']} pessoa(s) ao meio-dia e {plaza['at_night']} "
            f"à noite. Se a noite não é mais vazia que o dia, não há ciclo de vida nenhum."
        )

    weathers = {entry["id"]: entry for entry in report["weather"]}
    if len(weathers) < len(P.WEATHER_PROFILES):
        problems.append(
            f"só {len(weathers)} de {len(P.WEATHER_PROFILES)} climas responderam."
        )
    elif weathers["chuva"]["fog_density"] <= weathers["ensolarado"]["fog_density"]:
        problems.append("a chuva não deixa a névoa mais densa que o sol.")
    elif weathers["chuva"]["rain"] <= 0.0:
        problems.append("o clima de chuva não põe gota nenhuma no ar.")
    elif weathers["chuva"]["muffle_hz"] >= weathers["ensolarado"]["muffle_hz"]:
        problems.append("a chuva não abafa o barramento de áudio.")
    return problems


def main(argv: list[str] | None = None) -> int:
    del argv
    try:
        ensure_imported()
        process = run_godot(["--headless", "--script", DAYNIGHT_SCRIPT])
    except (GodotMissing, GodotTimeout) as error:
        fail(str(error))
        return 1

    report = _extract(process.stdout)
    if report is None:
        fail(f"o Godot terminou com código {process.returncode} sem reportar medição.")
        for line in (process.stdout + process.stderr).splitlines():
            if line.startswith("SCRIPT ERROR") or line.startswith("ERROR"):
                print(f"  {line}", file=sys.stderr)
        return 1

    run, sweep = report["run"], report["sweep"]
    lights, plaza = report["lights"], report["plaza"]
    print(
        f"  dia:        {report['seconds_per_day']:g} s reais, {report['keys']} chaves, "
        f"períodos {', '.join(report['periods'])}"
    )
    print(
        f"  acelerado:  {run['scale']:g}x ({run['real_seconds']:.1f} s reais), "
        f"{run['frames']} quadros, maior passo de cor {run['max_step']:.4f}"
    )
    print(
        f"  excesso:    {run['max_excess']:.4f} de cor e {run['max_energy_excess']:.4f} de "
        f"energia além da interpolação (teto {report['max_color_step']:.3f} / "
        f"{report['max_energy_step']:.3f})"
    )
    print(
        f"  gradiente:  {sweep['max_color_rate']:.2f} de cor por hora no pico, às "
        f"{sweep['worst_at_hour']:.2f}h (teto {report['max_color_rate']:.2f}); "
        f"meia-noite {sweep['midnight_color']:.4f}"
    )
    idle = report["idle"]
    print(
        f"  custo:      {idle['updates']} reaplicações em {idle['frames']} quadros na "
        f"velocidade normal (1 a cada {idle['frames_per_update']:.0f})"
    )
    hitch = report["hitch"]
    if hitch.get("checked"):
        print(
            f"  virada:     {hitch['after_one_frame']:.0%} da transição para "
            f"{hitch['to']} num quadro só (teto de {hitch['max_step']:g}s por quadro "
            f"em {hitch['seconds']:g}s de virada)"
        )
    strip = _draw_strip(report)
    print(f"  tira:       {strip.relative_to(ROOT)} ({sweep['samples']} colunas do dia)")
    print(
        f"  noite:      janelas {lights['day']['emission']:.2f} -> "
        f"{lights['night']['emission']:.2f}, lampiões "
        f"{lights['day']['lamps_on']} -> {lights['night']['lamps_on']}"
        f"/{lights['night']['lamps_total']} "
        f"({lights['day']['period']} -> {lights['night']['period']})"
    )
    print(
        f"  praça:      {plaza['at_noon']}/{plaza['npcs']} ao meio-dia, "
        f"{plaza['at_night']}/{plaza['npcs']} à {P.DAYNIGHT_NIGHT_HOUR:g}h "
        f"({plaza['night_fraction']:.0%}, teto {report['max_night_plaza']:.0%})"
    )
    for entry in report["weather"]:
        print(
            f"  clima {entry['id']:<11s} névoa {entry['fog_density']:.4f}, sol "
            f"{entry['sun_energy']:.2f}, chuva {entry['rain']:.0%}, "
            f"abafamento {entry['muffle_hz']:.0f} Hz"
        )

    problems = _audit(report)
    if problems:
        print()
        for problem in problems:
            print(f"  ESTOUROU: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
