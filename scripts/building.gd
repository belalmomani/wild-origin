extends Node3D
## Spawns real 3D stone pieces for puzzle boards; progress is stored in GameState.placed.
signal message(text: String)
const D := preload("res://scripts/building_data.gd")
const M := preload("res://scripts/mats.gd")
var boards: Array = []

func _ready() -> void:
	boards = D.make_boards()
	for b in boards:
		for p in b.pieces:
			if GameState.placed.has(p.id):
				_spawn(p)

func remaining(bi: int) -> int:
	var n := 0
	for p in boards[bi].pieces:
		if not GameState.placed.has(p.id):
			n += 1
	return n

func current_index() -> int:
	for i in boards.size():
		if remaining(i) > 0:
			return i
	return -1

func place(bi: int, pi: int) -> bool:
	var p: Dictionary = boards[bi].pieces[pi]
	if GameState.placed.has(p.id):
		return false
	if not GameState.spend(p.cost, 1):
		message.emit("ينقصك %s — اجمع المزيد" % ("حجارة" if p.cost == "stone" else "خشب"))
		return false
	GameState.placed[p.id] = true
	GameState.xp += 1
	_spawn(p)
	return true

func _spawn(p: Dictionary) -> void:
	var mesh := _extrude(p.mesh_poly, p.thick)
	if mesh == null:
		return
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var tint: Color = D.piece_color(p).lightened(0.45)
	var m: StandardMaterial3D = M.pbr("rock" if p.cost == "stone" else "bark", tint, 0.6 if p.cost == "stone" else 1.2, 0.95, true).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape()
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)
	body.transform = p.xf

func _extrude(poly: PackedVector2Array, t: float) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.size() < 3:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := t * 0.5
	st.set_normal(Vector3(0, 0, 1))
	for k in idx:
		st.add_vertex(Vector3(poly[k].x, poly[k].y, h))
	st.set_normal(Vector3(0, 0, -1))
	for k in idx:
		st.add_vertex(Vector3(poly[k].x, poly[k].y, -h))
	var area := 0.0
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var sg := 1.0 if area > 0.0 else -1.0
	for k in poly.size():
		var a2 := poly[k]
		var b2 := poly[(k + 1) % poly.size()]
		var e := b2 - a2
		st.set_normal(Vector3(e.y, -e.x, 0.0).normalized() * sg)
		var a0 := Vector3(a2.x, a2.y, h)
		var a1 := Vector3(a2.x, a2.y, -h)
		var b0 := Vector3(b2.x, b2.y, h)
		var b1 := Vector3(b2.x, b2.y, -h)
		for v in [a0, b0, b1, a0, b1, a1]:
			st.add_vertex(v)
	return st.commit()
