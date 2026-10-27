#!/usr/bin/env python3
"""Synthesises the game's sound effects into assets/audio/sfx/*.wav.

Pure stdlib (wave, math, random, struct), deterministic (fixed seeds), so the
set can be regenerated at any time:

    python3 tools/gen_sfx.py            # all sounds
    python3 tools/gen_sfx.py hull_hit   # only the named ones

Look: grounded and mechanical (The Expanse), not cartoony. Weapons are dull
thuds with a crack, hits are metal, explosions are low and short, UI cues are
soft and quiet. 44.1 kHz, mono, 16 bit. mining_laser is a seamless loop.
"""

import math
import os
import random
import struct
import sys
import wave

RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "sfx")
TAU = math.tau


# --- Building blocks ---------------------------------------------------------

def n_samples(seconds):
    return int(seconds * RATE)


def silence(seconds):
    return [0.0] * n_samples(seconds)


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n_samples(seconds))]


def mix_into(dst, src, at=0.0, gain=1.0):
    """Adds src into dst starting at [at] seconds (dst grows if needed)."""
    o = n_samples(at)
    need = o + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[o + i] += v * gain
    return dst


def env_exp(sig, decay, attack=0.0):
    """Exponential decay with time constant [decay] s, linear attack."""
    out = []
    a = max(n_samples(attack), 1)
    for i, v in enumerate(sig):
        t = i / RATE
        e = math.exp(-t / decay)
        if i < a:
            e *= i / a
        out.append(v * e)
    return out


def env_curve(sig, points):
    """Piecewise-linear envelope; points = [(t, gain), ...]."""
    out = []
    j = 0
    for i, v in enumerate(sig):
        t = i / RATE
        while j < len(points) - 2 and t > points[j + 1][0]:
            j += 1
        t0, g0 = points[j]
        t1, g1 = points[j + 1]
        k = 0.0 if t1 <= t0 else min(max((t - t0) / (t1 - t0), 0.0), 1.0)
        out.append(v * (g0 + (g1 - g0) * k))
    return out


def sweep(seconds, f0, f1, shape="exp", harmonics=None, phase=0.0):
    """Sine (or a sum of [harmonics] = [(mult, gain)]) sweeping f0 -> f1."""
    harmonics = harmonics or [(1.0, 1.0)]
    n = n_samples(seconds)
    out = []
    ph = phase
    for i in range(n):
        k = i / max(n - 1, 1)
        if shape == "exp" and f0 > 0 and f1 > 0:
            f = f0 * (f1 / f0) ** k
        else:
            f = f0 + (f1 - f0) * k
        ph += TAU * f / RATE
        out.append(sum(g * math.sin(ph * m) for m, g in harmonics))
    return out


def tone(seconds, freq, harmonics=None):
    return sweep(seconds, freq, freq, "lin", harmonics)


class Biquad:
    """RBJ cookbook biquad; kind = lp, hp, bp."""

    def __init__(self, kind, freq, q=0.707):
        self.kind = kind
        self.q = q
        self.z1 = self.z2 = 0.0
        self.set(freq)

    def set(self, freq):
        freq = min(max(freq, 10.0), RATE * 0.45)
        w = TAU * freq / RATE
        c = math.cos(w)
        s = math.sin(w)
        alpha = s / (2.0 * self.q)
        if self.kind == "lp":
            b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
        elif self.kind == "hp":
            b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
        else:
            b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
        self.b0, self.b1, self.b2 = b0 / a0, b1 / a0, b2 / a0
        self.a1, self.a2 = a1 / a0, a2 / a0

    def run(self, x):
        # Transposed direct form II.
        y = self.b0 * x + self.z1
        self.z1 = self.b1 * x - self.a1 * y + self.z2
        self.z2 = self.b2 * x - self.a2 * y
        return y


def filt(sig, kind, freq, q=0.707):
    """Static or swept filter: freq is a number or a function of t (s)."""
    f = Biquad(kind, freq(0.0) if callable(freq) else freq, q)
    out = []
    for i, v in enumerate(sig):
        if callable(freq) and i % 32 == 0:
            f.set(freq(i / RATE))
        out.append(f.run(v))
    return out


def saturate(sig, drive=1.5):
    k = math.tanh(drive)
    return [math.tanh(v * drive) / k for v in sig]


def gain(sig, g):
    return [v * g for v in sig]


def normalize(sig, peak=0.9):
    m = max((abs(v) for v in sig), default=0.0)
    return sig if m <= 0 else [v * peak / m for v in sig]


