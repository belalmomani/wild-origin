#!/usr/bin/env python3
"""Procedural, anatomically shaped red-deer stag and Nubian ibex for the game (rigid bone rig, painted vertex colours).

    python3 tools/build_animals.py              # writes assets/animals/{deer,ibex}_data.gd
    python3 tools/build_animals.py --preview    # also renders tools/preview_*.png (matplotlib) for a quick look

The supplied GLBs (tools/animals_src) were made of boxy ellipsoid blobs with 18-vertex prism legs, far from the reference
renders. Here every body part is a smooth lofted tube (elliptical cross-sections following the animal's silhouette),
the colours are painted per vertex from anatomy (pale belly / throat, dark back stripe, white socks, dark hooves ...)
with baked ambient occlusion and a little fur variation. Output goes to a GDScript data file (see scripts/animal_rig.gd).

Game axes: X right (left leg = -X), Y up, forward = -Z. Author-space helper P(x, y, f) takes f = distance forward.
"""
import os, sys, zlib
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "..", "assets", "animals")


def P(x, y, f):
    return np.array([x, y, -f], float)


def norm(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.where(n < 1e-12, 1, n)


# ------------------------------------------------------------------ meshes
def catmull(path, sub):
    p = np.asarray(path, float)
    if len(p) < 3:
        t = np.linspace(0, 1, sub * (len(p) - 1) + 1)[:, None]
        return p[0] * (1 - t) + p[-1] * t, np.linspace(0, len(p) - 1, len(t))
    ext = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    out, par = [], []
    for i in range(len(p) - 1):
        p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
        for s in range(sub):
            t = s / sub
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
            par.append(i + t)
    out.append(p[-1])
    par.append(len(p) - 1)
    return np.array(out), np.array(par)


def tube(path, rx, ry=None, seg=12, sub=5, ref=(0, 1, 0), ridge=None, caps=(True, True)):
    """Smooth tube along a Catmull-Rom path. rx = half width (side to side), ry = half height; scalars or per-key arrays."""
    path = np.asarray(path, float)
    n = len(path)
    rx = np.broadcast_to(np.asarray(rx, float), (n,)).copy()
    ry = rx.copy() if ry is None else np.broadcast_to(np.asarray(ry, float), (n,)).copy()
    pts, par = catmull(path, sub)
    idx = np.arange(n)
    ax = np.interp(par, idx, rx)
    ay = np.interp(par, idx, ry)
    T = norm(np.gradient(pts, axis=0))
    R = np.asarray(ref, float)
    lat = np.cross(T, R)
    bad = np.linalg.norm(lat, axis=1) < 1e-3
    lat[bad] = np.cross(T[bad], np.array([1.0, 0, 0]))
    lat = norm(lat)
    up2 = norm(np.cross(lat, T))
    if ridge is not None:
        m = 1.0 + ridge[0] * np.cos(par * ridge[1])
        ax, ay = ax * m, ay * m
    rings, nrms = [], []
    th = np.linspace(0, 2 * np.pi, seg, endpoint=False)
    c, s = np.cos(th), np.sin(th)

    def ring(center, a, b, l, u, t, phi):
        p = center[None] + (a * c)[:, None] * l[None] * np.cos(phi) + (b * s)[:, None] * u[None] * np.cos(phi) + t[None] * (np.sin(phi) * 0.5 * (a + b))
        nn = norm((c / a)[:, None] * l[None] * np.cos(phi) + (s / b)[:, None] * u[None] * np.cos(phi) + t[None] * np.sin(phi))
        return p, nn
    if caps[0]:
        for phi in (-1.35, -0.95, -0.5):
            p, nn = ring(pts[0], ax[0], ay[0], lat[0], up2[0], T[0], phi)
            rings.append(p)
            nrms.append(nn)
    for i in range(len(pts)):
        p, nn = ring(pts[i], ax[i], ay[i], lat[i], up2[i], T[i], 0.0)
        rings.append(p)
        nrms.append(nn)
    if caps[1]:
        for phi in (0.5, 0.95, 1.35):
            p, nn = ring(pts[-1], ax[-1], ay[-1], lat[-1], up2[-1], T[-1], phi)
            rings.append(p)
            nrms.append(nn)
    V = np.concatenate(rings)
    N = np.concatenate(nrms)
    F = []
    nr = len(rings)
    for i in range(nr - 1):
        for j in range(seg):
            a, b = i * seg + j, i * seg + (j + 1) % seg
            c2, d = (i + 1) * seg + j, (i + 1) * seg + (j + 1) % seg
            F += [(a, b, d), (a, d, c2)]
    extra = []
    if caps[0]:
        extra.append((V[: seg].mean(0), -T[0], 0))
    if caps[1]:
        extra.append((V[-seg:].mean(0), T[-1], len(V) - seg))
    for centre, nv, base in extra:
        k = len(V)
        V = np.vstack([V, centre])
        N = np.vstack([N, nv[None]])
        for j in range(seg):
            F.append((k, base + j, base + (j + 1) % seg))
    return V, N, np.array(F)


def icosphere(level):
    t = (1.0 + 5 ** 0.5) / 2.0
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    v = [np.array(p, float) / np.linalg.norm(p) for p in v]
    for _ in range(level):
        cache, nf = {}, []

        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                m = (v[a] + v[b]) / 2.0
                v.append(m / np.linalg.norm(m))
                cache[k] = len(v) - 1
            return cache[k]
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return np.array(v), np.array(f)


def ell(centre, r, level=2, rot=None):
    """Ellipsoid with half extents r=(x, y, z) in game axes; rot = 3x3 matrix applied to the local axes."""
    U, F = icosphere(level)
    r = np.asarray(r, float)
    pts = U * r
    nrm = norm(U / r)
    if rot is not None:
        pts = pts @ rot.T
        nrm = nrm @ rot.T
    return pts + np.asarray(centre, float), nrm, F


def rotz(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rotx(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def roty(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


# ------------------------------------------------------------------ colour helpers
def mix(a, b, w):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    w = np.asarray(w, float)[..., None] if np.ndim(w) else w
    return a * (1 - w) + b * w


def ss(a, b, x):
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def flat(c):
    return lambda p, n: np.tile(np.asarray(c, float), (len(p), 1))


# ------------------------------------------------------------------ animals
class Part:
    def __init__(self, bone, mesh, color, name=""):
        self.bone, self.mesh, self.color, self.name = bone, mesh, color, name


def lr(side):          # leg side tag -> x sign (left = -X)
    return -1.0 if side == "l" else 1.0


def deer():
    parts = []
    brown, cream = np.array([0.69, 0.37, 0.15]), np.array([0.93, 0.87, 0.76])
    dark = np.array([0.16, 0.12, 0.10])
    # torso -------------------------------------------------------------
    st = [(-0.52, 0.91, .05, .08), (-0.46, 0.90, .12, .16), (-0.30, 0.82, .15, .20), (-0.08, 0.79, .145, .21), (0.14, 0.79, .15, .22),
          (0.32, 0.80, .15, .23), (0.45, 0.85, .12, .19), (0.55, 0.91, .08, .12)]
    path = [P(0, y, f) for f, y, w, h in st]
    m = tube(path, [s[2] for s in st], [s[3] for s in st], seg=18, sub=6)

    def torso_col(p, n):
        f = -p[:, 2]
        c = mix(brown, cream, ss(0.15, -0.75, n[:, 1]))
        c = mix(c, cream, ss(0.40, 0.52, f) * ss(0.5, -0.2, n[:, 1]) * 0.9)         # pale throat / chest front
        c = mix(c, cream, ss(-0.36, -0.52, f) * ss(0.3, -0.5, n[:, 1]) * 0.8)         # pale rump underside
        return c * (1 - 0.14 * ss(0.5, 1.0, n[:, 1]))[:, None]
    parts.append(Part("spine", m, torso_col, "torso"))
    for sx in (-1, 1):                                        # haunch and shoulder muscle
        parts.append(Part("spine", ell(P(sx * .09, .76, -.33), (.06, .18, .19), 2, rotx(-0.15)), lambda p, n: mix(brown, cream, ss(0.1, -0.7, n[:, 1]) * 0.8), "haunch"))
        parts.append(Part("spine", ell(P(sx * .105, .74, .30), (.06, .19, .14), 2, rotx(0.2)), lambda p, n: mix(brown, cream, ss(0.1, -0.7, n[:, 1]) * 0.8), "shoulder"))
    # neck (white throat, brown crest) ------------------------------------
    path = [P(0, 0.90, 0.38), P(0, 1.04, 0.52), P(0, 1.22, 0.66), P(0, 1.38, 0.78)]
    m = tube(path, [.115, .085, .065, .056], [.15, .11, .08, .068], seg=14, sub=6)

    def neck_col(p, n):
        c = mix(cream, brown, ss(0.15, 0.85, n[:, 1] + 0.35 * np.clip(-n[:, 2] * 0, 0, 1)))
        return mix(c, brown, ss(0.95, 0.80, p[:, 1]) * 0.8)                           # base blends into the shoulder
    parts.append(Part("neck", m, neck_col, "neck"))
    # head ------------------------------------------------------------------
    path = [P(0, 1.38, 0.76), P(0, 1.35, 0.86), P(0, 1.28, 0.97), P(0, 1.23, 1.08)]
    m = tube(path, [.060, .058, .045, .030], [.074, .068, .052, .036], seg=14, sub=6)

    def head_col(p, n):
        f = -p[:, 2]
        c = mix(brown, cream, ss(-0.1, -0.8, n[:, 1]) * 0.6)
        c = mix(c, cream, ss(0.93, 1.03, f) * 0.85)                                   # pale muzzle
        return mix(c, dark, ss(1.07, 1.10, f))                                       # nose tip
    parts.append(Part("head", m, head_col, "head"))
    for sx in (-1, 1):
        parts.append(Part("head", ell(P(sx * 0.052, 1.355, 0.93), (.026, .020, .03), 1), flat((0.95, 0.9, 0.82)), "eye_ring"))
        parts.append(Part("head", ell(P(sx * 0.056, 1.355, 0.945), (.016, .016, .018), 1), flat((0.05, 0.04, 0.04)), "eye"))
        ear = ell(P(sx * 0.105, 1.50, 0.76), (.012, .08, .036), 2, rotz(sx * 0.55) @ rotx(-0.25))
        parts.append(Part("ear_l" if sx < 0 else "ear_r", ear, lambda p, n: mix(brown, np.array([0.85, 0.6, 0.55]), ss(0.0, 0.7, np.abs(n[:, 0]) * 0 + 0.5 + 0 * n[:, 1])), "ear"))
    parts.append(Part("head", ell(P(0, 1.235, 1.10), (.030, .022, .026), 1), flat(dark), "nose"))
    # tail ----------------------------------------------------------------
    parts.append(Part("tail", ell(P(0, 0.93, -0.58), (.03, .06, .05), 1, rotx(0.5)), flat(cream), "tail"))
    # antlers ---------------------------------------------------------------
    ant_col = lambda p, n: mix(np.array([0.55, 0.42, 0.30]), np.array([0.90, 0.85, 0.74]), ss(1.52, 1.78, p[:, 1]))
    for sx in (-1, 1):
        def A(x, y, f):
            return P(sx * x, y, f)
        beam = [A(.04, 1.42, .82), A(.08, 1.60, .78), A(.15, 1.78, .73), A(.26, 1.90, .77), A(.40, 1.98, .87)]
        parts.append(Part("horn_l" if sx < 0 else "horn_r", tube(beam, [.022, .02, .017, .014, .008], seg=8, sub=5, ref=(1, 0, 0)), ant_col, "beam"))
        for tine in ([A(.08, 1.60, .78), A(.10, 1.82, .84), A(.10, 1.95, .86)], [A(.15, 1.78, .73), A(.17, 2.0, .78), A(.16, 2.12, .80)],
                     [A(.26, 1.90, .77), A(.29, 2.08, .84)]):
            rr = [.014, .011, .005] if len(tine) == 3 else [.013, .005]
            parts.append(Part("horn_l" if sx < 0 else "horn_r", tube(tine, rr, seg=8, sub=4, ref=(1, 0, 0)), ant_col, "tine"))
    # legs ------------------------------------------------------------------
    legs(parts, front=dict(hip=(.33, .70), knee=(.35, .44), fet=(.36, .12), hoof=(.375, .0), thick=(.052, .036), cannon=(.036, .026), x=.095),
         hind=dict(hip=(-.34, .78), stifle=(-.25, .55), hock=(-.40, .37), fet=(-.40, .12), hoof=(-.39, .0), thick=(.095, .042), cannon=(.036, .026), x=.105),
         upper=lambda p, n: mix(mix(brown, cream, ss(0.62, 0.36, p[:, 1])), cream, ss(0.2, -0.8, n[:, 0] * np.sign(p[:, 0] + 1e-9))),
         lower=lambda p, n: mix(np.array([0.90, 0.83, 0.70]), np.array([0.62, 0.45, 0.30]), ss(0.4, 1.0, n[:, 2] * -1) * 0.25),
         hoof=dark, hoofsize=(.032, .036, .046), sock=None)
    bones = {"root": (None, (0, 0, 0)), "spine": ("root", (0, .80, .10)), "chest": ("spine", (0, .80, -.30)), "neck": ("chest", (0, .90, -.38)),
             "head": ("neck", (0, 1.38, -.76)), "tail": ("spine", (0, .95, .52)),
             "ear_l": ("head", (-.07, 1.44, -.76)), "ear_r": ("head", (.07, 1.44, -.76)), "horn_l": ("head", (-.04, 1.42, -.82)), "horn_r": ("head", (.04, 1.42, -.82))}
    leg_bones(bones, front=dict(hip=(.33, .70), knee=(.35, .44), fet=(.36, .12), x=.095), hind=dict(hip=(-.34, .78), knee=(-.40, .37), fet=(-.40, .12), x=.105))
    return parts, bones


def ibex():
    parts = []
    tan, belly = np.array([0.60, 0.40, 0.23]), np.array([0.88, 0.80, 0.66])
    dark, horn = np.array([0.13, 0.10, 0.08]), np.array([0.30, 0.22, 0.15])
    st = [(-0.50, 0.87, .06, .10), (-0.42, 0.85, .14, .19), (-0.24, 0.80, .17, .23), (0.0, 0.77, .175, .24), (0.25, 0.79, .175, .25),
          (0.42, 0.84, .15, .22), (0.54, 0.91, .10, .15)]
    m = tube([P(0, y, f) for f, y, w, h in st], [s[2] for s in st], [s[3] for s in st], seg=18, sub=6)

    def torso_col(p, n):
        f = -p[:, 2]
        c = mix(tan, belly, ss(0.0, -0.6, n[:, 1]))
        c = mix(c, np.array([0.80, 0.66, 0.46]), ss(0.15, 0.35, f) * ss(0.5, -0.3, np.abs(n[:, 0]) * -1 + 0.7) * 0.6)    # lighter shoulder
        return c * (1 - 0.30 * ss(0.6, 1.0, n[:, 1]))[:, None]                      # dark dorsal stripe
    parts.append(Part("spine", m, torso_col, "torso"))
    for sx in (-1, 1):
        parts.append(Part("spine", ell(P(sx * .11, .76, -.34), (.07, .19, .20), 2, rotx(-0.15)), lambda p, n: mix(tan, belly, ss(0.1, -0.7, n[:, 1]) * 0.8), "haunch"))
        parts.append(Part("spine", ell(P(sx * .125, .74, .31), (.07, .20, .15), 2, rotx(0.2)), lambda p, n: mix(np.array([0.78, 0.64, 0.45]), belly, ss(0.1, -0.7, n[:, 1]) * 0.8), "shoulder"))
    neck = tube([P(0, .92, .36), P(0, 1.08, .56), P(0, 1.22, .68), P(0, 1.30, .74)], [.125, .10, .08, .07], [.16, .125, .10, .09], seg=14, sub=6)
    parts.append(Part("neck", neck, lambda p, n: mix(mix(np.array([0.72, 0.55, 0.38]), belly, ss(0.2, -0.6, n[:, 1]) * 0.7), tan, ss(0.95, 0.8, p[:, 1]) * 0.7), "neck"))
    head = tube([P(0, 1.30, .72), P(0, 1.27, .83), P(0, 1.20, .94), P(0, 1.14, 1.04)], [.070, .066, .052, .040], [.088, .080, .060, .044], seg=14, sub=6)

    def head_col(p, n):
        f = -p[:, 2]
        c = mix(np.array([0.80, 0.68, 0.50]), tan, ss(0.4, 1.0, n[:, 1]) * 0.35)
        c = mix(c, np.array([0.88, 0.80, 0.66]), ss(0.92, 1.0, f) * 0.6)
        return mix(c, dark, ss(1.02, 1.05, f))
    parts.append(Part("head", head, head_col, "head"))
    for sx in (-1, 1):
        parts.append(Part("head", ell(P(sx * .056, 1.255, .85), (.022, .019, .028), 1), flat((0.90, 0.84, 0.70)), "eye_ring"))
        parts.append(Part("head", ell(P(sx * .060, 1.255, .865), (.014, .014, .017), 1), flat((0.05, 0.04, 0.04)), "eye"))
        parts.append(Part("ear_l" if sx < 0 else "ear_r", ell(P(sx * .12, 1.34, .66), (.012, .05, .035), 2, rotz(sx * 0.9) @ rotx(-0.2)), flat((0.66, 0.50, 0.34)), "ear"))
    parts.append(Part("head", ell(P(0, 1.14, 1.06), (.034, .024, .028), 1), flat(dark), "nose"))
    beard = tube([P(0, 1.10, .98), P(0, 1.02, .95), P(0, .93, .92)], [.016, .020, .008], [.016, .030, .008], seg=8, sub=4)
    parts.append(Part("head", beard, flat((0.20, 0.14, 0.10)), "beard"))
    parts.append(Part("tail", ell(P(0, .93, -.56), (.03, .075, .04), 1, rotx(0.35)), flat(tan * 0.9), "tail"))
    parts.append(Part("tail", ell(P(0, .87, -.60), (.028, .05, .036), 1, rotx(0.35)), flat(dark), "tail_tip"))
    for sx in (-1, 1):
        def A(x, y, f):
            return P(sx * x, y, f)
        hp = [A(.05, 1.37, .72), A(.07, 1.52, .66), A(.10, 1.68, .55), A(.12, 1.80, .38), A(.13, 1.86, .16), A(.13, 1.84, -.07), A(.12, 1.74, -.25), A(.11, 1.60, -.36)]
        parts.append(Part("horn_l" if sx < 0 else "horn_r", tube(hp, [.060, .056, .050, .042, .035, .028, .020, .010], seg=12, sub=7, ref=(1, 0, 0), ridge=(0.10, 11.0)),
                          lambda p, n: mix(horn, np.array([0.55, 0.45, 0.33]), ss(1.6, 1.38, p[:, 1]) * 0.5), "horn"))
    sock = lambda p, n: np.tile(np.array([0.9, 0.88, 0.82]), (len(p), 1))
    legs(parts, front=dict(hip=(.33, .70), knee=(.35, .43), fet=(.36, .12), hoof=(.375, .0), thick=(.062, .046), cannon=(.040, .030), x=.105),
         hind=dict(hip=(-.34, .78), stifle=(-.25, .55), hock=(-.40, .38), fet=(-.40, .12), hoof=(-.39, .0), thick=(.10, .048), cannon=(.038, .028), x=.11),
         upper=lambda p, n: mix(tan, belly, ss(0.2, -0.8, n[:, 0] * np.sign(p[:, 0] + 1e-9)) * 0.8),
         lower=lambda p, n: mix(mix(np.array([0.84, 0.78, 0.66]), np.array([0.18, 0.13, 0.10]), ss(-0.1, 0.8, n[:, 2] * -1 + 0.0)), np.array([0.90, 0.88, 0.82]), ss(0.20, 0.12, p[:, 1])),
         hoof=dark, hoofsize=(.036, .036, .05), sock=sock)
    bones = {"root": (None, (0, 0, 0)), "spine": ("root", (0, .80, .12)), "chest": ("spine", (0, .80, -.30)), "neck": ("chest", (0, .92, -.36)),
             "head": ("neck", (0, 1.30, -.72)), "tail": ("spine", (0, .93, .50)),
             "ear_l": ("head", (-.08, 1.34, -.70)), "ear_r": ("head", (.08, 1.34, -.70)), "horn_l": ("head", (-.045, 1.37, -.72)), "horn_r": ("head", (.045, 1.37, -.72))}
    leg_bones(bones, front=dict(hip=(.33, .70), knee=(.35, .43), fet=(.36, .12), x=.105), hind=dict(hip=(-.34, .78), knee=(-.40, .38), fet=(-.40, .12), x=.11))
    scale_all(parts, bones, 0.86)
    return parts, bones


def leg_bones(bones, front, hind):
    for lab, d in (("f", front), ("h", hind)):
        parent = "chest" if lab == "f" else "spine"
        for side in ("l", "r"):
            x = lr(side) * d["x"]
            bones[f"{lab}{side}_up"] = (parent, P(x, d["hip"][1], d["hip"][0]))
            bones[f"{lab}{side}_lo"] = (f"{lab}{side}_up", P(x, d["knee"][1], d["knee"][0]))
            bones[f"{lab}{side}_ft"] = (f"{lab}{side}_lo", P(x, d["fet"][1], d["fet"][0]))


def legs(parts, front, hind, upper, lower, hoof, hoofsize, sock):
    for lab, d in (("f", front), ("h", hind)):
        for side in ("l", "r"):
            x = lr(side) * d["x"]
            b = f"{lab}{side}"
            if lab == "f":
                up = [P(x, d["hip"][1] + .04, d["hip"][0] - .02), P(x, (d["hip"][1] + d["knee"][1]) / 2, (d["hip"][0] + d["knee"][0]) / 2), P(x, d["knee"][1], d["knee"][0])]
                ru = [d["thick"][0], (d["thick"][0] + d["thick"][1]) / 2, d["thick"][1]]
            else:
                up = [P(x * 1.1, d["hip"][1] + .02, d["hip"][0] + .02), P(x, d["stifle"][1], d["stifle"][0]), P(x * .9, d["hock"][1], d["hock"][0])]
                ru = [d["thick"][0], d["thick"][0] * .72, d["thick"][1]]
            parts.append(Part(b + "_up", tube(up, ru, [r * (1.15 if lab == "h" else 1.0) for r in ru], seg=10, sub=6, ref=(1, 0, 0)), upper, "leg_up"))
            k = d["knee"] if lab == "f" else d["hock"]
            lo = [P(x, k[1] + .02, k[0]), P(x, (k[1] + d["fet"][1]) / 2, (k[0] + d["fet"][0]) / 2), P(x, d["fet"][1], d["fet"][0])]
            parts.append(Part(b + "_lo", tube(lo, [d["cannon"][0], d["cannon"][1] * 0.9, d["cannon"][0] * 0.95], [d["cannon"][0] * 1.1, d["cannon"][1], d["cannon"][0]], seg=10, sub=5, ref=(1, 0, 0)), lower, "leg_lo"))
            parts.append(Part(b + "_lo", ell(P(x, k[1], k[0]), (d["cannon"][0] * 1.3, d["cannon"][0] * 1.3, d["cannon"][0] * 1.3), 1), lambda p, n, f=upper: f(p, n), "joint"))
            fet_col = lower
            parts.append(Part(b + "_ft", ell(P(x, d["fet"][1] - 0.005, d["fet"][0]), (d["cannon"][0] * 1.2, d["cannon"][0] * 1.4, d["cannon"][0] * 1.4), 1), fet_col, "fetlock"))
            hs = hoofsize
            pas = [P(x, d["fet"][1], d["fet"][0]), P(x, d["fet"][1] * 0.5, d["fet"][0] + .012), P(x, 0.03, d["fet"][0] + .02)]
            parts.append(Part(b + "_ft", tube(pas, [d["cannon"][0] * 1.1, d["cannon"][0] * 1.0, d["cannon"][0] * 1.1], seg=9, sub=3, ref=(1, 0, 0), caps=(False, False)), fet_col, "pastern"))
            parts.append(Part(b + "_ft", ell(P(x, 0.032, d["fet"][0] + .026), (hs[0], 0.034, hs[2]), 2), flat(hoof), "hoof"))


def scale_all(parts, bones, k):
    for p in parts:
        p.mesh = (p.mesh[0] * k, p.mesh[1], p.mesh[2])
    for n, (par, h) in list(bones.items()):
        bones[n] = (par, np.asarray(h, float) * k)
    # colour functions read heights in unscaled units: wrap them
    for p in parts:
        f = p.color
        p.color = (lambda pp, nn, f=f: f(pp / k, nn))


# ------------------------------------------------------------------ build
def shade(col, nrm, pts, rng):
    """Baked ambient occlusion + fur variation."""
    up = nrm[:, 1]
    k = 0.70 + 0.30 * np.clip(up * 0.5 + 0.5, 0, 1) ** 0.9
    k = k * (0.88 + 0.12 * np.clip(pts[:, 1] / 0.7, 0, 1))
    k = k * (1.0 + rng.normal(0, 0.03, len(col)))
    return np.clip(col * k[:, None], 0, 1)


def fmt(a, nd=4):
    return ", ".join(("%.*f" % (nd, x)).rstrip("0").rstrip(".") if abs(x) > 1e-9 else "0" for x in np.asarray(a).ravel())


def build(name, parts, bones):
    order = list(bones.keys())
    head = {k: np.asarray(v[1], float) for k, v in bones.items()}
    groups = {k: {"v": [], "n": [], "c": [], "i": [], "off": 0} for k in order}
    tot = 0
    zone_pts = {"head": [], "body": [], "legs": []}
    for part in parts:
        V, N, F = part.mesh
        N = norm(N)
        rng = np.random.default_rng(zlib.crc32((name + part.name).encode()) % 100000)
        col = shade(part.color(V, N), N, V, rng)
        # winding: Godot front faces are clockwise -> (b-a)x(c-a) must point against the outward normal
        tri = V[F]
        gn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        flip = (gn * N[F].sum(axis=1)).sum(axis=1) > 0
        F = np.where(flip[:, None], F[:, [0, 2, 1]], F)
        g = groups[part.bone]
        g["v"].append(V - head[part.bone])
        g["n"].append(N)
        g["c"].append(col)
        g["i"].append(F + g["off"])
        g["off"] += len(V)
        tot += len(F)
        b = part.bone
        key = "head" if b == "head" else ("legs" if len(b) > 2 and b[0] in "fh" and b[1] in "lr" and b[2] == "_" else ("body" if b in ("spine", "neck", "chest") else None))
        if key:
            zone_pts[key].append(V)
        part.final = (V, N, col, F)
    zones = {}
    for k, lst in zone_pts.items():
        allp = np.concatenate(lst)
        lo, hi = allp.min(0), allp.max(0)
        zones[k] = ((lo + hi) / 2, np.maximum(hi - lo, 0.08))
    lines = ["# GENERATED by tools/build_animals.py (procedural %s). Do not edit by hand." % name,
             "# %d triangles." % tot, "extends RefCounted", "", "static func data() -> Dictionary:", "\treturn {", '\t\t"bones": [']
    for k in order:
        par = bones[k][0]
        rel = head[k] - (head[par] if par else 0)
        lines.append('\t\t\t{"name": "%s", "parent": "%s", "pos": Vector3(%s)},' % (k, par or "", fmt(rel)))
    lines += ["\t\t],", '\t\t"meshes": {']
    for k in order:
        g = groups[k]
        if not g["v"]:
            continue
        lines.append('\t\t\t"%s": {' % k)
        lines.append('\t\t\t\t"v": PackedFloat32Array([%s]),' % fmt(np.concatenate(g["v"])))
        lines.append('\t\t\t\t"n": PackedFloat32Array([%s]),' % fmt(np.concatenate(g["n"]), 3))
        lines.append('\t\t\t\t"c": PackedFloat32Array([%s]),' % fmt(np.concatenate(g["c"]), 3))
        lines.append('\t\t\t\t"i": PackedInt32Array([%s]),' % ", ".join(str(int(x)) for x in np.concatenate(g["i"]).ravel()))
        lines.append("\t\t\t},")
    lines += ["\t\t},", '\t\t"zones": {']
    for k, (c, s) in zones.items():
        lines.append('\t\t\t"%s": {"pos": Vector3(%s), "size": Vector3(%s)},' % (k, fmt(c, 3), fmt(s, 3)))
    lines += ["\t\t},", "\t}"]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "%s_data.gd" % name)
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    allv = np.concatenate([p.final[0] for p in parts])
    print("%s: %d triangles, %d bones, %.0f KB; bounds min %s max %s" % (name, tot, len(order), os.path.getsize(path) / 1024, allv.min(0).round(2), allv.max(0).round(2)))


def preview(name, parts, view="side", yaw=0.0):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection
    polys, cols, depth = [], [], []
    ldir = norm(np.array([0.5, 0.8, -0.6]))
    for part in parts:
        V, N, C, F = part.final
        if yaw:
            R = roty(yaw)
            V, N = V @ R.T, N @ R.T
        for tri in F:
            a, b, c = V[tri]
            nn = N[tri].mean(0)
            if view == "side":
                if nn[0] < -0.2:
                    continue
                pts2 = [(-v[2], v[1]) for v in (a, b, c)]
                d = (a[0] + b[0] + c[0]) / 3
            else:
                if nn[2] > 0.2:
                    continue
                pts2 = [(v[0], v[1]) for v in (a, b, c)]
                d = -(a[2] + b[2] + c[2]) / 3
            lam = 0.55 + 0.45 * max(0.0, float(np.dot(norm(nn), ldir)))
            polys.append(pts2)
            cols.append(tuple(np.clip(C[tri].mean(0) * lam * 1.25, 0, 1)))
            depth.append(d)
    order = np.argsort(depth)
    fig, ax = plt.subplots(figsize=(8, 6), dpi=110)
    ax.set_facecolor("#33383c")
    ax.add_collection(PolyCollection([polys[i] for i in order], facecolors=[cols[i] for i in order], edgecolors="none"))
    ax.set_xlim(-1.4, 1.4)
    ax.set_ylim(-0.05, 2.1)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.patch.set_facecolor("#33383c")
    out = os.path.join(ROOT, "preview_%s_%s.png" % (name, view))
    fig.savefig(out, facecolor=fig.get_facecolor())
    plt.close(fig)
    print("preview ->", out)


if __name__ == "__main__":
    for nm, fn in (("deer", deer), ("ibex", ibex)):
        prts, bns = fn()
        build(nm, prts, bns)
        if "--preview" in sys.argv:
            preview(nm, prts, "side")
            preview(nm, prts, "front")
            preview(nm + "3q", prts, "side", 0.7)
