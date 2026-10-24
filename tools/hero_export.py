#!/usr/bin/env python3
"""Builds assets/hero/hero.glb: skinned explorer (16 bones named like scripts/character.gd joints), PBR materials,
embedded 256px textures. Run: python3 tools/hero_export.py  (needs numpy + Pillow)."""
import io, json, math, os, struct, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import hero_model as H
import gen_textures as T

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "hero", "hero.glb")
TEX = os.path.join(ROOT, "assets", "textures")

def png_bytes(arr_or_img):
    im = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(arr_or_img)
    b = io.BytesIO(); im.save(b, "PNG", optimize=True); return b.getvalue()

def emblem_png():
    """Original compass emblem: copper 8-point star inside a ring on a dark disc (no real-world logo)."""
    from PIL import ImageDraw
    S = 256; Z = 4; im = Image.new("RGBA", (S * Z, S * Z), (0, 0, 0, 0)); d = ImageDraw.Draw(im); c = S * Z // 2
    cu = (200, 108, 44, 255); dk = (34, 28, 22, 255); lt = (226, 160, 92, 255)
    d.ellipse([c - c, c - c, c + c - 1, c + c - 1], fill=dk)
    d.ellipse([c - int(c * .94), c - int(c * .94), c + int(c * .94), c + int(c * .94)], outline=cu, width=int(S * Z * .035))
    for k in range(32):                       # ring ticks
        a = 2 * math.pi * k / 32; r0, r1 = c * (.80 if k % 4 else .74), c * .86
        d.line([(c + r0 * math.cos(a), c + r0 * math.sin(a)), (c + r1 * math.cos(a), c + r1 * math.sin(a))], fill=cu, width=int(S * Z * .012))
    def diamond(a, L, W, col):
        ca, sa = math.cos(a), math.sin(a)
        pts = [(c + L * ca, c + L * sa), (c - W * sa, c + W * ca), (c - L * .22 * ca, c - L * .22 * sa), (c + W * sa, c - W * ca)]
        d.polygon(pts, fill=col)
    for k in range(4): diamond(k * math.pi / 2 - math.pi / 2, c * .70, c * .13, cu)        # N E S W points
    for k in range(4): diamond(math.pi / 4 + k * math.pi / 2, c * .42, c * .085, lt)       # diagonals
    d.ellipse([c - c * .11, c - c * .11, c + c * .11, c + c * .11], fill=dk, outline=cu, width=int(S * Z * .012))
    d.ellipse([c - c * .04, c - c * .04, c + c * .04, c + c * .04], fill=lt)
    return png_bytes(im.resize((S, S), Image.LANCZOS))

def make_textures():
    """name -> (albedo PNG bytes, normal PNG bytes or None, mean brightness)."""
    tex = {}
    for nm in ("fabric", "leather"):
        a = Image.open(os.path.join(TEX, nm + "_a.png")).convert("RGB").resize((256, 256), Image.LANCZOS)
        n = Image.open(os.path.join(TEX, nm + "_n.png")).convert("RGB").resize((256, 256), Image.LANCZOS)
        tex[nm] = (png_bytes(a), png_bytes(n), float(np.asarray(a).mean() / 255) ** 2.2)
    # skin: near-white pore/blotch detail (tint comes from the material factor)
    N = 256; f = T.fbm(N, 1.2, 71); g = T.fbm(N, 0.5, 72)
    h = 0.93 + 0.05 * (f - .5) + 0.04 * (g - .5)
    skin_a = np.stack([h * 255, (h - .015 * (g - .5)) * 255, (h - .03 * (g - .5)) * 255], -1)
    dx = np.roll(g, -1, 1) - np.roll(g, 1, 1); dy = np.roll(g, -1, 0) - np.roll(g, 1, 0)
    nx, ny = -dx * 3.0, dy * 3.0; l = np.sqrt(nx ** 2 + ny ** 2 + 1)
    skin_n = (np.stack([nx / l, ny / l, 1 / l], -1) * .5 + .5) * 255
    tex["skin"] = (png_bytes(skin_a.clip(0, 255).astype(np.uint8)), png_bytes(skin_n.astype(np.uint8)), float((.93) ** 2.2))
    # hair: dark strands
    s = T.fbm(N, 1.0, 73, stretch=(1, 7)); s2 = T.fbm(N, 0.6, 74, stretch=(1, 14))
    hv = 0.55 + .35 * (s - .5) + .25 * (s2 - .5)
    tex["hair"] = (png_bytes(np.stack([hv * 255] * 3, -1).clip(0, 255).astype(np.uint8)), None, float(.55 ** 2.2))
    tex["emblem"] = (emblem_png(), None, 1.0)
    return tex