def fade_tail(sig, seconds=0.02):
    n = min(n_samples(seconds), len(sig))
    for i in range(n):
        sig[len(sig) - 1 - i] *= i / n
    return sig


def crackle(seconds, rng, density, decay, hp=2500.0):
    """Sparse random clicks thinning out over [decay] s (debris, sparks)."""
    out = silence(seconds)
    for i in range(len(out)):
        t = i / RATE
        if rng.random() < density * math.exp(-t / decay) / RATE:
            amp = rng.uniform(0.3, 1.0)
            for k in range(min(60, len(out) - i)):
                out[i + k] += amp * rng.uniform(-1, 1) * math.exp(-k / 12.0)
    return filt(out, "hp", hp)


def modal(seconds, partials):
    """Struck metal: partials = [(freq, gain, decay)]."""
    out = silence(seconds)
    for f, g, d in partials:
        for i in range(len(out)):
            t = i / RATE
            out[i] += g * math.sin(TAU * f * t) * math.exp(-t / d)
    return out


def write(name, sig, peak=0.9):
    sig = normalize(sig, peak)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in sig))
    print("%-18s %5.2f s" % (name, len(sig) / RATE))


# --- Sounds -------------------------------------------------------------------

def autocannon():
    """Three-round burst: dull thump, crack and a short mechanical tail each."""
    rng = random.Random(11)
    out = silence(0.5)
    for r, at in enumerate((0.0, 0.072, 0.146)):
        thump = env_exp(sweep(0.12, 140, 48), 0.035)
        crack = env_exp(filt(noise(0.06, rng), "bp", 1700 - r * 120, 0.9), 0.012)
        click = env_exp(filt(noise(0.01, rng), "hp", 4000), 0.002)
        tail = env_exp(filt(noise(0.2, rng), "lp", 900), 0.05)
        mix_into(out, thump, at, 1.0)
        mix_into(out, crack, at, 0.7)
        mix_into(out, click, at, 0.25)
        mix_into(out, tail, at + 0.004, 0.35)
    write("autocannon", fade_tail(saturate(out, 1.8)), 0.85)


def missile_launch():
    """Ignition pop, then a rocket roar that opens up and recedes."""
    rng = random.Random(12)
    d = 1.6
    roar = filt(noise(d, rng), "lp", lambda t: 500 + 2600 * min(t / 0.35, 1.0) - 1400 * max(t - 0.6, 0) / 1.0)
    roar = env_curve(roar, [(0, 0), (0.04, 1.0), (0.5, 0.8), (d, 0.0)])
    rumble = env_curve(filt(noise(d, rng), "lp", 160), [(0, 0), (0.05, 1.0), (d, 0.0)])
    pop = env_exp(sweep(0.15, 220, 60), 0.03)
    hiss = env_curve(filt(noise(d, rng), "hp", 3500), [(0, 0), (0.08, 0.5), (0.4, 0.2), (d, 0)])
    out = silence(d)
    mix_into(out, roar, 0.03, 0.8)
    mix_into(out, rumble, 0.03, 1.2)
    mix_into(out, pop, 0.0, 0.9)
    mix_into(out, hiss, 0.03, 0.25)
    write("missile_launch", fade_tail(saturate(out, 1.3)), 0.8)


def mining_laser():
    """Seamless 2 s loop: a low electrical hum with slow beating and a sizzle.
    Every frequency fits a whole number of cycles in the loop."""
    rng = random.Random(13)
    loop = 2.0
    n = n_samples(loop)
    hum = []
    for i in range(n):
        t = i / RATE
        trem = 0.85 + 0.15 * math.sin(TAU * 4.0 * t)
        v = (0.6 * math.sin(TAU * 110.0 * t) + 0.45 * math.sin(TAU * 110.5 * t)
             + 0.3 * math.sin(TAU * 220.0 * t) + 0.12 * math.sin(TAU * 330.0 * t)
             + 0.05 * math.sin(TAU * 661.0 * t))
        hum.append(v * trem)
    # Sizzle: filtered noise crossfaded over the loop seam.
    x = n_samples(0.25)
    raw = filt(noise(loop + 0.25, rng), "bp", 2400, 1.2)
    fizz = []
    for i in range(n):
        if i < x:
            k = i / x
            fizz.append(raw[i] * k + raw[n + i] * (1.0 - k))
        else:
            fizz.append(raw[i])
    out = [h * 0.8 + f * 0.35 for h, f in zip(hum, fizz)]
    write("mining_laser", saturate(out, 1.2), 0.7)


