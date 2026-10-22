"""Prototype of the walking/aiming pose maths (mirrors scripts/character.gd) rendered on the skinned hero."""
import sys, math
sys.path.insert(0, "/tmp"); sys.path.insert(0, "tools")
import numpy as np
from PIL import Image
exec(open("tools/hero_check.py").read().split("# poses in MODEL frame")[0])   # loads parts, rot(), pose() (prints validation)

def sm(a, b, x):
    t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t)

def gait(ph, spd):
    """char-frame joint rotations (x = forward swing). ph = phase (pi per step)."""
    t = min(max((spd - 1.6) / 4.2, 0), 1)
    A = (0.28 + 0.14 * min(spd / 2.2, 1)) + 0.33 * t
    sw, cs = math.sin(ph), math.cos(ph); K = 0.9 + 0.6 * t
    arm = 0.30 + 0.35 * t; tw = 0.5 + t
    r = {}
    r["hipL"] = (sw * A, 0, 0); r["hipR"] = (-sw * A, 0, 0)
    r["knL"] = (-(0.08 + K * max(0, cs) ** 1.4 + 0.14 * max(0, sw) ** 2), 0, 0)
    r["knR"] = (-(0.08 + K * max(0, -cs) ** 1.4 + 0.14 * max(0, -sw) ** 2), 0, 0)
    el = 0.22 + 1.0 * t
    r["shL"] = (-sw * arm - 0.04, 0, 0.05); r["shR"] = (sw * arm - 0.04, 0, -0.05)
    r["elL"] = (el + (0.25 + 0.4 * t) * max(0, -sw), 0, 0); r["elR"] = (el + (0.25 + 0.4 * t) * max(0, sw), 0, 0)
    r["hips"] = (0, sw * 0.10 * tw, 0); r["spine"] = (-(0.03 + 0.2 * t), -sw * 0.08 * tw, 0); r["head"] = (0.03 + 0.15 * t, sw * 0.03, 0)
    dy = -(0.02 + 0.035 * t) * (1 - abs(cs))
    return r, dy

def to_model(r):
    out = {}
    for k, (x, y, z) in r.items(): out[k] = (-x, y, -z)
    # ankles keep the foot flat (same rule as the game)
    for s in "LR":
        h = r["hip" + s][0]; kn = r["kn" + s][0]; out["an" + s] = ((h + kn) * .8, 0, 0)
    return out

frames = []
for spd, label in ((1.5, "slow"), (3.0, "walk"), (6.0, "run")):
    for k in (0, 2, 4, 6):
        ph = k * math.pi / 4 + .3
        r, dy = gait(ph, spd)
        frames.append(PV.render(pose(parts, to_model(r), dy), 90, W=250, Hh=420, crop=(0, 1.9)))
sheet = Image.new("RGB", (250 * 4, 420 * 3))
for i, f in enumerate(frames): sheet.paste(f, ((i % 4) * 250, (i // 4) * 420))
sheet.save("/tmp/gait.png"); print("saved gait")
