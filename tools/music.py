"""Música generativa: modo, progressão por regras e três timbres sintetizados.

Não há partitura em lugar nenhum deste projeto, e não vai haver. Há um modo (que grau
soa), uma tabela de transição (que acorde pode vir depois de qual) e três regras de
melodia. O tema sai daí, e a mesma seed sai igual.

Por que modal e não maior/menor: a terça menor com a sexta maior — o dórico — é o que soa
medieval sem soar triste, e o mixolídio com a sétima abaixada é o que soa aberto sem soar
alegre demais. Escrever isso como "maior com alterações" seria descrever o resultado em
vez da causa.

As três regras da melodia, e o defeito que cada uma evita:

1. **Grau de acorde no tempo forte.** Sem isso a melodia flutua por cima da harmonia e o
   tema soa desafinado sem estar desafinado.
2. **Passo antes de salto.** Uma melodia sorteada uniformemente entre os sete graus é
   ruído com afinação: o que faz linha melódica é a segunda vizinhança.
3. **Salto resolve por passo contrário.** É a regra mais velha do contraponto, e é a única
   que faz um salto soar como intenção em vez de como erro.
"""

from __future__ import annotations

import numpy as np

from . import dsp
from . import params as P

SEMITONES_PER_OCTAVE = 12
DEGREES_PER_SCALE = 7
# Notas do acorde: tônica, terça e quinta são os graus 0, 2 e 4 da escala a partir da
# fundamental. Vale para qualquer modo — é o que "acorde" quer dizer.
TRIAD_STEPS = (0, 2, 4)
# Alcance da melodia em graus acima e abaixo da nota atual. Cinco graus é o que uma voz
# alcança sem esforço, e é o que faz a linha caber num instrumento imaginável.
MELODY_REACH = 5
LEAP_DEGREES = 2                # daqui para cima já é salto, e salto pede resolução
BEAT_STRONG = 0                 # o tempo em que a melodia prefere grau de acorde


def _frequency(root: float, mode: tuple[int, ...], degree: int) -> float:
    """Frequência de um grau da escala, com oitavas acima e abaixo do alcance de sete."""
    octave, step = divmod(degree, DEGREES_PER_SCALE)
    return root * 2.0 ** ((mode[step] + SEMITONES_PER_OCTAVE * octave) / SEMITONES_PER_OCTAVE)


def _progression(gen: np.random.Generator, bars: int) -> list[int]:
    """Graus dos acordes, um por compasso. Começa e termina na tônica."""
    degrees = [0]
    for _ in range(bars - 1):
        options = P.MUSIC_TRANSITIONS[degrees[-1]]
        weights = np.array([weight for _, weight in options], dtype=np.float64)
        pick = gen.choice(len(options), p=weights / weights.sum())
        degrees.append(options[pick][0])
    # A última casa volta para a tônica: sem isso o laço emenda um acorde de tensão no
    # acorde de repouso do começo, e a repetição soa como erro de corte.
    degrees[-1] = 0
    return degrees


def _melody(
    gen: np.random.Generator, progression: list[int], spec: dict
) -> list[tuple[int, int, int]]:
    """A linha da flauta: lista de (compasso, tempo, grau)."""
    notes: list[tuple[int, int, int]] = []
    current = DEGREES_PER_SCALE  # começa uma oitava acima da tônica
    last_leap = 0
    for bar, chord in enumerate(progression):
        for beat in range(P.MUSIC_BEATS_PER_BAR):
            if gen.random() >= float(spec["melody"]):
                continue
            chord_tones = [chord + step for step in TRIAD_STEPS]

            if last_leap != 0:
                # 3. Salto resolve por passo contrário.
                current -= int(np.sign(last_leap))
                last_leap = 0
            else:
                candidates = list(range(current - MELODY_REACH, current + MELODY_REACH + 1))
                weights = []
                for candidate in candidates:
                    distance = abs(candidate - current)
                    if distance == 0:
                        weight = 0.25
                    elif distance <= 1:
                        weight = 1.0          # 2. Passo antes de salto.
                    else:
                        weight = 0.35 / float(distance)
                    if beat == BEAT_STRONG and candidate % DEGREES_PER_SCALE in [
                        tone % DEGREES_PER_SCALE for tone in chord_tones
                    ]:
                        weight *= 3.0         # 1. Grau de acorde no tempo forte.
                    weights.append(weight)
                array = np.array(weights, dtype=np.float64)
                choice = candidates[gen.choice(len(candidates), p=array / array.sum())]
                if abs(choice - current) >= LEAP_DEGREES:
                    last_leap = choice - current
                current = choice

            current = int(np.clip(current, 0, DEGREES_PER_SCALE * 2))
            notes.append((bar, beat, current))
    return notes


