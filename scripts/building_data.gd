extends RefCounted
## Pure data: puzzle boards (4 facades, roof, 4 fence sides). Each board = irregular stone pieces.
const ORIGIN := Vector3(0, 0, 0)   # house stands in the middle of the clearing
const BARN := Vector3(13, 0, 0)    # barn east of the house (door faces +Z, the pen is in front of it)
const DOOR_HINGE := Vector3(-0.75, 0.0, 2.0)   # house door: hinge on the left jamb, closed leaf spans x -0.75..0.75
const DOOR_C := Vector3(0, 0, 2.0)
const BED_C := Vector3(-1.35, 0, -0.85)
const HEARTH_C := Vector3(1.3, 0, -1.45)
const LAMP_POS := Vector3(0, 2.33, 0)
const POND_C := Vector3(-34, 0, 22)  # the lake, a little way from the house (world.gd carves the basin and flattens the shore)
const POND_R := 17.0                 # lake radius: a real, wide lake
const POND_DEPTH := 3.6              # depth at the middle
const CABIN_C := Vector3(-9, 0, 39)   # settlers' cabin, built together with the rescued travellers
const TOWER_C := Vector3(-21, 0, 39)  # lookout tower on the lake shore (the ground is flattened there by world.gd)
const WATER_Y := -0.35               # water surface (the shore is at ground level 0)
const FARM_C := Vector3(-14, 0, 0)  # fenced farm, west of the house (gate on its east side, facing the house)
## Hinged doors / gates. board = puzzle board that builds it, c = centre, out = the side it swings to,
## block = radius where closing is refused (the leaf would sweep through you), reach = interact distance.
const DOORS := {
	"house": {"board": "I_door", "c": Vector3(0, 0, 2.0), "out": Vector3(0, 0, 1), "block": 1.9, "reach": 2.6, "name": "الباب"},
	"fence": {"board": "G_fence", "c": Vector3(0, 0, 6.0), "out": Vector3(0, 0, 1), "block": 2.9, "reach": 3.8, "name": "بوابة السور"},
	"farm": {"board": "M_gate", "c": Vector3(-9, 0, 0), "out": Vector3(1, 0, 0), "block": 2.9, "reach": 3.8, "name": "بوابة المزرعة"},
}

static func piece_color(p: Dictionary) -> Color:
	var h := absi(hash(p.id))
	if p.has("tint"):
		var tc: Color = p["tint"]
		return tc.darkened((h % 10) / 100.0)
	if p.cost == "wood":
		return Color(0.55, 0.36, 0.2).darkened((h % 20) / 100.0)
	var base := Color(0.46, 0.47, 0.5)
	if h % 5 == 0:
		base = Color(0.5, 0.34, 0.28)
	return base.darkened((h % 25) / 100.0)

static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in p:
		c += v
	return c / p.size()

static func wall_board(id: String, title: String, w: float, h: float, nx: int, ny: int, thick: float,
		cost: String, b: Basis, base: Vector3, openings: Array, seed_v: int, legacy: Array = []) -> Dictionary:
	# legacy = the openings an older version used. Piece ids are numbered as if only those openings existed,
	# so a save made before an opening was widened keeps pointing at the same pieces.
	var id_openings: Array = legacy if not legacy.is_empty() else openings
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cw := w / nx
	var ch := h / ny
	var vt := {}
	for i in nx + 1:
		for j in ny + 1:
			var p := Vector2(-w / 2.0 + i * cw, j * ch)
			if i > 0 and i < nx:
				p.x += rng.randf_range(-0.22, 0.22) * cw
			if j > 0 and j < ny:
				p.y += rng.randf_range(-0.22, 0.22) * ch
			vt[Vector2i(i, j)] = p
	var hm := {}  # notch vertex on horizontal interior edges
	var vm := {}  # notch vertex on vertical interior edges
	for i in nx:
		for j in range(1, ny):
			var a: Vector2 = vt[Vector2i(i, j)]
			var c: Vector2 = vt[Vector2i(i + 1, j)]
			var d := c - a
			hm[Vector2i(i, j)] = (a + c) * 0.5 + Vector2(-d.y, d.x).normalized() * rng.randf_range(-0.18, 0.18) * d.length()
	for i in range(1, nx):
		for j in ny:
			var a2: Vector2 = vt[Vector2i(i, j)]
			var c2: Vector2 = vt[Vector2i(i, j + 1)]
			var d2 := c2 - a2
			vm[Vector2i(i, j)] = (a2 + c2) * 0.5 + Vector2(-d2.y, d2.x).normalized() * rng.randf_range(-0.18, 0.18) * d2.length()
	var pieces: Array = []
	var n := 0
	for j in ny:
		for i in nx:
			var poly := PackedVector2Array()
			poly.append(vt[Vector2i(i, j)])
			if hm.has(Vector2i(i, j)):
				poly.append(hm[Vector2i(i, j)])
			poly.append(vt[Vector2i(i + 1, j)])
			if vm.has(Vector2i(i + 1, j)):
				poly.append(vm[Vector2i(i + 1, j)])
			poly.append(vt[Vector2i(i + 1, j + 1)])
			if hm.has(Vector2i(i, j + 1)):
				poly.append(hm[Vector2i(i, j + 1)])
			poly.append(vt[Vector2i(i, j + 1)])
			if vm.has(Vector2i(i, j)):
				poly.append(vm[Vector2i(i, j)])
			var c3 := _centroid(poly)
			var legacy_skip := false
			for o in id_openings:
				if (o as Rect2).has_point(c3):
					legacy_skip = true
			if legacy_skip:
				continue
			var skip := false
			for o2 in openings:
				if (o2 as Rect2).has_point(c3):
					skip = true
			if skip:
				n += 1      # keeps the id numbering of older saves; the piece itself is no longer part of the wall
				continue
			var rel := PackedVector2Array()
			for v in poly:
				rel.append(v - c3)
			pieces.append({"id": "%s_%d" % [id, n], "poly": poly, "mesh_poly": rel,
				"xf": Transform3D(b, base + b * Vector3(c3.x, c3.y, 0.0)), "thick": thick, "cost": cost})
			n += 1
	return {"id": id, "name": title, "w": w, "h": h, "pieces": pieces, "openings": openings}

