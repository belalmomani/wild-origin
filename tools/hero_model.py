#!/usr/bin/env python3
"""WILD ORIGIN hero v2 — procedural adult explorer ("المستكشف").
Model space: Y up, character FRONT = +Z (glTF), character LEFT = +X. 17-bone skeleton (16 game joints + 'pack').
Groups: 'base' (body, clothes, pack), 'detail' (stitching, zips, buckles, laces, emblems — hidden at distance),
'head' (face, hair, beard, eyes with 5 expression morph targets)."""
import math
import numpy as np

BONES = ["hips", "spine", "chest", "head", "shL", "elL", "handL", "shR", "elR", "handR",
         "hipL", "knL", "anL", "hipR", "knR", "anR", "pack"]
BI = {b: i for i, b in enumerate(BONES)}; NB = len(BONES)
PARENT = {"hips": None, "spine": "hips", "chest": "spine", "head": "chest", "shL": "chest", "elL": "shL", "handL": "elL",
          "shR": "chest", "elR": "shR", "handR": "elR", "hipL": "hips", "knL": "hipL", "anL": "knL",
          "hipR": "hips", "knR": "hipR", "anR": "knR", "pack": "chest"}
POS = {"hips": (0, .92, 0), "spine": (0, .98, 0), "chest": (0, 1.28, 0), "head": (0, 1.52, 0.0),
       "shL": (.228, 1.43, 0), "elL": (.245, 1.15, 0), "handL": (.255, .90, 0),
       "shR": (-.228, 1.43, 0), "elR": (-.245, 1.15, 0), "handR": (-.255, .90, 0),
       "hipL": (.098, .90, 0), "knL": (.098, .49, 0), "anL": (.098, .09, 0),
       "hipR": (-.098, .90, 0), "knR": (-.098, .49, 0), "anR": (-.098, .09, 0), "pack": (0, 1.33, -.12)}
TARGETS = ["smile", "surprise", "focus", "fear", "tired"]

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def norm(v, eps=1e-9):
    return v / (np.linalg.norm(v, axis=-1, keepdims=True) + eps)

PARTS = []
GROUP = "base"
def grp(g):
    global GROUP; GROUP = g

def new_part(mat, P, N, UV, I, C=None, W=None, D=None):
    n = len(P)
    C = np.ones((n, 4)) if C is None else C
    W = np.zeros((n, NB)) if W is None else W
    PARTS.append(dict(mat=mat, group=GROUP, P=np.asarray(P, float), N=np.asarray(N, float), UV=np.asarray(UV, float),
                      I=np.asarray(I, np.int64), C=np.asarray(C, float), W=np.asarray(W, float), D=D))
    return PARTS[-1]

def w_single(n, bone):
    W = np.zeros((n, NB)); W[:, BI[bone]] = 1.0; return W

def w_chain(v, bones, cuts, widths):
    n = len(v); W = np.zeros((n, NB)); prev = np.ones(n)
    for i, b in enumerate(bones):
        if i < len(cuts):
            t = smooth(cuts[i] - widths[i], cuts[i] + widths[i], v)
            W[:, BI[b]] += prev * (1 - t); prev = prev * t
        else:
            W[:, BI[b]] += prev
    return W

def resample(arrs, R, smooth_iter=2):
    k = len(arrs[0]); t0 = np.linspace(0, 1, k); t1 = np.linspace(0, 1, R); out = []
    for a in arrs:
        a = np.asarray(a, float)
        r = np.interp(t1, t0, a) if a.ndim == 1 else np.stack([np.interp(t1, t0, a[:, j]) for j in range(a.shape[1])], 1)
        for _ in range(smooth_iter):
            p = np.pad(r, [(1, 1)] + [(0, 0)] * (r.ndim - 1), mode="edge"); r = (p[:-2] + 2 * p[1:-1] + p[2:]) / 4.0
        out.append(r)
    return out

def vertex_normals(P, I):
    tri = P[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); N = np.zeros_like(P)
    for j in range(3): np.add.at(N, I[:, j], fn)
    key = np.round(P * 1e5).astype(np.int64); _, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.reshape(-1)
    acc = np.zeros((inv.max() + 1, 3)); np.add.at(acc, inv, N); return norm(acc[inv])

