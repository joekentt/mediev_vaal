"""Ferramentas de síntese em NumPy: osciladores, envelopes, filtros e mistura.

É o `meshlib.py` do som. Nenhuma função daqui conhece o jogo — elas fazem ruído, seno,
envelope e filtro, e quem sabe o que é um passo na pedra é `gen_audio.py`.

Duas escolhas de projeto valem estar escritas, porque as duas foram deliberadas:

**Filtro é por FFT, não por recursão.** Um biquad é a forma clássica, e é recursivo: cada
amostra depende da anterior, o que em Python puro seria um laço de 44 100 iterações por
segundo de som. Multiplicar o espectro por uma máscara é vetorizado, roda em milissegundos
e dá controle exato sobre a forma da banda. O preço é que o filtro não pode variar ao
longo do tempo — e onde isso faz falta (o rangido da porta), a solução foi mudar a
**fonte** e deixar o filtro parado: a porta é um trem de pulsos que escorrega, passando por
uma ressonância fixa de madeira, que é o que fisicamente acontece.

**Frequência varia por fase integrada.** Para um som que escorrega de altura, somar
`2π·f/sr` ao longo do tempo e tomar o seno da soma acumulada é a única forma de não ter
descontinuidade de fase. Recalcular `sin(2π·f(t)·t)` com `f` variável parece igual e
produz um estalo em cada amostra em que `f` muda.
"""

from __future__ import annotations

import struct
import wave
from pathlib import Path

import numpy as np

from .util import ROOT, write_bytes_if_changed

TWO_PI = 2.0 * np.pi
INT16_MAX = 32767
MS_PER_SEC = 1000.0
# Largura da saia dos filtros, em oitavas. Corte abrupto no espectro vira eco antes e
# depois do transiente (o zumbido de Gibbs); uma oitava de rampa some com ele.
SKIRT_OCTAVES = 0.5


def generator(seed: int) -> np.random.Generator:
    """Fonte de aleatório da síntese. PCG64 semeado: mesma seed, mesmo byte."""
    return np.random.default_rng(seed)


def samples(seconds: float, rate: int) -> int:
    return max(int(round(seconds * rate)), 1)


def silence(seconds: float, rate: int) -> np.ndarray:
    return np.zeros(samples(seconds, rate), dtype=np.float64)


def noise(gen: np.random.Generator, count: int) -> np.ndarray:
    """Ruído branco em [-1, 1]. A base de tudo que é percussivo ou soprado."""
    return gen.uniform(-1.0, 1.0, count)


def timeline(count: int, rate: int) -> np.ndarray:
    return np.arange(count, dtype=np.float64) / float(rate)


def sine(freq: np.ndarray | float, count: int, rate: int, phase: float = 0.0) -> np.ndarray:
    """Seno de frequência fixa ou variável, por fase integrada."""
    return np.sin(_phase(freq, count, rate) + phase)


def _phase(freq: np.ndarray | float, count: int, rate: int) -> np.ndarray:
    if np.isscalar(freq):
        return TWO_PI * float(freq) * timeline(count, rate)
    curve = np.asarray(freq, dtype=np.float64)
    return TWO_PI * np.cumsum(curve) / float(rate)


def fm(
    carrier: np.ndarray | float,
    ratio: float,
    index: np.ndarray | float,
    count: int,
    rate: int,
) -> np.ndarray:
    """Modulação de frequência: o caminho curto para um espectro largo que escorrega.

    Um chilro de pássaro tem dezenas de parciais que se movem juntos. Somados um a um
    seriam dezenas de osciladores; em FM são dois, e o índice de modulação é o botão que
    abre e fecha o espectro inteiro de uma vez.
    """
    modulator = np.sin(_phase(np.asarray(carrier, dtype=np.float64) * ratio, count, rate))
    return np.sin(_phase(carrier, count, rate) + np.asarray(index) * modulator)


def sweep(start: float, end: float, count: int, curve: float = 1.0) -> np.ndarray:
    """Rampa geométrica de `start` a `end`. Geométrica porque altura é multiplicativa:
    subir uma oitava é dobrar, e uma rampa linear em Hz sobe rápido demais no começo."""
    t = np.linspace(0.0, 1.0, count) ** curve
    return start * (end / start) ** t