# --- Timbres ------------------------------------------------------------------


def pluck(freq: float, seconds: float, rate: int) -> np.ndarray:
    """Corda dedilhada, por síntese aditiva com decaimento por harmônico.

    Karplus-Strong seria o caminho clássico e é recursivo — 44 100 iterações de Python por
    segundo de som. Somar harmônicos cujo decaimento encurta com a ordem produz o mesmo
    efeito que importa (o brilho morre antes do fundamental) e é vetorizado.
    """
    count = dsp.samples(seconds, rate)
    total = np.zeros(count)
    for harmonic in range(1, P.MUSIC_PLUCK_HARMONICS + 1):
        decay = P.MUSIC_PLUCK_DECAY / float(harmonic)
        # Inarmonicidade leve: corda real tem rigidez, e os parciais sobem um pouco.
        partial = freq * harmonic * (1.0 + 0.0004 * harmonic * harmonic)
        total += dsp.sine(partial, count, rate) * dsp.env_decay(count, rate, decay) / harmonic
    return total * dsp.env_ar(count, rate, 0.004, 0.02)


def flute(freq: float, seconds: float, rate: int, gen: np.random.Generator) -> np.ndarray:
    """Sopro: seno com vibrato mais um ruído de ar na mesma banda."""
    count = dsp.samples(seconds, rate)
    vibrato = dsp.lfo(count, rate, P.MUSIC_FLUTE_VIBRATO_HZ, P.MUSIC_FLUTE_VIBRATO)
    body = dsp.sine(freq * vibrato, count, rate)
    body += 0.18 * dsp.sine(freq * 2.0 * vibrato, count, rate)
    breath = dsp.band(dsp.noise(gen, count), rate, freq * 0.8, freq * 4.0)
    envelope = dsp.env_ar(count, rate, seconds * 0.18, seconds * 0.3)
    return (body + P.MUSIC_FLUTE_BREATH * breath) * envelope


def drone(freq: float, seconds: float, rate: int) -> np.ndarray:
    """O bordão: tônica e quinta sustentadas, com respiração lenta de volume."""
    count = dsp.samples(seconds, rate)
    total = np.zeros(count)
    for harmonic in range(1, P.MUSIC_DRONE_HARMONICS + 1):
        total += dsp.sine(freq * harmonic, count, rate) / float(harmonic * harmonic)
    fifth = np.zeros(count)
    for harmonic in range(1, P.MUSIC_DRONE_HARMONICS + 1):
        fifth += dsp.sine(freq * 1.5 * harmonic, count, rate) / float(harmonic * harmonic)
    swell = dsp.lfo(count, rate, 0.07, 0.28)
    return (total + 0.6 * fifth) * swell * dsp.env_ar(count, rate, 2.0, 2.0)


# --- Tema ---------------------------------------------------------------------


def tuning(signal: np.ndarray, name: str, rate: int) -> dict:
    """Os picos mais fortes do espectro caem em graus do modo? Em quantos centésimos?

    É a diferença entre "gerou som" e "gerou música", e é medível. Um erro de oitava, uma
    razão de harmônico trocada ou um modo lido errado não saem afinados por acaso: o pico
    apareceria a meio semitom de qualquer grau da escala. Como a síntese é aditiva sobre
    frequências exatas, o esperado aqui é ordem de um centésimo — o que passar de
    `MUSIC_TUNING_CENTS` é defeito, não imprecisão de medida.
    """
    spec = np.abs(np.fft.rfft(signal * np.hanning(signal.size)))
    freqs = np.fft.rfftfreq(signal.size, 1.0 / rate)
    low, high = P.MUSIC_TUNING_BAND
    band = (freqs > low) & (freqs < high)
    strongest = np.argsort(spec[band])[-P.MUSIC_TUNING_PEAKS:]

    spec_music = P.MUSIC_THEMES[name]
    mode = P.MUSIC_MODES[spec_music["mode"]]
    root = P.MUSIC_ROOT_HZ * 2.0 ** (float(spec_music["root_shift"]) / SEMITONES_PER_OCTAVE)

    worst = 0.0
    off_scale: list[str] = []
    for freq in np.sort(freqs[band][strongest]):
        semitones = SEMITONES_PER_OCTAVE * np.log2(freq / root)
        degree = int(round(semitones)) % SEMITONES_PER_OCTAVE
        cents = abs(semitones - round(semitones)) * CENTS_PER_SEMITONE
        worst = max(worst, cents)
        if degree not in mode:
            off_scale.append(f"{freq:.1f} Hz (grau {degree})")
    return {"worst_cents": float(worst), "off_scale": off_scale}


