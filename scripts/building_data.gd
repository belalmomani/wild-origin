extends RefCounted
## Pure data: puzzle boards (4 facades, roof, 4 fence sides). Each board = irregular stone pieces.
const ORIGIN := Vector3(0, 0, 0)   # house stands in the middle of the clearing

static func piece_color(p: Dictionary) -> Color:
	var h := absi(hash(p.id))
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
		cost: String, b: Basis, base: Vector3, openings: Array, seed_v: int) -> Dictionary:
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
			var skip := false
			for o in openings:
				if (o as Rect2).has_point(c3):
					skip = true
			if skip:
				continue
			var rel := PackedVector2Array()
			for v in poly:
				rel.append(v - c3)
			pieces.append({"id": "%s_%d" % [id, n], "poly": poly, "mesh_poly": rel,
				"xf": Transform3D(b, base + b * Vector3(c3.x, c3.y, 0.0)), "thick": thick, "cost": cost})
			n += 1
	return {"id": id, "name": title, "w": w, "h": h, "pieces": pieces, "openings": openings}

static func roof_board(o: Vector3) -> Dictionary:
	var s := sin(deg_to_rad(31.0))
	var c := cos(deg_to_rad(31.0))
	var xs := Vector3(1, 0, 0)
	var slab := PackedVector2Array([Vector2(-2.3, -1.25), Vector2(2.3, -1.25), Vector2(2.3, 1.25), Vector2(-2.3, 1.25)])
	var tri := PackedVector2Array([Vector2(-2, -0.6), Vector2(2, -0.6), Vector2(0, 0.6)])
	var ya := Vector3(0, s, -c)
	var yb := Vector3(0, s, c)
	var pieces: Array = []
	pieces.append({"id": "ROOF_0", "poly": PackedVector2Array([Vector2(-4.8, 1.6), Vector2(-0.2, 1.6), Vector2(-0.2, 4.1), Vector2(-4.8, 4.1)]),
		"mesh_poly": slab, "xf": Transform3D(Basis(xs, ya, xs.cross(ya)), o + Vector3(0, 3.0, 1.0)), "thick": 0.15, "cost": "wood"})
	pieces.append({"id": "ROOF_1", "poly": PackedVector2Array([Vector2(0.2, 1.6), Vector2(4.8, 1.6), Vector2(4.8, 4.1), Vector2(0.2, 4.1)]),
		"mesh_poly": slab, "xf": Transform3D(Basis(xs, yb, xs.cross(yb)), o + Vector3(0, 3.0, -1.0)), "thick": 0.15, "cost": "wood"})
	for k in [1, 3]:
		var b := Basis(Vector3.UP, deg_to_rad(k * 90.0))
		var x0 := -4.2 if k == 1 else 0.2
		pieces.append({"id": "ROOF_%d" % (k + 1), "poly": PackedVector2Array([Vector2(x0, 0.2), Vector2(x0 + 4.0, 0.2), Vector2(x0 + 2.0, 1.4)]),
			"mesh_poly": tri, "xf": Transform3D(b, o + b * Vector3(0, 3.0, 2.0)), "thick": 0.3, "cost": "wood"})
	return {"id": "ROOF", "name": "السقف", "w": 10.0, "h": 4.2, "pieces": pieces, "openings": []}

static func make_boards() -> Array:
	var out: Array = []
	var o := ORIGIN
	var names := ["الواجهة الأمامية (الباب)", "الواجهة اليمنى (نافذة)", "الواجهة الخلفية", "الواجهة اليسرى (نافذة)"]
	for k in 4:
		var b := Basis(Vector3.UP, deg_to_rad(k * 90.0))
		var op: Array = []
		if k == 0:
			op = [Rect2(-0.4, 0.0, 0.8, 1.92)]
		elif k == 1 or k == 3:
			op = [Rect2(-0.4, 0.96, 0.8, 0.96)]
		out.append(wall_board("F%d" % k, names[k], 4.0, 2.4, 10, 5, 0.3, "wood", b, o + b * Vector3(0, 0, 2), op, 100 + k))
	out.append(roof_board(o))
	for s in 4:
		var b2 := Basis(Vector3.UP, deg_to_rad(s * 90.0))
		var op2: Array = []
		if s == 0:
			op2 = [Rect2(-0.8, 0.0, 1.6, 1.2)]
		out.append(wall_board("S%d" % s, "السور %d من 4" % (s + 1), 11.0, 1.2, 6, 2, 0.5, "stone", b2, o + b2 * Vector3(0, 0, 6), op2, 200 + s))
	return out