static func roof_board(o: Vector3, rid: String = "ROOF", title: String = "السقف") -> Dictionary:
	var s := sin(deg_to_rad(31.0))
	var c := cos(deg_to_rad(31.0))
	var xs := Vector3(1, 0, 0)
	var slab := PackedVector2Array([Vector2(-2.3, -1.25), Vector2(2.3, -1.25), Vector2(2.3, 1.25), Vector2(-2.3, 1.25)])
	var tri := PackedVector2Array([Vector2(-2, -0.6), Vector2(2, -0.6), Vector2(0, 0.6)])
	var ya := Vector3(0, s, -c)
	var yb := Vector3(0, s, c)
	var pieces: Array = []
	pieces.append({"id": rid + "_0", "poly": PackedVector2Array([Vector2(-4.8, 1.6), Vector2(-0.2, 1.6), Vector2(-0.2, 4.1), Vector2(-4.8, 4.1)]),
		"mesh_poly": slab, "xf": Transform3D(Basis(xs, ya, xs.cross(ya)), o + Vector3(0, 3.0, 1.0)), "thick": 0.15, "cost": "wood"})
	pieces.append({"id": rid + "_1", "poly": PackedVector2Array([Vector2(0.2, 1.6), Vector2(4.8, 1.6), Vector2(4.8, 4.1), Vector2(0.2, 4.1)]),
		"mesh_poly": slab, "xf": Transform3D(Basis(xs, yb, xs.cross(yb)), o + Vector3(0, 3.0, -1.0)), "thick": 0.15, "cost": "wood"})
	for k in [1, 3]:
		var b := Basis(Vector3.UP, deg_to_rad(k * 90.0))
		var x0 := -4.2 if k == 1 else 0.2
		pieces.append({"id": "%s_%d" % [rid, k + 1], "poly": PackedVector2Array([Vector2(x0, 0.2), Vector2(x0 + 4.0, 0.2), Vector2(x0 + 2.0, 1.4)]),
			"mesh_poly": tri, "xf": Transform3D(b, o + b * Vector3(0, 3.0, 2.0)), "thick": 0.3, "cost": "wood"})
	return {"id": rid, "name": title, "w": 10.0, "h": 4.2, "pieces": pieces, "openings": []}