CENTS_PER_SEMITONE = 100.0


def theme(name: str, rate: int) -> tuple[np.ndarray, dict]:
    """Um tema inteiro. Devolve o sinal e o que foi decidido, para o relatório."""
    spec = P.MUSIC_THEMES[name]
    gen = dsp.generator(P.MUSIC_SEED + sum(ord(letter) for letter in name))
    mode = P.MUSIC_MODES[spec["mode"]]
    root = P.MUSIC_ROOT_HZ * 2.0 ** (float(spec["root_shift"]) / SEMITONES_PER_OCTAVE)

    beat = 60.0 / float(spec["bpm"])
    bar = beat * P.MUSIC_BEATS_PER_BAR
    seconds = bar * P.MUSIC_BARS + P.MUSIC_LOOP_TAIL
    count = dsp.samples(seconds, rate)

    progression = _progression(gen, P.MUSIC_BARS)
    track_drone = np.zeros(count)
    track_pluck = np.zeros(count)
    track_flute = np.zeros(count)

    # O bordão segue a fundamental de cada acorde uma oitava abaixo da melodia. Um bordão
    # imóvel na tônica seria mais "medieval de gaita" e brigaria com metade da progressão.
    for index, degree in enumerate(progression):
        freq = _frequency(root, mode, degree) * 0.5
        dsp.place(track_drone, drone(freq, bar + P.MUSIC_LOOP_TAIL, rate),
                  dsp.samples(index * bar, rate))

    # Arpejo: `arp` notas por compasso, subindo pelas notas do acorde e passando à oitava
    # de cima quando a volta fecha. É o que dá movimento contínuo sem uma segunda melodia.
    arp = max(int(spec["arp"]), 1)
    spacing = bar / float(arp)
    for index, degree in enumerate(progression):
        for step in range(arp):
            tone = TRIAD_STEPS[step % len(TRIAD_STEPS)]
            octave = DEGREES_PER_SCALE * (step // len(TRIAD_STEPS))
            freq = _frequency(root, mode, degree + tone + octave)
            at = dsp.samples(index * bar + step * spacing, rate)
            dsp.place(track_pluck, pluck(freq, min(P.MUSIC_PLUCK_DECAY, bar), rate), at)

    notes = _melody(gen, progression, spec)
    for note_bar, note_beat, degree in notes:
        freq = _frequency(root, mode, degree) * float(2 ** (int(spec["octave"]) - 1))
        length = beat * float(gen.choice([1.0, 1.5, 2.0], p=[0.55, 0.2, 0.25]))
        at = dsp.samples(note_bar * bar + note_beat * beat, rate)
        dsp.place(track_flute, flute(freq, length, rate, gen), at)

    mixed = dsp.mix(
        dsp.gain(dsp.normalize(track_drone, 1.0), float(spec["drone_db"])),
        dsp.gain(dsp.normalize(track_pluck, 1.0), float(spec["pluck_db"])),
        dsp.gain(dsp.normalize(track_flute, 1.0), float(spec["flute_db"])),
    )
    looped = dsp.normalize(dsp.wrap_tail(mixed, dsp.samples(P.MUSIC_LOOP_TAIL, rate)), P.AUDIO_PEAK)
    return looped, {
        "mode": spec["mode"],
        "bpm": float(spec["bpm"]),
        "bars": P.MUSIC_BARS,
        "seconds": dsp.duration(looped, rate),
        "progression": progression,
        "notes": len(notes),
        "tuning": tuning(looped, name, rate),
    }
