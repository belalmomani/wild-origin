extends Node3D
## World: splat-textured terrain (shader), detailed trees/rocks (mesh_gen), grass tufts. Bounded by a mountain ring.
const HALF := 100.0
const CELL := 2.0
const M := preload("res://scripts/mats.gd")
const G := preload("res://scripts/mesh_gen.gd")
const D := preload("res://scripts/building_data.gd")
var noise := FastNoiseLite.new()
var patch := FastNoiseLite.new()
var tree_meshes: Array = []
var grass_node: MultiMeshInstance3D
var flowers_node: MultiMeshInstance3D
var _tree_variants: Array = []   # [species][variant] -> ArrayMesh
var _rock_variants: Array = []

func height_at(x: float, z: float) -> float:
	var f := smoothstep(26.0, 50.0, Vector2(x, z).length())  # flat build area near origin
	var edge := smoothstep(70.0, 98.0, maxf(absf(x), absf(z)))  # mountain ring = world boundary
	var h := noise.get_noise_2d(x, z) * 15.0 * f + edge * (24.0 + noise.get_noise_2d(x * 2.0, z * 2.0) * 7.0)
	var ld := Vector2(x - D.POND_C.x, z - D.POND_C.z).length()
	if ld < D.POND_R + 10.0:                   # lake: flat shore around it, a deep basin carved into the ground
		h = lerpf(h, 0.0, 1.0 - smoothstep(D.POND_R + 1.0, D.POND_R + 10.0, ld))
		h -= D.POND_DEPTH * (1.0 - smoothstep(D.POND_R * 0.35, D.POND_R + 1.0, ld))
	return h

func build(removed: Dictionary) -> void:
	noise.seed = 1337
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	patch.seed = 99
	patch.frequency = 0.05
	_terrain()
	for sp in 5:
		var vs: Array = []
		for v in 3:
			vs.append(G.tree(sp, v + 1))
		_tree_variants.append(vs)
	for i in 6:
		_rock_variants.append(G.rock(500 + i, 2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 200:
		var p := Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))   # 50% closer than before (was +-80)
		var s := rng.randf_range(0.85, 1.35)
		if p.length() < 20.0 or removed.has(i) or _in_lake(p, 3.5):
			continue
		_tree(Vector3(p.x, height_at(p.x, p.y), p.y), i, s, rng.randf() * TAU)
	for i in 70:
		var p := Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		var sc := rng.randf_range(0.9, 1.8)
		if p.length() < 20.0 or removed.has(1000 + i) or _in_lake(p, 3.0):
			continue
		_rock(Vector3(p.x, height_at(p.x, p.y), p.y), 1000 + i, sc, rng.randf() * TAU)
	_grass(rng)
	_lake_shore(removed)

func _weights(x: float, z: float, h: float) -> Color:
	var sx := (height_at(x + 1.0, z) - height_at(x - 1.0, z)) * 0.5
	var sz := (height_at(x, z + 1.0) - height_at(x, z - 1.0)) * 0.5
	var slope := Vector2(sx, sz).length()
	var n1 := patch.get_noise_2d(x, z) * 0.5 + 0.5
	var n2 := patch.get_noise_2d(x + 300.0, z - 200.0) * 0.5 + 0.5
	var rock := clampf(smoothstep(0.55, 1.1, slope) + smoothstep(9.0, 14.0, h), 0.0, 1.0)
	var dirt := smoothstep(0.62, 0.78, n1) * 0.9
	dirt = maxf(dirt, 1.0 - smoothstep(D.POND_R * 0.7, D.POND_R + 1.5, Vector2(x - D.POND_C.x, z - D.POND_C.z).length()))
	var site := 1.0 - smoothstep(7.0, 12.0, Vector2(x, z).length())   # packed earth around the build site
	dirt = maxf(dirt, site)
	var gravel := smoothstep(0.66, 0.8, n2) * 0.8
	var grass := maxf(0.05, 1.0 - maxf(dirt, gravel) - rock)
	return Color(grass, dirt, gravel, rock)

func _terrain() -> void:
	var n := int(HALF * 2.0 / CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in n:
			var x0 := -HALF + i * CELL
			var z0 := -HALF + j * CELL
			var p := [Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0, 0, z0 + CELL)]
			var c := []
			for k in 4:
				p[k].y = height_at(p[k].x, p[k].z)
				c.append(_weights(p[k].x, p[k].z, p[k].y))
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(c[idx])
				st.add_vertex(p[idx])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, M.terrain())
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)

func _tree(pos: Vector3, id: int, s: float, yaw: float) -> void:
	var k := id % 20
	var sp := 0 if k < 7 else (1 if k < 12 else (2 if k < 14 else (3 if k < 17 else 4)))
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation.y = yaw
	b.add_to_group("tree")
	b.set_meta("id", id)
	b.set_meta("hp", 3)
	var mi := MeshInstance3D.new()
	mi.mesh = _tree_variants[sp][id % 3]
	mi.scale = Vector3.ONE * s
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.4 * s
	sh.height = 3.0 * s
	cs.shape = sh
	cs.position.y = 1.5 * s
	b.add_child(cs)
	add_child(b)
	tree_meshes.append(mi)

func _rock(pos: Vector3, id: int, sc: float, yaw: float) -> void:
	var b := StaticBody3D.new()
	b.position = pos + Vector3(0, sc * 0.45, 0)
	b.rotation.y = yaw
	b.add_to_group("rock")
	b.set_meta("id", id)
	b.set_meta("hp", 3)
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_variants[id % 6]
	mi.scale = Vector3.ONE * sc
	mi.material_override = M.pbr("rock", Color(1, 1, 1).darkened((id % 4) * 0.08), 0.45, 0.95, true)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.85 * sc
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	tree_meshes.append(mi)

