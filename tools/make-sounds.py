#!/usr/bin/env python3
"""Writes the built-in sounds to sounds/. Same synthesis as the omatimer app:
a sine with a quieter, slightly inharmonic overtone (what makes a bell sound
like a bell), a 4 ms fade-in so it doesn't pop, and an exponential fade-out.
16-bit mono WAV. Run from the repo root: python3 tools/make-sounds.py"""

import math
import struct
from pathlib import Path

RATE = 44100


def synth(notes, seconds):
    """notes: (start s, freq Hz, level 0..1, decay s to fade to ~37%)"""
    n = int(seconds * RATE)
    mixed = [0.0] * n
    for start, freq, level, decay in notes:
        for i in range(int(start * RATE), n):
            t = i / RATE - start
            env = min(1.0, t / 0.004) * math.exp(-t / decay)
            mixed[i] += level * env * (
                math.sin(2 * math.pi * freq * t)
                + 0.25 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-t / 0.15)
            )
    pcm = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000)) for v in mixed)
    header = b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt "
    header += struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16)
    return header + b"data" + struct.pack("<I", len(pcm)) + pcm


SOUNDS = {
    # three rising notes, C6 E6 G6
    "chime": ([(0, 1046.5, 0.30, 0.45), (0.14, 1318.5, 0.28, 0.45), (0.28, 1568, 0.28, 0.6)], 1.8),
    # one struck A5
    "bell": ([(0, 880, 0.45, 0.7)], 2.2),
    # a short soft tick
    "click": ([(0, 1800, 0.35, 0.012)], 0.08),
}

out = Path(__file__).resolve().parent.parent / "sounds"
out.mkdir(exist_ok=True)
for name, (notes, seconds) in SOUNDS.items():
    (out / f"{name}.wav").write_bytes(synth(notes, seconds))
    print(f"sounds/{name}.wav")