def hull_hit():
    """Slug on armour plate: a thud, a short clang, grit."""
    rng = random.Random(14)
    out = silence(0.45)
    mix_into(out, env_exp(sweep(0.15, 110, 55), 0.04), 0.0, 1.0)
    mix_into(out, modal(0.4, [(410, 0.5, 0.09), (1130, 0.35, 0.06), (1870, 0.25, 0.045), (2690, 0.15, 0.03)]), 0.0, 0.55)
    mix_into(out, env_exp(filt(noise(0.05, rng), "bp", 2200, 0.8), 0.008), 0.0, 0.8)
    mix_into(out, crackle(0.3, rng, 300, 0.05, 3000), 0.005, 0.3)
    write("hull_hit", fade_tail(saturate(out, 1.6)), 0.8)


def shield_hit():
    """Energy bubble taking a round: a falling electric zap over a low wum."""
    rng = random.Random(15)
    d = 0.5
    zap = []
    ph = 0.0
    for i in range(n_samples(d)):
        t = i / RATE
        f = 600 + 1300 * math.exp(-t / 0.05)
        ph += TAU * f / RATE
        zap.append(math.sin(ph + 2.5 * math.sin(TAU * 87 * t)))
    zap = env_exp(zap, 0.07, 0.002)
    wum = env_curve(tone(d, 85, [(1, 1.0), (2, 0.3)]), [(0, 0), (0.02, 1.0), (d, 0)])
    buzz = env_exp(filt(noise(d, rng), "bp", 3200, 2.0), 0.05)
    out = silence(d)
    mix_into(out, zap, 0.0, 0.5)
    mix_into(out, wum, 0.0, 0.6)
    mix_into(out, buzz, 0.0, 0.45)
    write("shield_hit", fade_tail(saturate(out, 1.4)), 0.75)


def explosion_small():
    """Ship-sized: a crack, a low body that closes down, debris ticks."""
    rng = random.Random(16)
    d = 1.8
    body = filt(noise(d, rng), "lp", lambda t: 300 + 2800 * math.exp(-t / 0.12))
    body = env_exp(body, 0.35, 0.004)
    sub = env_exp(sweep(0.8, 75, 28), 0.22, 0.003)
    crack = env_exp(noise(0.03, rng), 0.006)
    out = silence(d)
    mix_into(out, body, 0.0, 1.0)
    mix_into(out, sub, 0.0, 1.3)
    mix_into(out, crack, 0.0, 0.5)
    mix_into(out, crackle(1.4, rng, 900, 0.3, 1800), 0.03, 0.35)
    write("explosion_small", fade_tail(saturate(out, 2.0), 0.2), 0.9)


def explosion_big():
    """Station or den: layered booms, a long rumble, tearing metal."""
    rng = random.Random(17)
    d = 4.5
    out = silence(d)
    for at, g in ((0.0, 1.0), (0.22, 0.7), (0.65, 0.8)):
        body = env_exp(filt(noise(1.8, rng), "lp", lambda t: 200 + 2000 * math.exp(-t / 0.15)), 0.5, 0.005)
        mix_into(out, body, at, g)
        mix_into(out, env_exp(sweep(1.4, 55, 20), 0.45, 0.004), at, 1.3 * g)
    rumble = env_curve(filt(noise(d, rng), "lp", 130), [(0, 0), (0.1, 1.0), (1.5, 0.6), (d, 0)])
    mix_into(out, rumble, 0.0, 1.2)
    groan = env_curve(sweep(2.0, 190, 85, "exp", [(1, 1.0), (2.03, 0.4), (3.1, 0.2)]), [(0, 0), (0.4, 0.4), (1.2, 0.3), (2.0, 0)])
    mix_into(out, filt(groan, "lp", 900), 0.9, 0.25)
    mix_into(out, crackle(3.5, rng, 700, 0.9, 1500), 0.05, 0.35)
    write("explosion_big", fade_tail(saturate(out, 2.2), 0.4), 0.95)


