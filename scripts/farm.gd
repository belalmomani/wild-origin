extends Node3D
## Apple orchard: plant, water daily, watch growth stages, harvest fruit. State lives in GameState.crops.
signal message(text: String)
const L := preload("res://scripts/farm_logic.gd")
const G := preload("res://scripts/mesh_gen.gd")
const M := preload("res://scripts/mats.gd")
const MAX_OFFLINE_HOURS := 48.0
var world
var nodes := {}
var tree_mesh: ArrayMesh
var wilt_mat: StandardMaterial3D
var dead_mat: StandardMaterial3D
var apple_mesh := SphereMesh.new()
var apple_mat: StandardMaterial3D

func _ready() -> void:
	tree_mesh = G.tree(2, 5)
	wilt_mat = M.leaf("leaf_apple").duplicate()
	wilt_mat.albedo_color = Color(0.85, 0.68, 0.4)
	dead_mat = M.leaf("leaf_apple").duplicate()
	dead_mat.albedo_color = Color(1, 1, 1, 0)    # alpha 0 => leaves vanish, bare trunk remains
	apple_mesh.radius = 0.11
	apple_mesh.height = 0.22
	apple_mesh.radial_segments = 8
	apple_mesh.rings = 4
	apple_mat = M.flat(Color(0.75, 0.08, 0.06), 0.4)
	for c in GameState.crops:
		_spawn(c)

func _now() -> float:
	return GameState.clock_hours / 24.0

func _spawn(c: Dictionary) -> void:
	var n := Node3D.new()
	var y := 0.0
	if world != null:
		y = world.height_at(c.x, c.z)
	n.position = Vector3(c.x, y, c.z)
	n.add_to_group("crop")
	n.set_meta("cid", int(c.id))
	var mound := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.38
	cm.height = 0.14
	cm.radial_segments = 10
	mound.mesh = cm
	mound.position.y = 0.05
	mound.material_override = M.pbr("dirt", Color(0.8, 0.7, 0.6), 1.0, 1.0, true)
	n.add_child(mound)
	var ti := MeshInstance3D.new()
	ti.name = "T"
	ti.mesh = tree_mesh
	n.add_child(ti)
	var fruit := Node3D.new()
	fruit.name = "F"
	ti.add_child(fruit)
	var r := RandomNumberGenerator.new()
	r.seed = int(c.id) * 977
	for i in 10:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.4, 1), r.randf_range(-1, 1)).normalized() * r.randf_range(1.2, 1.8)
		var a := MeshInstance3D.new()
		a.mesh = apple_mesh
		a.material_override = apple_mat
		a.position = Vector3(0, 3.3, 0) + d
		fruit.add_child(a)
	add_child(n)
	nodes[int(c.id)] = n
	_refresh(c)

func _refresh(c: Dictionary) -> void:
	var n: Node3D = nodes.get(int(c.id))
	if n == null:
		return
	var ti: MeshInstance3D = n.get_node("T")
	ti.visible = float(c.g) >= L.FIRST_SIGN_DAYS or bool(c.dead)
	ti.scale = Vector3.ONE * L.scale_of(c)
	if c.dead:
		ti.set_surface_override_material(1, dead_mat)
	elif float(c.h) <= 0.6 or L.moisture(c, _now()) < 0.2:
		ti.set_surface_override_material(1, wilt_mat)
	else:
		ti.set_surface_override_material(1, null)
	(n.get_node("T/F") as Node3D).visible = bool(c.fruit)

func refresh_all() -> void:
	for c in GameState.crops:
		_refresh(c)

func tick(dt_hours: float, offline: bool = false) -> void:
	var now := _now()
	var dt := dt_hours / 24.0
	for c in GameState.crops:
		var ev := L.step(c, now, dt, offline)
		if offline:
			continue
		match ev:
			"dry": message.emit("شجرة تفاح عطشى — اسقها اليوم قبل أن تتدهور!")
			"dying": message.emit("شجرة تفاح تتدهور! اسقها فورًا وإلا ستموت.")
			"dead": message.emit("ماتت شجرة تفاح. أزِلها ثم ازرع بذرة جديدة.")
			"fruit": message.emit("نضجت الثمار! اقترب من الشجرة واضغط «تفاعل».")
	if not offline and Engine.get_process_frames() % 30 == 0:
		refresh_all()