def loft(P, rx, rz, mat, weights, color=None, R=16, segs=14, hs=(1, 0, 0), hf=(0, 0, 1), caps=(True, True),
         uv=(2.0, 6.0), smooth_iter=2, fcross=False, cap_rings=3):
    P, rx, rz = resample([P, rx, rz], R, smooth_iter)
    T = norm(np.gradient(P, axis=0)); hs = np.array(hs, float); hf = np.array(hf, float)
    S = norm(hs[None] - (T @ hs)[:, None] * T)
    F = norm(np.cross(T, S)) if fcross else norm(hf[None] - (T @ hf)[:, None] * T - (S @ hf)[:, None] * S)
    def cap(i, sign):
        out = []; r = (rx[i] + rz[i]) / 2
        for j in range(1, cap_rings + 1):
            th = j * (math.pi / 2) / cap_rings; f = max(math.cos(th), 0.03)
            out.append((P[i] + sign * T[i] * math.sin(th) * r, T[i], S[i], F[i], rx[i] * f, rz[i] * f))
        return out
    seq = []
    if caps[0]: seq += cap(0, -1)[::-1]
    seq += [(P[i], T[i], S[i], F[i], rx[i], rz[i]) for i in range(R)]
    if caps[1]: seq += cap(R - 1, +1)
    nr = len(seq); V = []; Nn = []; UVs = []; s_acc = 0.0
    for i, (c, t, s, f, a, b) in enumerate(seq):
        if i > 0: s_acc += np.linalg.norm(c - seq[i - 1][0])
        for k in range(segs + 1):
            ang = 2 * math.pi * k / segs; ca, sa = math.cos(ang), math.sin(ang)
            V.append(c + s * a * ca + f * b * sa); Nn.append(s * ca / max(a, 1e-4) + f * sa / max(b, 1e-4)); UVs.append((uv[0] * k / segs, uv[1] * s_acc))
    V = np.array(V); Nn = norm(np.array(Nn)); UVs = np.array(UVs); I = []
    for i in range(nr - 1):
        for k in range(segs):
            a = i * (segs + 1) + k; b = a + 1; c2 = a + segs + 1; d = c2 + 1; I += [(a, c2, b), (b, c2, d)]
    I = np.array(I); tri = V[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if np.sum(np.einsum("ij,ij->i", fn, Nn[I[:, 0]])) < 0: I = I[:, ::-1]
    W = weights(V) if callable(weights) else w_single(len(V), weights)
    C = None if color is None else (color(V) if callable(color) else np.tile(np.array(color, float), (len(V), 1)))
    return new_part(mat, V, Nn, UVs, I, C, W)

def sgnpow(x, e): return np.sign(x) * np.abs(x) ** e

def rbox(mat, c, size, weights, color=None, e=0.28, yaw=0.0, tilt=0.0, nu=12, nv=6):
    """Rounded box (superquadric): cheap, soft edges. size = (x, y, z) full extents."""
    a, b, cz = [s / 2 for s in size]; V = []; UVs = []
    for i in range(nv + 1):
        v = -math.pi / 2 + math.pi * i / nv
        for k in range(nu + 1):
            u = 2 * math.pi * k / nu
            cv, sv, cu, su = sgnpow(math.cos(v), e), sgnpow(math.sin(v), e), sgnpow(math.cos(u), e), sgnpow(math.sin(u), e)
            V.append((a * cv * cu, b * sv, cz * cv * su)); UVs.append((k / nu, i / nv))
    V = np.array(V)
    cy, sy, ct, st = math.cos(yaw), math.sin(yaw), math.cos(tilt), math.sin(tilt)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]); Rx = np.array([[1, 0, 0], [0, ct, -st], [0, st, ct]])
    V = (V @ Rx.T @ Ry.T) + np.array(c, float); I = []
    for i in range(nv):
        for k in range(nu):
            a_ = i * (nu + 1) + k; b_ = a_ + 1; c_ = a_ + nu + 1; d_ = c_ + 1; I += [(a_, c_, b_), (b_, c_, d_)]
    I = np.array(I); tri = V[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if np.sum(np.einsum("ij,ij->i", fn, tri.mean(1) - np.array(c, float))) < 0: I = I[:, ::-1]
    N = vertex_normals(V, I); W = weights(V) if callable(weights) else w_single(len(V), weights)
    C = None if color is None else (color(V) if callable(color) else np.tile(np.array(color, float), (len(V), 1)))
    return new_part(mat, V, N, np.array(UVs), I, C, W)

def disc(mat, c, normal, r, weights, nseg=28, color=None):
    """Flat disc with planar UVs (emblem texture); normal must be an axis-aligned unit vector."""
    n = np.array(normal, float); c = np.array(c, float)
    ref = np.array([0, 1, 0]) if abs(n[1]) < .9 else np.array([1, 0, 0]); u = norm(np.cross(ref, n)); v = np.cross(n, u)
    P = [c]; UV = [(.5, .5)]
    for k in range(nseg):
        a = 2 * math.pi * k / nseg; P.append(c + r * (math.cos(a) * u + math.sin(a) * v)); UV.append((.5 + .5 * math.cos(a), .5 - .5 * math.sin(a)))
    I = [(0, 1 + k, 1 + (k + 1) % nseg) for k in range(nseg)]; P = np.array(P); I = np.array(I)
    tri = P[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if np.sum(fn @ n) < 0: I = I[:, ::-1]
    W = weights(P) if callable(weights) else w_single(len(P), weights)
    C = None if color is None else np.tile(np.array(color, float), (len(P), 1))
    return new_part(mat, P, np.tile(n, (len(P), 1)), np.array(UV), I, C, W)

def wrinkle(V, amp=0.10, f=60.0, seed=0):
    r = np.random.default_rng(seed); ph = r.uniform(0, 6.28, 3)
    return 1.0 - amp * (np.sin(V[:, 1] * f + ph[0] + 3 * np.sin(np.arctan2(V[:, 0], V[:, 2]) * 3 + ph[1])) * .5 + .5)

def tone(rgb, amp=.10, f=60.0, seed=0):
    def fn(V):
        c = np.ones((len(V), 4)); w = wrinkle(V, amp, f, seed); c[:, :3] = (w[:, None] * np.array(rgb)[None]); return c
    return fn

# profile helper: front surface z of the torso at height y
TY = [.86, .92, .98, 1.06, 1.14, 1.22, 1.30, 1.38, 1.44, 1.485, 1.52]
TRX = [.178, .174, .162, .166, .176, .192, .206, .214, .204, .124, .066]
TRZ = [.108, .106, .100, .103, .109, .118, .126, .128, .112, .084, .060]
TCZ = [0, 0, 0, 0, .002, .006, .012, .014, .006, -.004, -.008]
def torso_front(y): return float(np.interp(y, TY, np.array(TRZ) + np.array(TCZ)))
def torso_half(y): return float(np.interp(y, TY, TRX))
tw = lambda V: w_chain(V[:, 1], ["hips", "spine", "chest"], [.99, 1.22], [.07, .07])

# ---------------------------------------------------------------- body ----
def build_body():
    # --- jacket torso (forest green)
    P = np.array([[0, y, c] for y, c in zip(TY, TCZ)])
    def tcol(V):
        c = np.ones((len(V), 4)); w = wrinkle(V, .12, 55, 1); hem = 1 - .25 * (1 - smooth(.86, .93, V[:, 1]))
        shoulder = 1 - .20 * smooth(1.40, 1.46, V[:, 1]) * smooth(.06, .12, np.abs(V[:, 0]))           # reinforced shoulder yoke
        c[:, :3] = (w * hem * shoulder * (0.86 + 0.14 * smooth(.86, 1.3, V[:, 1])))[:, None]; return c
    loft(P, TRX, TRZ, "shirt", tw, tcol, R=20, uv=(2, 5))
    # --- trousers waist
    P = np.array([[0, y, 0] for y in [.80, .84, .90, .96, 1.0]])
    loft(P, [.132, .164, .184, .180, .172], [.100, .118, .126, .120, .112], "pants", "hips", color=tone((1, 1, 1), .16, 46, 3), R=10, uv=(2, 3))
    # --- belt + buckle
    P = np.array([[0, .958, 0], [0, .998, 0]])
    loft(P, [.19, .19], [.13, .13], "leather", "hips", R=4, caps=(False, False), uv=(4, 2))
    # --- neck
    P = np.array([[0, 1.48, 0.002], [0, 1.54, 0.008], [0, 1.605, 0.014]])
    loft(P, [.058, .053, .051], [.060, .055, .052], "skin", lambda V: w_chain(V[:, 1], ["chest", "head"], [1.54], [.04]), R=8, caps=(False, False), uv=(2, 3))
    for sd, nm in ((1, "L"), (-1, "R")):
        build_arm(sd, nm); build_leg(sd, nm)
    build_jacket_details(); build_pack(); build_head()

def build_arm(sd, nm):
    x = .229 * sd
    ys = [1.475, 1.44, 1.36, 1.26, 1.18, 1.155, 1.135]; r = [.056, .059, .054, .050, .048, .055, .055]
    P = np.array([[x + .004 * sd * i, y, 0] for i, y in enumerate(ys)])
    ww = lambda V: w_chain(-V[:, 1], ["chest", "sh" + nm, "el" + nm], [-1.455, -1.15], [.05, .04])
    def sc(V):
        c = np.ones((len(V), 4)); w = wrinkle(V, .12, 70, 2); patch = 1 - .22 * smooth(1.30, 1.20, V[:, 1]) * smooth(1.10, 1.17, V[:, 1]) * 0 
        c[:, :3] = w[:, None]; return c
    loft(P, r, r, "shirt", ww, sc, R=16, uv=(2, 3))
    # reinforced elbow patch (darker, slightly proud) on the sleeve end
    P = np.array([[x + .020 * sd, 1.215, 0], [x + .022 * sd, 1.165, 0]])
    loft(P, [.062, .064], [.062, .064], "shirt", ww, tone((.72, .76, .70), .08, 80, 5), R=4, segs=12, caps=(False, False), uv=(2, 1))
    ys = [1.15, 1.10, 1.03, .965, .915, .895]; rx = [.044, .046, .042, .035, .031, .030]; rz = [.043, .045, .041, .035, .032, .030]
    P = np.array([[x + (.020 + .002 * i) * sd, y, 0] for i, y in enumerate(ys)])
    wf = lambda V: w_chain(-V[:, 1], ["el" + nm, "hand" + nm], [-.90], [.03])
    def skin_c(V):
        c = np.ones((len(V), 4)); n = np.sin(V[:, 1] * 90) * .02; c[:, 1] = 1 + n; c[:, 2] = 1 + n * 1.5
        c[:, :3] *= (1 - .10 * (V[:, 2] < -.0) * 0)[:, None]; return c
    loft(P, rx, rz, "skin", wf, skin_c, R=12, uv=(2, 2), caps=(False, False))
    # fingerless glove: palm, knuckle band, wrist strap, finger-base sleeves, bare fingertips
    hx = x + .030 * sd; ys = [.90, .875, .84, .805, .79]
    P = np.array([[hx + .002 * sd * i, y, .002 * i] for i, y in enumerate(ys)])
    loft(P, [.031, .027, .025, .023, .021], [.031, .044, .048, .046, .043], "leather_dark", "hand" + nm, R=8, caps=(False, True), uv=(2, 1))
    P = np.array([[hx + .001 * sd, .908, 0], [hx + .001 * sd, .890, 0]])
    loft(P, [.036, .036], [.036, .036], "leather", "hand" + nm, R=3, segs=12, caps=(False, False), uv=(2, 1))
    rbox("metal", (hx + .002 * sd + .0 , .898, .03 * 1), (.012, .012, .01), "hand" + nm) if False else None
    for fz, ln in ((-.032, .060), (-.011, .068), (.011, .066), (.032, .056)):
        p0 = np.array([hx + .004 * sd, .795, fz])
        path = np.array([p0, p0 + [-.002 * sd, -ln * .45, .004], p0 + [-.006 * sd, -ln * .8, .014], p0 + [-.010 * sd, -ln * .98, .026]])
        loft(path, [.0095, .0090, .0085, .0075], [.0095, .0090, .0085, .0075], "skin", "hand" + nm, R=5, segs=7, caps=(False, True), uv=(1, 1), smooth_iter=1)
        grp("detail")
        loft(np.array([p0 + [0, .004, 0], p0 + [-.001 * sd, -.016, .002]]), [.0112, .0112], [.0112, .0112], "leather_dark", "hand" + nm, R=3, segs=7, caps=(False, False), uv=(1, 1))
        grp("base")
    p0 = np.array([hx - .012 * sd, .86, .042])
    path = np.array([p0, p0 + [-.004 * sd, -.018, .016], p0 + [-.008 * sd, -.040, .030], p0 + [-.010 * sd, -.056, .038]])
    loft(path, [.0125, .0115, .0100, .0085], [.0125, .0115, .0100, .0085], "skin", "hand" + nm, R=5, segs=7, caps=(False, True), uv=(1, 1), smooth_iter=1)

def build_leg(sd, nm):
    x = .098 * sd
    ys = [.94, .86, .76, .66, .56, .49, .42, .33, .25, .19]
    rx = [.108, .110, .104, .094, .079, .074, .077, .069, .066, .070]; rz = [.112, .116, .108, .098, .083, .078, .083, .075, .070, .074]
    cz = [0, 0, 0, .002, .004, .006, -.006, -.004, 0, .004]
    P = np.array([[x, y, c] for y, c in zip(ys, cz)])
    wl = lambda V: w_chain(-V[:, 1], ["hip" + nm, "kn" + nm, "an" + nm], [-.49, -.12], [.06, .05])
    def pc(V):
        c = np.ones((len(V), 4)); w = wrinkle(V, .16, 46, 3 + (1 if sd > 0 else 0))
        knee = np.exp(-((V[:, 1] - .49) / .05) ** 2); fold = 1.0 - .20 * knee * (V[:, 2] < .02) - .12 * np.exp(-((V[:, 1] - .22) / .03) ** 2)
        pad = 1.0 - .22 * np.exp(-((V[:, 1] - .52) / .06) ** 2) * (V[:, 2] > .03)        # darker knee reinforcement
        c[:, :3] = (w * fold * pad)[:, None]; return c
    loft(P, rx, rz, "pants", wl, pc, R=22, uv=(2, 6), caps=(True, False))
    # knee reinforcement pad (raised) + side cargo pocket with flap
    rbox("pants", (x, .525, .083), (.112, .135, .026), wl, tone((.72, .66, .58), .06, 90, 7), e=.35)
    rbox("pants", (x + .102 * sd, .70, .0), (.034, .16, .118), wl, tone((.95, .95, .92), .1, 50, 8), e=.3)
    grp("detail")
    rbox("pants", (x + .106 * sd, .775, .0), (.036, .04, .122), wl, tone((.8, .78, .72), .05, 90, 9), e=.3)
    rbox("metal", (x + .12 * sd, .765, .035), (.008, .016, .016), wl, e=.4, nu=8, nv=4)
    loft(np.array([[x, .215, 0], [x, .195, 0]]), [.074, .074], [.078, .078], "leather", wl, tone((.55, .5, .45), .04, 60, 31), R=3, segs=14, caps=(False, False), uv=(2, 1))   # ankle cord band
    grp("base")
    # boot: padded collar + shaft
    P = np.array([[x, .285, 0], [x, .23, 0], [x, .15, 0], [x, .09, 0]])
    loft(P, [.073, .069, .060, .058], [.076, .072, .062, .060], "leather", lambda V: w_chain(-V[:, 1], ["kn" + nm, "an" + nm], [-.26], [.05]), R=8, caps=(False, False), uv=(2, 3))
    loft(np.array([[x, .30, 0], [x, .275, 0]]), [.078, .078], [.081, .081], "leather", lambda V: w_chain(-V[:, 1], ["kn" + nm, "an" + nm], [-.26], [.05]), tone((.6, .55, .5), .04, 60, 32), R=3, segs=14, caps=(False, False), uv=(2, 1))
    zs = [-.078, -.05, -.01, .05, .11, .16, .21]
    P = np.array([[x, y, z] for y, z in zip([.066, .062, .057, .052, .049, .045, .040], zs)])
    loft(P, [.050, .058, .062, .061, .058, .052, .040], [.054, .054, .049, .044, .038, .032, .024], "leather", "an" + nm, hs=(1, 0, 0), hf=(0, 1, 0), R=12, uv=(2, 3))
    # thicker rubber sole with a lighter midsole stripe + heel block
    P = np.array([[x, y, z] for y, z in zip([.020, .018, .016, .016, .016, .016, .018], zs)])
    loft(P, [.054, .062, .065, .064, .061, .055, .042], [.021, .021, .019, .018, .018, .018, .018], "rubber", "an" + nm, hs=(1, 0, 0), hf=(0, 1, 0), R=12, uv=(2, 3))
    P = np.array([[x, y, z] for y, z in zip([.043, .041, .038, .038, .038, .038, .040], zs)])
    grp("detail")
    loft(P, [.055, .063, .066, .065, .062, .056, .043], [.007, .007, .007, .007, .007, .007, .007], "midsole", "an" + nm, hs=(1, 0, 0), hf=(0, 1, 0), R=12, uv=(2, 3), caps=(False, False))
    # toe-cap bumper + laces
    ellip = lambda c, r: None
    rbox("rubber", (x, .043, .192), (.092, .050, .070), "an" + nm, e=.5, nu=10, nv=5)
    for i, (y, z) in enumerate(zip([.250, .215, .180, .145, .115], [.071, .074, .077, .082, .092])):
        rbox("midsole", (x, y, z), (.062, .007, .010), lambda V, nm=nm, y=y: w_chain(-V[:, 1], ["kn" + nm, "an" + nm], [-.26], [.05]) if y > .12 else w_single(len(V), "an" + nm), e=.4, nu=8, nv=3, tilt=-.15)
    grp("base")

def build_jacket_details():
    grp("detail")
    # zipper tape + teeth + copper pull down the front
    ys = np.linspace(1.485, .895, 8)
    P = np.array([[0, y, torso_front(y) + .003] for y in ys])
    loft(P, [.009] * 8, [.0022] * 8, "pants", tw, tone((.45, .5, .42), .05, 30, 4), R=12, segs=8, caps=(False, False), uv=(1, 6), hs=(1, 0, 0), hf=(0, 0, 1))
    loft(P + np.array([0, 0, .002]), [.0028] * 8, [.0016] * 8, "metal", tw, R=12, segs=6, caps=(False, False), uv=(1, 6))
    rbox("copper", (0, 1.30, torso_front(1.30) + .012), (.012, .03, .008), "chest", e=.4, nu=8, nv=4)
    # chest pocket (wearer's left, +X) with flap + button; two lower patch pockets
    rbox("shirt", (.098, 1.30, torso_front(1.30) + .008), (.088, .082, .016), tw, tone((.9, .95, .88), .08, 70, 11), e=.3)
    rbox("shirt", (.098, 1.345, torso_front(1.345) + .011), (.092, .028, .014), tw, tone((.78, .84, .76), .05, 70, 12), e=.3)
    rbox("metal", (.098, 1.332, torso_front(1.332) + .02), (.012, .012, .006), "chest", e=.45, nu=8, nv=4)
    for s in (-1, 1):
        rbox("shirt", (s * .098, 1.04, torso_front(1.04) + .01), (.092, .10, .018), tw, tone((.9, .95, .88), .08, 70, 13 + s), e=.3, yaw=0, tilt=0)
        rbox("shirt", (s * .098, 1.085, torso_front(1.085) + .013), (.096, .03, .016), tw, tone((.78, .84, .76), .05, 70, 15), e=.3)
        rbox("metal", (s * .098, 1.07, torso_front(1.07) + .022), (.012, .012, .006), tw, e=.45, nu=8, nv=4)
    # collar (V-open) and shoulder reinforcement
    grp("base")
    for s in (-1, 1):
        ang = np.linspace(math.pi * .95, .30, 9)
        P = np.array([[s * .086 * math.sin(a), 1.535 - .03 * max(0, 1.2 - a) - .02 * (a < 1.0), .092 * math.cos(a) * 1.0 + .004] for a in ang])
        loft(P, [.020] * 9, [.007] * 9, "shirt", lambda V: w_chain(V[:, 1], ["chest", "head"], [1.57], [.03]), tone((.85, .9, .82), .06, 80, 16), R=14, segs=8,
             hs=(0, 1, 0), fcross=True, caps=(True, True), uv=(1, 4), smooth_iter=2)
    grp("detail")
    # stitching (ochre thread): shoulder seams, side seams, pocket edges
    for s in (-1, 1):
        ys2 = np.linspace(.9, 1.42, 8); P = np.array([[s * (torso_half(y) - .001), y, .0] for y in ys2])
        loft(P, [.0022] * 8, [.0022] * 8, "thread", tw, R=10, segs=5, caps=(False, False), uv=(1, 4))
        P = np.array([[s * .07, 1.5, .02], [s * .13, 1.492, .022], [s * .19, 1.466, .02], [s * .228, 1.445, .018]])
        loft(P, [.0022] * 4, [.0022] * 4, "thread", lambda V, s=s: w_chain(-V[:, 1], ["chest", "sh" + ("L" if s > 0 else "R")], [-1.455], [.05]), R=6, segs=5, caps=(False, False), uv=(1, 2))
    # sleeve cuff strap + button (rolled sleeve), compass shoulder badge on the wearer's left upper arm
    for s, nm in ((1, "L"), (-1, "R")):
        wcuff = lambda V, nm=nm: w_chain(-V[:, 1], ["chest", "sh" + nm, "el" + nm], [-1.455, -1.15], [.05, .04])
        loft(np.array([[s * .252, 1.162, 0], [s * .254, 1.152, 0]]), [.062, .062], [.062, .062], "leather", wcuff, R=3, segs=12, caps=(False, False), uv=(2, 1))
        rbox("metal", (s * .309, 1.157, 0.0), (.008, .016, .016), wcuff, e=.4, nu=8, nv=4)
    disc("emblem", (.3055, 1.355, 0.0), (1, 0, 0), .036, lambda V: w_chain(-V[:, 1], ["chest", "shL", "elL"], [-1.455, -1.15], [.05, .04]))
    grp("base")

def build_pack(): 
    pk = lambda V: w_single(len(V), "pack")
    # padded back panel (rides on the chest) + main body
    rbox("pack", (0, 1.20, -.108), (.31, .42, .04), "chest", tone((.6, .58, .52), .06, 40, 20), e=.35)
    ys = [.90, .97, 1.10, 1.25, 1.38, 1.42]; rx = [.150, .168, .172, .165, .150, .12]; rz = [.062, .082, .088, .084, .072, .05]
    P = np.array([[0, y, -.19 + .01 * (y - 1.1)] for y in ys])
    def pcol(V):
        c = np.ones((len(V), 4)); w = wrinkle(V, .10, 36, 21); c[:, :3] = w[:, None] * np.array([1.0, 1.0, .98])[None]; return c
    loft(P, rx, rz, "pack", pk, pcol, R=14, segs=16, hs=(1, 0, 0), hf=(0, 0, 1), caps=(True, True), uv=(2, 3))
    # lid (tan leather) folding over the top, front pocket, side pouches
    rbox("leather", (0, 1.395, -.19), (.31, .10, .19), pk, tone((1.0, .92, .78), .06, 40, 22), e=.3)
    rbox("pack", (0, 1.055, -.268), (.25, .17, .055), pk, tone((1.05, 1.0, .9), .08, 50, 23), e=.3)
    for s in (-1, 1):
        rbox("pack", (s * .195, 1.10, -.19), (.07, .19, .11), pk, tone((1.0, .96, .88), .08, 50, 24), e=.3)
        rbox("leather_dark", (s * .195, 1.18, -.19), (.074, .026, .114), pk, e=.3)
    # bedroll (two straps) under the pack
    P = np.array([[-.12, .93, -.19], [0, .93, -.19], [.12, .93, -.19]])
    loft(P, [.044] * 3, [.044] * 3, "bedroll", pk, tone((1.0, .94, .84), .08, 40, 25), R=6, segs=14, hs=(0, 1, 0), hf=(0, 0, 1), caps=(True, True), uv=(2, 2), smooth_iter=0)
    # shoulder straps (padded webbing) from the pack top over the shoulders to the chest, sternum strap
    for s in (-1, 1):
        nm = "L" if s > 0 else "R"
        ys2 = [1.40, 1.50, 1.45, 1.36, 1.24, 1.10, 1.02]; zs = [-.11, -.02, .085, .120, .124, .118, .105]; xs = [s * .085, s * .09, s * .095, s * .10, s * .102, s * .10, s * .098]
        P = np.array(list(zip(xs, ys2, zs)))
        loft(P, [.019] * 7, [.0065] * 7, "pants", lambda V: w_chain(V[:, 1], ["hips", "spine", "chest"], [.99, 1.22], [.07, .07]), tone((.62, .6, .5), .05, 60, 26), R=18, segs=10, hs=(1, 0, 0), hf=(0, 0, 1), caps=(True, True), uv=(1, 6))
    grp("detail")
    rbox("leather", (0, 1.30, -.268 + -.0), (.034, .22, .012), pk, e=.35)
    rbox("metal", (0, 1.19, -.282), (.042, .03, .012), pk, e=.4, nu=8, nv=4)
    for k in (-1, 1): rbox("metal", (k * .195, 1.18, -.25), (.02, .02, .008), pk, e=.4, nu=8, nv=4)
    for xx in (-.07, .07): loft(np.array([[xx, .93 - .048, -.19], [xx, .93 + .048, -.19]]), [.008, .008], [.047, .047], "leather", pk, R=3, segs=10, caps=(False, False), uv=(1, 1))
    # zipper line on the front pocket, compass emblem (rear lid) and the copper cloth ribbon
    loft(np.array([[-.11, 1.115, -.2975], [.11, 1.115, -.2975]]), [.0022] * 2, [.0022] * 2, "thread", pk, R=4, segs=5, caps=(False, False), uv=(1, 1), hs=(0, 1, 0))
    disc("emblem", (0, 1.34, -.2915), (0, 0, -1), .066, pk)
    ys3 = np.linspace(1.40, 1.02, 9); P = np.array([[.12 + .012 * math.sin(i * .8), y, -.285 - .004 * i] for i, y in enumerate(ys3)])
    loft(P, [.016] * 9, [.004] * 9, "copper", pk, tone((1.0, .95, .9), .15, 40, 27), R=14, segs=8, hs=(1, 0, 0), hf=(0, 0, 1), caps=(True, True), uv=(1, 4))
    grp("base")

# ---------------------------------------------------------------- head ----
HEAD_C = np.array([0, 1.69, 0.012])
def G(x, y, cx, cy, sx, sy): return np.exp(-((x - cx) / sx) ** 2 - ((y - cy) / sy) ** 2)

def head_shape(q):
    qx, qy, qz = q[:, 0], q[:, 1], q[:, 2]
    x = qx * .0785; y = qy * .115; z = qz * .105; z = np.where(qz < 0, z * 1.08, z)
    low = smooth(0.0, -1.0, qy); x = x * (1 - .27 * low ** 1.25)
    z = z * (1 - .10 * low) + np.where((qz > 0) & (qy < -.5), .022 * smooth(-.5, -.95, qy), 0); y = y - .008 * smooth(-.6, -1.0, qy)
    f = qz > 0.1; zf = np.zeros_like(z)
    zf += (.013 + .021 * smooth(.02, -.04, y)) * G(x, y, 0, -.012, .0095, .036) * (y > -.05)
    for s in (-1, 1):
        zf += .008 * G(x, y, s * .0155, -.036, .008, .008) - .0078 * G(x, y, s * .034, .020, .017, .011)
        zf += .0075 * G(x, y, s * .058, -.014, .02, .02) - .0050 * G(x, y, s * .050, -.046, .02, .02)
        zf += .004 * G(x, y, s * .066, -.075, .018, .020)                                           # jaw angle
    zf += .010 * G(x, y, 0, .034, .060, .011) + .004 * G(x, y, 0, -.062, .020, .0055) + .005 * G(x, y, 0, -.075, .022, .007)
    zf += -.0035 * G(x, y, 0, -.0685, .028, .0016) + .007 * G(x, y, 0, -.098, .02, .015)
    return np.stack([x, y, z + zf * f], 1)

def morph_deltas(L):
    x, y, z = L[:, 0], L[:, 1], L[:, 2]; ax = np.abs(x); sg = np.sign(x)
    f = smooth(-0.03, 0.05, z)
    corner = G(ax, y, .026, -.068, .014, .010); cheek = G(ax, y, .05, -.032, .022, .020)
    brow = G(ax, y, .035, .044, .030, .012); fore = G(x, y, 0, .07, .06, .02); jaw = smooth(-.05, -.10, y) * f
    outer = G(ax, y, .055, .040, .02, .012); bags = G(ax, y, .034, .0, .02, .010)
    D = {}
    d = np.zeros_like(L); d[:, 1] += .008 * corner + .0035 * cheek; d[:, 0] += sg * (.005 * corner + .002 * cheek); d[:, 2] += .003 * corner; d[:, 1] -= .003 * G(x, y, 0, -.0755, .02, .006); D["smile"] = d * f[:, None]
    d = np.zeros_like(L); d[:, 1] += .008 * brow + .004 * fore - .015 * jaw; d[:, 2] -= .003 * jaw; D["surprise"] = d * f[:, None] if False else d
    d = np.zeros_like(L); d[:, 1] += -.005 * brow + .002 * cheek; d[:, 0] += -sg * .003 * brow; D["focus"] = d * f[:, None]
    d = np.zeros_like(L); d[:, 1] += .006 * brow - .002 * corner - .006 * jaw; d[:, 0] += -sg * .004 * brow + sg * .004 * corner; D["fear"] = d * f[:, None] if False else d
    d = np.zeros_like(L); d[:, 1] += -.004 * outer - .002 * bags - .004 * corner - .004 * jaw; d[:, 2] += .001 * bags; D["tired"] = d * f[:, None] if False else d
    for k in ("surprise", "fear", "tired"): D[k] = D[k] * f[:, None]
    return D

def build_head():
    grp("head"); nlat, nlon = 48, 64; qs = []
    for i in range(nlat + 1):
        th = math.pi * i / nlat
        for k in range(nlon + 1):
            ph = 2 * math.pi * k / nlon; qs.append((math.sin(th) * math.sin(ph), math.cos(th), math.sin(th) * math.cos(ph)))
    q = np.array(qs); Pm = head_shape(q) + HEAD_C; idx = lambda i, k: i * (nlon + 1) + k; I = []
    for i in range(nlat):
        for k in range(nlon):
            a, b, c, d = idx(i, k), idx(i, k + 1), idx(i + 1, k), idx(i + 1, k + 1); I += [(a, c, b), (b, c, d)]
    I = np.array(I); tri = Pm[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); cen = tri.mean(1) - HEAD_C
    if np.sum(np.einsum("ij,ij->i", fn, cen)) < 0: I = I[:, ::-1]
    N = vertex_normals(Pm, I); local = Pm - HEAD_C; x, y, z = local.T
    uv = np.stack([np.arange(len(Pm)) % (nlon + 1) / nlon * 3, 1 - np.arange(len(Pm)) // (nlon + 1) / nlat * 3], 1)
    C = np.ones((len(Pm), 4)); front = (z > 0).astype(float); ax = np.abs(x)
    def mix(col, m):
        for j in range(3): C[:, j] = C[:, j] * (1 - m) + col[j] * m
    mix((1.0, .70, .68), np.clip(G(x, y, 0, -.0625, .021, .0042) + G(x, y, 0, -.0745, .021, .006), 0, 1) * front)
    ey = .043 + .005 * (ax / .035); mix((.30, .22, .18), np.clip(np.exp(-((y - ey) / .0058) ** 2) * ((ax > .012) & (ax < .062)), 0, 1) * front * .92)
    mix((.88, .72, .70), np.clip(G(ax, y, .055, -.03, .02, .02), 0, 1) * front * .5)
    mix((.62, .45, .42), np.clip(G(ax, y, .034, .019, .016, .011) * .5, 0, 1) * front)
    mix((.50, .35, .34), np.clip(G(ax, y, .0155, -.040, .006, .005), 0, 1) * front)
    mix((.42, .33, .28), (1 - smooth(-.095, -.050, y)) * front * .34 * (1 - np.clip(G(x, y, 0, -.0685, .03, .007) * 2, 0, 1)))
    mix((.70, .55, .50), np.clip(G(ax, y, .034, -.004, .02, .007), 0, 1) * front * .35)          # faint eye bags
    D = morph_deltas(local)
    new_part("skin", Pm, N, uv, I, C, w_single(len(Pm), "head"), D)
    skin_part = PARTS[-1]
    for s in (-1, 1):
        ep = ellipsoid((s * .0805, 0, -.014) + HEAD_C, (.0095, .031, .021), 12, 9); ep["mat"] = "skin"; ep["W"] = w_single(len(ep["P"]), "head"); ep["group"] = "head"; ep["D"] = None; PARTS.append(ep)
    for s in (-1, 1):
        ep = ellipsoid((s * .0345, .019, .0775) + HEAD_C, (.0118, .0118, .0118), 18, 12, eye=True); ep["mat"] = "eye"; ep["W"] = w_single(len(ep["P"]), "head"); ep["group"] = "head"; ep["D"] = None
        d = ep["P"] - (np.array([s * .0345, .019, .0775]) + HEAD_C); ang = np.arccos(np.clip(d[:, 2] / np.linalg.norm(d, axis=1), -1, 1)); Ce = np.ones((len(d), 4))
        iris = np.clip((0.62 - ang) / 0.06, 0, 1); pupil = np.clip((0.26 - ang) / 0.05, 0, 1); ring = np.clip((ang - .50) / .06, 0, 1) * iris
        for j, col in enumerate((.20, .30, .22)): Ce[:, j] = (1 - iris) + col * iris * (1 - .5 * ring)
        for j in range(3): Ce[:, j] = Ce[:, j] * (1 - pupil) + 0.02 * pupil
        ep["C"] = Ce; PARTS.append(ep)
    shell(Pm, N, I, local, D, hair=True); shell(Pm, N, I, local, D, hair=False); grp("base")

def ellipsoid(c, r, nlat, nlon, eye=False):
    V = []; Nn = []; UV = []
    for i in range(nlat + 1):
        th = math.pi * i / nlat
        for k in range(nlon + 1):
            ph = 2 * math.pi * k / nlon; q = np.array([math.sin(th) * math.sin(ph), math.cos(th), math.sin(th) * math.cos(ph)])
            V.append(np.array(c) + q * np.array(r)); Nn.append(q / np.array(r)); UV.append((0.5 + q[0] * 0.5, 0.5 - q[1] * 0.5) if eye else (k / nlon, i / nlat))
    I = []
    for i in range(nlat):
        for k in range(nlon):
            a = i * (nlon + 1) + k; b = a + 1; c2 = a + nlon + 1; d = c2 + 1; I += [(a, c2, b), (b, c2, d)]
    V = np.array(V); Nn = norm(np.array(Nn)); I = np.array(I); tri = V[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if np.sum(np.einsum("ij,ij->i", fn, Nn[I[:, 0]])) < 0: I = I[:, ::-1]
    return dict(P=V, N=Nn, UV=np.array(UV), I=I, C=np.ones((len(V), 4)), W=np.zeros((len(V), NB)), mat="skin", group="head", D=None)

def shell(Pm, N, I, local, D, hair):
    x, y, z = local.T; ax = np.abs(x); rng = np.random.default_rng(11 if hair else 12)
    if hair:
        # practical, slightly messy cut: side part, longer top, short sides, uneven locks
        hairline = .040 + .026 * smooth(0, .07, ax) + .010 * np.sin(x * 70)
        wgt = np.clip(smooth(hairline - .004, hairline + .012, y), 0, 1)
        wgt = np.maximum(wgt, np.clip(smooth(.0, -.02, z) * smooth(-.06, -.01, y) + smooth(-.02, .02, -z) * (y > -.05), 0, 1))
        wgt = np.maximum(wgt, np.clip(smooth(.058, .066, ax) * smooth(-.012, .01, y) * (z < .035), 0, 1))
        wgt = wgt * (1 - np.clip((y < .02) & (z > .02), 0, 1))
        lock = np.sin(np.arctan2(x, z) * 11 + y * 60) * np.sin(z * 90 + 1.3)
        off = .0075 + .0045 * lock * .8 + .004 * smooth(0, .1, y) * (np.sin(np.arctan2(x, z) * 7 + 1.1) * .5 + .5)
        off = off + .008 * G(x, y, -.022, .076, .03, .02) + .005 * G(x, y, .03, .062, .02, .015) - .003 * G(x, y, 0.0, .0, .2, .02) * (z > 0)
        reg = wgt > .5; col = np.array([.30, .20, .13]); mat = "hair"
    else:
        mouth = (np.abs(x) < .0215) & (y > -.0735) & (y < -.0640) & (z > .0)
        jaw = -.038 + .040 * smooth(.030, .078, ax); wgt = smooth(jaw + .006, jaw - .006, y) * smooth(-.03, .01, z)
        wgt = np.maximum(wgt, np.clip((y > -.058) & (y < -.049) & (ax < .034) & (z > .06), 0, 1) * .95)
        wgt = wgt * (1 - mouth) * (1 - np.clip(G(x, y, 0, -.0685, .026, .0045) * 1.2, 0, 1))
        off = (.005 + .0018 * np.sin(x * 220 + y * 160)) * np.maximum(wgt, 0.15); reg = wgt > .08; col = np.array([.23, .15, .10]); mat = "beard"
    ok = reg[I].all(axis=1) if hair else reg[I].any(axis=1)
    sel = I[ok]; used = np.unique(sel); remap = -np.ones(len(Pm), int); remap[used] = np.arange(len(used))
    V = Pm[used] + N[used] * off[used][:, None]; nn = N[used]; uvs = np.stack([x[used] * 9, y[used] * 9], 1) + rng.uniform(0, .2)
    C = np.ones((len(V), 4)); jit = 0.8 + .35 * rng.random(len(V)); C[:, :3] = (np.array([1.0, .86, .72]) * jit[:, None]) * (0.6 if hair else 0.5)
    if not hair: C[:, 3] = np.clip(wgt[used] * 1.6, 0, 1)             # soft, feathered beard edge (alpha blend material)
    Dm = {k: v[used] for k, v in D.items()}
    new_part(mat, V, nn, uvs, remap[sel], C, w_single(len(V), "head"), Dm)

def assemble():
    PARTS.clear(); grp("base"); build_body(); return PARTS

if __name__ == "__main__":
    parts = assemble()
    from collections import Counter
    print("parts", len(parts), "verts", sum(len(p["P"]) for p in parts), "tris", sum(len(p["I"]) for p in parts))
    print(Counter(p["group"] for p in parts)); print(Counter(p["mat"] for p in parts))
    for g in ("base", "detail", "head"): print(g, "tris", sum(len(p["I"]) for p in parts if p["group"] == g))
