#!/usr/bin/env python3
"""Generates the game's sound effects with the ElevenLabs sound effects API
into assets/audio/sfx/*.wav (the source the game ships with; tools/gen_sfx.py
is the offline synth fallback that writes the same names).

    python3 tools/gen_sfx_elevenlabs.py               # missing files only
    python3 tools/gen_sfx_elevenlabs.py --force       # regenerate all
    python3 tools/gen_sfx_elevenlabs.py hull_hit_2    # only the named files
    python3 tools/gen_sfx_elevenlabs.py --post-only   # re-run trim/levels on the raw files

The API key is read at runtime from ~/.config/elevenlabs/api_key (one line)
and only ever sent in the request header. It is never printed or written.

Each request asks for raw PCM (mono 16 bit 44.1 kHz). The raw take is kept in
tools/sfx_raw/ (ignored by Godot via .gdignore) so the level pass can be
re-run without new generations. The level pass trims leading and trailing
silence (not on loops), fades the tail, then sets the RMS to the sound's
target with a peak ceiling, so all sounds sit together before the per-sound
volume in scripts/sfx.gd.

Existing files are skipped unless --force, so re-runs cost nothing.
Variants: name_1.wav, name_2.wav, ...; scripts/sfx.gd picks one at random.
"""

import array
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request
import wave

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
RAW_DIR = os.path.join(ROOT, "tools", "sfx_raw")  # .gdignore'd raw takes
KEY_PATH = os.path.expanduser("~/.config/elevenlabs/api_key")
URL = "https://api.elevenlabs.io/v1/sound-generation?output_format=pcm_44100"

STYLE = "dry, realistic sci-fi, hard science fiction like The Expanse, no music, no voices, no reverb tail"

# name: (prompt, duration s, prompt influence, loop, variants, target RMS dBFS, max length s)
SOUNDS = {
    "autocannon": ("short three-round burst from a heavy ship-mounted autocannon, punchy mechanical thuds with a sharp crack, " + STYLE, 0.6, 0.6, False, 3, -14.0, 0.6),
    "missile_launch": ("small missile launching from a warship rail, ignition pop then a short rocket motor roar moving away, " + STYLE, 1.6, 0.5, False, 1, -16.0, 1.8),
    "mining_laser": ("steady low electrical hum of an industrial mining laser cutting rock, faint sizzle, constant, seamless, " + STYLE, 3.0, 0.5, True, 1, -20.0, 0.0),
    "hull_hit": ("kinetic slug impacting thick spaceship armour plate, heavy metallic clank and thud, " + STYLE, 0.5, 0.6, False, 3, -15.0, 0.5),
    "shield_hit": ("projectile hitting an energy shield, short electric zap with a low hum, " + STYLE, 0.6, 0.5, False, 1, -17.0, 0.6),
    "explosion_small": ("small spaceship exploding, muffled heavy blast with metal debris, short tail, " + STYLE, 1.5, 0.5, False, 3, -13.0, 1.8),
    "explosion_big": ("huge space station explosion, deep layered booms, long low rumble and tearing metal, " + STYLE, 4.0, 0.5, False, 1, -12.0, 4.5),
    "warp_spool": ("spaceship drive spooling up, rising electrical hum building in pitch, " + STYLE, 2.0, 0.5, False, 1, -19.0, 2.2),
    "warp_jump": ("spaceship engaging a warp drive, sudden deep whoomp and pressure release, " + STYLE, 1.2, 0.5, False, 1, -16.0, 1.5),
    "gate_transit": ("ship passing through a giant ring gate, deep resonant swell then a heavy thump, " + STYLE, 2.5, 0.5, False, 1, -16.0, 2.8),
    "dock": ("spaceship docking clamps engaging, heavy metal clunk, latch click and a short air hiss, " + STYLE, 0.8, 0.6, False, 1, -17.0, 0.9),
    "undock": ("docking clamps releasing, latch click, air hiss and a lighter metal clunk, " + STYLE, 0.8, 0.6, False, 1, -18.0, 0.9),
    "ui_click": ("single soft user interface click, short dry tick", 0.5, 0.6, False, 1, -24.0, 0.08),
    "build_placed": ("heavy modular structure locking into place, deep metal thunk and a short servo whir, " + STYLE, 0.9, 0.5, False, 1, -16.0, 1.0),
    "research_done": ("soft two-tone computer confirmation chime, clean and subtle, no music", 1.0, 0.5, False, 1, -22.0, 1.2),
    "alert": ("spaceship alarm klaxon, two short urgent pulses, dry", 1.6, 0.6, False, 1, -18.0, 1.8),
    "contract_posted": ("short digital data chirp, three quick soft blips, computer terminal", 0.5, 0.6, False, 1, -24.0, 0.45),
    "credits": ("very subtle soft coin-like digital chime, quiet and short", 0.6, 0.5, False, 1, -27.0, 0.7),
}
PEAK_CEILING_DB = -1.0
SILENCE_DB = -45.0


