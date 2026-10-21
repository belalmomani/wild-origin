#!/usr/bin/env python3
"""Generates all game audio procedurally (22.05 kHz 16-bit mono WAV): SFX, day/night ambience loops, music loop.
No third-party audio -> no licensing issues. Run: python3 tools/gen_audio.py"""
import os, wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(2026)

def T(d): return np.arange(int(SR * d)) / SR
def noise(n): return rng.standard_normal(n)
def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def band(x, lo=None, hi=None):
    """FFT band-pass with soft edges (also periodic -> loops cleanly)."""
    F = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR); g = np.ones_like(f)
    if lo: g *= smooth(lo * .7, lo * 1.3, f)
    if hi: g *= 1 - smooth(hi * .8, hi * 1.2, f)
    return np.fft.irfft(F * g, len(x))

def env_ad(t, a=.004, k=20.0): return np.minimum(t / a, 1) * np.exp(-t * k)
def norm(x, peak=.85): return x / (np.abs(x).max() + 1e-9) * peak
def sine(t, f, ph=0): return np.sin(2 * np.pi * f * t + ph)

def save(name, x):
    if name in LOOPS:                      # 40 ms equal-power crossfade of the tail into the head -> click-free loop
        f = int(SR * .04); w = np.linspace(0, 1, f); x = x.copy()
        x[:f] = x[:f] * np.sqrt(w) + x[-f:] * np.sqrt(1 - w); x = x[:-f]
    x = np.clip(x, -1, 1); fade = min(len(x) // 50, 200)
    if name not in LOOPS: x = x.copy(); x[:20] *= np.linspace(0, 1, 20); x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype("<i2").tobytes())

LOOPS = {"ambient_day", "ambient_night", "music"}

# ------------------------------------------------------------------ SFX ----
def chop():
    t = T(.42); thud = sine(t, 110 * np.exp(-t * 7) + 48) * np.exp(-t * 13)
    crack = band(noise(len(t)), 900, 6000) * np.exp(-t * 45) * .7; wood = band(noise(len(t)), 180, 1300) * env_ad(t, .002, 16) * .8
    return norm(thud * .9 + crack + wood)

def rock():
    t = T(.3); clack = band(noise(len(t)), 1500, 7000) * env_ad(t, .001, 55); ring = sine(t, 1750) * np.exp(-t * 30) * .25 + sine(t, 2650) * np.exp(-t * 40) * .15
    thump = sine(t, 90 * np.exp(-t * 10) + 55) * np.exp(-t * 18) * .6
    return norm(clack + ring + thump)

def place():
    t = T(.28); knock = (sine(t, 190) * .8 + sine(t, 385) * .4) * np.exp(-t * 26); tick = band(noise(len(t)), 600, 4000) * np.exp(-t * 70) * .5
    return norm(knock + tick)

def step(seed):
    r = np.random.default_rng(seed); t = T(.14); n = band(r.standard_normal(len(t)), 120, 1100)
    return norm(n * env_ad(t, .006, 24) * (1 + .3 * sine(t, 70)), .5)

def click():
    t = T(.06); return norm(sine(t, 900) * np.exp(-t * 60) + sine(t, 1800) * np.exp(-t * 90) * .3, .5)

def whoosh(d, f0, f1):
    t = T(d); x = noise(len(t)); out = np.zeros(len(t))
    for fc, w in zip(np.geomspace(f0, f1, 6), np.linspace(0, 1, 6)):
        out += band(x, fc * .6, fc * 1.6) * np.exp(-((t / d - w) ** 2) / .03)
    return out * np.minimum(t / .02, 1)

def shot_sling():
    t = T(.5); tw = sine(t, 260 * np.exp(-t * 3) + 140) * np.exp(-t * 11) * .6
    return norm(whoosh(.5, 2500, 700) * .8 + tw)

def shot_bow():
    t = T(.7); tw = (sine(t, 150 * np.exp(-t * 2.5) + 95) + .5 * sine(t, 300 * np.exp(-t * 2.5) + 190) + .25 * sine(t, 450)) * np.exp(-t * 7)
    return norm(tw * .8 + whoosh(.7, 3500, 900) * .5)

def hit():
    t = T(.25); return norm(sine(t, 100 * np.exp(-t * 12) + 45) * np.exp(-t * 14) + band(noise(len(t)), 200, 2500) * np.exp(-t * 35) * .5)

def water():
    t = T(.9); n = band(noise(len(t)), 250, 3500); m = .5 + .5 * np.sin(2 * np.pi * (9 + 4 * np.sin(t * 5)) * t)
    return norm(n * m * np.minimum(t / .05, 1) * np.exp(-t * 2.2))

def harvest():
    t = T(.22); f = 420 + 520 * smooth(0, .12, t); return norm(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 14), .6)

def chime():
    t = T(.9); x = np.zeros(len(t))
    for i, f in enumerate((660, 880, 1320)):
        s = (t > i * .13)
        x += (sine(t, f) + .3 * sine(t, 2 * f)) * np.exp(-np.clip(t - i * .13, 0, None) * 4.5) * s * (.7 if i < 2 else .5)
    return norm(x, .6)

def jump():
    t = T(.28); return norm(whoosh(.28, 400, 200) * np.exp(-t * 3), .4)

