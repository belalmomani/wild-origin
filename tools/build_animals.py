#!/usr/bin/env python3
"""Convert the supplied animal GLBs (forest deer, Nubian ibex) into light, game-ready rigid-rig data for Godot.

    python3 tools/build_animals.py        # needs numpy; reads tools/animals_src/*.glb

The source models are static, material-less, Z-up meshes made of ~640-vertex ellipsoids (1280 triangles each):
34k / 55k triangles per animal is far too heavy for a phone. Every ellipsoid is detected (exact fit), regenerated
as a 20 / 80 / 320-triangle icosphere, and the parts are merged per bone. Output: assets/animals/<name>_data.gd
(positions relative to each bone pivot, in game axes: Y up, forward = -Z, X = right, metres, scaled).

Bone layout follows tools/blender/rig_deer.py and build_nubian_ibex_rig.py. A few joint pivots are corrected where the
Blender scripts put them in the middle of a leg segment.
"""
import json, os, struct, sys, zlib
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "animals_src")
OUT = os.path.join(ROOT, "..", "assets", "animals")
SCALE = 0.5


# ------------------------------------------------------------------ GLB reading
def load_glb(path):
    b = open(path, "rb").read()
    off = 12
    js = bn = None
    while off < len(b):
        l, t = struct.unpack("<I4s", b[off:off + 8])
        d = b[off + 8:off + 8 + l]
        off += 8 + l
        if t == b"JSON":
            js = json.loads(d)
        elif t.startswith(b"BIN"):
            bn = d
    return js, bn