def files():
    """(file name, sound name) for every output file, variants expanded."""
    out = []
    for name, spec in SOUNDS.items():
        n = spec[4]
        if n <= 1:
            out.append((name, name))
        else:
            out.extend(("%s_%d" % (name, i + 1), name) for i in range(n))
    return out


def read_key():
    with open(KEY_PATH, "r", encoding="utf-8") as f:
        return f.read().strip()


def request(key, prompt, duration, influence, loop):
    """Raw PCM bytes. Retries once without loop if the API rejects it."""
    body = {"text": prompt, "duration_seconds": duration, "prompt_influence": influence}
    if loop:
        body["loop"] = True
    for attempt in range(3):
        req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                     headers={"xi-api-key": key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode("utf-8", "replace")
            if e.code in (400, 422) and "loop" in body:
                print("  loop rejected (%d), retrying without" % e.code)
                body.pop("loop")
                continue
            if e.code == 429 and attempt < 2:
                time.sleep(5)
                continue
            raise SystemExit("API error %d: %s" % (e.code, msg))
    raise SystemExit("API failed")


def to_floats(pcm):
    a = array.array("h")
    a.frombytes(pcm[: len(pcm) // 2 * 2])
    if sys.byteorder != "little":
        a.byteswap()
    return [v / 32768.0 for v in a]


def db(x):
    return 20.0 * math.log10(max(x, 1e-9))


def post(sig, loop, target_rms_db, max_len):
    """Trim, fade, level. Returns (samples, report)."""
    thr = 10 ** (SILENCE_DB / 20.0)
    if not loop:
        start = next((i for i, v in enumerate(sig) if abs(v) > thr), 0)
        end = len(sig) - next((i for i, v in enumerate(reversed(sig)) if abs(v) > thr), 0)
        start = max(start - int(0.003 * RATE), 0)
        sig = sig[start:end]
        if max_len > 0 and len(sig) > int(max_len * RATE):
            sig = sig[: int(max_len * RATE)]
        fade = min(int(0.03 * RATE), len(sig) // 4)
        for i in range(fade):
            sig[len(sig) - 1 - i] *= i / fade
        fade_in = min(int(0.002 * RATE), len(sig) // 8)
        for i in range(fade_in):
            sig[i] *= i / fade_in
    if not sig:
        return sig, "empty"
    # Loudness: all of a loop, the loudest 0.3 s window of a one-shot (swells
    # and late booms count, not the quiet start).
    if loop:
        rms = math.sqrt(sum(v * v for v in sig) / len(sig))
    else:
        win = min(int(0.3 * RATE), len(sig))
        acc = sum(v * v for v in sig[:win])
        best = acc
        for i in range(win, len(sig)):
            acc += sig[i] * sig[i] - sig[i - win] * sig[i - win]
            best = max(best, acc)
        rms = math.sqrt(max(best, 0.0) / win)
    peak = max(abs(v) for v in sig)
    g = min(10 ** ((target_rms_db - db(rms)) / 20.0), 10 ** (PEAK_CEILING_DB / 20.0) / max(peak, 1e-9))
    sig = [v * g for v in sig]
    rep = "%.2f s  rms %.1f dB  peak %.1f dB" % (len(sig) / RATE, db(rms * g), db(peak * g))
    return sig, rep


def write_wav(path, sig):
    a = array.array("h", (int(max(-1.0, min(1.0, v)) * 32767) for v in sig))
    if sys.byteorder != "little":
        a.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(a.tobytes())


def main():
    args = sys.argv[1:]
    force = "--force" in args
    post_only = "--post-only" in args
    names = [a for a in args if not a.startswith("--")]
    todo = [f for f in files() if not names or f[0] in names or f[1] in names]
    if names and not todo:
        raise SystemExit("unknown sound(s): %s" % ", ".join(names))
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(RAW_DIR, exist_ok=True)
    gdignore = os.path.join(RAW_DIR, ".gdignore")
    if not os.path.exists(gdignore):
        open(gdignore, "w").close()
    key = None
    made = 0
    for fname, sname in todo:
        prompt, dur, infl, loop, _n, target, max_len = SOUNDS[sname]
        out = os.path.join(OUT_DIR, fname + ".wav")
        raw = os.path.join(RAW_DIR, fname + ".pcm")
        if os.path.exists(out) and not force and not post_only:
            print("%-18s exists, skipped" % fname)
            continue
        if not os.path.exists(raw) or (force and not post_only):
            if post_only:
                print("%-18s no raw take, skipped" % fname)
                continue
            key = key or read_key()
            print("%-18s generating (%.1f s)" % (fname, dur))
            with open(raw, "wb") as f:
                f.write(request(key, prompt, dur, infl, loop))
            made += 1
        with open(raw, "rb") as f:
            sig, rep = post(to_floats(f.read()), loop, target, max_len)
        write_wav(out, sig)
        print("%-18s %s" % (fname, rep))
    print("generations this run: %d" % made)


if __name__ == "__main__":
    main()