def warp_spool():
    """Drive charging: a rising harmonic hum with a pulse that speeds up."""
    rng = random.Random(18)
    d = 2.2
    hum = sweep(d, 55, 230, "exp", [(1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)])
    out = []
    ph = 0.0
    for i, v in enumerate(hum):
        t = i / RATE
        ph += TAU * (3.0 + 18.0 * (t / d) ** 2) / RATE
        out.append(v * (0.75 + 0.25 * math.sin(ph)))
    out = env_curve(out, [(0, 0), (0.3, 0.35), (d - 0.15, 1.0), (d, 0.0)])
    whine = env_curve(filt(noise(d, rng), "bp", lambda t: 800 + 3200 * (t / d) ** 1.5, 4.0), [(0, 0), (d - 0.15, 1.0), (d, 0)])
    mix_into(out, whine, 0.0, 0.4)
    write("warp_spool", saturate(filt(out, "lp", 4000), 1.3), 0.7)


def warp_jump():
    """Drop into warp: a fast low whoomp and a short shimmer."""
    rng = random.Random(19)
    d = 1.4
    out = silence(d)
    mix_into(out, env_curve(sweep(1.0, 160, 22), [(0, 0), (0.03, 1.0), (1.0, 0)]), 0.0, 1.2)
    mix_into(out, env_exp(filt(noise(0.9, rng), "lp", lambda t: 3000 * math.exp(-t / 0.08) + 120), 0.18, 0.01), 0.0, 0.9)
    shimmer = env_exp(filt(noise(d, rng), "bp", 5200, 3.0), 0.3, 0.02)
    mix_into(out, shimmer, 0.02, 0.2)
    write("warp_jump", fade_tail(saturate(out, 1.6), 0.15), 0.85)


def gate_transit():
    """Jump gate portal: a swelling resonant drone, then a deep thump."""
    rng = random.Random(20)
    d = 2.6
    drone = silence(d)
    for f, g in ((55.0, 1.0), (55.4, 0.8), (82.5, 0.5), (110.3, 0.35), (164.8, 0.15)):
        mix_into(drone, tone(d, f), 0.0, g)
    drone = env_curve(drone, [(0, 0), (1.6, 1.0), (1.9, 0.6), (d, 0)])
    air = filt(noise(d, rng), "bp", lambda t: 300 + 2500 * math.sin(math.pi * min(t / 1.9, 1.0)), 1.5)
    air = env_curve(air, [(0, 0), (1.5, 1.0), (1.9, 0.2), (d, 0)])
    out = silence(d)
    mix_into(out, drone, 0.0, 0.7)
    mix_into(out, air, 0.0, 0.45)
    mix_into(out, env_exp(sweep(0.7, 90, 30), 0.15, 0.004), 1.75, 1.2)
    write("gate_transit", fade_tail(saturate(out, 1.4), 0.2), 0.8)


def dock():
    """Docking clamps: a heavy thud, a clank, the latch, a pressure hiss."""
    rng = random.Random(21)
    out = silence(0.8)
    mix_into(out, env_exp(sweep(0.25, 75, 40), 0.06, 0.002), 0.0, 1.0)
    mix_into(out, modal(0.4, [(185, 0.6, 0.08), (470, 0.4, 0.05), (830, 0.25, 0.04)]), 0.0, 0.5)
    mix_into(out, env_exp(filt(noise(0.02, rng), "hp", 3500), 0.003), 0.13, 0.6)
    mix_into(out, modal(0.1, [(1250, 0.4, 0.02), (2100, 0.2, 0.015)]), 0.13, 0.4)
    mix_into(out, env_curve(filt(noise(0.5, rng), "hp", 2500), [(0, 0), (0.03, 1.0), (0.5, 0)]), 0.22, 0.18)
    write("dock", fade_tail(saturate(out, 1.5)), 0.75)


def undock():
    """Release: latch click, a hiss, then a lighter clamp clunk."""
    rng = random.Random(22)
    out = silence(0.7)
    mix_into(out, env_exp(filt(noise(0.02, rng), "hp", 3500), 0.003), 0.0, 0.6)
    mix_into(out, modal(0.1, [(1180, 0.4, 0.02), (1980, 0.2, 0.015)]), 0.0, 0.4)
    mix_into(out, env_curve(filt(noise(0.35, rng), "hp", 2200), [(0, 0), (0.02, 1.0), (0.35, 0)]), 0.03, 0.22)
    mix_into(out, env_exp(sweep(0.2, 95, 50), 0.05, 0.002), 0.2, 0.8)
    mix_into(out, modal(0.3, [(220, 0.5, 0.06), (560, 0.3, 0.04)]), 0.2, 0.4)
    write("undock", fade_tail(saturate(out, 1.4)), 0.7)