static func make_boards() -> Array:
	var out: Array = []
	var o := ORIGIN
	var names := ["الواجهة الأمامية (الباب)", "الواجهة اليمنى (نافذة)", "الواجهة الخلفية", "الواجهة اليسرى (نافذة)"]
	for k in 4:
		var b := Basis(Vector3.UP, deg_to_rad(k * 90.0))
		var op: Array = []
		var leg: Array = []
		if k == 0:
			# The old 0.8 m doorway was narrower than the player (0.7 m capsule) once wall pieces
			# jutted into it, so the house could not be entered. Now 1.6 m wide, full height.
			op = [Rect2(-0.8, 0.0, 1.6, 2.45)]
			leg = [Rect2(-0.4, 0.0, 0.8, 1.92)]
		elif k == 1 or k == 3:
			op = [Rect2(-0.4, 0.96, 0.8, 0.96)]
		out.append(wall_board("F%d" % k, names[k], 4.0, 2.4, 10, 5, 0.3, "wood", b, o + b * Vector3(0, 0, 2), op, 100 + k, leg))
	out.append(roof_board(o))
	for s in 4:
		var b2 := Basis(Vector3.UP, deg_to_rad(s * 90.0))
		var op2: Array = []
		var leg2: Array = []
		if s == 0:
			# fence columns are 1.83 m wide, so the old 1.6 m gate could remove no piece at all: now 2 columns.
			op2 = [Rect2(-1.9, 0.0, 3.8, 1.3)]
			leg2 = [Rect2(-0.8, 0.0, 1.6, 1.2)]
		out.append(wall_board("S%d" % s, "السور %d من 4" % (s + 1), 11.0, 1.2, 6, 2, 0.5, "stone", b2, o + b2 * Vector3(0, 0, 6), op2, 200 + s, leg2))
	out.append(gate_board("G_fence", "بوابة السور", "fence", Vector3(0, 0, 6.0), Basis.IDENTITY, 1.9, 1.1, 900))
	# barn (unlocked after the first animal is caught): 4 plank walls + roof, same puzzle system
	var bn := ["الحظيرة: الواجهة الأمامية (البوابة)", "الحظيرة: الجدار الأيمن", "الحظيرة: الجدار الخلفي", "الحظيرة: الجدار الأيسر"]
	for k in 4:
		var b3 := Basis(Vector3.UP, deg_to_rad(k * 90.0))
		var op3: Array = []
		if k == 0:
			op3 = [Rect2(-0.6, 0.0, 1.2, 1.9)]
		out.append(wall_board("B%d" % k, bn[k], 4.0, 2.4, 8, 4, 0.3, "wood", b3, BARN + b3 * Vector3(0, 0, 2), op3, 300 + k))
	out.append(roof_board(BARN, "BROOF", "سقف الحظيرة"))
	out.append_array(interior_boards())
	out.append_array(farm_boards())
	out.append_array(fishing_boards())
	out.append_array(tower_boards())
	out.append_array(cabin_boards())
	return out

## Two-leaf gate built as one puzzle board. Each leaf hangs on its own hinge (local x = -half / +half) and swings outwards.
static func gate_board(id: String, title: String, group: String, center: Vector3, b: Basis, half: float, h: float, seed_v: int) -> Dictionary:
	var pieces: Array = []
	for side in [-1, 1]:
		var sd := float(side)
		var leaf := "L" if side < 0 else "R"
		var leaf_c := center + b * Vector3(sd * half * 0.5, 0.0, 0.0)
		var lb := wall_board(id + leaf, title, half, h, 4, 3, 0.1, "wood", b, leaf_c, [], seed_v + (0 if side < 0 else 1))
		var hinge := center + b * Vector3(sd * half, 0.0, 0.0)
		var off := Vector2(sd * half * 0.5, 0.0)
		for p in lb.pieces:
			p["door"] = group
			p["leaf"] = leaf
			p["hinge"] = hinge
			p["angle"] = 1.75 * sd
			var np := PackedVector2Array()
			for v in p["poly"]:
				np.append(v + off)
			p["poly"] = np
			pieces.append(p)
	return {"id": id, "name": title, "w": half * 2.0, "h": h, "pieces": pieces, "openings": []}

## Farm: a closed 10x10 wooden fence west of the house, with a two-leaf gate on the side facing the house.
static func farm_boards() -> Array:
	var out: Array = []
	var names := ["سور المزرعة: الجهة الجنوبية", "سور المزرعة: جهة المنزل (البوابة)", "سور المزرعة: الجهة الشمالية", "سور المزرعة: الجهة الغربية"]
	for k in 4:
		var b := Basis(Vector3.UP, deg_to_rad(k * 90.0))
		var op: Array = []
		if k == 1:
			op = [Rect2(-1.2, 0.0, 2.4, 1.5)]
		out.append(wall_board("M_S%d" % k, names[k], 10.0, 1.3, 6, 2, 0.2, "wood", b, FARM_C + b * Vector3(0, 0, 5), op, 800 + k))
	out.append(gate_board("M_gate", "بوابة المزرعة", "farm", FARM_C + Basis(Vector3.UP, PI / 2.0) * Vector3(0, 0, 5), Basis(Vector3.UP, PI / 2.0), 1.7, 1.2, 950))
	return out

# ---------------------------------------------------------------- interior (phase 2)
## One furniture part: a world-aligned box. dim = size (x, y, z), c = centre. Optional keys: tex, tint, nocol, emit.
static func _b(dim: Vector3, c: Vector3, cost: String = "wood", extra: Dictionary = {}) -> Dictionary:
	var d := {"dim": dim, "c": c, "cost": cost}
	for k in extra:
		d[k] = extra[k]
	return d

static func _pack_rects(sizes: Array, gap: float, max_w: float) -> Dictionary:
	var pos: Array = []
	var x := 0.0
	var y := 0.0
	var row_h := 0.0
	var used_w := 0.0
	for s in sizes:
		var sz: Vector2 = s
		if x > 0.0 and x + sz.x > max_w:
			x = 0.0
			y += row_h + gap
			row_h = 0.0
		pos.append(Vector2(x, y))
		x += sz.x + gap
		used_w = maxf(used_w, x - gap)
		row_h = maxf(row_h, sz.y)
	return {"pos": pos, "w": used_w, "h": y + row_h}

