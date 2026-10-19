#!/usr/bin/env python3
"""Procedural adult male explorer: smooth lofted body, sculpted face, hands with fingers, hair, beard,
clothes and gear. Model space: Y up, character FRONT = +Z (glTF convention), character LEFT = +X.
Everything is skinned to a 16-bone skeleton (bone names match scripts/character.gd joints)."""
import math
import numpy as np

BONES = ["hips", "spine", "chest", "head", "shL", "elL", "handL", "shR", "elR", "handR",
         "hipL", "knL", "anL", "hipR", "knR", "anR"]
BI = {b: i for i, b in enumerate(BONES)}
PARENT = {"hips": None, "spine": "hips", "chest": "spine", "head": "chest", "shL": "chest", "elL": "shL", "handL": "elL",
          "shR": "chest", "elR": "shR", "handR": "elR", "hipL": "hips", "knL": "hipL", "anL": "knL",
          "hipR": "hips", "knR": "hipR", "anR": "knR"}
# global rest positions of the joints (meters)
POS = {"hips": (0, .92, 0), "spine": (0, .98, 0), "chest": (0, 1.28, 0), "head": (0, 1.52, 0.0),
       "shL": (.205, 1.43, 0), "elL": (.222, 1.15, 0), "handL": (.230, .90, 0),
       "shR": (-.205, 1.43, 0), "elR": (-.222, 1.15, 0), "handR": (-.230, .90, 0),
       "hipL": (.095, .90, 0), "knL": (.095, .49, 0), "anL": (.095, .09, 0),
       "hipR": (-.095, .90, 0), "knR": (-.095, .49, 0), "anR": (-.095, .09, 0)}

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def norm(v, eps=1e-9):
    return v / (np.linalg.norm(v, axis=-1, keepdims=True) + eps)

PARTS = []

def new_part(mat, P, N, UV, I, C=None, W=None):
    n = len(P)
    C = np.ones((n, 4)) if C is None else C
    W = np.zeros((n, 16)) if W is None else W
    PARTS.append(dict(mat=mat, P=np.asarray(P, float), N=np.asarray(N, float), UV=np.asarray(UV, float),
                      I=np.asarray(I, np.int64), C=np.asarray(C, float), W=np.asarray(W, float)))
    return PARTS[-1]

def w_single(n, bone):
    W = np.zeros((n, 16)); W[:, BI[bone]] = 1.0; return W

def w_chain(v, bones, cuts, widths):
    """Blend bones along coordinate v (increasing). cuts[i] separates bones[i] and bones[i+1]."""
    n = len(v); W = np.zeros((n, 16)); prev = np.ones(n)
    for i, b in enumerate(bones):
        if i < len(cuts):
            t = smooth(cuts[i] - widths[i], cuts[i] + widths[i], v)
        else:
            t = np.ones(n)
        W[:, BI[b]] += prev * (1 - t) if i < len(cuts) else prev
        prev = prev * t
    return W

def resample(arrs, R, smooth_iter=2):
    """arrs: list of (k,...) control arrays -> (R,...) smooth profiles."""
    k = len(arrs[0]); t0 = np.linspace(0, 1, k); t1 = np.linspace(0, 1, R); out = []
    for a in arrs:
        a = np.asarray(a, float)
        if a.ndim == 1:
            r = np.interp(t1, t0, a)
        else:
            r = np.stack([np.interp(t1, t0, a[:, j]) for j in range(a.shape[1])], 1)
        for _ in range(smooth_iter):
            p = np.pad(r, [(1, 1)] + [(0, 0)] * (r.ndim - 1), mode="edge")
            r = (p[:-2] + 2 * p[1:-1] + p[2:]) / 4.0
        out.append(r)
    return out

