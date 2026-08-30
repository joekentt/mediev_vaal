"""Gera o banco sonoro inteiro: barramentos, efeitos, vozes, ambiências e música.

Todo som deste jogo nasce aqui, em NumPy, e sai em `.wav` para `assets/generated/audio/`.
Nada é baixado, gravado ou comprado — é a mesma regra do resto do projeto aplicada ao que
se ouve. `make audio` reconstrói o banco do zero, e a mesma seed devolve os mesmos bytes.

O layout de barramentos (`default_bus_layout.tres`) sai de `params.AUDIO_BUSES`: mexer em
volume de barramento é mexer no .py, nunca no painel de Audio do editor. Ele leva um
passa-baixa em `SFX` e em `Ambience` — é por esse filtro que a chuva abafa o mundo e que
estar dentro da taverna soa como estar dentro da taverna. O filtro nasce aberto em
`AUDIO_FILTER_MAX_HZ`, que é o mesmo que não estar lá.

A organização dos arquivos é por família, e o jogo monta o caminho a partir do nome:

    passos/<superfície>_<n>.wav   ambiencia/<zona>.wav   voz/<postura>_<n>.wav
    efeitos/<nome>.wav            musica/<contexto>.wav

Sem registro, sem tabela para atualizar — a mesma escolha das árvores de conversa.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from . import dsp, music
from . import params as P
from .util import GENERATED_HEADER, ROOT, write_bytes_if_changed, write_if_changed

BUS_LAYOUT_OUTPUT = Path("assets/generated/audio/default_bus_layout.tres")
TONE_OUTPUT = Path("assets/generated/audio/calibration_tone.wav")
AUDIO_DIR = Path(P.AUDIO_DIR)
MANIFEST_OUTPUT = AUDIO_DIR / "manifest.json"

MS_PER_SEC = 1000.0
# Barramentos que ganham o passa-baixa do clima e do interior. Música fica de fora: a
# trilha é extradiegética — ela não está dentro da chuva, está por cima dela.
FILTERED_BUSES = ("SFX", "Ambience")

# Constantes de forma da síntese. Seguem a convenção do kit: o que caracteriza um som tem
# nome aqui ou em `params.py`, e os fatores de mistura ficam à vista na expressão.
_CLICK_DECAY = 0.008           # s do estalo do contato do pé com a superfície
_BODY_DECAY_FACTOR = 2.0       # o corpo ressoa o dobro do tempo do golpe
_CLICK_BAND = 0.6              # fração da banda alta em que o estalo começa
_BIRD_ATTACK = 0.006           # s: um chilro não tem ataque, tem começo
_BIRD_AIR = (2000.0, 9000.0)   # Hz do sopro de ar que tira o brilho de sintetizador do FM
_BIRD_AIR_LEVEL = 0.05
_BIRD_AIR_GATE = 0.02          # só há ar onde há canto: abaixo disto, silêncio
_ANVIL_STRIKE_BAND = 900.0     # Hz acima dos quais vive o golpe seco do martelo
_DOOR_PULSE_WIDTH = 0.05       # fração do período em que a madeira agarra
_LATCH_BAND = (400.0, 4000.0)  # Hz da tranca batendo no batente
_LATCH_DECAY = 0.05
_SPLASH_BAND = (1200.0, 6000.0)
_SPLASH_DECAY = 0.006
_DROP_DECAY = 0.02
_GLOTTAL_WIDTH = 0.06          # fração do período em que a glote está aberta
_CROWD_FLOOR = 180.0           # Hz abaixo dos quais murmúrio vira ronco
_RAIN_GUST = (0.09, 0.22)      # Hz e profundidade da respiração do chiado
_RAIN_TICK = 0.02              # s de cada gota destacada
_RAIN_TICK_DECAY = 0.004
_RAIN_TICK_BAND = (2000.0, 11000.0)


# ---------------------------------------------------------------------------
# Barramentos
# ---------------------------------------------------------------------------


def _bus_layout() -> str:
    filtered = [
        index for index, (name, _, _) in enumerate(P.AUDIO_BUSES) if name in FILTERED_BUSES
    ]
    lines = [
        GENERATED_HEADER("tools/gen_audio.py", "tools/params.py", ";"),
        f'[gd_resource type="AudioBusLayout" load_steps={len(filtered) + 1} format=3]',
        "",
    ]
    for index in filtered:
        lines.append(f'[sub_resource type="AudioEffectLowPassFilter" id="Filter_{index}"]')
        lines.append(f"cutoff_hz = {P.num(P.AUDIO_FILTER_MAX_HZ)}")
        lines.append("")
    lines.append("[resource]")
    for index, (name, volume_db, send) in enumerate(P.AUDIO_BUSES):
        lines.append(f'bus/{index}/name = &"{name}"')
        lines.append(f"bus/{index}/solo = false")
        lines.append(f"bus/{index}/mute = false")
        lines.append(f"bus/{index}/bypass_fx = false")
        lines.append(f"bus/{index}/volume_db = {P.num(volume_db)}")
        lines.append(f'bus/{index}/send = &"{send}"')
        if index in filtered:
            lines.append(f'bus/{index}/effect/0/effect = SubResource("Filter_{index}")')
            lines.append(f"bus/{index}/effect/0/enabled = true")
    return "\n".join(lines) + "\n"


def _calibration_tone(rate: int) -> np.ndarray:
    """Seno de 1 kHz. Não é conteúdo de jogo: é o sinal que prova o caminho inteiro —
    síntese em Python, .wav, import do Godot, AudioManager, barramento."""
    count = dsp.samples(P.CALIBRATION_TONE_SEC, rate)
    tone = dsp.sine(P.CALIBRATION_TONE_HZ, count, rate)
    tone = dsp.gain(tone, P.CALIBRATION_TONE_DB)
    return dsp.fade_edges(tone, rate, P.CALIBRATION_TONE_FADE_MS)


# ---------------------------------------------------------------------------
# Efeitos
# ---------------------------------------------------------------------------


def _footstep(surface: str, variant: int, gen: np.random.Generator, rate: int) -> np.ndarray:
    """Um passo: golpe de ruído filtrado mais o corpo que ressoa embaixo dele.

    O que separa terra de pedra não é o volume, é onde está a energia e quanto tempo ela
    fica: terra é grave e morre em 55 ms, pedra é aguda e morre em 30, madeira tem uma
    ressonância no meio que continua soando depois de o golpe acabar.
    """
    spec = P.STEP_SURFACES[surface]
    count = dsp.samples(P.STEP_SECONDS, rate)
    # Cada variante desloca a altura: o mesmo passo repetido lê como metrônomo, e é o
    # defeito mais audível de um jogo com som sintetizado.
    shift = 1.0 + P.STEP_PITCH_SPREAD * (float(variant) / max(P.STEP_VARIANTS - 1, 1) - 0.5)

    grit = dsp.band(dsp.noise(gen, count), rate, spec["low"] * shift, spec["high"] * shift)
    grit *= dsp.env_decay(count, rate, spec["decay"])

    body = dsp.sine(spec["body"] * shift, count, rate)
    body *= dsp.env_decay(count, rate, spec["decay"] * _BODY_DECAY_FACTOR)
    body = dsp.gain(body, spec["body_db"])

    # O estalo é o primeiro milissegundo do contato. Na pedra ele é quase o som todo.
    click = dsp.band(dsp.noise(gen, count), rate, spec["high"] * _CLICK_BAND, None)
    click *= dsp.env_decay(count, rate, _CLICK_DECAY) * spec["click"]

    return dsp.fade_edges(dsp.mix(grit, body, click), rate, P.AUDIO_FADE_MS)


def _wind(seconds: float, gen: np.random.Generator, rate: int) -> np.ndarray:
    """Vento em três camadas com rajadas independentes.

    A independência é o ponto. Uma camada só, por mais filtrada que seja, tem um período
    audível: passa meio minuto e o ouvido reconhece a rajada de antes. Três envelopes de
    frequências primas entre si demoram muito mais que o laço para se repetirem.
    """
    count = dsp.samples(seconds, rate)
    layers = []
    for index, layer in enumerate(P.WIND_LAYERS):
        raw = dsp.band(dsp.noise(gen, count), rate, layer["low"], layer["high"])
        gust = dsp.lfo(count, rate, layer["gust_hz"], layer["depth"], float(index))
        layers.append(dsp.gain(raw * gust, layer["db"]))
    return dsp.mix(*layers)


def _bird(call: dict, gen: np.random.Generator, rate: int) -> np.ndarray:
    """Chilro por FM, com a portadora escorregando dentro de cada nota."""
    chirp = dsp.samples(call["chirp_ms"] / MS_PER_SEC, rate)
    gap = dsp.samples(call["gap_ms"] / MS_PER_SEC, rate)
    total = np.zeros(call["chirps"] * (chirp + gap))
    for index in range(call["chirps"]):
        carrier = dsp.sweep(
            call["carrier"], call["carrier"] * call["sweep"], chirp
        )
        # O índice de modulação cai dentro da nota: o chilro abre largo e fecha em assobio.
        envelope = dsp.env_ar(chirp, rate, _BIRD_ATTACK, call["chirp_ms"] / MS_PER_SEC * _CLICK_BAND)
        voice = dsp.fm(carrier, call["ratio"], call["index"] * envelope, chirp, rate)
        dsp.place(total, voice * envelope, index * (chirp + gap))
    # Um sopro de ar em volta tira o brilho de sintetizador puro do FM.
    total += _BIRD_AIR_LEVEL * dsp.band(dsp.noise(gen, total.size), rate, *_BIRD_AIR) * (
        np.abs(total) > _BIRD_AIR_GATE
    )
    return dsp.fade_edges(total, rate, P.AUDIO_FADE_MS)


def _anvil(gen: np.random.Generator, rate: int) -> np.ndarray:
    """Martelo na bigorna: parciais inarmônicos, decaimentos diferentes, golpe na frente.

    Harmônicos inteiros soariam afinados, e bigorna afinada é sino. As razões da tabela
    são propositalmente irracionais entre si — é o que faz o metal soar como metal.
    """
    count = dsp.samples(P.ANVIL_SECONDS, rate)
    total = np.zeros(count)
    for freq, decay, level in P.ANVIL_PARTIALS:
        total += level * dsp.sine(freq, count, rate) * dsp.env_decay(count, rate, decay)
    strike = dsp.band(dsp.noise(gen, count), rate, _ANVIL_STRIKE_BAND, None)
    strike *= dsp.env_decay(count, rate, P.ANVIL_STRIKE_MS / MS_PER_SEC)
    return dsp.fade_edges(dsp.mix(total, strike * 0.8), rate, P.AUDIO_FADE_MS)


def _door(gen: np.random.Generator, rate: int) -> np.ndarray:
    """Porta: o rangido e a tranca.

    O rangido é um trem de pulsos que desacelera passando por uma ressonância parada — que
    é literalmente o que acontece numa dobradiça: a madeira agarra e escorrega dezenas de
    vezes por segundo, cada vez mais devagar, e o corpo da porta ressoa em cima disso.
    Filtro que varia no tempo não é preciso; quem varia é a fonte.
    """
    count = dsp.samples(P.DOOR_SECONDS, rate)
    slip = dsp.samples(P.DOOR_SECONDS * P.DOOR_LATCH_AT, rate)
    rate_curve = dsp.sweep(P.DOOR_CREAK_FROM, P.DOOR_CREAK_TO, slip, curve=0.6)
    creak = dsp.pulse_train(rate_curve, slip, rate, width=_DOOR_PULSE_WIDTH)
    creak = dsp.resonate(creak, rate, P.DOOR_CREAK_FROM * 0.8, P.DOOR_CREAK_Q)
    creak *= dsp.env_ar(slip, rate, 0.05, P.DOOR_SECONDS * 0.4)

    latch_count = count - slip
    latch = dsp.sine(P.DOOR_LATCH_HZ, latch_count, rate)
    latch += dsp.band(dsp.noise(gen, latch_count), rate, *_LATCH_BAND)
    latch *= dsp.env_decay(latch_count, rate, _LATCH_DECAY)

    total = np.zeros(count)
    dsp.place(total, creak, 0, 0.7)
    dsp.place(total, latch, slip, 0.9)
    return dsp.fade_edges(total, rate, P.AUDIO_FADE_MS)


def _well_water(gen: np.random.Generator, rate: int) -> np.ndarray:
    """Água do poço: gotas com a altura subindo dentro de cada uma.

    A subida é o efeito todo. Uma gota num copo desce de altura; uma gota num poço fundo
    sobe, porque a coluna de ar acima da água encurta enquanto a bolha sobe. Sem essa
    subida o som é de pia, e o poço da praça vira uma torneira.
    """
    count = dsp.samples(P.WATER_SECONDS, rate)
    total = np.zeros(count)
    drop_count = dsp.samples(P.WATER_DROP_MS / MS_PER_SEC, rate)
    for index in range(P.WATER_DROPS):
        base = P.WATER_DROP_HZ * float(gen.uniform(0.8, 1.3))
        curve = dsp.sweep(base, base * P.WATER_DROP_SWEEP, drop_count, curve=0.5)
        drop = dsp.sine(curve, drop_count, rate) * dsp.env_decay(drop_count, rate, _DROP_DECAY)
        splash = dsp.band(dsp.noise(gen, drop_count), rate, *_SPLASH_BAND)
        splash *= dsp.env_decay(drop_count, rate, _SPLASH_DECAY)
        at = int(gen.uniform(0.0, 1.0) * (count - drop_count))
        dsp.place(total, drop + 0.25 * splash, at, float(gen.uniform(0.5, 1.0)))
    return dsp.fade_edges(total, rate, P.AUDIO_FADE_MS)


# ---------------------------------------------------------------------------
# Voz
# ---------------------------------------------------------------------------


def _syllable(posture: str, index: int, gen: np.random.Generator, rate: int) -> np.ndarray:
    """Uma sílaba do banco de uma raça.

    Fonte e filtro, que é como a voz humana funciona: um trem de pulsos faz o zumbido da
    glote e duas ressonâncias — os formantes F1 e F2 — dizem que vogal é. Mover os dois
    formantes muda **quem** está falando sem mexer na altura da voz, e é por isso que a
    tabela de raças é uma tabela de formantes e não de frequências fundamentais.
    """
    spec = P.VOICE_FORMANTS[posture]
    shape = P.VOICE_SYLLABLE_SHAPES[index % len(P.VOICE_SYLLABLE_SHAPES)]
    count = dsp.samples(P.VOICE_SYLLABLE_MS / MS_PER_SEC, rate)

    profile = P.VOICE_PROFILES[posture]
    base = float(profile["base_hz"])
    # A altura escorrega dentro da sílaba, por `wobble` Hz. Constante, soa como robô lendo
    # em voz alta: uma vogal humana nunca fica parada na mesma frequência por 95 ms.
    slide = base + float(profile["wobble"]) * float(gen.uniform(-1.0, 1.0))
    pitch = dsp.sweep(base, slide, count)
    source = dsp.pulse_train(pitch, count, rate, width=_GLOTTAL_WIDTH)
    source += spec["breath"] * dsp.noise(gen, count)

    first = dsp.resonate(source, rate, spec["f1"] * shape[0], spec["q"])
    second = dsp.resonate(source, rate, spec["f2"] * shape[1], spec["q"] * 0.7)
    second *= float(profile["brightness"])
    voiced = dsp.tilt(first + second, rate, spec["tilt"])

    # `VOICE_ATTACK` e `VOICE_RELEASE` são **frações** da sílaba, não segundos: uma sílaba
    # de raça baixa e uma de raça aguda têm a mesma forma, e é a forma que faz a fala soar
    # como fala. Passá-las como segundos daria um ataque mais longo que a sílaba inteira, e
    # o que se ouviria seria um crescendo em vez de uma vogal.
    seconds = P.VOICE_SYLLABLE_MS / MS_PER_SEC
    envelope = dsp.env_ar(count, rate, seconds * P.VOICE_ATTACK, seconds * P.VOICE_RELEASE)
    return dsp.normalize(dsp.fade_edges(voiced * envelope, rate, P.AUDIO_FADE_MS), P.AUDIO_PEAK)


def _crowd(bank: dict[str, list[np.ndarray]], gen: np.random.Generator, rate: int) -> np.ndarray:
    """Murmúrio: sílabas do banco sobrepostas fora de fase, com os agudos cortados.

    Ninguém pode entender uma palavra, e é isso que distingue murmúrio de conversa. O
    corte em 1,7 kHz é o que tira a inteligibilidade sem tirar a presença — é o mesmo
    motivo de uma conversa na sala ao lado soar como murmúrio através da parede.
    """
    count = dsp.samples(P.CROWD_SECONDS, rate)
    total = np.zeros(count)
    voices = [syllable for group in bank.values() for syllable in group]
    if not voices:
        return total
    placements = int(P.CROWD_VOICES * P.CROWD_SECONDS * P.CROWD_DENSITY)
    for _ in range(placements):
        piece = voices[int(gen.integers(0, len(voices)))]
        stretch = float(gen.uniform(1.0 - P.CROWD_PITCH_SPREAD, 1.0 + P.CROWD_PITCH_SPREAD))
        # Reamostragem por interpolação: mudar a altura de uma sílaba pronta é mais barato
        # que sintetizar outra, e vinte e duas vozes distintas sairiam do orçamento de
        # tempo de geração sem que ninguém ouvisse a diferença.
        source = np.interp(
            np.arange(0, piece.size, stretch), np.arange(piece.size), piece
        )
        dsp.place(total, source, int(gen.integers(0, count)), float(gen.uniform(0.3, 1.0)))
    return dsp.band(total, rate, _CROWD_FLOOR, P.CROWD_LOWPASS)


# ---------------------------------------------------------------------------
# Ambiência
# ---------------------------------------------------------------------------


def _bed(
    zone: str,
    parts: dict,
    gen: np.random.Generator,
    rate: int,
) -> np.ndarray:
    """Um leito de zona, montado do que já foi sintetizado.

    O laço fecha por `wrap_tail`: a cauda que passaria do fim volta somada no começo, e a
    costura da repetição some. Sem isso, um leito de 22 s entrega o truque a cada 22 s —
    que é o intervalo exato em que o ouvido começa a reconhecer um padrão.
    """
    spec = P.AMBIENCE_BEDS[zone]
    count = dsp.samples(P.AMBIENCE_SECONDS, rate)
    total = np.zeros(count)

    wind = _wind(P.AMBIENCE_SECONDS, gen, rate)
    wind = dsp.band(wind, rate, None, spec["wind_lowpass"])
    total += dsp.gain(dsp.normalize(wind, 1.0), spec["wind_db"])

    for _ in range(spec["birds"]):
        call = _bird(P.BIRD_CALLS[int(gen.integers(0, len(P.BIRD_CALLS)))], gen, rate)
        dsp.place(total, call, int(gen.integers(0, count)), float(gen.uniform(0.05, 0.16)))

    if spec["crowd_db"] is not None:
        crowd = _crowd(parts["voice"], gen, rate)
        # O murmúrio é mais curto que o leito: entra duas vezes, deslocado, e as duas
        # cópias somadas já não têm período reconhecível.
        for offset in (0, count // 2):
            dsp.place(total, crowd, offset, 10.0 ** (spec["crowd_db"] / 20.0))

    for _ in range(spec["steps"]):
        surface = ["pedra", "terra"][int(gen.integers(0, 2))]
        step = parts["steps"][surface][int(gen.integers(0, P.STEP_VARIANTS))]
        dsp.place(total, step, int(gen.integers(0, count)), float(gen.uniform(0.05, 0.18)))

    for _ in range(spec["creaks"]):
        dsp.place(total, parts["door"], int(gen.integers(0, count)), float(gen.uniform(0.04, 0.12)))

    looped = dsp.wrap_tail(total, dsp.samples(P.AUDIO_LOOP_TAIL, rate))
    return dsp.normalize(looped, P.AUDIO_PEAK)


def _rain(gen: np.random.Generator, rate: int) -> np.ndarray:
    """Chuva: chiado de banda larga mais gotas destacadas por cima.

    Só o chiado seria estático — ruído filtrado é ruído filtrado, e o ouvido desliga. As
    gotas isoladas são o que dá escala à chuva: são elas que dizem que a água está caindo
    em cima de alguma coisa, e não saindo de um alto-falante.
    """
    count = dsp.samples(P.RAIN_SECONDS, rate)
    hiss = dsp.band(dsp.noise(gen, count), rate, P.RAIN_HIGHPASS, P.RAIN_LOWPASS)
    hiss *= dsp.lfo(count, rate, *_RAIN_GUST)
    total = dsp.normalize(hiss, 0.7)

    tick = dsp.samples(_RAIN_TICK, rate)
    for _ in range(P.RAIN_DROPS):
        drop = dsp.band(dsp.noise(gen, tick), rate, *_RAIN_TICK_BAND)
        drop *= dsp.env_decay(tick, rate, _RAIN_TICK_DECAY)
        dsp.place(total, drop, int(gen.integers(0, count)), float(gen.uniform(0.1, 0.45)))

    looped = dsp.wrap_tail(total, dsp.samples(P.AUDIO_LOOP_TAIL, rate))
    return dsp.normalize(looped, P.AUDIO_PEAK)


# ---------------------------------------------------------------------------
# Geração
# ---------------------------------------------------------------------------


def _write(relative: Path, signal: np.ndarray, rate: int, written: list[Path],
           manifest: dict) -> None:
    normalized = dsp.normalize(signal, P.AUDIO_PEAK)
    written += dsp.write_wav(relative, normalized, rate)
    manifest[str(relative.relative_to(AUDIO_DIR))] = {
        "seconds": round(dsp.duration(normalized, rate), 3),
        "rate": rate,
    }


def main() -> list[Path]:
    rate = P.AUDIO_SAMPLE_RATE
    gen = dsp.generator(P.AUDIO_SEED)
    written = write_if_changed(BUS_LAYOUT_OUTPUT, _bus_layout())
    manifest: dict = {}

    _write(TONE_OUTPUT, _calibration_tone(rate), rate, written, manifest)

    # 1. Passos por superfície. Ficam guardados: os leitos de cidade os reaproveitam.
    steps: dict[str, list[np.ndarray]] = {}
    for surface in P.STEP_SURFACES:
        steps[surface] = []
        for variant in range(P.STEP_VARIANTS):
            signal = _footstep(surface, variant, gen, rate)
            steps[surface].append(signal)
            _write(AUDIO_DIR / "passos" / f"{surface}_{variant}.wav", signal, rate,
                   written, manifest)

    # 2. Efeitos soltos.
    door = _door(gen, rate)
    effects = {
        "vento": _wind(P.WIND_SECONDS, gen, rate),
        "martelo": _anvil(gen, rate),
        "porta": door,
        "agua_poco": _well_water(gen, rate),
        "chuva": _rain(gen, rate),
    }
    for index, call in enumerate(P.BIRD_CALLS):
        effects[f"passaro_{index}"] = _bird(call, gen, rate)
    for name, signal in effects.items():
        _write(AUDIO_DIR / "efeitos" / f"{name}.wav", signal, rate, written, manifest)

    # 3. Banco de sílabas por raça, na taxa da voz — metade da do resto, porque nenhuma
    # sílaba tem energia acima de 8 kHz e o dobro do arquivo não traria nada.
    voice: dict[str, list[np.ndarray]] = {}
    for posture in P.VOICE_FORMANTS:
        voice[posture] = []
        for index in range(P.VOICE_BANK_SYLLABLES):
            signal = _syllable(posture, index, gen, P.VOICE_SAMPLE_RATE)
            voice[posture].append(signal)
            _write(AUDIO_DIR / "voz" / f"{posture}_{index}.wav", signal,
                   P.VOICE_SAMPLE_RATE, written, manifest)

    # 4. Murmúrio, que sai do banco de voz, e os leitos, que saem de tudo o que veio antes.
    _write(AUDIO_DIR / "efeitos" / "murmurio.wav", _crowd(voice, gen, rate), rate,
           written, manifest)
    parts = {"steps": steps, "voice": voice, "door": door}
    for zone in P.AMBIENCE_BEDS:
        _write(AUDIO_DIR / "ambiencia" / f"{zone}.wav", _bed(zone, parts, gen, rate), rate,
               written, manifest)

    # 5. Música: um tema por contexto, cada um com a sua própria seed.
    themes: dict[str, dict] = {}
    for name in P.MUSIC_THEMES:
        signal, report = music.theme(name, P.MUSIC_SAMPLE_RATE)
        themes[name] = report
        _audit_tuning(name, report["tuning"])
        _write(AUDIO_DIR / "musica" / f"{name}.wav", signal, P.MUSIC_SAMPLE_RATE,
               written, manifest)

    written += _write_manifest(manifest, themes)
    _report(manifest, themes)
    return written


def _audit_tuning(name: str, tuning: dict) -> None:
    """Reprova a geração se o tema saiu desafinado ou fora do modo que ele declara.

    Uma trilha gerada por regra pode sair errada de um jeito que o log não mostra: um erro
    de oitava num harmônico, uma razão trocada, um modo lido do dicionário errado. Nada
    disso muda o número de notas nem a duração — muda só onde as notas caem, que é
    exatamente o que ninguém confere lendo saída de terminal.
    """
    if tuning["off_scale"]:
        raise SystemExit(
            f"Tema {name!r} tem pico fora do modo: {', '.join(tuning['off_scale'])}. "
            f"A progressão ou os timbres estão saindo de graus que a escala não tem."
        )
    if tuning["worst_cents"] > P.MUSIC_TUNING_CENTS:
        raise SystemExit(
            f"Tema {name!r} desafinado em {tuning['worst_cents']:.1f} centésimos, acima do "
            f"limite de {P.MUSIC_TUNING_CENTS:g}. A síntese é aditiva sobre frequências "
            f"exatas: isto não é imprecisão de medida, é conta errada."
        )


def _write_manifest(manifest: dict, themes: dict) -> list[Path]:
    total = sum(entry["seconds"] for entry in manifest.values())
    payload = {
        "seed": P.AUDIO_SEED,
        "files": dict(sorted(manifest.items())),
        "themes": themes,
        "total_seconds": round(total, 2),
    }
    return write_bytes_if_changed(
        MANIFEST_OUTPUT,
        (json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8"),
    )


def _report(manifest: dict, themes: dict) -> None:
    families: dict[str, int] = {}
    for name in manifest:
        family = Path(name).parent.name or "raiz"
        families[family] = families.get(family, 0) + 1
    listing = ", ".join(f"{family} {count}" for family, count in sorted(families.items()))
    size = sum(
        (ROOT / AUDIO_DIR / name).stat().st_size for name in manifest
        if (ROOT / AUDIO_DIR / name).exists()
    )
    bus_names = ", ".join(name for name, _, _ in P.AUDIO_BUSES)
    print(f"  barramentos: {bus_names} (passa-baixa em {', '.join(FILTERED_BUSES)})")
    print(f"  banco: {len(manifest)} arquivos ({listing})")
    print(
        f"  duração: {sum(e['seconds'] for e in manifest.values()):.1f} s de som, "
        f"{size / (1 << 20):.1f} MiB"
    )
    for name, report in themes.items():
        degrees = "-".join(str(degree + 1) for degree in report["progression"][:8])
        print(
            f"  tema {name}: {report['mode']}, {report['bpm']:g} bpm, "
            f"{report['notes']} notas, {report['seconds']:.1f} s, graus {degrees}…, "
            f"afinação {report['tuning']['worst_cents']:.1f}c"
        )


if __name__ == "__main__":
    main()