## A puzzle board for furniture. Every part is a box that goes exactly where it belongs in the room; the board
## itself is just a tidy tray layout (parts laid out in rows), so you assemble it piece by piece like the walls.
static func box_board(id: String, title: String, boxes: Array) -> Dictionary:
	var sizes: Array = []
	var meta: Array = []
	for bx in boxes:
		var s: Vector3 = bx["dim"]
		var face := Vector2.ZERO
		var thick := 0.0
		var basis := Basis.IDENTITY
		if s.z <= s.x and s.z <= s.y:
			face = Vector2(s.x, s.y)
			thick = s.z
		elif s.y <= s.x and s.y <= s.z:
			face = Vector2(s.x, s.z)
			thick = s.y
			basis = Basis(Vector3.RIGHT, -PI / 2.0)
		else:
			face = Vector2(s.z, s.y)
			thick = s.x
			basis = Basis(Vector3.UP, PI / 2.0)
		meta.append({"face": face, "thick": thick, "basis": basis})
		sizes.append(Vector2(clampf(face.x * 1.6, 0.45, 3.0), clampf(face.y * 1.6, 0.45, 3.0)))
	var packed := _pack_rects(sizes, 0.2, 6.0)
	var bw: float = maxf(float(packed["w"]), 2.0) + 0.3
	var bh: float = float(packed["h"]) + 0.3
	var pieces: Array = []
	for i in boxes.size():
		var bx2: Dictionary = boxes[i]
		var m: Dictionary = meta[i]
		var sz: Vector2 = sizes[i]
		var tl: Vector2 = packed["pos"][i]
		var x0 := -bw * 0.5 + 0.15 + tl.x
		var y0 := bh - 0.15 - tl.y - sz.y
		var poly := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + sz.x, y0), Vector2(x0 + sz.x, y0 + sz.y), Vector2(x0, y0 + sz.y)])
		var face2: Vector2 = m["face"]
		var hw := face2.x * 0.5
		var hh := face2.y * 0.5
		var mp := PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		var c: Vector3 = bx2["c"]
		var bs: Basis = m["basis"]
		var piece := {"id": "%s_%d" % [id, i], "poly": poly, "mesh_poly": mp, "xf": Transform3D(bs, c),
			"thick": float(m["thick"]), "cost": bx2["cost"],
			"sig": "%.2f_%.2f_%.2f_%s_%s_%s" % [face2.x, face2.y, float(m["thick"]), bx2["cost"], str(bx2.get("tex", "")), str(bx2.get("tint", ""))]}
		for key in ["tex", "tint", "nocol", "emit"]:
			if bx2.has(key):
				piece[key] = bx2[key]
		pieces.append(piece)
	return {"id": id, "name": title, "w": bw, "h": bh, "pieces": pieces, "openings": []}

static func _window_board(id: String, title: String, side: float) -> Dictionary:
	# frame sits in the wall opening (centre y 1.44, 0.8 wide x 0.96 high); glass appears when it is finished
	var cx := 2.0 * side
	var bars: Array = [
		_b(Vector3(0.16, 1.1, 0.1), Vector3(cx, 1.44, -0.4)),
		_b(Vector3(0.16, 1.1, 0.1), Vector3(cx, 1.44, 0.4)),
		_b(Vector3(0.16, 0.1, 0.7), Vector3(cx, 1.94, 0.0)),
		_b(Vector3(0.16, 0.1, 0.7), Vector3(cx, 0.94, 0.0)),
		_b(Vector3(0.1, 0.9, 0.06), Vector3(cx, 1.44, 0.0)),
		_b(Vector3(0.1, 0.06, 0.7), Vector3(cx, 1.44, 0.0)),
	]
	return box_board(id, title, bars)