## Time away from the game: growth continues, trees can weaken but never die while you are away.
func advance_offline(hours: float) -> void:
	var left := minf(hours, MAX_OFFLINE_HOURS)
	while left > 0.0:
		var step := minf(1.0, left)
		GameState.clock_hours += step
		tick(step, true)
		left -= step
	refresh_all()
	for c in GameState.crops:
		if not c.dead and (float(c.h) < 1.0 or _now() - float(c.lw) >= L.WARN_DAYS):
			message.emit("مرّ وقت أثناء غيابك: تحقّق من أشجار التفاح واسقِها.")
			break

func _nearest(pos: Vector3, maxd: float) -> Dictionary:
	var best := {}
	var bd := maxd
	for c in GameState.crops:
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
		if d < bd:
			bd = d
			best = c
	return best

func plant(pos: Vector3) -> bool:
	if not _nearest(pos, 1.6).is_empty():
		message.emit("قريب جدًا من شجرة أخرى")
		return false
	if GameState.count("seeds") < 1:
		if GameState.spend("wood", 3):
			GameState.add("seeds", 1)
			message.emit("اشتريت بذرة تفاح (3 خشب)")
		else:
			message.emit("تحتاج بذرة تفاح — تُشترى بـ 3 خشب")
			return false
	GameState.spend("seeds", 1)
	var c := L.new_crop(GameState.next_crop_id, pos.x, pos.z, _now())
	GameState.next_crop_id += 1
	GameState.crops.append(c)
	_spawn(c)
	message.emit("زرعتَ بذرة تفاح. اسقها كل يوم!")
	return true

func water_near(pos: Vector3) -> bool:
	var c := _nearest(pos, 3.5)
	if c.is_empty() or c.dead:
		message.emit("لا توجد شجرة حية قريبة للسقي")
		return false
	L.water(c, _now())
	_refresh(c)
	message.emit("سقيتَ الشجرة ✓")
	return true

func interact(cid: int) -> void:
	var c := {}
	for x in GameState.crops:
		if int(x.id) == cid:
			c = x
	if c.is_empty():
		return
	if c.dead:
		GameState.crops.erase(c)
		var n: Node3D = nodes.get(cid)
		if n:
			n.queue_free()
		nodes.erase(cid)
		GameState.add("wood", 1)
		message.emit("أزلتَ الشجرة الميتة (+1 خشب). ازرع بذرة جديدة.")
	elif c.fruit:
		L.harvest(c, _now())
		GameState.add("apples", 3)
		var got_seed := randf() < 0.4
		if got_seed:
			GameState.add("seeds", 1)
		_refresh(c)
		GameState.xp += 2
		message.emit("+3 تفاح" + (" و+1 بذرة" if got_seed else ""))
	else:
		message.emit("%s — %s" % [L.stage(c), info_bars(c)])

func _bar(v: float) -> String:
	var n := int(round(clampf(v, 0.0, 1.0) * 10.0))
	return "█".repeat(n) + "░".repeat(10 - n)

func info_bars(c: Dictionary) -> String:
	var g := clampf(float(c.g) / L.FRUIT_DAYS, 0.0, 1.0)
	return "نمو %s %d%% | رطوبة %s | صحة %s%s" % [_bar(g), int(g * 100.0), _bar(L.moisture(c, _now())), _bar(float(c.h)), " | ثمار جاهزة!" if c.fruit else ""]

func info_text(pos: Vector3) -> String:
	var c := _nearest(pos, 5.0)
	if c.is_empty():
		return ""
	return "شجرة تفاح (%s)\n%s" % [L.stage(c), info_bars(c)]
