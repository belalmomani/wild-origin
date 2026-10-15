extends Node3D
## Piece-by-piece building: ghost preview, rotation, lift, snapping tolerance, hints, persistence.
signal message(text: String)
signal state_changed
const D := preload("res://scripts/building_data.gd")

var origin := Vector3(0, 0, -12)
var player
var slots: Array = []
var active := false
var type_idx := 0
var yaw := 0.0
var lift := 0.9
var ghost: MeshInstance3D
var marker: MeshInstance3D
var ghost_mat := StandardMaterial3D.new()
var ghost_type := ""
var last_match: Dictionary = {}
var hint_nodes: Array = []

func _ready() -> void:
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost = MeshInstance3D.new()
	ghost.visible = false
	ghost.material_override = ghost_mat
	add_child(ghost)
	marker = MeshInstance3D.new()
	marker.mesh = PlaneMesh.new()
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.9, 0.2, 0.25)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mm
	marker.visible = false
	add_child(marker)
	slots = D.make_slots(origin)
	for s in slots:
		if GameState.placed.has(s.id):
			_spawn(s)
	Ads.reward_granted.connect(_on_reward)

func prefix() -> String:
	return "h" if GameState.phase == 1 else ("f" if GameState.phase == 3 else "")

func open_slots() -> Array:
	var p := prefix()
	return slots.filter(func(s): return s.id.begins_with(p) and not GameState.placed.has(s.id))

func remaining(p: String) -> int:
	return slots.filter(func(s): return s.id.begins_with(p) and not GameState.placed.has(s.id)).size()

func available_types() -> Array:
	var out: Array = []
	for s in open_slots():
		if not out.has(s.type):
			out.append(s.type)
	return out

func toggle() -> void:
	if prefix() == "":
		message.emit("لا يوجد بناء متاح الآن.")
		return
	active = not active
	if not active:
		ghost.visible = false
		marker.visible = false
	state_changed.emit()

func rotate_step() -> void:
	yaw = fposmod(yaw + 15.0, 360.0)

func change_lift(dir: int) -> void:
	lift = snappedf(clampf(lift + 0.3 * dir, 0.0, 4.5), 0.3)

func next_type() -> void:
	var n := available_types().size()
	if n > 0:
		type_idx = (type_idx + 1) % n
		_clear_hints()

func info_text() -> String:
	if not active or ghost_type == "":
		return ""
	var left := open_slots().filter(func(s): return s.type == ghost_type).size()
	return "%s (متبقي %d)\nالارتفاع %.1f   الدوران %d°   مساعدات: %d" % [D.NAMES[ghost_type], left, lift, int(yaw), GameState.hints_left]

func _gp() -> Vector3:
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, player.cam_yaw)
	var g: Vector3 = player.global_position + fwd * 3.0
	g.y = lift
	return g

func _match(gp: Vector3, t: String) -> Dictionary:
	for s in open_slots():
		if s.type != t or s.pos.distance_to(gp) > 0.8:
			continue
		if D.TYPES[t]["sym"] or absf(fposmod(s.yaw - yaw + 90.0, 180.0) - 90.0) <= 10.0:
			return s
	return {}

func _basis(yaw_d: float, pitch_d: float) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(pitch_d), deg_to_rad(yaw_d), 0.0))

func _process(_d: float) -> void:
	if not active or player == null:
		return
	var types := available_types()
	if types.is_empty():
		active = false
		ghost.visible = false
		marker.visible = false
		state_changed.emit()
		return
	type_idx = clampi(type_idx, 0, types.size() - 1)
	var t: String = types[type_idx]
	if ghost_type != t:
		ghost_type = t
		ghost.mesh = _make_mesh(t)
	var sz := 4.8 if GameState.phase == 1 else 12.4
	(marker.mesh as PlaneMesh).size = Vector2(sz, sz)
	marker.position = origin + Vector3(0, 0.05, 0)
	marker.visible = true
	var gp := _gp()
	last_match = _match(gp, t)
	ghost.visible = true
	if last_match.is_empty():
		ghost.global_transform = Transform3D(_basis(yaw, 0.0), gp)
		ghost_mat.albedo_color = Color(1, 0.2, 0.2, 0.5)
	else:
		ghost.global_transform = Transform3D(_basis(last_match.yaw, last_match.pitch), last_match.pos)
		ghost_mat.albedo_color = Color(0.2, 1, 0.3, 0.6)

func place() -> void:
	if not active:
		return
	if last_match.is_empty():
		message.emit("غير مطابق — جرّب موضعًا أو ارتفاعًا أو دورانًا آخر")
		return
	var cost: String = D.TYPES[ghost_type]["cost"]
	if not GameState.spend(cost, 1):
		message.emit("ينقصك %s" % ("خشب" if cost == "wood" else "حجر"))
		return
	GameState.placed[last_match.id] = true
	GameState.xp += 2
	_spawn(last_match)
	_clear_hints()
	message.emit("تم التثبيت ✓")
	state_changed.emit()

func _make_mesh(t: String) -> Mesh:
	var info: Dictionary = D.TYPES[t]
	var dim: Vector3 = info["dim"]
	match info["shape"]:
		"hex":
			var c := CylinderMesh.new()
			c.top_radius = dim.x * 0.5
			c.bottom_radius = dim.x * 0.5
			c.height = dim.y
			c.radial_segments = 6
			c.rings = 1
			return c
		"tri":
			var p := PrismMesh.new()
			p.size = dim
			return p
		_:
			var b := BoxMesh.new()
			b.size = dim
			return b

func _spawn(s: Dictionary) -> void:
	var info: Dictionary = D.TYPES[s.type]
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _make_mesh(s.type)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.36, 0.2) if info["cost"] == "wood" else Color(0.5, 0.5, 0.53).darkened(randf() * 0.15)
	m.roughness = 1.0
	mi.material_override = m
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = info["dim"]
	cs.shape = bx
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)
	body.global_transform = Transform3D(_basis(s.yaw, s.pitch), s.pos)

func hint() -> void:
	if not active:
		message.emit("فعّل وضع البناء أولًا")
		return
	if GameState.hints_left > 0:
		GameState.hints_left -= 1
		_show_hint()
		message.emit("المواضع الصحيحة بالأزرق لمدة 10 ثوانٍ — تبقى %d" % GameState.hints_left)
	elif Ads.is_available():
		message.emit("جارٍ تحميل إعلان المكافأة%s" % (" (محاكاة تطوير)" if Ads.is_simulated() else ""))
		Ads.show_rewarded("hint")
	else:
		message.emit("نفدت المساعدات ولا يتوفر إعلان الآن. جرّب بنفسك!")

func _on_reward(placement: String) -> void:
	if placement == "hint":
		_show_hint()

func _show_hint() -> void:
	_clear_hints()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.5, 1.0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for s in open_slots():
		if s.type != ghost_type:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _make_mesh(s.type)
		mi.material_override = m
		add_child(mi)
		mi.global_transform = Transform3D(_basis(s.yaw, s.pitch), s.pos)
		hint_nodes.append(mi)
	get_tree().create_timer(10.0).timeout.connect(_clear_hints)

func _clear_hints() -> void:
	for n in hint_nodes:
		if is_instance_valid(n):
			n.queue_free()
	hint_nodes.clear()