## Fishing (unlocked once the well-to-lake channel exists): a small dock into the lake, then the rod itself.
static func fishing_boards() -> Array:
	var dock: Array = []
	for i in 4:
		dock.append(_b(Vector3(1.0, 0.08, 1.3), POND_C + Vector3(POND_R + 0.4 - 1.1 * i, 0.17, 0.0)))
	dock.append(_b(Vector3(0.14, 0.7, 0.14), POND_C + Vector3(POND_R - 1.5, 0.35, -0.6)))
	dock.append(_b(Vector3(0.14, 0.7, 0.14), POND_C + Vector3(POND_R - 1.5, 0.35, 0.6)))
	var rc := POND_C + Vector3(POND_R + 0.9, 0.0, 1.1)       # the rod stands in its holder at the dock's root
	var rod: Array = [
		_b(Vector3(0.1, 0.5, 0.1), rc + Vector3(0, 0.25, 0)),                                            # holder post
		_b(Vector3(0.06, 1.7, 0.06), rc + Vector3(0, 1.35, 0), "wood", {"tint": Color(0.62, 0.45, 0.25)}),  # shaft
		_b(Vector3(0.09, 0.32, 0.09), rc + Vector3(0, 0.72, 0), "wood", {"tint": Color(0.3, 0.2, 0.12)}),   # grip
		_b(Vector3(0.025, 1.0, 0.025), rc + Vector3(-0.15, 1.65, 0), "wood", {"tint": Color(0.9, 0.88, 0.8)}),  # line (rope)
		_b(Vector3(0.07, 0.07, 0.07), rc + Vector3(-0.15, 1.12, 0), "wood", {"tint": Color(0.9, 0.12, 0.1)}),  # float
		_b(Vector3(0.05, 0.1, 0.05), rc + Vector3(-0.15, 1.0, 0), "stone", {"tint": Color(0.7, 0.72, 0.75)}),   # hook
	]
	return [box_board("R_rod", "السنّارة (خشب + حبل + خطّاف)", rod), box_board("R_dock", "رصيف الصيد", dock)]

## The lookout tower beside the lake: eight stages, built in order, mixing stone (foundation, buttresses) and wood.
static func tower_boards() -> Array:
	var c := TOWER_C
	var e := 1.6                                         # half width of the frame
	var found: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			found.append(_b(Vector3(0.9, 0.6, 0.9), c + Vector3(sx * e, 0.3, sz * e), "stone"))
	for sz in [-1.0, 1.0]:
		found.append(_b(Vector3(3.2, 0.3, 0.4), c + Vector3(0, 0.55, sz * e), "stone"))
	for sx in [-1.0, 1.0]:
		found.append(_b(Vector3(0.4, 0.3, 3.2), c + Vector3(sx * e, 0.55, 0), "stone"))
	found.append(_b(Vector3(3.6, 0.2, 3.6), c + Vector3(0, 0.1, 0), "stone", {"tint": Color(0.55, 0.55, 0.52)}))
	var posts: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			posts.append(_b(Vector3(0.32, 6.0, 0.32), c + Vector3(sx * e, 3.65, sz * e)))
	var beams: Array = []
	for yy in [2.4, 4.6]:
		for sz in [-1.0, 1.0]:
			beams.append(_b(Vector3(3.2, 0.26, 0.26), c + Vector3(0, yy, sz * e)))
		for sx in [-1.0, 1.0]:
			beams.append(_b(Vector3(0.26, 0.26, 3.2), c + Vector3(sx * e, yy, 0)))
	beams.append(_b(Vector3(3.2, 0.2, 0.2), c + Vector3(0, 3.5, -e)))
	beams.append(_b(Vector3(3.2, 0.2, 0.2), c + Vector3(0, 3.5, e)))
	var buttress: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			buttress.append(_b(Vector3(0.7, 1.2, 0.7), c + Vector3(sx * (e + 0.55), 0.6, sz * (e + 0.55)), "stone"))
	for i in 3:
		buttress.append(_b(Vector3(1.4, 0.3, 0.7), c + Vector3(0, 0.15 + 0.3 * i, e + 1.2 + 0.0 * i - 0.5 * i), "stone"))
	var ladder: Array = []
	for sx in [-1.0, 1.0]:
		ladder.append(_b(Vector3(0.12, 5.6, 0.12), c + Vector3(sx * 0.5, 3.1, e + 0.2)))
	for i in 9:
		ladder.append(_b(Vector3(1.0, 0.1, 0.1), c + Vector3(0, 0.9 + 0.6 * i, e + 0.2)))
	var deck: Array = []
	for i in 6:
		deck.append(_b(Vector3(3.8, 0.14, 0.6), c + Vector3(0, 6.15, -1.5 + 0.6 * i)))
	for sx in [-1.2, -0.4, 0.4, 1.2]:
		deck.append(_b(Vector3(0.2, 0.25, 3.6), c + Vector3(sx, 5.9, 0)))
	var rails: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			rails.append(_b(Vector3(0.14, 1.0, 0.14), c + Vector3(sx * 1.8, 6.75, sz * 1.8)))
	for yy in [6.95, 6.5]:
		for sz in [-1.0, 1.0]:
			rails.append(_b(Vector3(3.7, 0.1, 0.1), c + Vector3(0, yy, sz * 1.8)))
		for sx in [-1.0, 1.0]:
			rails.append(_b(Vector3(0.1, 0.1, 3.7), c + Vector3(sx * 1.8, yy, 0)))
	var roof: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			roof.append(_b(Vector3(0.14, 1.5, 0.14), c + Vector3(sx * 1.7, 7.5, sz * 1.7)))
	roof.append(_b(Vector3(4.6, 0.2, 4.6), c + Vector3(0, 8.35, 0), "wood", {"tint": Color(0.45, 0.28, 0.16)}))
	roof.append(_b(Vector3(2.8, 0.25, 2.8), c + Vector3(0, 8.6, 0), "wood", {"tint": Color(0.5, 0.31, 0.18)}))
	roof.append(_b(Vector3(0.07, 2.0, 0.07), c + Vector3(0, 9.7, 0)))
	roof.append(_b(Vector3(0.9, 0.5, 0.04), c + Vector3(0.5, 10.1, 0), "wood", {"tint": Color(0.8, 0.12, 0.1)}))
	roof.append(_b(Vector3(0.3, 0.3, 0.3), c + Vector3(0, 7.0, 0), "wood", {"tint": Color(1.0, 0.8, 0.4), "emit": true, "nocol": true}))
	return [
		box_board("T_1", "برج المراقبة 1/8: الأساس الحجري", found),
		box_board("T_2", "برج المراقبة 2/8: الأعمدة الأربعة", posts),
		box_board("T_3", "برج المراقبة 3/8: عوارض الإطار", beams),
		box_board("T_4", "برج المراقبة 4/8: حجارة السند والدرج", buttress),
		box_board("T_5", "برج المراقبة 5/8: السلّم", ladder),
		box_board("T_6", "برج المراقبة 6/8: منصة المراقبة", deck),
		box_board("T_7", "برج المراقبة 7/8: سور المنصة", rails),
		box_board("T_8", "برج المراقبة 8/8: السقف والراية", roof),
	]

