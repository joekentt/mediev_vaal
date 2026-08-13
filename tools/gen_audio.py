"""Gera o áudio derivado: layout de barramentos e o tom de calibração.

O layout de barramentos (`default_bus_layout.tres`) sai de `params.AUDIO_BUSES` — mexer
em volume de barramento é mexer no .py, nunca no painel de Audio do editor.

O tom de calibração é um seno de 1 kHz sintetizado aqui em Python. Não é conteúdo de
jogo: é o sinal de teste que prova o caminho inteiro (síntese em Python -> .wav ->
import do Godot -> AudioManager -> barramento). É esse mesmo caminho que a fase 10 usa
para a trilha e os efeitos de verdade.
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

from . import params as P
from .util import GENERATED_HEADER, ROOT, write_if_changed

BUS_LAYOUT_OUTPUT = Path("assets/generated/audio/default_bus_layout.tres")
TONE_OUTPUT = Path("assets/generated/audio/calibration_tone.wav")

_INT16_MAX = 32767
_MS_PER_SEC = 1000.0


def _bus_layout() -> str:
    lines = [
        GENERATED_HEADER("tools/gen_audio.py", "tools/params.py", ";"),
        '[gd_resource type="AudioBusLayout" format=3]',
        "",
        "[resource]",
    ]
    for index, (name, volume_db, send) in enumerate(P.AUDIO_BUSES):
        lines.append(f'bus/{index}/name = &"{name}"')
        lines.append(f"bus/{index}/solo = false")
        lines.append(f"bus/{index}/mute = false")
        lines.append(f"bus/{index}/bypass_fx = false")
        lines.append(f"bus/{index}/volume_db = {P.num(volume_db)}")
        lines.append(f'bus/{index}/send = &"{send}"')
    return "\n".join(lines) + "\n"


def _calibration_tone_bytes() -> bytes:
    """Seno com fade in/out curto — sem clique nas bordas."""
    sample_rate = P.AUDIO_SAMPLE_RATE
    total = int(sample_rate * P.CALIBRATION_TONE_SEC)
    fade = max(1, int(sample_rate * P.CALIBRATION_TONE_FADE_MS / _MS_PER_SEC))
    amplitude = 10.0 ** (P.CALIBRATION_TONE_DB / 20.0)
    angular = 2.0 * math.pi * P.CALIBRATION_TONE_HZ / sample_rate

    samples = bytearray()
    for index in range(total):
        envelope = 1.0
        if index < fade:
            envelope = index / fade
        elif index >= total - fade:
            envelope = (total - index) / fade
        value = math.sin(angular * index) * amplitude * envelope
        samples += struct.pack("<h", int(round(value * _INT16_MAX)))
    return bytes(samples)


def _write_tone() -> list[Path]:
    path = ROOT / TONE_OUTPUT
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = _calibration_tone_bytes()

    if path.exists():
        with wave.open(str(path), "rb") as existing:
            if existing.readframes(existing.getnframes()) == payload:
                return []

    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(P.AUDIO_SAMPLE_RATE)
        handle.writeframes(payload)
    return [path]


def main() -> list[Path]:
    written = write_if_changed(BUS_LAYOUT_OUTPUT, _bus_layout())
    written += _write_tone()
    bus_names = ", ".join(name for name, _, _ in P.AUDIO_BUSES)
    print(f"  barramentos: {bus_names}")
    print(
        f"  tom de calibração: {P.num(P.CALIBRATION_TONE_HZ)} Hz, "
        f"{P.num(P.CALIBRATION_TONE_SEC)} s, {P.num(P.CALIBRATION_TONE_DB)} dBFS"
    )
    return written


if __name__ == "__main__":
    main()