def pulse_train(freq: np.ndarray | float, count: int, rate: int, width: float = 0.02) -> np.ndarray:
    """Trem de pulsos curtos na frequência dada. É a fonte de voz humana (a glote) e a de
    um rangido (o escorrega-e-agarra da madeira) — o que muda é o filtro depois."""
    phase = np.mod(_phase(freq, count, rate) / TWO_PI, 1.0)
    return np.where(phase < width, 1.0, 0.0) - width


def env_decay(count: int, rate: int, decay: float) -> np.ndarray:
    """Queda exponencial. `decay` é o tempo até 1/e — quase todo som percussivo é isto."""
    return np.exp(-timeline(count, rate) / max(decay, 1e-4))


def env_ar(count: int, rate: int, attack: float, release: float) -> np.ndarray:
    """Ataque e queda, com o corpo no meio. Ataque em zero seria um clique."""
    envelope = np.ones(count)
    rise = min(samples(attack, rate), count)
    fall = min(samples(release, rate), count - rise) if count > rise else 0
    if rise > 0:
        envelope[:rise] = np.linspace(0.0, 1.0, rise)
    if fall > 0:
        envelope[count - fall:] = np.linspace(1.0, 0.0, fall)
    return envelope


def lfo(count: int, rate: int, freq: float, depth: float, phase: float = 0.0) -> np.ndarray:
    """Oscilação lenta em torno de 1. É o que faz vento ter rajada e flauta ter vibrato."""
    return 1.0 + depth * np.sin(TWO_PI * freq * timeline(count, rate) + phase)


def band(
    signal: np.ndarray,
    rate: int,
    low: float | None = None,
    high: float | None = None,
) -> np.ndarray:
    """Passa-banda por FFT, com saias suaves. `low`/`high` em Hz; `None` deixa passar."""
    if signal.size == 0:
        return signal
    spectrum = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(signal.size, 1.0 / rate)
    gain = np.ones(freqs.size)
    safe = np.maximum(freqs, 1e-6)
    if low is not None and low > 0.0:
        # Rampa em oitavas, não em Hz: o ouvido ouve razão de frequência, e uma saia de
        # 200 Hz é suave em 4 kHz e um penhasco em 300 Hz.
        gain *= np.clip(np.log2(safe / low) / SKIRT_OCTAVES + 1.0, 0.0, 1.0)
    if high is not None and high > 0.0:
        gain *= np.clip(np.log2(high / safe) / SKIRT_OCTAVES + 1.0, 0.0, 1.0)
    return np.fft.irfft(spectrum * gain, n=signal.size)


def resonate(signal: np.ndarray, rate: int, freq: float, q: float) -> np.ndarray:
    """Ressonância em `freq` com fator `q`. É o corpo de madeira, o formante da vogal e o
    tom de uma bigorna — tudo que soa "de alguma coisa" em vez de "de nada"."""
    if signal.size == 0:
        return signal
    spectrum = np.fft.rfft(signal)
    freqs = np.maximum(np.fft.rfftfreq(signal.size, 1.0 / rate), 1e-6)
    detune = freqs / freq - freq / freqs
    return np.fft.irfft(spectrum / np.sqrt(1.0 + (q * detune) ** 2), n=signal.size)


def tilt(signal: np.ndarray, rate: int, db_per_octave: float, pivot: float = 1000.0) -> np.ndarray:
    """Inclina o espectro. Voz grave não é voz aguda com menos agudo: é uma inclinação
    diferente da mesma fonte, e é isso que este filtro faz."""
    spectrum = np.fft.rfft(signal)
    freqs = np.maximum(np.fft.rfftfreq(signal.size, 1.0 / rate), 1e-6)
    octaves = np.log2(freqs / pivot)
    return np.fft.irfft(spectrum * 10.0 ** (db_per_octave * octaves / 20.0), n=signal.size)


def gain(signal: np.ndarray, decibels: float) -> np.ndarray:
    return signal * 10.0 ** (decibels / 20.0)