## Settlers' cabin (boards C_1..C_5): stone footing, log walls in two courses, stepped roof, door / window / chimney.
## The door faces the tower (-x). Built by the player together with the three rescued travellers.
static func cabin_boards() -> Array:
	var c := CABIN_C
	var hx := 3.0
	var hz := 2.5
	var found: Array = []
	found.append(_b(Vector3(6.6, 0.3, 5.6), c + Vector3(0, 0.15, 0), "stone", {"tint": Color(0.5, 0.5, 0.48)}))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			found.append(_b(Vector3(0.7, 0.5, 0.7), c + Vector3(sx * hx, 0.25, sz * hz), "stone"))
	for sz in [-1.0, 1.0]:
		found.append(_b(Vector3(2.4, 0.3, 0.5), c + Vector3(-1.4, 0.35, sz * hz), "stone"))
		found.append(_b(Vector3(2.4, 0.3, 0.5), c + Vector3(1.4, 0.35, sz * hz), "stone"))
	var low: Array = []
	var high: Array = []
	for r in 8:
		var y := 0.5 + 0.3 * r + 0.15
		var tgt: Array = low if r < 4 else high
		var tn := Color(0.56, 0.36, 0.2) if r % 2 == 0 else Color(0.5, 0.32, 0.18)
		for sz in [-1.0, 1.0]:                                        # long walls (north / south)
			for hxs in [-1.5, 1.5]:
				tgt.append(_b(Vector3(3.0, 0.28, 0.4), c + Vector3(hxs, y, sz * hz), "wood", {"tint": tn}))
		if r >= 3 and r <= 5:                                          # window gap in the back wall
			for sz in [-1.0, 1.0]:
				tgt.append(_b(Vector3(0.4, 0.28, 1.7), c + Vector3(hx, y, sz * 1.35), "wood", {"tint": tn}))
		else:
			tgt.append(_b(Vector3(0.4, 0.28, 5.0), c + Vector3(hx, y, 0), "wood", {"tint": tn}))
		if r >= 6:                                                      # above the door: a full course
			tgt.append(_b(Vector3(0.4, 0.28, 5.0), c + Vector3(-hx, y, 0), "wood", {"tint": tn}))
		else:                                                           # door gap, 1.3 m wide
			for sz in [-1.0, 1.0]:
				tgt.append(_b(Vector3(0.4, 0.28, 1.85), c + Vector3(-hx, y, sz * 1.575), "wood", {"tint": tn}))
	var roof: Array = []
	var dims := [Vector2(7.2, 6.2), Vector2(6.2, 5.0), Vector2(5.0, 3.8), Vector2(3.8, 2.6), Vector2(2.6, 1.4)]
	for i in dims.size():
		roof.append(_b(Vector3(dims[i].x, 0.28, dims[i].y), c + Vector3(0, 2.95 + 0.28 * i, 0), "wood", {"tint": Color(0.42, 0.26, 0.15).lightened(0.04 * i)}))
	var trim: Array = []
	trim.append(_b(Vector3(0.2, 0.2, 1.5), c + Vector3(-hx - 0.1, 1.75, 0), "wood", {"tint": Color(0.4, 0.25, 0.14)}))   # lintel
	for sz in [-1.0, 1.0]:
		trim.append(_b(Vector3(0.2, 1.4, 0.16), c + Vector3(-hx - 0.1, 1.2, sz * 0.72), "wood", {"tint": Color(0.4, 0.25, 0.14)}))
	trim.append(_b(Vector3(0.1, 1.4, 0.7), c + Vector3(-hx - 0.4, 1.2, 0.95), "wood", {"tint": Color(0.6, 0.4, 0.22)}))     # door leaf, open
	trim.append(_b(Vector3(0.14, 0.9, 1.5), c + Vector3(hx, 1.55, 0), "wood", {"tint": Color(0.7, 0.85, 0.95), "nocol": true}))  # window glass
	trim.append(_b(Vector3(1.0, 3.6, 1.0), c + Vector3(1.2, 3.6, -1.4), "stone", {"tint": Color(0.5, 0.42, 0.38)}))          # chimney
	trim.append(_b(Vector3(1.4, 0.25, 1.4), c + Vector3(1.2, 5.5, -1.4), "stone"))
	trim.append(_b(Vector3(0.8, 0.5, 0.8), c + Vector3(-hx - 1.3, 0.25, 0), "stone"))                                        # doorstep
	return [
		box_board("C_1", "الكوخ 1/5: الأساس الحجري", found),
		box_board("C_2", "الكوخ 2/5: جذوع الجدران السفلى", low),
		box_board("C_3", "الكوخ 3/5: جذوع الجدران العليا", high),
		box_board("C_4", "الكوخ 4/5: السقف", roof),
		box_board("C_5", "الكوخ 5/5: الباب والنافذة والمدخنة", trim),
	]

