#!/usr/bin/env python3
"""Turns a folder of source sounds (mp3/wav/m4a/...) into game-ready takes.

    python3 tools/prep_sfx.py "assets/audio/sfx/laser bolt" laser_bolt --max 1.0

Writes assets/audio/sfx/<stem>_1.wav .. <stem>_N.wav (sorted by source
name): decoded with macOS afconvert, mixed to mono, leading silence cut
(below -40 dBFS), capped at --max seconds with a --fade s fade-out, and
levelled so the loudest 100 ms peaks at -14 dBFS (the mix then lives in the
"db" column of scripts/sfx.gd). The source folder gets a .gdignore so Godot
does not import (or ship) the originals.
"""
import argparse
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

OUT_DIR = "assets/audio/sfx"
EXTS = (".mp3", ".wav", ".m4a", ".aif", ".aiff", ".flac", ".caf")
GATE_DB = -40.0
TARGET_DB = -14.0


def decode(path: str, tmp: str) -> tuple[list[float], int]:
	out = os.path.join(tmp, "dec.wav")
	subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", path, out], check=True)
	with wave.open(out) as w:
		ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
		raw = struct.unpack(f"<{n * ch}h", w.readframes(n))
	mono = [sum(raw[i * ch:(i + 1) * ch]) / (ch * 32768.0) for i in range(n)]
	return mono, rate


def process(s: list[float], rate: int, max_s: float, fade_s: float) -> list[float]:
	gate = 10 ** (GATE_DB / 20)
	start = next((i for i, v in enumerate(s) if abs(v) > gate), 0)
	s = s[max(start - int(rate * 0.002), 0):]
	s = s[:int(rate * max_s)]
	fade = min(int(rate * fade_s), len(s))
	for i in range(fade):
		s[len(s) - fade + i] *= math.cos(0.5 * math.pi * i / fade)
	win = int(rate * 0.1)
	loud = max(max(abs(v) for v in s[j:j + win]) for j in range(0, len(s), win // 4))
	gain = 10 ** (TARGET_DB / 20) / max(loud, 1e-6)
	return [max(-1.0, min(1.0, v * gain)) for v in s]


def main() -> None:
	ap = argparse.ArgumentParser()
	ap.add_argument("src")
	ap.add_argument("stem")
	ap.add_argument("--max", type=float, default=1.0)
	ap.add_argument("--fade", type=float, default=0.3)
	a = ap.parse_args()
	files = sorted(f for f in os.listdir(a.src) if f.lower().endswith(EXTS))
	if not files:
		sys.exit(f"no sounds in {a.src}")
	with tempfile.TemporaryDirectory() as tmp:
		for i, f in enumerate(files, 1):
			s, rate = decode(os.path.join(a.src, f), tmp)
			s = process(s, rate, a.max, a.fade)
			out = os.path.join(OUT_DIR, f"{a.stem}_{i}.wav")
			with wave.open(out, "wb") as w:
				w.setnchannels(1)
				w.setsampwidth(2)
				w.setframerate(rate)
				w.writeframes(struct.pack(f"<{len(s)}h", *(int(v * 32767) for v in s)))
			print(f"{f} -> {out} ({len(s) / rate:.2f} s)")
	open(os.path.join(a.src, ".gdignore"), "a").close()


if __name__ == "__main__":
	main()