def cluck():
    t = T(.55); x = np.zeros(len(t))
    for st, f0 in ((0.02, 640), (0.16, 760), (0.30, 700)):
        tt = np.clip(t - st, 0, .1); m = (t > st) & (t < st + .1)
        f = f0 + 260 * np.sin(np.pi * tt / .1)
        x += m * (np.sin(2 * np.pi * np.cumsum(f) / SR) + .5 * np.sin(2 * np.pi * np.cumsum(2 * f) / SR)) * np.sin(np.pi * tt / .1) ** 0.7
    return norm(band(x, 300, 4000), .6)

# -------------------------------------------------------------- ambience ----
def add_circular(buf, snd, pos):
    n = len(buf); idx = (np.arange(len(snd)) + pos) % n; buf[idx] += snd

def chirp(d=.11, f0=3200, f1=5200, vib=40):
    t = T(d); f = f0 + (f1 - f0) * smooth(0, d, t) + 160 * np.sin(2 * np.pi * vib * t)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / d) ** 1.5 * .5

def ambient_day():
    N = int(SR * 8); wind = band(noise(N), 60, 700); m = .55 + .45 * band(noise(N), 0.01, 0.6)
    wind = wind / np.abs(wind).max() * (0.25 + 0.2 * (m - m.min()) / (np.ptp(m) + 1e-9))
    rustle = band(noise(N), 2000, 6000) * (0.04 + 0.04 * np.maximum(0, band(noise(N), 0.05, 0.8)))
    x = wind + rustle
    r = np.random.default_rng(5)
    for _ in range(7):
        pos = int(r.uniform(.2, 7.6) * SR); f0 = r.uniform(2600, 3800); base = chirp(.1, f0, f0 + r.uniform(500, 1800))
        for k in range(r.integers(1, 4)):
            add_circular(x, base * r.uniform(.15, .3), pos + int(k * .14 * SR))
    return norm(x, .5)

def ambient_night():
    N = int(SR * 8); x = band(noise(N), 50, 400) * 0.12 / (np.abs(band(noise(N), 50, 400)).max() + 1e-9) * 3
    t = T(8); r = np.random.default_rng(9)
    for c in range(5):
        f = 3900 + 120 * c; ph = r.uniform(0, 1); rate = 28 + 2 * c; period = .45 + .03 * c
        gate = (((t + ph) % period) < period * .55).astype(float) * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t))
        gate = np.convolve(gate, np.ones(20) / 20, "same")
        x += sine(t, f) * gate * (.05 + .01 * c)
    hoot = np.zeros(N)
    for k, (st, f) in enumerate(((2.4, 340), (3.0, 300))):
        tt = T(.35); h = sine(tt, f) * np.sin(np.pi * tt / .35) ** 2 * .2; hoot[int(st * SR):int(st * SR) + len(h)] += h
    x += hoot
    return norm(x, .5)

# ----------------------------------------------------------------- music ----
def pad_note(t, f, a=1.6, r=2.0, d=8.0):
    env = np.minimum(t / a, 1) * np.clip((d - t) / r, 0, 1)
    return (sine(t, f) + .35 * sine(t, 2 * f) + .15 * sine(t, 3 * f) + .25 * sine(t, f * 1.003)) * env

def music():
    chords = [(110.0, 130.81, 164.81, 220.0), (87.31, 130.81, 174.61, 220.0), (130.81, 164.81, 196.0, 261.63), (98.0, 146.83, 196.0, 246.94)]
    seg = 8.0; N = int(SR * seg * 4); x = np.zeros(N)
    for i, ch in enumerate(chords):
        t = T(seg + 2.0)
        for f in ch:
            n = pad_note(t, f, 1.8, 2.5, seg + 2.0) * .12
            s = int(i * seg * SR); e = min(N, s + len(n)); x[s:e] += n[:e - s]
            if s + len(n) > N: x[:s + len(n) - N] += n[e - s:] if False else n[N - s:]
    # soft plucked arpeggio
    r = np.random.default_rng(3); penta = [220, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25]
    for k in range(32):
        f = penta[r.integers(0, len(penta))]; t = T(2.5); n = (sine(t, f) + .3 * sine(t, 2 * f)) * np.exp(-t * 1.9) * np.minimum(t / .01, 1) * .09
        s = int(k * 1.0 * SR); idx = (np.arange(len(n)) + s) % N; x[idx] += n
    x = band(x, 60, 2800)
    return norm(x, .6)

if __name__ == "__main__":
    items = {"chop": chop(), "rock": rock(), "place": place(), "step1": step(1), "step2": step(2), "click": click(),
             "shot_sling": shot_sling(), "shot_bow": shot_bow(), "hit": hit(), "water": water(), "harvest": harvest(),
             "chime": chime(), "jump": jump(), "cluck": cluck(), "ambient_day": ambient_day(), "ambient_night": ambient_night(), "music": music()}
    tot = 0
    for k, v in items.items():
        save(k, v); p = os.path.join(OUT, k + ".wav"); tot += os.path.getsize(p)
        print(f"{k:14s} {len(v)/SR:5.2f}s peak {np.abs(v).max():.2f} rms {np.sqrt((v**2).mean()):.3f}" + (f"  loop jump {abs(v[0]-v[-1]):.3f}" if k in LOOPS else ""))
    print("total KB", tot // 1024)
