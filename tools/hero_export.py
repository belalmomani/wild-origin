#!/usr/bin/env python3
"""Builds assets/hero/hero.glb: skinned explorer (16 bones named like scripts/character.gd joints), PBR materials,
embedded 256px textures. Run: python3 tools/hero_export.py  (needs numpy + Pillow)."""
import io, json, os, struct, sys
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
    return tex

# material -> (texture key or None, linear base colour, roughness, metallic)
MATS = {
    "skin": ("skin", (.82, .60, .46), .55, 0.0), "shirt": ("fabric", (.34, .42, .26), .9, 0.0),
    "pants": ("fabric", (.30, .24, .17), .9, 0.0), "leather": ("leather", (.42, .26, .13), .65, 0.0),
    "leather_dark": (None, (.10, .09, .08), .7, 0.0), "rubber": (None, (.07, .06, .05), .9, 0.0),
    "pack": ("fabric", (.42, .37, .24), .92, 0.0), "scarf": ("fabric", (.66, .52, .36), .92, 0.0),
    "bedroll": ("fabric", (.45, .40, .30), .95, 0.0), "hair": ("hair", (.50, .35, .24), .55, 0.0),
    "eye": (None, (.95, .95, .95), .12, 0.0), "metal": (None, (.65, .66, .70), .35, 0.9),
}

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
    prims = []; mat_index = {}; materials = []; images = []; textures = []; tex_index = {}
    def tex_idx(key, normal):
        k = (key, normal)
        if k in tex_index: return tex_index[k]
        data = tex[key][1 if normal else 0]
        images.append({"bufferView": view(data), "mimeType": "image/png", "name": key + ("_n" if normal else "_a")})
        textures.append({"source": len(images) - 1, "sampler": 0}); tex_index[k] = len(textures) - 1; return tex_index[k]
    order = []
    for p in parts:
        if p["mat"] not in order: order.append(p["mat"])
    for m in order:
        group = [p for p in parts if p["mat"] == m]
        P = np.concatenate([g["P"] for g in group]); N = np.concatenate([g["N"] for g in group])
        UV = np.concatenate([g["UV"] for g in group]); C = np.concatenate([g["C"] for g in group]); W = np.concatenate([g["W"] for g in group])
        off = 0; I = []
        for g in group:
            I.append(g["I"] + off); off += len(g["P"])
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
        key, col, rough, metal = MATS[m]
        pbr = {"baseColorFactor": [*[min(1.0, c / tex[key][2]) if key else c for c in col], 1.0], "roughnessFactor": rough, "metallicFactor": metal}
        mat = {"name": m, "pbrMetallicRoughness": pbr}
        if key:
            pbr["baseColorTexture"] = {"index": tex_idx(key, False)}
            if tex[key][1] is not None:
                mat["normalTexture"] = {"index": tex_idx(key, True), "scale": 0.8}
        materials.append(mat)
        prims.append({"attributes": a, "indices": ci, "material": len(materials) - 1, "mode": 4})
    # skeleton
    nodes = [{"name": "Hero", "mesh": 0, "skin": 0}]
    for b in H.BONES:
        par = H.PARENT[b]; gp = np.array(H.POS[b]); pp = np.array(H.POS[par]) if par else np.zeros(3)
        nodes.append({"name": b, "translation": [float(x) for x in (gp - pp)]})
    for b in H.BONES:
        par = H.PARENT[b]
        if par: nodes[1 + H.BI[par]].setdefault("children", []).append(1 + H.BI[b])
    ibm = bytearray()
    for b in H.BONES:
        x, y, z = H.POS[b]
        ibm += struct.pack("<16f", 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1)
    ibm_acc = acc(view(bytes(ibm)), 5126, len(H.BONES), "MAT4")
    gltf = {"asset": {"version": "2.0", "generator": "WILD ORIGIN tools/hero_export.py"},
            "scene": 0, "scenes": [{"nodes": [0, 1]}], "nodes": nodes,
            "meshes": [{"name": "Hero", "primitives": prims}],
            "skins": [{"name": "HeroSkin", "joints": [1 + i for i in range(len(H.BONES))], "inverseBindMatrices": ibm_acc, "skeleton": 1}],
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
