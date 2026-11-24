extends Node3D
## Spawns real 3D stone pieces for puzzle boards; progress is stored in GameState.placed.
signal message(text: String)
const D := preload("res://scripts/building_data.gd")
const M := preload("res://scripts/mats.gd")
var boards: Array = []
var pivots := {}      # "group:leaf" -> Node3D hinge (house door, fence gate leaves, farm gate leaves)
var opened := {}      # group -> bool

func _ready() -> void:
	boards = D.make_boards()
	for b in boards:
		for p in b.pieces:
			if GameState.placed.has(p.id):
				_spawn(p)
	_update_progress()

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
	if id.begins_with("I_") or id.begins_with("M_"):
		return shell_done()
	if id.begins_with("G_"):
		return board_done("S0")
	if id.begins_with("R_"):
		return GameState.channel          # the rod and dock come after the wooden channel to the lake
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
	return group_complete("house")

func group_complete(g: String) -> bool:
	return board_done(str(D.DOORS[g]["board"]))

func is_open(g: String) -> bool:
	return bool(opened.get(g, false))

func farm_done() -> bool:
	for id in ["M_S0", "M_S1", "M_S2", "M_S3", "M_gate"]:
		if not board_done(id):
			return false
	return true

func _pivot(group: String, leaf: String, hinge: Vector3, angle: float) -> Node3D:
	var key := group + ":" + leaf
	if pivots.has(key):
		return pivots[key]
	var n := Node3D.new()
	n.position = hinge
	n.set_meta("group", group)
	n.set_meta("angle", angle)
	add_child(n)
	pivots[key] = n
	return n

## Open/close a hinged door or gate group ("house", "fence", "farm"). Returns "open", "closed", "blocked" or "no".
func toggle_group(g: String, pos: Vector3) -> String:
	if not group_complete(g):
		return "no"
	var info: Dictionary = D.DOORS[g]
	var rel: Vector3 = pos - (info["c"] as Vector3)
	rel.y = 0.0
	if is_open(g) and rel.length() < float(info["block"]) and rel.dot(info["out"] as Vector3) > -0.35:
		return "blocked"      # standing where the leaf would sweep through
	var now_open := not is_open(g)
	opened[g] = now_open
	for key in pivots:
		var node: Node3D = pivots[key]
		if str(node.get_meta("group")) != g:
			continue
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(node, "rotation:y", float(node.get_meta("angle")) if now_open else 0.0, 0.6)
		if now_open:
			_door_collision(node, false)
		else:
			t.tween_callback(_door_collision.bind(node, true))
	return "open" if now_open else "closed"

func _door_collision(node: Node3D, on: bool) -> void:
	for c in node.get_children():
		if c is StaticBody3D:
			(c as StaticBody3D).collision_layer = 1 if on else 0

func place(bi: int, pi: int) -> bool:
	var p: Dictionary = boards[bi].pieces[pi]
	if GameState.placed.has(p.id):
		return false
	var free := GameState.has_tech("build_save") and GameState.placed.size() % 2 == 1
	if not free:
		# every finished build makes the next ones 1% harder: the price per piece grows (fractions accumulate)
		var acc: float = GameState.cost_acc + GameState.difficulty()
		var take := int(acc)
		if GameState.count(p.cost) < take:
			message.emit("ينقصك %s — تحتاج %d للقطعة (الصعوبة +%d%%)" % ["حجارة" if p.cost == "stone" else "خشب", take, GameState.difficulty_pct()])
			return false
		GameState.spend(p.cost, take)
		GameState.cost_acc = acc - float(take)
	GameState.placed[p.id] = true
	GameState.xp += 1
	_spawn(p)
	if remaining(bi) == 0:
		_update_progress()
	return true

## Finished builds raise the difficulty by 1% each (counted from the first time this save was seen).
func _update_progress() -> void:
	var done := 0
	for i in boards.size():
		if remaining(i) == 0:
			done += 1
	if GameState.diff_base < 0:
		GameState.diff_base = done
	GameState.builds_done = maxi(0, done - GameState.diff_base)

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
	var grp := str(p.get("door", ""))
	if grp != "":
		var hinge: Vector3 = p["hinge"]
		var pv := _pivot(grp, str(p["leaf"]), hinge, float(p["angle"]))
		body.transform = Transform3D(xf.basis, xf.origin - hinge)
		pv.add_child(body)
		if is_open(grp):
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
