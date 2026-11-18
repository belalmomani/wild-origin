extends Node3D
## Life inside the house once its parts are built: window glass, hanging lamp, hearth fire (fuel + cooking),
## bed (sleep through the night) and the door. All the physical parts come from the puzzle boards (building.gd).
signal message(text: String)
signal sleep_request
const D := preload("res://scripts/building_data.gd")
const FUEL_PER_WOOD := 3.0     # game hours of fire per piece of wood
const FUEL_MAX := 24.0

var builder
var night := false
var _glass := {}               # window board id -> true once the glass exists
var _lamp_light: OmniLight3D
var _fire_root: Node3D
var _fire_light: OmniLight3D
var _flames: Array = []
var _hearth_done := false
var _t := 0.0

func _ready() -> void:
	refresh()

func _done(id: String) -> bool:
	return builder.board_done(id)

## Call after any piece is placed (and once at start): creates whatever a finished board brings to life.
func refresh() -> void:
	for wid in ["I_winR", "I_winL"]:
		if not _glass.has(wid) and _done(wid):
			_make_glass(wid)
	if _lamp_light == null and _done("I_lamp"):
		_make_lamp()
	if not _hearth_done and _done("I_hearth"):
		_make_fire()

func glass_count() -> int:
	return _glass.size()

func lamp_ready() -> bool:
	return _lamp_light != null

func fire_lit() -> bool:
	return _hearth_done and GameState.fire_fuel > 0.0

func set_night(on: bool) -> void:
	night = on
	if _lamp_light != null:
		_lamp_light.visible = on

func _make_glass(wid: String) -> void:
	_glass[wid] = true
	var x := 2.0 if wid == "I_winR" else -2.0
	var body := StaticBody3D.new()
	body.position = Vector3(x, 1.44, 0.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.9, 0.7)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.82, 1.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)

func _make_lamp() -> void:
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = D.LAMP_POS
	_lamp_light.omni_range = 8.0
	_lamp_light.light_energy = 1.8
	_lamp_light.light_color = Color(1.0, 0.8, 0.5)
	_lamp_light.visible = night
	add_child(_lamp_light)

func _flame_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m

func _make_fire() -> void:
	_hearth_done = true
	if not GameState.hearth_init:
		GameState.hearth_init = true
		GameState.fire_fuel = 8.0
		message.emit("اشتعلت النار! أضف حطبًا بـ«تفاعل» لتبقى مشتعلة")
	_fire_root = Node3D.new()
	_fire_root.position = D.HEARTH_C + Vector3(0, 0.2, 0)
	add_child(_fire_root)
	var specs := [[0.13, 0.5, Vector3(0, 0.25, 0), Color(1.0, 0.45, 0.1)],
			[0.09, 0.36, Vector3(0.08, 0.2, 0.05), Color(1.0, 0.7, 0.2)],
			[0.08, 0.3, Vector3(-0.07, 0.17, -0.06), Color(1.0, 0.85, 0.35)]]
	for sp in specs:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = float(sp[0])
		cm.height = float(sp[1])
		cm.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.position = sp[2]
		mi.material_override = _flame_mat(sp[3])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fire_root.add_child(mi)
		_flames.append(mi)
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0, 0.45, 0.1)
	_fire_light.omni_range = 7.0
	_fire_light.light_energy = 2.2
	_fire_light.light_color = Color(1.0, 0.6, 0.25)
	_fire_root.add_child(_fire_light)
	_apply_fire()

func _apply_fire() -> void:
	if _fire_root == null:
		return
	var on := GameState.fire_fuel > 0.0
	for f in _flames:
		f.visible = on
	_fire_light.visible = on

## Fuel burns with game time. quiet = offline/sleep (no "went out" message).
func tick(dt_hours: float, quiet: bool = false) -> void:
	if not _hearth_done:
		return
	var before: float = GameState.fire_fuel
	if before > 0.0:
		GameState.fire_fuel = maxf(0.0, before - dt_hours)
		if before > 0.0 and GameState.fire_fuel <= 0.0:
			_apply_fire()
			if not quiet:
				message.emit("انطفأت النار — أضف حطبًا من الموقد")

func _process(d: float) -> void:
	if _fire_root == null or GameState.fire_fuel <= 0.0:
		return
	_t += d
	var low := clampf(GameState.fire_fuel / 4.0, 0.35, 1.0)   # dies down when almost out
	_fire_light.light_energy = 2.2 * low * (0.85 + 0.15 * sin(_t * 17.0) + 0.08 * sin(_t * 31.0))
	for i in _flames.size():
		var f: Node3D = _flames[i]
		f.scale = Vector3(1.0, low * (0.85 + 0.25 * sin(_t * (11.0 + i * 4.0) + i)), 1.0)

func _d2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## The «تفاعل» button near the door, bed or hearth. Returns true when it handled the press.
func interact(pos: Vector3) -> bool:
	var best := ""
	var bd := 99.0
	var d: float
	if builder.door_complete():
		d = _d2(pos, D.DOOR_C)
		if d < 2.6 and d < bd:
			bd = d
			best = "door"
	if _done("I_bed"):
		d = _d2(pos, D.BED_C)
		if d < 1.7 and d < bd:
			bd = d
			best = "bed"
	if _hearth_done:
		d = _d2(pos, D.HEARTH_C)
		if d < 1.7 and d < bd:
			bd = d
			best = "fire"
	match best:
		"door":
			var r: String = builder.toggle_door(pos)
			if r == "open":
				message.emit("فتحتَ الباب")
			elif r == "closed":
				message.emit("أغلقتَ الباب")
			elif r == "blocked":
				message.emit("ابتعد عن الباب أولًا ثم أغلقه")
			return true
		"bed":
			var tod: float = GameState.time_of_day
			if tod >= 6.0 and tod < 18.5:
				message.emit("لا تشعر بالنعاس — يمكنك النوم من الغروب (18:30) حتى الفجر")
			else:
				sleep_request.emit()
			return true
		"fire":
			_tend_fire()
			return true
	return false

func _tend_fire() -> void:
	var fuel: float = GameState.fire_fuel
	if fuel >= 6.0 and GameState.count("meat") > 0:
		GameState.spend("meat", 1)
		GameState.xp += 2
		message.emit("طبختَ وجبة لحم على النار ✓ (+2 خبرة)")
		return
	if fuel >= FUEL_MAX - FUEL_PER_WOOD + 0.5:
		message.emit("النار مشتعلة بقوة")
		return
	if GameState.spend("wood", 1):
		GameState.fire_fuel = minf(FUEL_MAX, fuel + FUEL_PER_WOOD)
		_apply_fire()
		message.emit("أضفتَ حطبًا للنار")
	else:
		message.emit("لا يوجد خشب لإبقاء النار مشتعلة")

func info_text(pos: Vector3) -> String:
	if not _hearth_done or _d2(pos, D.HEARTH_C) > 4.0:
		return ""
	var f: float = GameState.fire_fuel
	var n := int(round(clampf(f / FUEL_MAX, 0.0, 1.0) * 10.0))
	return "الموقد: %s %d ساعة | خشب %d | لحم %d" % ["█".repeat(n) + "░".repeat(10 - n), int(f), GameState.count("wood"), GameState.count("meat")]
