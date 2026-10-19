import sys, math
sys.path.insert(0, "tools")
import numpy as np
from PIL import Image
import hero_model as H

PAL = {"skin": (.82, .60, .46), "shirt": (.34, .42, .26), "pants": (.30, .24, .17), "leather": (.42, .26, .13), "leather_dark": (.10, .09, .08),
       "rubber": (.07, .06, .05), "pack": (.42, .37, .24), "scarf": (.66, .52, .36), "bedroll": (.45, .40, .30), "hair": (.30, .20, .13),
       "eye": (.95, .95, .95), "metal": (.65, .66, .70)}

def render(parts, yaw_deg, W=560, Hh=820, crop=(0.0, 1.86), zoom=None, center_x=0.0):
    y0, y1 = crop; scale = Hh / (y1 - y0) * .96
    yaw = math.radians(yaw_deg); c, s = math.cos(yaw), math.sin(yaw)
    img = np.full((Hh, W, 3), (205, 215, 225), float); zb = np.full((Hh, W), -1e9)
    L = np.array([-.4, .55, .75]); L /= np.linalg.norm(L)
    for p in parts:
        P = p["P"]; N = p["N"]; I = p["I"]
        X = P[:, 0] * c + P[:, 2] * s; Z = -P[:, 0] * s + P[:, 2] * c     # rotate about Y
        NX = N[:, 0] * c + N[:, 2] * s; NZ = -N[:, 0] * s + N[:, 2] * c
        base = np.array(PAL[p["mat"]]); col = np.clip(base[None] * p["C"][:, :3], 0, 1)
        lam = np.clip(NX * L[0] + N[:, 1] * L[1] + NZ * L[2], 0, 1) * .85 + .25
        shade = np.clip(col * lam[:, None], 0, 1) ** (1 / 2.2)
        sx = W / 2 + (X - center_x) * scale; sy = Hh - (P[:, 1] - y0) * scale - 20
        for t in I:
            a, b, d = t
            x0, x1_ = int(max(0, min(sx[a], sx[b], sx[d]))), int(min(W - 1, max(sx[a], sx[b], sx[d])) + 1)
            ya, yb = int(max(0, min(sy[a], sy[b], sy[d]))), int(min(Hh - 1, max(sy[a], sy[b], sy[d])) + 1)
            if x1_ <= x0 or yb <= ya: continue
            den = (sy[b] - sy[d]) * (sx[a] - sx[d]) + (sx[d] - sx[b]) * (sy[a] - sy[d])
            if abs(den) < 1e-9: continue
            gx, gy = np.meshgrid(np.arange(x0, x1_) + .5, np.arange(ya, yb) + .5)
            w0 = ((sy[b] - sy[d]) * (gx - sx[d]) + (sx[d] - sx[b]) * (gy - sy[d])) / den
            w1 = ((sy[d] - sy[a]) * (gx - sx[d]) + (sx[a] - sx[d]) * (gy - sy[d])) / den
            w2 = 1 - w0 - w1
            m = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
            if not m.any(): continue
            z = w0 * Z[a] + w1 * Z[b] + w2 * Z[d]
            sub = zb[ya:yb, x0:x1_]; ok = m & (z > sub)
            if not ok.any(): continue
            colr = w0[..., None] * shade[a] + w1[..., None] * shade[b] + w2[..., None] * shade[d]
            sub[ok] = z[ok]; img[ya:yb, x0:x1_][ok] = colr[ok] * 255
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))

if __name__ == "__main__":
    parts = H.assemble()
    mode = sys.argv[1] if len(sys.argv) > 1 else "body"
    out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/hero_prev.png"
    if mode == "body":
        views = [render(parts, a) for a in (0, 90, 180)]
    else:
        views = [render(parts, a, W=700, Hh=820, crop=(1.50, 1.84), center_x=0.0) for a in (0, 35, 90)]
    sheet = Image.new("RGB", (sum(v.width for v in views), views[0].height))
    x = 0
    for v in views: sheet.paste(v, (x, 0)); x += v.width
    sheet.save(out); print("saved", out, sheet.size)
