extends RefCounted
## Procedural meshes: displaced flat-shaded rocks, branching trees (bark + alpha leaf cards), grass tufts.
const M := preload("res://scripts/mats.gd")

# ---------- helpers ----------
static func _basis_for(dir: Vector3) -> Basis:
	var up := dir.normalized()
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)

## Tapered cylinder from a to b with UVs (u around, v along length).
static func cyl(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, segs: int = 7) -> void:
	var bs := _basis_for(b - a)
	var ln := (b - a).length()
	for i in segs:
		var t0 := TAU * i / segs
		var t1 := TAU * (i + 1) / segs
		var d0 := bs * Vector3(cos(t0), 0, sin(t0))
		var d1 := bs * Vector3(cos(t1), 0, sin(t1))
		var p00 := a + d0 * r0
		var p10 := a + d1 * r0
		var p01 := b + d0 * r1
		var p11 := b + d1 * r1
		var u0 := float(i) / segs * 2.0
		var u1 := float(i + 1) / segs * 2.0
		var v := ln * 0.5
		var quad := [[p00, d0, Vector2(u0, 0)], [p01, d0, Vector2(u0, v)], [p11, d1, Vector2(u1, v)],
			[p00, d0, Vector2(u0, 0)], [p11, d1, Vector2(u1, v)], [p10, d1, Vector2(u1, 0)]]
		for q in quad:
			st.set_normal(q[1])
			st.set_uv(q[2])
			st.add_vertex(q[0])

## Quad card centred at c spanned by right/up (half-extents folded into the vectors).
static func card(st: SurfaceTool, c: Vector3, right: Vector3, up: Vector3, nrm: Vector3, col: Color) -> void:
	var p := [c - right - up, c + right - up, c + right + up, c - right + up]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(nrm)
		st.set_uv(uv[i])
		st.add_vertex(p[i])