def mix(*layers: np.ndarray) -> np.ndarray:
    """Soma camadas de comprimentos diferentes, esticando o resultado até a mais longa."""
    usable = [layer for layer in layers if layer is not None and layer.size > 0]
    if not usable:
        return np.zeros(1)
    total = np.zeros(max(layer.size for layer in usable))
    for layer in usable:
        total[: layer.size] += layer
    return total


def place(target: np.ndarray, piece: np.ndarray, at: int, level: float = 1.0) -> None:
    """Soma `piece` dentro de `target` na amostra `at`, cortando o que passar do fim.

    Corta em vez de dar a volta de propósito: para leito que precisa fechar o laço existe
    `wrap_tail`, e escolher isso explicitamente é melhor que descobrir que um som vazou
    para o começo do arquivo.
    """
    if at >= target.size:
        return
    end = min(at + piece.size, target.size)
    target[at:end] += piece[: end - at] * level


def wrap_tail(signal: np.ndarray, tail: int) -> np.ndarray:
    """Fecha o laço: a cauda que passaria do fim volta somada no começo.

    É o que faz um leito de 22 s tocar em repetição sem a costura aparecer. Cortar no fim
    deixa um silêncio abrupto; desvanecer as duas pontas deixa um buraco de volume a cada
    volta. Somar a cauda no começo é a única das três que não se ouve.
    """
    if tail <= 0 or tail >= signal.size:
        return signal
    body = signal[:-tail].copy()
    body[:tail] += signal[-tail:]
    return body


def fade_edges(signal: np.ndarray, rate: int, ms: float) -> np.ndarray:
    """Rampa nas duas pontas. Sem isto, todo .wav começa e termina com um clique."""
    count = min(samples(ms / MS_PER_SEC, rate), signal.size // 2)
    if count <= 1:
        return signal
    out = signal.copy()
    ramp = np.linspace(0.0, 1.0, count)
    out[:count] *= ramp
    out[-count:] *= ramp[::-1]
    return out


def normalize(signal: np.ndarray, peak: float) -> np.ndarray:
    """Leva o pico ao valor pedido. Um som sintetizado sem isto sai ou inaudível ou
    estourado, e qual dos dois depende de quantas camadas ele acabou tendo."""
    top = float(np.max(np.abs(signal))) if signal.size else 0.0
    if top <= 1e-9:
        return signal
    return signal * (peak / top)


def encode(signal: np.ndarray, rate: int) -> bytes:
    """Converte para o .wav mono de 16 bits que o Godot importa."""
    clipped = np.clip(signal, -1.0, 1.0)
    words = np.round(clipped * INT16_MAX).astype("<i2")
    return words.tobytes()


def write_wav(relative_path: str | Path, signal: np.ndarray, rate: int) -> list[Path]:
    """Grava o .wav se o conteúdo mudou. Devolve o que foi tocado."""
    payload = encode(signal, rate)
    header = _wav_header(len(payload), rate)
    return write_bytes_if_changed(relative_path, header + payload)


def _wav_header(size: int, rate: int) -> bytes:
    """Cabeçalho RIFF escrito à mão.

    O módulo `wave` da stdlib faria o mesmo, mas só escrevendo em disco — e escrever
    sempre derrotaria o `write_bytes_if_changed`, que é o que impede o Godot de reimportar
    quarenta arquivos idênticos a cada `make all`.
    """
    channels, width = 1, 2
    return (
        b"RIFF"
        + struct.pack("<I", 36 + size)
        + b"WAVEfmt "
        + struct.pack("<IHHIIHH", 16, 1, channels, rate, rate * channels * width,
                      channels * width, width * 8)
        + b"data"
        + struct.pack("<I", size)
    )


def read_wav(relative_path: str | Path) -> tuple[np.ndarray, int]:
    """Lê de volta um .wav gerado, em [-1, 1]. Usado pela prova e pelas receitas de leito
    que reaproveitam efeitos já sintetizados."""
    with wave.open(str(ROOT / relative_path), "rb") as handle:
        rate = handle.getframerate()
        raw = handle.readframes(handle.getnframes())
    return np.frombuffer(raw, dtype="<i2").astype(np.float64) / INT16_MAX, rate


def duration(signal: np.ndarray, rate: int) -> float:
    return signal.size / float(rate)