def ui_click():
    """A short, soft tick."""
    rng = random.Random(23)
    out = silence(0.05)
    mix_into(out, env_exp(tone(0.04, 1900), 0.006, 0.0005), 0.0, 0.7)
    mix_into(out, env_exp(filt(noise(0.01, rng), "hp", 5000), 0.0015), 0.0, 0.4)
    mix_into(out, env_exp(tone(0.04, 620), 0.01, 0.0005), 0.0, 0.3)
    write("ui_click", fade_tail(out, 0.01), 0.6)


def build_placed():
    """Structure set down: a heavy thunk, a ring, a servo settling."""
    rng = random.Random(24)
    out = silence(0.9)
    mix_into(out, env_exp(sweep(0.3, 90, 42), 0.08, 0.002), 0.0, 1.0)
    mix_into(out, modal(0.6, [(310, 0.5, 0.12), (770, 0.3, 0.09), (1520, 0.15, 0.06)]), 0.0, 0.45)
    mix_into(out, env_exp(filt(noise(0.03, rng), "bp", 1800), 0.006), 0.0, 0.5)
    servo = sweep(0.3, 260, 180, "exp", [(1, 1.0), (2, 0.5), (3, 0.3), (5, 0.1)])
    servo = env_curve(filt(servo, "lp", 2000), [(0, 0), (0.03, 0.6), (0.25, 0.4), (0.3, 0)])
    mix_into(out, servo, 0.28, 0.25)
    mix_into(out, env_exp(filt(noise(0.02, rng), "hp", 3000), 0.003), 0.58, 0.4)
    write("build_placed", fade_tail(saturate(out, 1.3)), 0.75)


def research_done():
    """Two soft rising data tones."""
    out = silence(1.1)
    for at, f in ((0.0, 659.3), (0.16, 987.8)):
        note = tone(0.8, f, [(1, 1.0), (2, 0.18), (3, 0.06)])
        mix_into(out, env_exp(note, 0.22, 0.008), at, 0.6)
        mix_into(out, env_exp(tone(0.8, f * 1.003), 0.22, 0.008), at, 0.25)
    write("research_done", fade_tail(filt(out, "lp", 5000), 0.1), 0.55)


def alert():
    """Raid incoming: two klaxon pulses, band-limited square, falling pitch."""
    out = silence(1.7)
    for at in (0.0, 0.8):
        k = sweep(0.62, 560, 430, "exp", [(1, 1.0), (3, 0.33), (5, 0.2), (7, 0.14)])
        k = env_curve(k, [(0, 0), (0.02, 1.0), (0.55, 0.8), (0.62, 0)])
        mix_into(out, filt(k, "lp", 2600), at, 0.8)
    write("alert", fade_tail(saturate(out, 1.2), 0.05), 0.7)


def contract_posted():
    """A short teletype-like chirp: three quick blips."""
    out = silence(0.4)
    for at, f in ((0.0, 1200.0), (0.06, 1500.0), (0.12, 1800.0)):
        b = env_curve(tone(0.05, f, [(1, 1.0), (2, 0.15)]), [(0, 0), (0.004, 1.0), (0.04, 0.6), (0.05, 0)])
        mix_into(out, b, at, 0.6)
    write("contract_posted", fade_tail(filt(out, "lp", 6000), 0.05), 0.5)


def credits():
    """Subtle chime: two soft bell partials."""
    out = silence(0.8)
    for at, f in ((0.0, 1318.5), (0.07, 1975.5)):
        bell = modal(0.7, [(f, 1.0, 0.22), (f * 2.76, 0.2, 0.08)])
        mix_into(out, env_exp(bell, 10.0, 0.004), at, 0.5)
    write("credits", fade_tail(out, 0.1), 0.45)


SOUNDS = {
    "autocannon": autocannon,
    "missile_launch": missile_launch,
    "mining_laser": mining_laser,
    "hull_hit": hull_hit,
    "shield_hit": shield_hit,
    "explosion_small": explosion_small,
    "explosion_big": explosion_big,
    "warp_spool": warp_spool,
    "warp_jump": warp_jump,
    "gate_transit": gate_transit,
    "dock": dock,
    "undock": undock,
    "ui_click": ui_click,
    "build_placed": build_placed,
    "research_done": research_done,
    "alert": alert,
    "contract_posted": contract_posted,
    "credits": credits,
}


if __name__ == "__main__":
    names = sys.argv[1:] or list(SOUNDS)
    for name in names:
        if name not in SOUNDS:
            sys.exit("unknown sound: %s (have: %s)" % (name, ", ".join(SOUNDS)))
        SOUNDS[name]()
