"""Escrita de PNG em stdlib pura. O bastante para uma tira de cores.

Existe porque `make daynight` roda **sem renderizador** — o que ele mede são os números
que alimentam o `Environment`, não os pixels que saem dele — e mesmo assim a fase precisa
de olhos. A tira do dia é desenhada a partir dos mesmos valores medidos: se a cor do céu
saltar, o salto aparece como uma listra na tira antes de aparecer em qualquer número.

PNG sem filtro de linha: o filtro é sempre `None` e a compressão é a do `zlib` da stdlib.
Numa tira de faixas de cor lisa isso não custa nada — a do dia sai com 4,5 KiB —, e o
código cabe em quarenta linhas em vez de depender de uma biblioteca de imagem.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

from .util import ROOT

CHANNELS = 3
BIT_DEPTH = 8
COLOR_TYPE_RGB = 2
FILTER_NONE = 0


class Canvas:
    """Uma imagem RGB de tamanho fixo, com pintura por retângulo."""

    def __init__(self, width: int, height: int, background: tuple[int, int, int]) -> None:
        self.width = width
        self.height = height
        self._pixels = bytearray(bytes(background) * (width * height))

    def fill(self, x: int, y: int, width: int, height: int, color: tuple[int, int, int]) -> None:
        left, top = max(x, 0), max(y, 0)
        right, bottom = min(x + width, self.width), min(y + height, self.height)
        if right <= left or bottom <= top:
            return
        row = bytes(color) * (right - left)
        for line in range(top, bottom):
            start = (line * self.width + left) * CHANNELS
            self._pixels[start:start + len(row)] = row

    def column(self, x: int, y: int, height: int, color: tuple[int, int, int]) -> None:
        self.fill(x, y, 1, height, color)

    def to_png(self) -> bytes:
        raw = bytearray()
        for line in range(self.height):
            start = line * self.width * CHANNELS
            raw.append(FILTER_NONE)
            raw += self._pixels[start:start + self.width * CHANNELS]

        header = struct.pack(
            ">IIBBBBB", self.width, self.height, BIT_DEPTH, COLOR_TYPE_RGB, 0, 0, 0
        )
        return (
            b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", header)
            + _chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + _chunk(b"IEND", b"")
        )

    def save(self, relative_path: str | Path) -> Path:
        path = ROOT / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.to_png())
        return path


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def hex_to_bytes(hex_color: str) -> tuple[int, int, int]:
    value = hex_color.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))  # type: ignore[return-value]


def scale(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(round(channel * factor)))) for channel in color)  # type: ignore[return-value]
