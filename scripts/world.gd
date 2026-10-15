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
	return noise.get_noise_2d(x, z) * 14.0 * f

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
		var p := Vector2(rng.randf_range(-92, 92), rng.randf_range(-92, 92))
		var s := rng.randf_range(0.8, 1.5)
		if p.length() < 24.0 or removed.has(i):
			continue
		_tree(Vector3(p.x, height_at(p.x, p.y), p.y), i, s)
	for i in 60:
		var p := Vector2(rng.randf_range(-92, 92), rng.randf_range(-92, 92))
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

func _tree(pos: Vector3, id: int, s: float) -> void:
	var b := StaticBody3D.new()
	b.position = pos
	b.add_to_group("tree")
	b.set_meta("id", id)
	b.set_meta("hp", 3)
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18 * s
	cm.bottom_radius = 0.28 * s
	cm.height = 2.4 * s
	trunk.mesh = cm
	trunk.position.y = 1.2 * s
	trunk.material_override = _mat(Color(0.35, 0.22, 0.12))
	var crown := MeshInstance3D.new()
	var cn := CylinderMesh.new()
	cn.top_radius = 0.0
	cn.bottom_radius = 1.5 * s
	cn.height = 3.5 * s
	crown.mesh = cn
	crown.position.y = 3.6 * s
	crown.material_override = _mat(Color(0.12, 0.33, 0.14))
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.3 * s
	sh.height = 2.4 * s
	cs.shape = sh
	cs.position.y = 1.2 * s
	for x in [trunk, crown, cs]:
		b.add_child(x)
	add_child(b)
	tree_meshes.append(trunk)
	tree_meshes.append(crown)

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
	mm.instance_count = 3000
	for i in 3000:
		var x := rng.randf_range(-70, 70)
		var z := rng.randf_range(-70, 70)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, height_at(x, z) + 0.3, z))
		mm.set_instance_transform(i, t)
	grass_node = MultiMeshInstance3D.new()
	grass_node.multimesh = mm
	grass_node.material_override = _mat(Color(0.25, 0.5, 0.18))
	grass_node.visibility_range_end = 45.0
	add_child(grass_node)

func apply_quality(q: int) -> void:
	var dist: float = [35.0, 60.0, 100.0][q]
	for m in tree_meshes:
		if is_instance_valid(m):
			m.visibility_range_end = dist
	if grass_node:
		grass_node.visible = q >= 1
