#!/usr/bin/env python3
"""Generates all PBR-ish textures (albedo + normal) and alpha leaf/grass cards procedurally.
No third-party art is used -> no licensing issues. Run: python3 tools/gen_textures.py"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
os.makedirs(OUT, exist_ok=True)
N = 512

def fbm(n=N, beta=2.0, seed=0, stretch=(1.0, 1.0)):
    """Tileable noise via FFT filtering. stretch=(4,1) => features elongated vertically."""
    r = np.random.default_rng(seed)
    F = np.fft.fft2(r.standard_normal((n, n)))
    fy = np.fft.fftfreq(n)[:, None] * stretch[0]
    fx = np.fft.fftfreq(n)[None, :] * stretch[1]
    f = np.sqrt(fx ** 2 + fy ** 2); f[0, 0] = 1.0
    F = F / (f ** (beta / 2.0)); F[0, 0] = 0
    a = np.real(np.fft.ifft2(F))
    return (a - a.min()) / (a.max() - a.min())

def lerp(c0, c1, t):
    c0 = np.array(c0, float); c1 = np.array(c1, float)
    return c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]

def save_rgb(name, rgb):
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_a.png"), optimize=True)

def save_normal(name, h, strength=4.0):
    dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    nx, ny, nz = -dx * strength * 8, dy * strength * 8, np.ones_like(h)
    l = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    img = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
    Image.fromarray((img * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_n.png"), optimize=True)

def grass():
    a = fbm(beta=2.2, seed=1); s = fbm(beta=1.1, seed=2, stretch=(5, 1)); p = fbm(beta=2.6, seed=3)
    col = lerp((38, 74, 26), (118, 158, 58), np.clip(a * 0.55 + s * 0.6, 0, 1))
    col = col * (0.8 + 0.4 * s[..., None])
    yellow = np.clip((p - 0.62) * 5, 0, 1) * 0.35
    col = col * (1 - yellow[..., None]) + np.array([150, 135, 62])[None, None, :] * yellow[..., None]
    save_rgb("grass", col); save_normal("grass", s * 0.6 + a * 0.4, 0.9)

def dirt():
    a = fbm(beta=2.0, seed=4); b = fbm(beta=0.8, seed=5)
    col = lerp((66, 47, 33), (128, 98, 70), a)
    col = col * (0.85 + 0.3 * b[..., None])
    pebbles = (fbm(beta=0.3, seed=6) > 0.93).astype(float)
    col = col * (1 - pebbles[..., None] * 0.4) + pebbles[..., None] * 60
    save_rgb("dirt", col); save_normal("dirt", a * 0.5 + b * 0.5, 1.4)

def stones_canvas(n_stones, smin, smax, palette, seed):
    r = np.random.default_rng(seed)
    S = N
    alb = Image.new("RGB", (S, S), (80, 76, 70)); hei = Image.new("L", (S, S), 40)
    da, dh = ImageDraw.Draw(alb), ImageDraw.Draw(hei)
    for _ in range(n_stones):
        x, y = r.integers(0, S, 2); w = r.integers(smin, smax); h = int(w * r.uniform(0.6, 1.0))
        c = palette[r.integers(0, len(palette))]; k = r.uniform(0.75, 1.15)
        c = tuple(int(min(255, v * k)) for v in c); hv = int(r.integers(120, 255))
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                bb = [x + ox - w, y + oy - h, x + ox + w, y + oy + h]
                da.ellipse(bb, fill=c); dh.ellipse(bb, fill=hv)
    hei = hei.filter(ImageFilter.GaussianBlur(2.2))
    return np.asarray(alb, float), np.asarray(hei, float) / 255.0

def gravel():
    pal = [(128, 122, 114), (150, 140, 124), (104, 98, 92), (160, 150, 130), (120, 104, 90), (90, 88, 86)]
    alb, h = stones_canvas(1500, 6, 16, pal, 7)
    alb = alb * (0.45 + 0.65 * h[..., None])
    save_rgb("gravel", alb); save_normal("gravel", h, 2.2)

def rock():
    r1 = 1 - np.abs(2 * fbm(beta=2.4, seed=8) - 1); r2 = fbm(beta=1.4, seed=9)
    base = np.clip(r1 * 0.6 + r2 * 0.4, 0, 1)
    col = lerp((48, 46, 45), (176, 168, 156), np.clip((base - 0.25) * 1.7, 0, 1))
    warm = fbm(beta=2.0, seed=10)
    col = col * (1 - warm[..., None] * 0.15) + np.array([20, 10, 0])[None, None, :] * warm[..., None]
    moss = np.clip((fbm(beta=2.2, seed=11) - 0.6) * 4, 0, 1) * 0.55
    col = col * (1 - moss[..., None]) + np.array([64, 88, 40])[None, None, :] * moss[..., None]
    crack = (1 - np.abs(2 * fbm(beta=1.8, seed=12) - 1)) ** 14
    col = col * (1 - crack[..., None] * 0.55)
    save_rgb("rock", col); save_normal("rock", base * 0.8 - crack * 0.6 + r2 * 0.2, 1.3)

def bark():
    n = fbm(beta=2.0, seed=13, stretch=(6, 1)); m = fbm(beta=1.0, seed=14, stretch=(3, 1))
    ridge = 1 - np.abs(2 * n - 1)
    col = lerp((34, 25, 18), (118, 92, 66), np.clip(ridge * 0.8 + m * 0.3, 0, 1))
    save_rgb("bark", col); save_normal("bark", ridge * 0.8 + m * 0.2, 2.2)

def fabric():
    y, x = np.mgrid[0:N, 0:N]
    twill = 0.5 + 0.5 * np.sin(2 * math.pi * (x + y) / 8.0)
    n = fbm(beta=1.0, seed=15)
    h = twill * 0.35 + n * 0.65
    save_rgb("fabric", np.stack([150 + 80 * h] * 3, -1)); save_normal("fabric", h, 0.8)

def leather():
    n = fbm(beta=1.6, seed=16); g = fbm(beta=0.7, seed=17)
    h = n * 0.5 + g * 0.5
    save_rgb("leather", np.stack([120 + 110 * h] * 3, -1)); save_normal("leather", h, 1.2)

# ---------- alpha cards (RGBA, supersampled) ----------
SS = 2
def card(size=256):
    s = size * SS
    return Image.new("RGBA", (s, s), (0, 0, 0, 0)), s

def finish(img, name, size=256):
    img = img.resize((size, size), Image.LANCZOS)
    a = np.asarray(img).copy()
    a[..., 3] = np.where(a[..., 3] > 110, 255, 0)   # hard alpha for scissor
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, name + ".png"), optimize=True)

def leaf_poly(cx, cy, L, W, ang, n=10):
    pts = []
    for i in range(n + 1):
        t = i / n; w = W * math.sin(math.pi * t) ** 0.8
        pts.append((t * L - L / 2, w))
    for i in range(n, -1, -1):
        t = i / n; w = W * math.sin(math.pi * t) ** 0.8
        pts.append((t * L - L / 2, -w))
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]

def foliage(name, count, L, W, base, var, seed, apples=0, silver=False):
    r = np.random.default_rng(seed)
    img, s = card(); d = ImageDraw.Draw(img)
    for _ in range(count):
        rad = r.uniform(0, 0.46) ** 0.6 * s * 0.5 * 1.9
        th = r.uniform(0, 2 * math.pi)
        cx, cy = s / 2 + rad * math.cos(th) * 0.52, s / 2 + rad * math.sin(th) * 0.52
        k = r.uniform(-1, 1) * var
        c = [int(np.clip(b + k, 0, 255)) for b in base]
        if silver and r.random() < 0.4: c = [int(v * 1.25 + 20) for v in c]
        ang = r.uniform(0, 2 * math.pi)
        d.polygon(leaf_poly(cx, cy, L * SS * r.uniform(0.8, 1.2), W * SS, ang), fill=tuple(min(255, v) for v in c) + (255,))
        d.line([(cx - math.cos(ang) * L * SS * 0.4, cy - math.sin(ang) * L * SS * 0.4), (cx + math.cos(ang) * L * SS * 0.4, cy + math.sin(ang) * L * SS * 0.4)], fill=tuple(max(0, v - 35) for v in c) + (255,), width=2)
    for _ in range(apples):
        cx, cy = r.uniform(0.2, 0.8) * s, r.uniform(0.2, 0.8) * s; R = 9 * SS
        d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(176, 28, 24, 255))
        d.ellipse([cx - R * 0.5, cy - R * 0.6, cx - R * 0.1, cy - R * 0.2], fill=(235, 110, 90, 255))
    finish(img, name)

def pine():
    r = np.random.default_rng(21)
    img, s = card(); d = ImageDraw.Draw(img)
    cx = s / 2
    d.line([(cx, s * 0.98), (cx, s * 0.04)], fill=(70, 48, 30, 255), width=5 * SS)
    for i in range(70):
        t = i / 69; y = s * (0.96 - 0.9 * t); span = (1.0 - t * 0.85) * s * 0.46
        for side in (-1, 1):
            ex, ey = cx + side * span * r.uniform(0.85, 1.0), y - span * 0.35
            c = (int(r.integers(26, 46)), int(r.integers(70, 105)), int(r.integers(36, 58)), 255)
            d.line([(cx, y), (ex, ey)], fill=c, width=int(3.2 * SS))
            for q in range(5):
                u = q / 5; px, py = cx + (ex - cx) * u, y + (ey - y) * u
                d.line([(px, py), (px + side * 10 * SS, py - 6 * SS)], fill=c, width=2 * SS)
    finish(img, "leaf_pine")

def palm():
    img, s = card(); d = ImageDraw.Draw(img)
    pts = [(s * 0.02, s * 0.5 + 0.0 * s)]
    for i in range(60):
        t = i / 59; x = s * (0.02 + 0.96 * t); y = s * (0.46 + 0.1 * t ** 2)
        pts.append((x, y))
    d.line(pts, fill=(80, 100, 40, 255), width=4 * SS)
    for i in range(3, 60, 3):
        x, y = pts[i]; t = i / 59; L = s * 0.5 * (1 - t) ** 0.5 + s * 0.05
        for side in (-1, 1):
            ang = side * (math.radians(62 - 25 * t)); ex = x + L * math.sin(abs(ang)) * 0.55; ey = y + side * L * math.cos(ang) * 0.5 + L * 0.12
            c = (int(52 + 30 * t), int(104 + 30 * (1 - t)), 38, 255)
            d.line([(x, y), (ex, ey)], fill=c, width=int(3.2 * SS))
    finish(img, "leaf_palm")

def tuft():
    r = np.random.default_rng(31)
    img, s = card(); d = ImageDraw.Draw(img)
    for _ in range(26):
        x0 = s * r.uniform(0.25, 0.75); h = s * r.uniform(0.45, 0.95); bend = r.uniform(-0.25, 0.25) * s; w = r.uniform(5, 9) * SS
        g = int(r.integers(95, 170)); c = (int(g * 0.55), g, int(g * 0.3), 255)
        pts = []
        for i in range(9):
            t = i / 8; pts.append((x0 + bend * t * t - w * (1 - t) * 0.5, s * 0.99 - h * t))
        for i in range(8, -1, -1):
            t = i / 8; pts.append((x0 + bend * t * t + w * (1 - t) * 0.5, s * 0.99 - h * t))
        d.polygon(pts, fill=c)
    finish(img, "grass_tuft")

if __name__ == "__main__":
    grass(); dirt(); gravel(); rock(); bark(); fabric(); leather()
    foliage("leaf_oak", 150, 30, 11, (58, 112, 36), 26, 41)
    foliage("leaf_apple", 140, 26, 10, (74, 126, 44), 22, 42, apples=14)
    foliage("leaf_olive", 190, 34, 5, (112, 132, 92), 24, 43, silver=True)
    pine(); palm(); tuft()
    print("textures written to", os.path.abspath(OUT))
