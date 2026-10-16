extends Node3D
## Procedural terrain, trees, rocks, grass. No external assets -> no licensing issues.
const HALF := 100.0
const CELL := 2.0
var noise := FastNoiseLite.new()
var tree_meshes: Array = []
var grass_node: MultiMeshInstance3D
var _mats := {}

func height_at(x: float, z: float) -> float:
	var f := smoothstep(26.0, 50.0, Vector2(x, z).length())  # flat build area near origin
	var edge := smoothstep(70.0, 98.0, maxf(absf(x), absf(z)))  # mountain ring = world boundary
	return noise.get_noise_2d(x, z) * 14.0 * f + edge * (22.0 + noise.get_noise_2d(x * 2.0, z * 2.0) * 6.0)

func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_mats[c] = m
	return _mats[c]

func build(removed: Dictionary) -> void:
	noise.seed = 1337
	noise.frequency = 0.012
	_terrain()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 170:
		var p := Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
		var s := rng.randf_range(0.8, 1.5)
		if p.length() < 24.0 or removed.has(i):
			continue
		_tree(Vector3(p.x, height_at(p.x, p.y), p.y), i, s)
	for i in 60:
		var p := Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
		var sc := Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.5, 1.0), rng.randf_range(0.7, 1.4))
		if p.length() < 24.0 or removed.has(1000 + i):
			continue
		_rock(Vector3(p.x, height_at(p.x, p.y), p.y), 1000 + i, sc)
	_grass(rng)

func _col(p: Vector3) -> Color:
	var n := noise.get_noise_2d(p.x * 3.1, p.z * 3.1) * 0.5 + 0.5
	var g := Color(0.20, 0.40, 0.14).lerp(Color(0.32, 0.50, 0.20), n)
	return g.lerp(Color(0.46, 0.43, 0.40), smoothstep(5.0, 9.0, p.y))

func _terrain() -> void:
	var n := int(HALF * 2.0 / CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in n:
			var x0 := -HALF + i * CELL
			var z0 := -HALF + j * CELL
			var p := [Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0, 0, z0 + CELL)]
			for k in 4:
				p[k].y = height_at(p[k].x, p[k].z)
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(_col(p[idx]))
				st.add_vertex(p[idx])
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mesh.surface_set_material(0, m)
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)

func _blob(b: Node3D, pos: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = 2.0 * r
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c)
	b.add_child(mi)
	tree_meshes.append(mi)

func _tree(pos: Vector3, id: int, s: float) -> void:
	var v := id % 6   # 0 green, 1 autumn-yellow, 2 pine, 3 blossom, 4 palm, 5 red-orange
	var b := StaticBody3D.new()
	b.position = pos
	b.add_to_group("tree")
	b.set_meta("id", id)
	b.set_meta("hp", 3)
	var th := 4.6 * s if v == 4 else 2.6 * s
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = (0.12 if v == 4 else 0.2) * s
	cm.bottom_radius = (0.2 if v == 4 else 0.34) * s
	cm.height = th
	trunk.mesh = cm
	trunk.position.y = th * 0.5
	trunk.material_override = _mat(Color(0.36, 0.24, 0.14))
	b.add_child(trunk)
	tree_meshes.append(trunk)
	var top := th
	match v:
		2:
			for k in 3:
				var cn := MeshInstance3D.new()
				var m := CylinderMesh.new()
				m.top_radius = 0.0
				m.bottom_radius = (1.6 - k * 0.4) * s
				m.height = 2.0 * s
				cn.mesh = m
				cn.position.y = top * 0.6 + k * 1.2 * s + 0.8 * s
				cn.material_override = _mat(Color(0.1, 0.3, 0.16))
				b.add_child(cn)
				tree_meshes.append(cn)
		4:
			for k in 6:
				var fr := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(2.0 * s, 0.05, 0.4 * s)
				fr.mesh = bm
				fr.position = Vector3(0, top, 0)
				fr.rotation = Vector3(0, k * TAU / 6.0, 0.0)
				fr.rotate_object_local(Vector3(0, 0, 1), -0.35)
				fr.translate_object_local(Vector3(1.0 * s, 0, 0))
				fr.material_override = _mat(Color(0.2, 0.5, 0.18))
				b.add_child(fr)
				tree_meshes.append(fr)
		_:
			var c := [Color(0.16, 0.4, 0.15), Color(0.85, 0.65, 0.12), Color(0), Color(0.9, 0.87, 0.78), Color(0), Color(0.75, 0.28, 0.12)][v]
			_blob(b, Vector3(0, top + 0.9 * s, 0), 1.6 * s, c)
			_blob(b, Vector3(1.0 * s, top + 0.3 * s, 0.4 * s), 1.1 * s, c.darkened(0.1))
			_blob(b, Vector3(-0.9 * s, top + 0.4 * s, -0.5 * s), 1.2 * s, c.lightened(0.08))
			_blob(b, Vector3(0.2 * s, top + 1.8 * s, -0.3 * s), 1.0 * s, c.lightened(0.04))
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.3 * s
	sh.height = th
	cs.shape = sh
	cs.position.y = th * 0.5
	b.add_child(cs)
	add_child(b)

func _rock(pos: Vector3, id: int, sc: Vector3) -> void:
	var b := StaticBody3D.new()
	b.position = pos + Vector3(0, sc.y * 0.4, 0)
	b.add_to_group("rock")
	b.set_meta("id", id)
	b.set_meta("hp", 3)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.scale = sc
	mi.material_override = _mat(Color(0.48, 0.48, 0.5))
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.8 * maxf(sc.x, sc.z)
	cs.shape = sh
	b.add_child(mi)
	b.add_child(cs)
	add_child(b)
	tree_meshes.append(mi)

func _grass(rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var blade := PrismMesh.new()
	blade.size = Vector3(0.15, 0.6, 0.02)
	mm.mesh = blade
	mm.instance_count = 5000
	for i in 5000:
		var x := rng.randf_range(-70, 70)
		var z := rng.randf_range(-70, 70)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, height_at(x, z) + 0.3, z))
		mm.set_instance_transform(i, t)
	grass_node = MultiMeshInstance3D.new()
	grass_node.multimesh = mm
	grass_node.material_override = _mat(Color(0.25, 0.5, 0.18))
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
	fm.instance_count = 500
	for i in 500:
		var fx := rng.randf_range(-70, 70)
		var fz := rng.randf_range(-70, 70)
		fm.set_instance_transform(i, Transform3D(Basis(), Vector3(fx, height_at(fx, fz) + 0.45, fz)))
	var fl := MultiMeshInstance3D.new()
	fl.multimesh = fm
	fl.material_override = _mat(Color(0.95, 0.95, 0.85))
	fl.visibility_range_end = 35.0
	add_child(fl)

func apply_quality(q: int) -> void:
	var dist: float = [35.0, 60.0, 100.0][q]
	for m in tree_meshes:
		if is_instance_valid(m):
			m.visibility_range_end = dist
	if grass_node:
		grass_node.visible = q >= 1