static func interior_boards() -> Array:
	var out: Array = []
	var W := "wood"
	var S := "stone"
	# 1) door: same jigsaw as the walls; its pieces hang on a hinge (see building.gd) and swing open
	var door := wall_board("I_door", "الباب", 1.5, 2.3, 5, 5, 0.1, W, Basis.IDENTITY, DOOR_C, [], 700)
	for dp in door.pieces:
		dp["door"] = "house"
		dp["leaf"] = "a"
		dp["hinge"] = DOOR_HINGE
		dp["angle"] = -1.75
	out.append(door)
	# 2) windows
	out.append(_window_board("I_winR", "النافذة اليمنى", 1.0))
	out.append(_window_board("I_winL", "النافذة اليسرى", -1.0))
	# 3) floor (planks, decoration only)
	var fl: Array = []
	for i in 6:
		fl.append(_b(Vector3(0.61, 0.04, 3.7), Vector3(-1.5417 + i * 0.6167, 0.02, 0.0), W, {"nocol": true}))
	out.append(box_board("I_floor", "الأرضية الخشبية", fl))
	# 4) bed (back-left corner, headboard on the back wall)
	var cloth := {"tex": "fabric", "tint": Color(0.5, 0.58, 0.7)}
	var pillow := {"tex": "fabric", "tint": Color(0.85, 0.85, 0.8)}
	out.append(box_board("I_bed", "التخت (السرير)", [
		_b(Vector3(0.1, 0.3, 0.1), Vector3(-1.75, 0.15, -1.75)),
		_b(Vector3(0.1, 0.3, 0.1), Vector3(-0.95, 0.15, -1.75)),
		_b(Vector3(0.1, 0.3, 0.1), Vector3(-1.75, 0.15, 0.03)),
		_b(Vector3(0.1, 0.3, 0.1), Vector3(-0.95, 0.15, 0.03)),
		_b(Vector3(0.06, 0.16, 1.86), Vector3(-1.78, 0.36, -0.86)),
		_b(Vector3(0.06, 0.16, 1.86), Vector3(-0.92, 0.36, -0.86)),
		_b(Vector3(0.8, 0.16, 0.06), Vector3(-1.35, 0.36, -1.77)),
		_b(Vector3(0.8, 0.16, 0.06), Vector3(-1.35, 0.36, 0.03)),
		_b(Vector3(0.8, 0.04, 1.8), Vector3(-1.35, 0.42, -0.87)),
		_b(Vector3(0.9, 0.75, 0.06), Vector3(-1.35, 0.7, -1.82)),
		_b(Vector3(0.9, 0.4, 0.06), Vector3(-1.35, 0.5, 0.09)),
		_b(Vector3(0.78, 0.14, 1.7), Vector3(-1.35, 0.51, -0.87), W, cloth),
		_b(Vector3(0.5, 0.1, 0.28), Vector3(-1.35, 0.63, -1.6), W, pillow),
	]))
	# 5) hearth + fire (back-right corner): stone ring, then two logs; the fire lights when it is finished
	out.append(box_board("I_hearth", "الموقد (النار)", [
		_b(Vector3(1.0, 0.06, 0.7), Vector3(1.3, 0.03, -1.45), S),
		_b(Vector3(0.48, 0.5, 0.14), Vector3(1.06, 0.31, -1.76), S),
		_b(Vector3(0.48, 0.5, 0.14), Vector3(1.54, 0.31, -1.76), S),
		_b(Vector3(0.14, 0.4, 0.33), Vector3(0.82, 0.26, -1.6), S),
		_b(Vector3(0.14, 0.4, 0.33), Vector3(0.82, 0.26, -1.28), S),
		_b(Vector3(0.14, 0.4, 0.33), Vector3(1.78, 0.26, -1.6), S),
		_b(Vector3(0.14, 0.4, 0.33), Vector3(1.78, 0.26, -1.28), S),
		_b(Vector3(0.4, 0.22, 0.12), Vector3(1.1, 0.17, -1.12), S),
		_b(Vector3(0.4, 0.22, 0.12), Vector3(1.5, 0.17, -1.12), S),
		_b(Vector3(0.5, 0.1, 0.1), Vector3(1.3, 0.11, -1.5), W),
		_b(Vector3(0.1, 0.1, 0.5), Vector3(1.3, 0.21, -1.45), W),
	]))
	# 6) table + two stools (against the back wall between bed and hearth)
	var tb: Array = [
		_b(Vector3(0.9, 0.06, 0.7), Vector3(-0.05, 0.78, -1.4)),
		_b(Vector3(0.07, 0.75, 0.07), Vector3(-0.45, 0.375, -1.7)),
		_b(Vector3(0.07, 0.75, 0.07), Vector3(0.35, 0.375, -1.7)),
		_b(Vector3(0.07, 0.75, 0.07), Vector3(-0.45, 0.375, -1.1)),
		_b(Vector3(0.07, 0.75, 0.07), Vector3(0.35, 0.375, -1.1)),
		_b(Vector3(0.8, 0.08, 0.04), Vector3(-0.05, 0.68, -1.72)),
		_b(Vector3(0.8, 0.08, 0.04), Vector3(-0.05, 0.68, -1.08)),
	]
	for sx in [-0.35, 0.25]:
		tb.append(_b(Vector3(0.34, 0.05, 0.34), Vector3(sx, 0.43, -0.7)))
		for lx in [-0.13, 0.13]:
			for lz in [-0.13, 0.13]:
				tb.append(_b(Vector3(0.05, 0.4, 0.05), Vector3(sx + lx, 0.2, -0.7 + lz)))
	out.append(box_board("I_table", "الطاولة والكراسي", tb))
	# 7) kitchen counter along the right wall, under the window
	var dark := {"tint": Color(0.35, 0.25, 0.18)}
	out.append(box_board("I_kitchen", "المطبخ", [
		_b(Vector3(0.04, 0.8, 1.6), Vector3(1.81, 0.4, 0.1)),
		_b(Vector3(0.04, 0.8, 1.6), Vector3(1.22, 0.4, 0.1)),
		_b(Vector3(0.6, 0.8, 0.04), Vector3(1.52, 0.4, -0.7)),
		_b(Vector3(0.6, 0.8, 0.04), Vector3(1.52, 0.4, 0.9)),
		_b(Vector3(0.56, 0.03, 1.56), Vector3(1.52, 0.3, 0.1)),
		_b(Vector3(0.66, 0.05, 1.7), Vector3(1.5, 0.825, 0.1)),
		_b(Vector3(0.03, 0.62, 0.72), Vector3(1.2, 0.42, -0.3), W, dark),
		_b(Vector3(0.03, 0.62, 0.72), Vector3(1.2, 0.42, 0.5), W, dark),
		_b(Vector3(0.4, 0.08, 0.5), Vector3(1.52, 0.89, 0.55), S),
	]))
	# 8) hanging lamp in the middle of the room; it lights up at night when finished
	var lp := {"nocol": true}
	var glow := {"nocol": true, "emit": true, "tint": Color(1.0, 0.8, 0.4)}
	out.append(box_board("I_lamp", "المصباح المعلّق", [
		_b(Vector3(0.03, 0.9, 0.03), Vector3(0, 3.0, 0), W, lp),
		_b(Vector3(0.26, 0.05, 0.26), Vector3(0, 2.52, 0), W, lp),
		_b(Vector3(0.26, 0.05, 0.26), Vector3(0, 2.14, 0), W, lp),
		_b(Vector3(0.03, 0.35, 0.03), Vector3(-0.11, 2.33, -0.11), W, lp),
		_b(Vector3(0.03, 0.35, 0.03), Vector3(0.11, 2.33, -0.11), W, lp),
		_b(Vector3(0.03, 0.35, 0.03), Vector3(-0.11, 2.33, 0.11), W, lp),
		_b(Vector3(0.03, 0.35, 0.03), Vector3(0.11, 2.33, 0.11), W, lp),
		_b(Vector3(0.14, 0.18, 0.14), LAMP_POS, W, glow),
	]))
	return out
