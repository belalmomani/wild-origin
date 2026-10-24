"""Reads assets/hero/hero.glb back, validates it and renders LBS-posed previews (checks the skin weights)."""
import sys, math, struct, json
sys.path.insert(0, "/tmp"); sys.path.insert(0, "tools")
import numpy as np
from glbtools import load, acc
import hero_model as H
import hero_preview as PV
from PIL import Image

j, bn = load("assets/hero/hero.glb")
assert j["asset"]["version"] == "2.0"
prims = [(mi, pr) for mi, m in enumerate(j["meshes"]) for pr in m["primitives"]]
sk = j["skins"][0]; names = [j["nodes"][i]["name"] for i in sk["joints"]]
print("bones:", names == H.BONES, len(names), "| meshes:", [m["name"] for m in j["meshes"]], "| materials:", len(j["materials"]))
print("images:", len(j["images"]), "| accessors:", len(j["accessors"]), "| buffer KB:", j["buffers"][0]["byteLength"] // 1024)
ibm = acc(j, bn, sk["inverseBindMatrices"])
print("ibm shape", ibm.shape)
parts = []; bad = 0
for mesh_i, p in prims:
    a = p["attributes"]
    P = acc(j, bn, a["POSITION"]).astype(float); N = acc(j, bn, a["NORMAL"]).astype(float)
    C = acc(j, bn, a["COLOR_0"]).astype(float) / 255.0; J = acc(j, bn, a["JOINTS_0"]).astype(int); W = acc(j, bn, a["WEIGHTS_0"]).astype(float)
    I = acc(j, bn, p["indices"]).reshape(-1, 3).astype(int)
    if abs(W.sum(1) - 1).max() > 1e-3 or I.max() >= len(P) or not np.isfinite(P).all(): bad += 1
    mname = j["materials"][p["material"]]["name"]
    tg = {}
    for ti, tdef in enumerate(p.get("targets", [])):
        tg[j["meshes"][mesh_i]["extras"]["targetNames"][ti]] = acc(j, bn, tdef["POSITION"]).astype(float)
    parts.append(dict(mat=mname, P=P, N=N, C=C, J=J, W=W, I=I, T=tg, mesh=mesh_i))
print("validation problems:", bad)
tri_by = {}
for p in parts: tri_by[p["mesh"]] = tri_by.get(p["mesh"], 0) + len(p["I"])
print("tris per mesh", tri_by, "draw calls", len(parts), "morph targets", sorted({k for p in parts for k in p["T"]}))
bb = np.concatenate([p["P"] for p in parts]); print("bbox min", bb.min(0).round(3), "max", bb.max(0).round(3), "height", round(bb[:, 1].max() - bb[:, 1].min(), 3))

def rot(rx=0, ry=0, rz=0):
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]]); Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]); Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Ry @ Rx @ Rz

def pose(parts, rots, hip_dy=0.0, morph=None):
    G = {}
    for b in H.BONES:
        par = H.PARENT[b]; loc = np.eye(4); loc[:3, :3] = rot(*rots.get(b, (0, 0, 0)))
        rest = np.array(H.POS[b]) - (np.array(H.POS[par]) if par else 0)
        loc[:3, 3] = rest + (np.array([0, hip_dy, 0]) if b == "hips" else 0)
        G[b] = (G[par] if par else np.eye(4)) @ loc
    M = np.stack([G[b] @ ibm[i].reshape(4, 4).T for i, b in enumerate(H.BONES)])   # ibm stored column-major
    out = []
    for p in parts:
        Mv = np.einsum("nk,nkij->nij", p["W"], M[p["J"]])
        P0 = p["P"].copy()
        for tn, wgt in (morph or {}).items():
            if tn in p["T"]: P0 = P0 + p["T"][tn] * wgt
        P = np.einsum("nij,nj->ni", Mv[:, :3, :3], P0) + Mv[:, :3, 3]
        N = np.einsum("nij,nj->ni", Mv[:, :3, :3], p["N"])
        out.append(dict(mat=p["mat"], P=P, N=N / (np.linalg.norm(N, axis=1, keepdims=True) + 1e-9), C=np.concatenate([p["C"][:, :3], p["C"][:, 3:4]], 1), I=p["I"]))
    return out

# --- expression close-ups (morph targets) and a pack-sway check
views = []
for name in [None, "smile", "surprise", "focus", "fear", "tired"]:
    views.append(PV.render(pose(parts, {}, 0.0, {name: 1.0} if name else None), 0, W=330, Hh=420, crop=(1.52, 1.84)))
sheet = Image.new("RGB", (330 * 6, 420)); x = 0
for v in views: sheet.paste(v, (x, 0)); x += 330
sheet.save("/tmp/expr.png")
walk = {"hipL": (-.5, 0, 0), "hipR": (.5, 0, 0), "knR": (1.0, 0, 0), "shL": (.5, 0, .06), "shR": (-.5, 0, -.06), "elL": (-.3, 0, 0), "elR": (-.5, 0, 0), "pack": (.05, 0, 0)}
crouch = {"hipL": (-1.25, 0, 0), "hipR": (-1.25, 0, 0), "knL": (2.15, 0, 0), "knR": (2.15, 0, 0), "spine": (.4, 0, 0), "head": (-.35, 0, 0), "pack": (-.05, 0, 0)}
views = [PV.render(pose(parts, r, dy), 90, W=520, Hh=700, crop=(0, 1.9)) for r, dy in ((walk, 0.0), (crouch, -.42))]
sheet = Image.new("RGB", (sum(v.width for v in views), views[0].height)); x = 0
for v in views: sheet.paste(v, (x, 0)); x += v.width
sheet.save("/tmp/hero_poses.png"); print("previews saved")