# ---------- rocks ----------
static func rock(seed_v: int, subdiv: int = 2) -> ArrayMesh:
	var verts: Array = []
	var f := (1.0 + sqrt(5.0)) / 2.0
	for v in [Vector3(-1, f, 0), Vector3(1, f, 0), Vector3(-1, -f, 0), Vector3(1, -f, 0), Vector3(0, -1, f), Vector3(0, 1, f),
			Vector3(0, -1, -f), Vector3(0, 1, -f), Vector3(f, 0, -1), Vector3(f, 0, 1), Vector3(-f, 0, -1), Vector3(-f, 0, 1)]:
		verts.append(v.normalized())
	var tris: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in subdiv:
		var cache := {}
		var nt: Array = []
		for t in tris:
			var m: Array = []
			for k in 3:
				var a: int = t[k]
				var b: int = t[(k + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					verts.append(((verts[a] as Vector3) + (verts[b] as Vector3)).normalized())
					cache[key] = verts.size() - 1
				m.append(cache[key])
			nt.append([t[0], m[0], m[2]])
			nt.append([t[1], m[1], m[0]])
			nt.append([t[2], m[2], m[1]])
			nt.append([m[0], m[1], m[2]])
		tris = nt
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 1.3
	noise.fractal_octaves = 3
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var sq := Vector3(r.randf_range(0.9, 1.4), r.randf_range(0.6, 0.95), r.randf_range(0.9, 1.4))
	var pts: Array = []
	for v in verts:
		var d: Vector3 = v
		var rad := 1.0 + noise.get_noise_3dv(d * 2.0) * 0.45
		var p := d * rad
		p.y = maxf(p.y, -0.55)            # flattened underside
		pts.append(Vector3(p.x * sq.x, p.y * sq.y, p.z * sq.z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)               # flat facets = chiselled rock look
	for t in tris:
		for k in [0, 1, 2]:
			st.add_vertex(pts[t[k]])
	st.generate_normals()
	return st.commit()

# ---------- trees ----------
## species: 0 pine, 1 oak, 2 apple, 3 olive, 4 palm. Returns mesh with surface 0 = bark, surface 1 = leaves.
static func tree(species: int, seed_v: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 31 + species
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf := SurfaceTool.new()
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	match species:
		0: _pine(wood, leaf, r)
		4: _palm(wood, leaf, r)
		_: _broadleaf(wood, leaf, r, species)
	wood.generate_tangents()   # bark normal map needs tangents
	var mesh := wood.commit()
	mesh = leaf.commit(mesh)
	mesh.surface_set_material(0, M.pbr("bark", Color(0.85, 0.8, 0.75), 0.6, 0.95, false))
	var names: Array = ["leaf_pine", "leaf_oak", "leaf_apple", "leaf_olive", "leaf_palm"]
	mesh.surface_set_material(1, M.leaf(names[species]))
	return mesh

static func _shade(r: RandomNumberGenerator, base: Color) -> Color:
	var k := r.randf_range(0.8, 1.15)
	return Color(base.r * k, base.g * k, base.b * k)

static func _pine(wood: SurfaceTool, leaf: SurfaceTool, r: RandomNumberGenerator) -> void:
	var h := r.randf_range(7.5, 9.5)
	cyl(wood, Vector3(0, -0.2, 0), Vector3(0, h, 0), 0.34, 0.05, 8)
	var tiers := 9
	for t in tiers:
		var f := float(t) / (tiers - 1)
		var y := 1.6 + f * (h - 2.4)
		var rad := lerpf(2.5, 0.5, f)
		var n := 6
		for i in n:
			var a := TAU * (i + r.randf() * 0.5 + t * 0.37) / n
			var dir := Vector3(cos(a), 0, sin(a))
			var tilt := -0.55
			var out := (dir + Vector3(0, tilt, 0)).normalized()
			var c := Vector3(0, y, 0) + dir * rad * 0.62
			var right := dir.cross(Vector3.UP).normalized() * rad * 0.62
			var up := out * rad * 0.7
			card(leaf, c, right, up, Vector3(dir.x, 0.6, dir.z).normalized(), _shade(r, Color(0.9, 1.0, 0.9)))

static func _broadleaf(wood: SurfaceTool, leaf: SurfaceTool, r: RandomNumberGenerator, species: int) -> void:
	var ths: Array = [0.0, 3.4, 2.4, 1.8]
	var crs: Array = [0.0, 2.9, 2.1, 2.2]
	var th: float = ths[species]
	var crown_r: float = crs[species]
	var lean := Vector3(r.randf_range(-0.25, 0.25), 0, r.randf_range(-0.25, 0.25)) * (2.0 if species == 3 else 0.6)
	var top := Vector3(0, th, 0) + lean
	cyl(wood, Vector3(0, -0.25, 0), top, 0.42 if species != 3 else 0.5, 0.2, 8)
	# root flare
	for i in 5:
		var a := TAU * i / 5.0 + r.randf() * 0.5
		cyl(wood, Vector3(cos(a), 0.0, sin(a)) * 0.6 + Vector3(0, -0.1, 0), Vector3(cos(a), 0.55, sin(a)) * 0.2, 0.1, 0.18, 5)
	var centre := top + Vector3(0, crown_r * 0.55, 0)
	var nb := 6 if species != 3 else 4
	for i in nb:
		var a := TAU * i / nb + r.randf() * 0.6
		var end := centre + Vector3(cos(a) * crown_r * 0.62, r.randf_range(-0.2, 0.5) * crown_r, sin(a) * crown_r * 0.62)
		cyl(wood, top - Vector3(0, 0.2, 0), end, 0.16, 0.05, 5)
	var counts: Array = [0, 34, 26, 30]
	var cols: Array = [Color.WHITE, Color(0.95, 1.0, 0.92), Color(1.0, 1.0, 0.95), Color(0.95, 1.0, 0.95)]
	var count: int = counts[species]
	var base_col: Color = cols[species]
	for i in count:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.55, 1.0), r.randf_range(-1, 1))
		if species == 3:
			d.y *= 0.55
		d = d.normalized() * pow(r.randf(), 0.45)
		var c := centre + d * crown_r
		var ang := r.randf() * TAU
		var tilt := r.randf_range(0.0, 1.2)
		var right := Vector3(cos(ang), 0, sin(ang)) * crown_r * 0.46
		var up := (Vector3(-sin(ang), 0, cos(ang)) * cos(tilt) + Vector3.UP * sin(tilt)) * crown_r * 0.46
		card(leaf, c, right, up, (c - centre).normalized() * 0.8 + Vector3.UP * 0.4, _shade(r, base_col))

static func _palm(wood: SurfaceTool, leaf: SurfaceTool, r: RandomNumberGenerator) -> void:
	var h := r.randf_range(6.0, 7.5)
	var bend := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * 0.9
	var prev := Vector3(0, -0.2, 0)
	for i in range(1, 7):
		var t := float(i) / 6.0
		var p := Vector3(0, h * t, 0) + bend * t * t
		cyl(wood, prev, p, lerpf(0.3, 0.17, t), lerpf(0.3, 0.17, minf(1.0, t + 0.17)), 8)
		prev = p
	var top := prev
	for i in 9:
		var a := TAU * i / 9.0 + r.randf() * 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var droop := r.randf_range(0.25, 0.55)
		var out := (dir + Vector3(0, 0.55 - droop, 0)).normalized()
		var length := r.randf_range(2.6, 3.3)
		var c := top + out * length * 0.5 + Vector3(0, -droop * 0.6, 0)
		var right := out * length * 0.5
		var up := dir.cross(Vector3.UP).normalized() * 0.95
		card(leaf, c, right, up, Vector3(0, 1, 0), _shade(r, Color(0.95, 1.0, 0.9)))

# ---------- grass tuft (two crossed cards) ----------
static func tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
		var right := Vector3(cos(a), 0, sin(a)) * 0.45
		card(st, Vector3(0, 0.42, 0), right, Vector3(0, 0.42, 0), Vector3(0, 1, 0), Color.WHITE)
	var mesh := st.commit()
	mesh.surface_set_material(0, M.leaf("grass_tuft"))
	return mesh