def loft(P, rx, rz, mat, weights, color=None, R=18, segs=14, hs=(1, 0, 0), hf=(0, 0, 1), caps=(True, True), uv=(2.0, 6.0), smooth_iter=2, shape_pow=1.0):
    P, rx, rz = resample([P, rx, rz], R, smooth_iter)
    T = norm(np.gradient(P, axis=0))
    hs = np.array(hs, float); hf = np.array(hf, float)
    S = norm(hs[None] - (T @ hs)[:, None] * T)
    F = norm(hf[None] - (T @ hf)[:, None] * T - (S @ hf)[:, None] * S)
    rings = [(P, T, S, F, rx, rz)]
    # rounded end caps (3 rings each)
    def cap(i, sign):
        out = []
        r = (rx[i] + rz[i]) / 2
        for j in (1, 2, 3):
            th = j * (math.pi / 2) / 3
            f = max(math.cos(th), 0.03)
            out.append((P[i] + sign * T[i] * math.sin(th) * r, T[i], S[i], F[i], rx[i] * f, rz[i] * f))
        return out
    seq = []
    if caps[0]:
        seq += cap(0, -1)[::-1]
    seq += [(P[i], T[i], S[i], F[i], rx[i], rz[i]) for i in range(R)]
    if caps[1]:
        seq += cap(R - 1, +1)
    nr = len(seq); V = []; Nn = []; UVs = []; s_acc = 0.0
    for i, (c, t, s, f, a, b) in enumerate(seq):
        if i > 0:
            s_acc += np.linalg.norm(c - seq[i - 1][0])
        for k in range(segs + 1):
            ang = 2 * math.pi * k / segs
            ca, sa = math.cos(ang), math.sin(ang)
            if shape_pow != 1.0:   # superellipse (boxy) cross-section
                ca = math.copysign(abs(ca) ** (2 / shape_pow), ca); sa = math.copysign(abs(sa) ** (2 / shape_pow), sa)
            V.append(c + s * a * ca + f * b * sa)
            n = s * ca / max(a, 1e-4) + f * sa / max(b, 1e-4)
            Nn.append(n)
            UVs.append((uv[0] * k / segs, uv[1] * s_acc))
    V = np.array(V); Nn = norm(np.array(Nn)); UVs = np.array(UVs)
    I = []
    for i in range(nr - 1):
        for k in range(segs):
            a = i * (segs + 1) + k; b = a + 1; c2 = a + segs + 1; d = c2 + 1
            I += [(a, c2, b), (b, c2, d)]
    I = np.array(I)
    # make winding agree with outward normals
    tri = V[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if np.sum(np.einsum("ij,ij->i", fn, Nn[I[:, 0]])) < 0:
        I = I[:, ::-1]
    W = weights(V) if callable(weights) else w_single(len(V), weights)
    C = None if color is None else (color(V) if callable(color) else np.tile(np.array(color, float), (len(V), 1)))
    return new_part(mat, V, Nn, UVs, I, C, W)

def line(*pts):
    return np.array(pts, float)

# ---------------------------------------------------------------- body ----
def wrinkle(V, amp=0.10, f=60.0, seed=0):
    r = np.random.default_rng(seed)
    ph = r.uniform(0, 6.28, 3)
    n = np.sin(V[:, 1] * f + ph[0] + 3 * np.sin(np.arctan2(V[:, 0], V[:, 2]) * 3 + ph[1])) * 0.5 + 0.5
    return 1.0 - amp * n

def build_body():
    # --- torso (olive overshirt)
    ys = [.86, .92, .98, 1.06, 1.14, 1.22, 1.30, 1.38, 1.44, 1.485, 1.52]
    rx = [.168, .164, .154, .156, .164, .176, .188, .194, .184, .110, .062]
    rz = [.106, .104, .098, .100, .106, .114, .122, .124, .110, .082, .060]
    cz = [0, 0, 0, 0, .002, .006, .012, .014, .006, -.004, -.008]
    P = np.array([[0, y, c] for y, c in zip(ys, cz)])
    tw = lambda V: w_chain(V[:, 1], ["hips", "spine", "chest"], [.99, 1.22], [.07, .07])
    def tcol(V):
        c = np.ones((len(V), 4)); w = wrinkle(V, .12, 55, 1); c[:, :3] = w[:, None]
        c[:, :3] *= (0.86 + 0.14 * smooth(.86, 1.3, V[:, 1]))[:, None]; return c
    loft(P, rx, rz, "shirt", tw, tcol, R=20, uv=(2, 5), caps=(True, True))
    # --- pelvis / trousers waist
    ys = [.80, .84, .90, .96, 1.0]
    P = np.array([[0, y, 0] for y in ys])
    loft(P, [.130, .160, .180, .176, .168], [.100, .116, .124, .118, .110], "pants", "hips", color=_wcol3, R=10, uv=(2, 3))
    # --- belt + buckle
    P = np.array([[0, .958, 0], [0, .998, 0]])
    loft(P, [.186, .186], [.128, .128], "leather", "hips", R=4, caps=(False, False), uv=(4, 2))
    box_at("leather", (0, .978, .131), (.05, .036, .012), "hips")
    box_at("metal", (0, .978, .139), (.03, .022, .004), "hips")
    # --- neck
    P = np.array([[0, 1.48, 0.002], [0, 1.54, 0.008], [0, 1.605, 0.014]])
    loft(P, [.054, .05, .049], [.057, .052, .05], "skin", lambda V: w_chain(V[:, 1], ["chest", "head"], [1.54], [.04]), R=8, caps=(False, False), uv=(2, 3))
    for sd, nm in ((1, "L"), (-1, "R")):
        build_arm(sd, nm); build_leg(sd, nm)
    build_head()
    build_gear()

def box_at(mat, c, size, bone, rot_y=0.0, round_=0.0, shape_pow=3.0):
    """Rounded box via a superellipse loft along Y."""
    c = np.array(c, float); h = size[1] / 2
    P = np.array([c + [0, -h, 0], c + [0, h, 0]])
    loft(P, [size[0] / 2] * 2, [size[2] / 2] * 2, mat, bone, R=4, segs=16, caps=(True, True), uv=(1, 2), shape_pow=shape_pow, smooth_iter=0)

def build_arm(sd, nm):
    x = .222 * sd
    # upper arm in rolled shirt sleeve
    ys = [1.475, 1.44, 1.36, 1.26, 1.18, 1.155, 1.135]
    r = [.054, .056, .050, .046, .044, .051, .051]
    P = np.array([[x + .004 * sd * i, y, 0] for i, y in enumerate(ys)])
    ww = lambda V: w_chain(-V[:, 1], ["chest", "sh" + nm, "el" + nm], [-1.455, -1.15], [.05, .04])
    loft(P, r, r, "shirt", ww, _wcol, R=18, uv=(2, 3), caps=(True, True))
    # forearm (skin) with muscle bulge
    ys = [1.15, 1.10, 1.03, .965, .915, .895]
    rx = [.041, .042, .038, .032, .028, .027]
    rz = [.040, .041, .037, .032, .030, .028]
    P = np.array([[x + (.020 + .002 * i) * sd, y, 0] for i, y in enumerate(ys)])
    wf = lambda V: w_chain(-V[:, 1], ["el" + nm, "hand" + nm], [-.90], [.03])
    loft(P, rx, rz, "skin", wf, _skin_col, R=14, uv=(2, 2), caps=(False, False))
    # hand: fingerless glove palm + bare fingers + thumb
    hx = x + .030 * sd
    ys = [.90, .875, .84, .805, .79]
    P = np.array([[hx + .002 * sd * i, y, .002 * i] for i, y in enumerate(ys)])
    loft(P, [.030, .026, .024, .022, .020], [.030, .043, .047, .045, .042], "leather_dark", "hand" + nm, hs=(1, 0, 0), hf=(0, 0, 1), R=8, caps=(False, True), uv=(2, 1))
    for fz, ln in ((-.032, .060), (-.011, .068), (.011, .066), (.032, .056)):
        p0 = np.array([hx + .004 * sd, .795, fz]); path = np.array([p0, p0 + [-.002 * sd, -ln * .45, .004], p0 + [-.006 * sd, -ln * .8, .014], p0 + [-.010 * sd, -ln * .98, .026]])
        loft(path, [.0095, .0090, .0085, .0075], [.0095, .0090, .0085, .0075], "skin", "hand" + nm, R=6, segs=8, caps=(False, True), uv=(1, 1), smooth_iter=1, hf=(0, 0, 1))
    p0 = np.array([hx - .012 * sd, .86, .042])
    path = np.array([p0, p0 + [-.004 * sd, -.018, .016], p0 + [-.008 * sd, -.040, .030], p0 + [-.010 * sd, -.056, .038]])
    loft(path, [.0125, .0115, .0100, .0085], [.0125, .0115, .0100, .0085], "skin", "hand" + nm, R=6, segs=8, caps=(False, True), uv=(1, 1), smooth_iter=1)

def _wcol3(V):
    c = np.ones((len(V), 4)); c[:, :3] = wrinkle(V, .15, 48, 3)[:, None]; return c

def _wcol(V):
    c = np.ones((len(V), 4)); c[:, :3] = wrinkle(V, .12, 70, 2)[:, None]; return c

def _skin_col(V):
    c = np.ones((len(V), 4)); n = np.sin(V[:, 1] * 90) * .02; c[:, 0] = 1.0; c[:, 1] = 1 + n; c[:, 2] = 1 + n * 1.5; return c

def build_leg(sd, nm):
    x = .095 * sd
    # trousers (cargo, slightly baggy) hip -> hem
    ys = [.94, .86, .76, .66, .56, .49, .42, .33, .25, .19]
    rx = [.104, .106, .100, .090, .076, .071, .074, .066, .064, .068]
    rz = [.108, .112, .104, .094, .080, .075, .080, .072, .068, .072]
    cz = [0, 0, 0, .002, .004, .006, -.006, -.004, 0, .004]
    P = np.array([[x * (1.0 if i > 1 else 1.0), y, c] for i, (y, c) in enumerate(zip(ys, cz))])
    wl = lambda V: w_chain(-V[:, 1], ["hip" + nm, "kn" + nm, "an" + nm], [-.49, -.12], [.06, .05])
    def pc(V):
        c = np.ones((len(V), 4)); w = wrinkle(V, .15, 48, 3 + (1 if sd > 0 else 0)); k = 1.0 - .18 * np.exp(-((V[:, 1] - .49) / .045) ** 2) * (V[:, 2] > 0)
        c[:, :3] = (w * k)[:, None]; return c
    loft(P, rx, rz, "pants", wl, pc, R=22, uv=(2, 6), caps=(True, False))
    # cargo pocket on the outer thigh + flap
    box_at("pants", (x + .098 * sd, .72, .0), (.032, .15, .115), "hip" + nm)
    box_at("pants", (x + .102 * sd, .775, .0), (.034, .035, .12), "hip" + nm)
    # boot shaft
    P = np.array([[x, .27, 0], [x, .20, 0], [x, .12, 0], [x, .07, 0]])
    loft(P, [.071, .066, .058, .056], [.074, .069, .060, .058], "leather", lambda V: w_chain(-V[:, 1], ["kn" + nm, "an" + nm], [-.25], [.05]), R=8, caps=(False, False), uv=(2, 3))
    # boot foot
    zs = [-.075, -.05, -.01, .05, .11, .16, .205]
    P = np.array([[x, y, z] for y, z in zip([.056, .052, .047, .042, .039, .035, .031], zs)])
    loft(P, [.048, .056, .060, .059, .056, .050, .036], [.052, .052, .047, .042, .036, .030, .022], "leather", "an" + nm, hs=(1, 0, 0), hf=(0, 1, 0), R=14, uv=(2, 3))
    # sole
    P = np.array([[x, y, z] for y, z in zip([.016, .014, .012, .012, .012, .012, .014], zs)])
    loft(P, [.052, .060, .063, .062, .059, .053, .040], [.016, .016, .013, .012, .012, .012, .012], "rubber", "an" + nm, hs=(1, 0, 0), hf=(0, 1, 0), R=14, caps=(True, True), uv=(2, 3))

# ---------------------------------------------------------------- head ----
HEAD_C = np.array([0, 1.69, 0.012])
def G(x, y, cx, cy, sx, sy):
    return np.exp(-((x - cx) / sx) ** 2 - ((y - cy) / sy) ** 2)

def head_shape(q):
    qx, qy, qz = q[:, 0], q[:, 1], q[:, 2]
    x = qx * .0775; y = qy * .115; z = qz * .105
    z = np.where(qz < 0, z * 1.08, z)
    low = smooth(0.0, -1.0, qy)                                  # 0 at brow level .. 1 at chin
    x = x * (1 - .30 * low ** 1.2)
    z = z * (1 - .10 * low) + np.where((qz > 0) & (qy < -.5), .020 * smooth(-.5, -.95, qy), 0)
    y = y - .008 * smooth(-.6, -1.0, qy)
    ax = np.abs(x)
    f = qz > 0.1
    zf = np.zeros_like(z)
    zf += (.012 + .020 * smooth(.02, -.04, y)) * G(x, y, 0, -.012, .0095, .036) * (y > -.05)   # nose bridge & tip
    for s in (-1, 1):
        zf += .008 * G(x, y, s * .0155, -.036, .008, .008)                                       # nostril wings
        zf += -.0075 * G(x, y, s * .034, .020, .017, .011)                                      # eye sockets
        zf += .0065 * G(x, y, s * .058, -.014, .02, .02)                                        # cheekbones
        zf += -.0045 * G(x, y, s * .050, -.046, .02, .02)                                       # cheek hollows
    zf += .009 * G(x, y, 0, .034, .060, .011)                                                   # brow ridge
    zf += .004 * G(x, y, 0, -.062, .020, .0055) + .005 * G(x, y, 0, -.075, .022, .007)          # lips
    zf += -.0035 * G(x, y, 0, -.0685, .028, .0016)                                              # mouth line
    zf += .006 * G(x, y, 0, -.098, .02, .015)                                                   # chin
    z = z + zf * f
    return np.stack([x, y, z], 1)

def build_head():
    nlat, nlon = 48, 64
    qs = []; 
    for i in range(nlat + 1):
        th = math.pi * i / nlat
        for k in range(nlon + 1):
            ph = 2 * math.pi * k / nlon          # 0 -> +Z front, increasing toward +X
            qs.append((math.sin(th) * math.sin(ph), math.cos(th), math.sin(th) * math.cos(ph)))
    q = np.array(qs); Pm = head_shape(q) + HEAD_C
    idx = lambda i, k: i * (nlon + 1) + k
    I = []
    for i in range(nlat):
        for k in range(nlon):
            a, b, c, d = idx(i, k), idx(i, k + 1), idx(i + 1, k), idx(i + 1, k + 1)
            I += [(a, c, b), (b, c, d)]
    I = np.array(I)
    tri = Pm[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); cen = tri.mean(1) - HEAD_C
    if np.sum(np.einsum("ij,ij->i", fn, cen)) < 0: I = I[:, ::-1]
    N = vertex_normals(Pm, I)
    local = Pm - HEAD_C; x, y, z = local[:, 0], local[:, 1], local[:, 2]
    uv = np.stack([np.arange(len(Pm)) % (nlon + 1) / nlon * 3, 1 - np.arange(len(Pm)) // (nlon + 1) / nlat * 3], 1)
    C = np.ones((len(Pm), 4)); front = (z > 0).astype(float)
    ax = np.abs(x); r = np.random.default_rng(5)
    def mix(col, m):
        for j in range(3): C[:, j] = C[:, j] * (1 - m) + col[j] * m
    mix((1.0, .70, .68), np.clip(G(x, y, 0, -.0625, .021, .0042) + G(x, y, 0, -.0745, .021, .006), 0, 1) * front)           # lips
    ey = .043 + .004 * (ax / .035)
    mix((.30, .22, .18), np.clip(np.exp(-((y - ey) / .0055) ** 2) * ((ax > .012) & (ax < .060)), 0, 1) * front * .9)       # brows
    mix((.80, .62, .62), np.clip(G(x, y, 0, -.0, .09, .028) * .0, 0, 1))
    mix((.88, .72, .70), np.clip(G(ax, y, .055, -.03, .02, .02), 0, 1) * front * .5)                                           # cheeks
    mix((.62, .45, .42), np.clip(G(ax, y, .034, .019, .016, .011) * .5, 0, 1) * front)                                         # eye shadow
    mix((.50, .35, .34), np.clip(G(ax, y, .0155, -.040, .006, .005), 0, 1) * front)                                            # nostrils
    mix((.42, .33, .28), (1 - smooth(-.08, -.045, y)) * smooth(.02, .06, ax + .0) * 0 + (1 - smooth(-.095, -.050, y)) * front * .38 * (1 - np.clip(G(x, y, 0, -.0685, .03, .007) * 2, 0, 1)))   # stubble
    new_part("skin", Pm, N, uv, I, C, w_single(len(Pm), "head"))
    # ears
    for s in (-1, 1):
        ep = ellipsoid((s * .0795, 0, -.014) + HEAD_C, (.0095, .031, .021), 14, 10)
        ep["W"] = w_single(len(ep["P"]), "head"); ep["mat"] = "skin"; PARTS.append(ep)
    # eyes (textured iris), sitting in the sockets
    for s in (-1, 1):
        zc = .0775
        ep = ellipsoid((s * .034, .019, zc) + HEAD_C, (.0118, .0118, .0118), 28, 20, eye=True)
        ep["W"] = w_single(len(ep["P"]), "head"); ep["mat"] = "eye"
        d = ep["P"] - (np.array([s * .034, .019, .0775]) + HEAD_C); ang = np.arccos(np.clip(d[:, 2] / np.linalg.norm(d, axis=1), -1, 1))
        C = np.ones((len(d), 4))
        iris = np.clip((0.62 - ang) / 0.06, 0, 1); pupil = np.clip((0.26 - ang) / 0.05, 0, 1); ring = np.clip((ang - .50) / .06, 0, 1) * iris
        for j, col in enumerate((.20, .30, .22)): C[:, j] = 1 * (1 - iris) + col * iris * (1 - .5 * ring)
        for j in range(3): C[:, j] = C[:, j] * (1 - pupil) + 0.02 * pupil
        ep["C"] = C; PARTS.append(ep)
    # hair + beard shells from the head surface
    shell(Pm, N, I, local, HEAD_C, hair=True)
    shell(Pm, N, I, local, HEAD_C, hair=False)

def vertex_normals(P, I):
    tri = P[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    N = np.zeros_like(P)
    for j in range(3): np.add.at(N, I[:, j], fn)
    key = np.round(P * 1e5).astype(np.int64)           # weld duplicates (UV seam, poles)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    acc = np.zeros((inv.max() + 1, 3)); np.add.at(acc, inv, N)
    return norm(acc[inv])

def ellipsoid(c, r, nlat, nlon, eye=False):
    V = []; Nn = []; UV = []
    for i in range(nlat + 1):
        th = math.pi * i / nlat
        for k in range(nlon + 1):
            ph = 2 * math.pi * k / nlon
            q = np.array([math.sin(th) * math.sin(ph), math.cos(th), math.sin(th) * math.cos(ph)])
            V.append(np.array(c) + q * np.array(r)); Nn.append(q / np.array(r))
            UV.append((0.5 + q[0] * 0.5, 0.5 - q[1] * 0.5) if eye else (k / nlon, i / nlat))
    I = []
    for i in range(nlat):
        for k in range(nlon):
            a = i * (nlon + 1) + k; b = a + 1; c2 = a + nlon + 1; d = c2 + 1
            I += [(a, c2, b), (b, c2, d)]
    V = np.array(V); Nn = norm(np.array(Nn)); I = np.array(I)
    tri = V[I]; fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if np.sum(np.einsum("ij,ij->i", fn, Nn[I[:, 0]])) < 0: I = I[:, ::-1]
    return dict(P=V, N=Nn, UV=np.array(UV), I=I, C=np.ones((len(V), 4)), W=np.zeros((len(V), 16)))

def shell(Pm, N, I, local, hc, hair):
    x, y, z = local[:, 0], local[:, 1], local[:, 2]; ax = np.abs(x)
    rng = np.random.default_rng(11 if hair else 12)
    if hair:
        hairline = .038 + .028 * smooth(0, .07, ax) - .0 * ax
        reg = ((y > hairline) & (z > -.2)) | ((z < -.01) & (y > -.045)) | ((ax > .060) & (y > -.012) & (z < .03))
        reg &= ~((y < .02) & (z > .02))
        off = .0075 + .0045 * np.sin(x * 140 + y * 90) * np.sin(z * 120 + 1.3) + .003 * (np.sin(np.arctan2(x, z) * 9) * .5 + .5) * smooth(0, .1, y)
        off = off + .006 * np.exp(-((x + .02) ** 2) / .0009) * np.exp(-((y - .075) ** 2) / .0009)        # swept fringe lock
        col = np.array([.30, .20, .13])
    else:
        mouth = (np.abs(x) < .021) & (y > -.0725) & (y < -.0645) & (z > .0)
        jaw = -.040 + .040 * smooth(.030, .078, ax)
        reg = ((y < jaw) & (z > -.02)) | ((y > -.058) & (y < -.050) & (ax < .032) & (z > .06))
        reg &= ~mouth
        off = .0055 + .002 * np.sin(x * 220 + y * 160)
        col = np.array([.23, .15, .10])
    ok = reg[I].all(axis=1)
    sel = I[ok]
    used = np.unique(sel); remap = -np.ones(len(Pm), int); remap[used] = np.arange(len(used))
    V = Pm[used] + N[used] * off[used][:, None]; nn = N[used]
    uvs = np.stack([x[used] * 9, y[used] * 9], 1) + rng.uniform(0, .2)
    C = np.ones((len(V), 4)); jit = 0.8 + .35 * rng.random(len(V)); C[:, :3] = (np.array([1.0, .86, .72]) * jit[:, None]) * (0.6 if hair else 0.5)
    new_part("hair", V, nn, uvs, remap[sel], C, w_single(len(V), "head"))

# ---------------------------------------------------------------- gear ----
def build_gear():
    # chest pockets with flaps
    for s in (-1, 1):
        box_at("shirt", (s * .088, 1.285, .138), (.092, .085, .016), "chest", shape_pow=4)
        box_at("shirt", (s * .088, 1.322, .144), (.096, .028, .018), "chest", shape_pow=4)
    # harness straps (leather) over shoulders, front and back
    for s in (-1, 1):
        ys = [1.50, 1.44, 1.36, 1.26, 1.14, 1.02]
        zs = [.03, .108, .134, .126, .112, .108]
        x = [s * .085, s * .092, s * .098, s * .102, s * .100, s * .098]
        P = np.array([[a, y, z] for a, y, z in zip(x, ys, zs)])
        loft(P, [.020] * 6, [.006] * 6, "leather", lambda V: w_chain(V[:, 1], ["hips", "spine", "chest"], [.99, 1.22], [.07, .07]), R=16, segs=10, caps=(True, True), uv=(1, 6), hs=(1, 0, 0), hf=(0, 0, 1))
        zs2 = [.03, -.10, -.126, -.12, -.108, -.10]
        P = np.array([[a, y, z] for a, y, z in zip(x, ys, zs2)])
        loft(P, [.022] * 6, [.007] * 6, "leather", "chest", R=16, segs=10, caps=(True, True), uv=(1, 6))
    # scarf: collar ring + hanging tail
    ang = np.linspace(0, 2 * math.pi, 28, endpoint=False)
    path = np.array([[.075 * math.sin(a), 1.525 + .006 * math.cos(2 * a), .08 * math.cos(a) + .004] for a in ang] + [[.0, 1.525, .084]])
    loft(path, [.024] * 29, [.026] * 29, "scarf", lambda V: w_chain(V[:, 1], ["chest", "head"], [1.56], [.03]), R=29, segs=12, caps=(False, False), uv=(2, 8), smooth_iter=0)
    P = np.array([[.035, 1.50, .125], [.04, 1.40, .142], [.045, 1.30, .144], [.047, 1.23, .141]])
    loft(P, [.034, .040, .042, .040], [.012, .012, .012, .010], "scarf", "chest", R=10, segs=12, caps=(False, True), uv=(1, 3), hs=(1, 0, 0), hf=(0, 0, 1))
    # backpack (rounded box) + flap + side pouches + bedroll + straps
    box_at("pack", (0, 1.19, -.165), (.34, .46, .17), "chest", shape_pow=3.2)
    box_at("leather", (0, 1.395, -.17), (.33, .09, .18), "chest", shape_pow=3.0)
    for s in (-1, 1):
        box_at("pack", (s * .195, 1.10, -.17), (.075, .20, .12), "chest", shape_pow=3)
        box_at("leather", (s * .075, 1.185, -.255), (.022, .30, .012), "chest", shape_pow=3)
    bedroll()
    # side satchel on the right hip with strap
    box_at("leather", (.10, .96, -.125), (.09, .09, .05), "hips", shape_pow=3)
    box_at("leather", (-.10, .96, -.125), (.09, .09, .05), "hips", shape_pow=3)

def bedroll():
    # horizontal cylinder under the pack (axis = X): path along x
    P = np.array([[-.17, .95, -.17], [0, .95, -.17], [.17, .95, -.17]])
    loft(P, [.065] * 3, [.065] * 3, "bedroll", "chest", hs=(0, 1, 0), hf=(0, 0, 1), R=6, segs=16, caps=(True, True), uv=(2, 2), smooth_iter=0)

# ------------------------------------------------------------- export prep ----
def assemble():
    PARTS.clear(); build_body()
    return PARTS

if __name__ == "__main__":
    parts = assemble()
    tv = sum(len(p["P"]) for p in parts); tt = sum(len(p["I"]) for p in parts)
    print("parts", len(parts), "verts", tv, "tris", tt)
    from collections import Counter
    print(Counter(p["mat"] for p in parts))