## True if the ground point (x, z) is on the lake or its shore margin (no trees / rocks / grass there).
func _in_lake(p: Vector2, margin: float) -> bool:
	return Vector2(p.x - D.POND_C.x, p.y - D.POND_C.z).length() < D.POND_R + margin

## Pines and boulders framing the lake, reeds and wild flowers along its shore (the side facing the house stays open).
func _lake_shore(removed: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var c := Vector2(D.POND_C.x, D.POND_C.z)
	var home_a := atan2(-c.y, -c.x)                      # direction from the lake to the house
	var pines := [0, 1, 2, 3, 4, 5, 6, 0, 1, 2, 3, 4, 5, 7, 9]   # id % 20: mostly pines, a few broadleaf
	var n := 0
	for k in 60:
		var a := rng.randf() * TAU
		var r := D.POND_R + rng.randf_range(4.5, 17.0)
		var id: int = 2000 + k * 20 + int(pines[k % pines.size()])
		if absf(angle_difference(a, home_a)) < 0.8 or removed.has(id):
			continue
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		if Vector2(x, z).length() < 22.0 or absf(x) > 66.0 or absf(z) > 66.0:
			continue
		_tree(Vector3(x, height_at(x, z), z), id, rng.randf_range(0.9, 1.5), rng.randf() * TAU)
		n += 1
	for k in 9:                                           # boulders on the shore
		var a := rng.randf() * TAU
		var r := D.POND_R + rng.randf_range(1.4, 6.0)
		if absf(angle_difference(a, home_a)) < 0.7 or removed.has(3000 + k):
			continue
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		_rock(Vector3(x, height_at(x, z), z), 3000 + k, rng.randf_range(0.9, 1.7), rng.randf() * TAU)
	var tuft := MultiMesh.new()                           # reeds / tall grass at the water's edge
	tuft.transform_format = MultiMesh.TRANSFORM_3D
	tuft.mesh = G.tuft()
	var lup := MultiMesh.new()                            # purple lupines
	lup.transform_format = MultiMesh.TRANSFORM_3D
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 0.5
	cone.radial_segments = 6
	lup.mesh = cone
	var dai := MultiMesh.new()                            # white daisies
	dai.transform_format = MultiMesh.TRANSFORM_3D
	var ds := SphereMesh.new()
	ds.radius = 0.09
	ds.height = 0.07
	ds.radial_segments = 6
	ds.rings = 3
	dai.mesh = ds
	var tf: Array = []
	var lf: Array = []
	var df: Array = []
	for i in 420:
		var a := rng.randf() * TAU
		if absf(angle_difference(a, home_a)) < 0.35:
			continue
		var r := D.POND_R + rng.randf_range(-0.8, 9.0)
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		var y := height_at(x, z)
		if y < D.WATER_Y + 0.12:
			continue
		var bs := Basis(Vector3.UP, rng.randf() * TAU)
		if r < D.POND_R + 1.6:
			tf.append(Transform3D(bs.scaled(Vector3.ONE * rng.randf_range(1.2, 2.0)), Vector3(x, y, z)))
		elif i % 3 == 0:
			lf.append(Transform3D(bs, Vector3(x, y + 0.25, z)))
		elif i % 3 == 1:
			df.append(Transform3D(bs, Vector3(x, y + 0.08, z)))
		else:
			tf.append(Transform3D(bs.scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), Vector3(x, y, z)))
	for pair in [[tuft, tf, null], [lup, lf, Color(0.55, 0.3, 0.85)], [dai, df, Color(0.97, 0.97, 0.92)]]:
		var mm: MultiMesh = pair[0]
		var arr: Array = pair[1]
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		if pair[2] != null:
			mi.material_override = M.flat(pair[2], 0.9)
		mi.visibility_range_end = 70.0
		add_child(mi)

func _grass(rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = G.tuft()
	var pts: Array = []
	var guard := 0
	while pts.size() < 3500 and guard < 20000:
		guard += 1
		var x := rng.randf_range(-75, 75)
		var z := rng.randf_range(-75, 75)
		var h := height_at(x, z)
		var w := _weights(x, z, h)
		if w.a > 0.4 or w.g > 0.6 or w.b > 0.6 or _in_lake(Vector2(x, z), 1.0):
			continue
		pts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), Vector3(x, h, z)))
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, pts[i])
	grass_node = MultiMeshInstance3D.new()
	grass_node.multimesh = mm
	grass_node.visibility_range_end = 45.0
	add_child(grass_node)
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	var fs := SphereMesh.new()
	fs.radius = 0.07
	fs.height = 0.14
	fs.radial_segments = 6
	fs.rings = 3
	fm.mesh = fs
	fm.instance_count = 400
	for i in 400:
		var fx := rng.randf_range(-70, 70)
		var fz := rng.randf_range(-70, 70)
		fm.set_instance_transform(i, Transform3D(Basis(), Vector3(fx, height_at(fx, fz) + 0.5, fz)))
	flowers_node = MultiMeshInstance3D.new()
	flowers_node.multimesh = fm
	flowers_node.material_override = M.flat(Color(0.95, 0.95, 0.85))
	flowers_node.visibility_range_end = 30.0
	add_child(flowers_node)

func apply_quality(q: int) -> void:
	var dist: float = [40.0, 70.0, 110.0][q]
	for m in tree_meshes:
		if is_instance_valid(m):
			m.visibility_range_end = dist
	if grass_node:
		grass_node.visible = q >= 1
		grass_node.visibility_range_end = 35.0 if q == 1 else 55.0
	if flowers_node:
		flowers_node.visible = q >= 1