def accessor(js, bn, ai):
    a = js["accessors"][ai]
    v = js["bufferViews"][a["bufferView"]]
    nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dt = {5126: "<f4", 5123: "<u2", 5125: "<u4", 5121: "u1"}[a["componentType"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(bn, dtype=dt, count=a["count"] * nc, offset=off)
    arr = arr.reshape(a["count"], nc) if nc > 1 else arr
    return arr, a


def read_parts(path):
    js, bn = load_glb(path)
    parts = []
    for n in js["nodes"]:
        if "mesh" not in n:
            continue
        pr = js["meshes"][n["mesh"]]["primitives"][0]
        P, _ = accessor(js, bn, pr["attributes"]["POSITION"])
        C, ca = accessor(js, bn, pr["attributes"]["COLOR_0"])
        I, _ = accessor(js, bn, pr["indices"])
        C = C.astype(np.float64)
        if ca["componentType"] == 5121:
            C = C / 255.0
        elif ca["componentType"] == 5123:
            C = C / 65535.0
        parts.append({"name": n["name"], "P": P.astype(np.float64), "C": C[:, :3], "I": I.reshape(-1, 3).astype(np.int64)})
    return parts


# ------------------------------------------------------------------ geometry helpers
def icosphere(level):
    t = (1.0 + 5 ** 0.5) / 2.0
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    v = [np.array(p, float) / np.linalg.norm(p) for p in v]
    for _ in range(level):
        cache = {}
        nf = []

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


def fit_ellipsoid(P):
    """Return (residual, rotation R, half extents, centre) for the best of axis-aligned / PCA axes."""
    c = (P.max(0) + P.min(0)) / 2
    Q = P - c
    _, V = np.linalg.eigh(np.cov(Q.T))
    best = None
    for R in (np.eye(3), V):
        L = Q @ R
        ext = (L.max(0) - L.min(0)) / 2
        c2 = (L.max(0) + L.min(0)) / 2
        U = (L - c2) / ext
        res = np.abs(np.linalg.norm(U, axis=1) - 1).max()
        if best is None or res < best[0]:
            best = (res, R, ext, c2 @ R.T + c)
    return best


def regen_ellipsoid(P):
    res, R, ext, c = fit_ellipsoid(P)
    if res > 0.02:
        return None
    m = float(ext.max())
    level = 3 if m > 0.45 else (2 if m > 0.22 else (1 if m > 0.05 else 0))
    U, F = icosphere(level)
    pts = c + (U * ext) @ R.T
    nrm = (U / ext) @ R.T
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    return pts, nrm, F


def flat_expand(P, I):
    """Flat-shaded copy (own vertices per triangle). Normal from the source (counter-clockwise) winding."""
    tri = P[I]                                   # (n,3,3)
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    n = n / np.where(ln == 0, 1, ln)
    pts = tri.reshape(-1, 3)
    nrm = np.repeat(n, 3, axis=0)
    F = np.arange(len(pts)).reshape(-1, 3)
    return pts, nrm, F


def part_mesh(part):
    r = regen_ellipsoid(part["P"]) if len(part["P"]) == 642 else None
    if r is None:
        r = flat_expand(part["P"], part["I"])
    pts, nrm, F = r
    col = np.tile(part["C"][0], (len(pts), 1))
    return pts, nrm, col, F


def shade(col, nrm_game, pts_game, seed):
    """Bake soft lighting into vertex colours so the models read as volumes: darker undersides / inner legs,
    lighter backs, plus a little per-vertex fur variation."""
    rng = np.random.default_rng(seed)
    up = nrm_game[:, 1]
    k = 0.66 + 0.34 * np.clip(up * 0.5 + 0.5, 0, 1) ** 0.8
    k = k * (1.0 + rng.normal(0, 0.035, len(col)))
    # lower parts of the body (close to the ground) sit in shadow
    k = k * (0.86 + 0.14 * np.clip(pts_game[:, 1] / 0.8, 0, 1))
    return np.clip(col * k[:, None], 0, 1)


# ------------------------------------------------------------------ animal definitions (model axes)
# Each animal: axis conversion model->game, bones {name: (parent, head)}, part->bone rule, hit zones by bone groups.
def conv_deer(v):        # model: +X forward, +Y left, +Z up   ->  game: forward -Z, left -X, up +Y
    v = np.asarray(v, float)
    return np.stack([-v[..., 1], v[..., 2], -v[..., 0]], axis=-1)


def conv_ibex(v):        # model: +Y forward, +X right, +Z up  ->  game: forward -Z, right +X, up +Y
    v = np.asarray(v, float)
    return np.stack([v[..., 0], v[..., 2], -v[..., 1]], axis=-1)


def deer_bones():
    b = {"root": (None, (0, 0, 0)), "spine": ("root", (-0.48, 0, 1.45)), "chest": ("spine", (0.18, 0, 1.60)),
         "neck": ("chest", (0.50, 0, 1.72)), "head": ("neck", (0.70, 0, 2.15)), "tail": ("spine", (-0.72, 0, 1.65)),
         "ear_l": ("head", (0.72, 0.08, 2.48)), "ear_r": ("head", (0.72, -0.08, 2.48)),
         "horn_l": ("head", (0.72, 0.10, 2.62)), "horn_r": ("head", (0.72, -0.10, 2.62))}
    for lab, parent, x, hip_x in [("f", "chest", 0.48, 0.48), ("h", "spine", -0.51, -0.51)]:
        for side, y in [("l", 0.22 if lab == "f" else 0.23), ("r", -0.22 if lab == "f" else -0.23)]:
            b[f"{lab}{side}_up"] = (parent, (x, y, 1.25))
            b[f"{lab}{side}_lo"] = (f"{lab}{side}_up", (x, y, 0.48))
            b[f"{lab}{side}_ft"] = (f"{lab}{side}_lo", (x + 0.02, y, 0.20))
    return b


def deer_bone_of(name, c):
    n = name.lower()
    for lab, key in [("f", "front"), ("h", "hind")]:
        for side, near in [("l", "far"), ("r", "near")]:
            if f"{key}_{near}" in n:
                if "hoof" in n:
                    return f"{lab}{side}_ft"
                if "lower" in n:
                    return f"{lab}{side}_lo"
                return f"{lab}{side}_up"       # upper + the knee bulge (it sits in the middle of the upper segment)
    if n.startswith("ear"):
        return "ear_l" if c[1] >= 0 else "ear_r"
    if n.startswith("antler"):
        return "horn_l" if c[1] >= 0 else "horn_r"
    if n.startswith("tail"):
        return "tail"
    if any(k in n for k in ("head", "muzzle", "nose", "eye")):
        return "head"
    if "neck" in n or "throat" in n:
        return "neck"
    if "chest" in n:
        return "chest"
    return "spine"


def ibex_bones():
    b = {"root": (None, (0, 0, 0)), "pelvis": ("root", (0, -0.48, 1.42)), "spine": ("pelvis", (0, -0.10, 1.48)),
         "chest": ("spine", (0, 0.42, 1.55)), "neck": ("chest", (0, 0.72, 1.72)), "head": ("neck", (0, 0.94, 2.02)),
         "tail": ("pelvis", (0, -0.48, 1.52))}
    for s, side in [(-1, "l"), (1, "r")]:
        b[f"ear_{side}"] = ("head", (s * 0.18, 0.82, 2.22))
        b[f"horn_{side}"] = ("head", (s * 0.16, 0.83, 2.29))
        for lab, y, parent in [("f", 0.53, "chest"), ("h", -0.57, "pelvis")]:
            b[f"{lab}{side}_up"] = (parent, (s * 0.27, y, 1.40))
            b[f"{lab}{side}_lo"] = (f"{lab}{side}_up", (s * 0.28, y + 0.02, 0.84 if lab == "f" else 0.87))
    return b


def ibex_bone_of(name, c):
    n = name.lower()
    if "horn" in n:
        return "horn_l" if n.endswith("_l") or "_l" in n.split("horn")[-1] else "horn_r"
    if n.startswith("ear"):
        return "ear_l" if n.endswith("_l") else "ear_r"
    if n.startswith("tail"):
        return "tail"
    for lab in ("f", "h"):
        for side in ("l", "r"):
            if n.endswith(f"_{lab}{side}"):
                return f"{lab}{side}_up" if n.startswith("legupper") else f"{lab}{side}_lo"   # knee, lower, hoof, toes
    if any(k in n for k in ("head", "muzzle", "nose", "eye", "beard")):
        return "head"
    if n == "neck":
        return "neck"
    if n == "chest":
        return "chest"
    if n.startswith("rump") or n.startswith("dorsal") or n.startswith("flank"):
        return "pelvis" if n.startswith("rump") else "spine"
    return "spine"


ANIMALS = {
    "deer": {"src": "stylized_forest_deer.glb", "conv": conv_deer, "bones": deer_bones, "bone_of": deer_bone_of},
    "ibex": {"src": "nubian_ibex_game_character.glb", "conv": conv_ibex, "bones": ibex_bones, "bone_of": ibex_bone_of},
}


# ------------------------------------------------------------------ build
def fmt(a, nd=4):
    return ", ".join(("%.*f" % (nd, x)).rstrip("0").rstrip(".") if abs(x) > 1e-9 else "0" for x in np.asarray(a).ravel())


def build(name, cfg):
    parts = read_parts(os.path.join(SRC, cfg["src"]))
    conv = cfg["conv"]
    bones_m = cfg["bones"]()
    head_g = {k: conv(v[1]) * SCALE for k, v in bones_m.items()}
    order = list(bones_m.keys())
    groups = {k: {"v": [], "n": [], "c": [], "i": [], "off": 0} for k in order}
    tot_tris = 0
    cross = {}
    zone_pts = {"head": [], "body": [], "legs": []}
    for part in parts:
        centre = (part["P"].max(0) + part["P"].min(0)) / 2
        bone = cfg["bone_of"](part["name"], centre)
        pts, nrm, col, F = part_mesh(part)
        g_pts = conv(pts) * SCALE
        g_nrm = conv(nrm)
        # winding: Godot front faces are clockwise -> (b-a)x(c-a) must point against the outward normal
        tri = g_pts[F]
        gn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        avg = g_nrm[F].sum(axis=1)
        flip = (gn * avg).sum(axis=1) > 0
        F = np.where(flip[:, None], F[:, [0, 2, 1]], F)
        col = shade(col, g_nrm, g_pts, zlib.crc32(part["name"].encode()) % 100000)
        ext = np.sort((part["P"].max(0) - part["P"].min(0)) / 2.0)
        cross.setdefault(bone, []).append((float(ext[1]) * SCALE, part["C"][0]))
        grp = groups[bone]
        grp["v"].append(g_pts - head_g[bone])
        grp["n"].append(g_nrm)
        grp["c"].append(col)
        grp["i"].append(F + grp["off"])
        grp["off"] += len(g_pts)
        tot_tris += len(F)
        zk = "head" if bone in ("head",) else ("legs" if bone[1:3] in ("l_", "r_") and bone[0] in "fh" else ("body" if bone in ("spine", "chest", "neck", "pelvis") else None))
        if zk:
            zone_pts[zk].append(g_pts)
    # joint balls: the ellipsoid segments only touch in points, so a swinging leg would open gaps. A ball centred on
    # every leg pivot (child bone) keeps hip / knee / ankle visibly connected.
    U1, F1 = icosphere(1)
    for bone, (par, _h) in bones_m.items():
        if len(bone) < 5 or bone[0] not in "fh" or bone[1] not in "lr" or bone[2] != "_":
            continue
        mine = max(cross.get(bone, [(0.03, np.array([0.5, 0.4, 0.3]))]), key=lambda t: t[0])
        r = mine[0]
        if bone.endswith("_lo") or bone.endswith("_ft"):
            theirs = cross.get(par, [])
            if theirs:
                r = (r + max(theirs, key=lambda t: t[0])[0]) * 0.5
        r = max(r * 1.08, 0.025)
        nrm = U1
        col = shade(np.tile(mine[1], (len(U1), 1)), nrm, U1 * r + head_g[bone], 7)
        g = groups[bone]
        tri = (U1 * r)[F1]              # Godot wants clockwise-from-outside: flip faces whose normal points outward
        gn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        flip = (gn * U1[F1].sum(axis=1)).sum(axis=1) > 0
        F = np.where(flip[:, None], F1[:, [0, 2, 1]], F1)
        g["v"].append(U1 * r)
        g["n"].append(nrm)
        g["c"].append(col)
        g["i"].append(F + g["off"])
        g["off"] += len(U1)
        tot_tris += len(F1)
    zones = {}
    for k, lst in zone_pts.items():
        allp = np.concatenate(lst)
        lo, hi = allp.min(0), allp.max(0)
        zones[k] = ((lo + hi) / 2, (hi - lo))
    lines = ["# GENERATED by tools/build_animals.py from the supplied %s model. Do not edit by hand." % cfg["src"],
             "# %d triangles (source model had ~%d)." % (tot_tris, sum(len(p['I']) for p in parts)),
             "extends RefCounted", "", "static func data() -> Dictionary:", "\treturn {"]
    lines.append('\t\t"bones": [')
    for k in order:
        par = bones_m[k][0]
        rel = head_g[k] - (head_g[par] if par else 0)
        lines.append('\t\t\t{"name": "%s", "parent": "%s", "pos": Vector3(%s)},' % (k, par or "", fmt(rel)))
    lines.append("\t\t],")
    lines.append('\t\t"meshes": {')
    for k in order:
        g = groups[k]
        if not g["v"]:
            continue
        v = np.concatenate(g["v"])
        n = np.concatenate(g["n"])
        c = np.concatenate(g["c"])
        i = np.concatenate(g["i"]).ravel()
        lines.append('\t\t\t"%s": {' % k)
        lines.append('\t\t\t\t"v": PackedFloat32Array([%s]),' % fmt(v))
        lines.append('\t\t\t\t"n": PackedFloat32Array([%s]),' % fmt(n, 3))
        lines.append('\t\t\t\t"c": PackedFloat32Array([%s]),' % fmt(c, 3))
        lines.append('\t\t\t\t"i": PackedInt32Array([%s]),' % ", ".join(str(int(x)) for x in i))
        lines.append("\t\t\t},")
    lines.append("\t\t},")
    lines.append('\t\t"zones": {')
    for k, (c, s) in zones.items():
        lines.append('\t\t\t"%s": {"pos": Vector3(%s), "size": Vector3(%s)},' % (k, fmt(c, 3), fmt(np.maximum(s, 0.08), 3)))
    lines.append("\t\t},")
    lines.append("\t}")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "%s_data.gd" % name)
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("%s: %d triangles (from %d), %d bones, %.0f KB -> %s" % (name, tot_tris, sum(len(p['I']) for p in parts), len(order), os.path.getsize(path) / 1024, os.path.relpath(path)))
    mins = np.min([np.concatenate(g["v"]).min(0) + head_g[k] for k, g in groups.items() if g["v"]], axis=0)
    maxs = np.max([np.concatenate(g["v"]).max(0) + head_g[k] for k, g in groups.items() if g["v"]], axis=0)
    print("   game-space bounds min", mins.round(2), "max", maxs.round(2))


if __name__ == "__main__":
    for nm, cf in ANIMALS.items():
        build(nm, cf)
