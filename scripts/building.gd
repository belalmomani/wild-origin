extends Node3D
## Spawns real 3D stone pieces for puzzle boards; progress is stored in GameState.placed.
signal message(text: String)
const D := preload("res://scripts/building_data.gd")
const M := preload("res://scripts/mats.gd")
var boards: Array = []
var door_pivot: Node3D
var door_open := false

func _ready() -> void:
	boards = D.make_boards()
	door_pivot = Node3D.new()      # the house door: its pieces hang here and swing on the hinge
	door_pivot.position = D.DOOR_HINGE
	add_child(door_pivot)
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

func barn_done() -> bool:
	for i in boards.size():
		if str(boards[i].id).begins_with("B") and remaining(i) > 0:
			return false
	return true

func index_of(id: String) -> int:
	for i in boards.size():
		if str(boards[i].id) == id:
			return i
	return -1

func board_done(id: String) -> bool:
	var i := index_of(id)
	return i >= 0 and remaining(i) == 0

## House shell finished (4 facades + roof): the interior boards open up.
func shell_done() -> bool:
	for id in ["F0", "F1", "F2", "F3", "ROOF"]:
		if not board_done(id):
			return false
	return true

func available(i: int) -> bool:
	var id := str(boards[i].id)
	if id.begins_with("B"):
		return GameState.barn_unlocked
	if id.begins_with("I_"):
		return shell_done()
	return true

func current_index() -> int:
	for i in boards.size():
		if available(i) and remaining(i) > 0:
			return i
	return -1

## Next unfinished, available board after `cur` (wraps around). -1 if none.
func next_available(cur: int) -> int:
	for k in range(1, boards.size() + 1):
		var i := (cur + k) % boards.size()
		if available(i) and remaining(i) > 0:
			return i
	return -1

func next_cost(bi: int) -> String:
	for p in boards[bi].pieces:
		if not GameState.placed.has(p.id):
			return str(p.cost)
	return "wood"

func door_complete() -> bool:
	return board_done("I_door")

## Open/close the house door. Returns "open", "closed", "blocked" or "no" (door not built yet).
func toggle_door(pos: Vector3) -> String:
	if not door_complete():
		return "no"
	if door_open and absf(pos.x) < 1.2 and pos.z > 1.6 and pos.z < 3.3:
		return "blocked"      # standing where the leaf would swing through
	door_open = not door_open
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(door_pivot, "rotation:y", -1.75 if door_open else 0.0, 0.6)
	if door_open:
		_door_collision(false)
	else:
		t.tween_callback(func(): _door_collision(true))
	return "open" if door_open else "closed"

func _door_collision(on: bool) -> void:
	for c in door_pivot.get_children():
		if c is StaticBody3D:
			(c as StaticBody3D).collision_layer = 1 if on else 0

func place(bi: int, pi: int) -> bool:
	var p: Dictionary = boards[bi].pieces[pi]
	if GameState.placed.has(p.id):
		return false
	var free := GameState.has_tech("build_save") and GameState.placed.size() % 2 == 1
	if not free and not GameState.spend(p.cost, 1):
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
	var is_stone: bool = p.cost == "stone"
	var tname: String = str(p.get("tex", "rock" if is_stone else "planks"))
	var m: StandardMaterial3D = M.pbr(tname, tint, 0.6 if is_stone else 0.8, 0.9, true).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if p.get("emit", false):
		m.emission_enabled = true
		m.emission = Color(1.0, 0.8, 0.45)
		m.emission_energy_multiplier = 2.0
	mi.material_override = m
	body.add_child(mi)
	if not p.get("nocol", false):
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_convex_shape()
		body.add_child(cs)
	var xf: Transform3D = p.xf
	if p.get("door", false):
		body.transform = Transform3D(xf.basis, xf.origin - D.DOOR_HINGE)
		door_pivot.add_child(body)
		if door_open:
			body.collision_layer = 0
	else:
		add_child(body)
		body.transform = xf

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