# material -> (texture key or None, linear base colour, roughness, metallic)
MATS = {
    "skin": ("skin", (.82, .60, .46), .55, 0.0), "shirt": ("fabric", (.26, .36, .20), .92, 0.0),
    "pants": ("fabric", (.36, .30, .23), .92, 0.0), "leather": ("leather", (.42, .26, .13), .6, 0.0),
    "leather_dark": (None, (.11, .10, .09), .75, 0.0), "rubber": (None, (.06, .055, .05), .95, 0.0),
    "pack": ("fabric", (.38, .32, .19), .93, 0.0), "bedroll": ("fabric", (.46, .40, .30), .95, 0.0),
    "hair": ("hair", (.50, .35, .24), .55, 0.0), "beard": ("hair", (.46, .32, .22), .6, 0.0),
    "eye": (None, (.95, .95, .95), .10, 0.0), "metal": (None, (.62, .63, .66), .38, 0.85),
    "emblem": ("emblem", (1, 1, 1), .5, 0.35), "copper": ("fabric", (.70, .34, .12), .9, 0.0),
    "thread": (None, (.60, .48, .27), .9, 0.0), "midsole": (None, (.50, .45, .37), .85, 0.0),
}
BLEND = {"beard"}

def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)

def build():
    parts = H.assemble()
    tex = make_textures()
    buf = bytearray(); views = []; accs = []
    def view(data, target=None):
        off = len(buf); buf.extend(pad4(bytes(data))); v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target: v["target"] = target
        views.append(v); return len(views) - 1
    def acc(vi, ctype, count, atype, mn=None, mx=None, normalized=False):
        a = {"bufferView": vi, "componentType": ctype, "count": int(count), "type": atype}
        if mn is not None: a["min"] = [float(x) for x in mn]; a["max"] = [float(x) for x in mx]
        if normalized: a["normalized"] = True
        accs.append(a); return len(accs) - 1
    materials = []; images = []; textures = []; tex_index = {}
    def tex_idx(key, normal):
        k = (key, normal)
        if k in tex_index: return tex_index[k]
        data = tex[key][1 if normal else 0]
        images.append({"bufferView": view(data), "mimeType": "image/png", "name": key + ("_n" if normal else "_a")})
        textures.append({"source": len(images) - 1, "sampler": 0}); tex_index[k] = len(textures) - 1; return tex_index[k]
    mats_done = {}
    def material_index(m):
        if m in mats_done: return mats_done[m]
        key, col, rough, metal = MATS[m]
        pbr = {"baseColorFactor": [*[min(1.0, c / tex[key][2]) if key else c for c in col], 1.0], "roughnessFactor": rough, "metallicFactor": metal}
        mat = {"name": m, "pbrMetallicRoughness": pbr}
        if m in BLEND: mat["alphaMode"] = "BLEND"
        if key:
            pbr["baseColorTexture"] = {"index": tex_idx(key, False)}
            if tex[key][1] is not None: mat["normalTexture"] = {"index": tex_idx(key, True), "scale": 0.8}
        materials.append(mat); mats_done[m] = len(materials) - 1; return mats_done[m]
    meshes = []
    for g in ("base", "detail", "head"):
        gparts = [p for p in parts if p["group"] == g]
        has_morph = any(p["D"] for p in gparts); prims = []
        order = []
        for p in gparts:
            if p["mat"] not in order: order.append(p["mat"])
        for m in order:
            group = [p for p in gparts if p["mat"] == m]
            P = np.concatenate([q["P"] for q in group]); N = np.concatenate([q["N"] for q in group])
            UV = np.concatenate([q["UV"] for q in group]); C = np.concatenate([q["C"] for q in group]); W = np.concatenate([q["W"] for q in group])
            off = 0; I = []
            for q in group:
                I.append(q["I"] + off); off += len(q["P"])
            I = np.concatenate(I).astype(np.uint16 if off < 65000 else np.uint32)
            top = np.argsort(-W, axis=1)[:, :4]; w4 = np.take_along_axis(W, top, 1); w4 = w4 / np.maximum(w4.sum(1, keepdims=True), 1e-9)
            a = {}
            a["POSITION"] = acc(view(P.astype("<f4").tobytes(), 34962), 5126, len(P), "VEC3", P.min(0), P.max(0))
            a["NORMAL"] = acc(view(N.astype("<f4").tobytes(), 34962), 5126, len(N), "VEC3")
            a["TEXCOORD_0"] = acc(view(UV.astype("<f4").tobytes(), 34962), 5126, len(UV), "VEC2")
            a["COLOR_0"] = acc(view((np.clip(C, 0, 1) * 255).round().astype(np.uint8).tobytes(), 34962), 5121, len(C), "VEC4", normalized=True)
            a["JOINTS_0"] = acc(view(top.astype(np.uint8).tobytes(), 34962), 5121, len(top), "VEC4")
            a["WEIGHTS_0"] = acc(view(w4.astype("<f4").tobytes(), 34962), 5126, len(w4), "VEC4")
            ci = acc(view(I.tobytes(), 34963), 5123 if I.dtype == np.uint16 else 5125, I.size, "SCALAR")
            prim = {"attributes": a, "indices": ci, "material": material_index(m), "mode": 4}
            if has_morph:
                tgs = []
                for tname in H.TARGETS:
                    dl = np.concatenate([(q["D"][tname] if q["D"] else np.zeros((len(q["P"]), 3))) for q in group]).astype("<f4")
                    tgs.append({"POSITION": acc(view(dl.tobytes(), 34962), 5126, len(dl), "VEC3", dl.min(0), dl.max(0))})
                prim["targets"] = tgs
            prims.append(prim)
        mesh = {"name": {"base": "Hero", "detail": "HeroDetail", "head": "Head"}[g], "primitives": prims}
        if has_morph: mesh["extras"] = {"targetNames": H.TARGETS}; mesh["weights"] = [0.0] * len(H.TARGETS)
        meshes.append(mesh)
    # skeleton
    nodes = [{"name": "Hero", "mesh": 0, "skin": 0}, {"name": "HeroDetail", "mesh": 1, "skin": 0}, {"name": "Head", "mesh": 2, "skin": 0}]
    NOFF = len(nodes)
    for b in H.BONES:
        par = H.PARENT[b]; gp = np.array(H.POS[b]); pp = np.array(H.POS[par]) if par else np.zeros(3)
        nodes.append({"name": b, "translation": [float(x) for x in (gp - pp)]})
    for b in H.BONES:
        par = H.PARENT[b]
        if par: nodes[NOFF + H.BI[par]].setdefault("children", []).append(NOFF + H.BI[b])
    ibm = bytearray()
    for b in H.BONES:
        x, y, z = H.POS[b]
        ibm += struct.pack("<16f", 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1)
    ibm_acc = acc(view(bytes(ibm)), 5126, len(H.BONES), "MAT4")
    gltf = {"asset": {"version": "2.0", "generator": "WILD ORIGIN tools/hero_export.py"},
            "scene": 0, "scenes": [{"nodes": [0, 1, 2, NOFF]}], "nodes": nodes,
            "meshes": meshes,
            "skins": [{"name": "HeroSkin", "joints": [NOFF + i for i in range(len(H.BONES))], "inverseBindMatrices": ibm_acc, "skeleton": NOFF}],
            "materials": materials, "textures": textures, "images": images,
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
            "buffers": [{"byteLength": len(buf)}], "bufferViews": views, "accessors": accs}
    js = pad4(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    bn = pad4(bytes(buf))
    total = 12 + 8 + len(js) + 8 + len(bn)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(bn), 0x004E4942)); f.write(bn)
    return parts, total

if __name__ == "__main__":
    parts, total = build()
    print("wrote", os.path.abspath(OUT), total // 1024, "KB;", sum(len(p["P"]) for p in parts), "verts,", sum(len(p["I"]) for p in parts), "tris")
