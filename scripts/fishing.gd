extends Node3D
## Fishing at the lake. The rod is NOT given: it is built piece by piece on the build board (R_rod, unlocked once the
## well-to-lake channel exists), like every other construction. With the rod, stand at the shore, cast, wait for a bite
## and press interact in time. A dry lake has no fish, so fishing depends on pumping water from the well.
signal message(text: String)
signal action(name: String)
const D := preload("res://scripts/building_data.gd")
const M := preload("res://scripts/mats.gd")
const WL := preload("res://scripts/weather_logic.gd")
const WATER_R := D.POND_R
var world
var pond
var builder
var player
var state := "idle"          # idle -> wait -> bite -> idle
var t := 0.0
var bobber: MeshInstance3D
var spot := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func has_rod() -> bool:
	return builder != null and builder.board_done("R_rod")

func _d2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Close enough to the water's edge (on the shore or on the dock).
func at_shore(pos: Vector3) -> bool:
	var d := _d2(pos, D.POND_C)
	return d > WATER_R - 2.2 and d < WATER_R + 3.2

func hint(pos: Vector3) -> String:
	if not at_shore(pos) or not has_rod():
		return ""
	match state:
		"wait":
			return "تفاعل: اسحب الخيط (تنتظر سمكة...)"
		"bite":
			return "الآن! اضغط «تفاعل» لسحب السمكة"
	return "تفاعل: ارمِ السنّارة" if pond.ok() else "البحيرة جافة — اضخّ الماء من البئر ليعود السمك"

func info_text(pos: Vector3) -> String:
	if not at_shore(pos) or has_rod():
		return ""
	if not GameState.channel:
		return "السمك: ابنِ القناة الخشبية من البئر أولًا، ثم اصنع السنّارة من لوحة البناء"
	return "اصنع السنّارة من لوحة البناء (اضغط «بناء» ثم اللوحة التالية: السنّارة)"

func interact(pos: Vector3) -> bool:
	if not at_shore(pos) or not has_rod():
		return false
	match state:
		"idle":
			if not pond.ok():
				message.emit("البحيرة جافة — لا يوجد سمك. اضخّ الماء من البئر")
				return true
			_cast(pos)
		"wait":
			_clear()
			message.emit("سحبتَ الخيط قبل أن تأكل سمكة")
		"bite":
			_catch()
	return true

func _cast(pos: Vector3) -> void:
	var dir := Vector3(pos.x - D.POND_C.x, 0, pos.z - D.POND_C.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT
	spot = D.POND_C + dir * (WATER_R - 3.0)
	bobber = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	bobber.mesh = sm
	bobber.material_override = M.flat(Color(0.9, 0.12, 0.1), 0.6)
	add_child(bobber)
	bobber.position = Vector3(spot.x, pond.base_y + 0.08, spot.z)
	state = "wait"
	t = _rng.randf_range(4.0, 9.0) * lerpf(1.5, 0.8, clampf(GameState.pond, 0.0, 1.0)) * (0.6 if WL.rain_at(GameState.clock_hours) > 0.0 else 1.0)
	action.emit("gather")
	message.emit("ألقيتَ السنّارة في البحيرة... انتظر حتى يهتزّ العوّامة")

func _clear() -> void:
	state = "idle"
	if bobber != null:
		bobber.queue_free()
		bobber = null

func _catch() -> void:
	_clear()
	var n := 2 if _rng.randf() < 0.12 else 1
	var got := GameState.add("fish", n)
	GameState.xp += 3
	action.emit("gather")
	if got > 0:
		message.emit("اصطدتَ %s ✓ (+%d سمك) — اطبخها على الموقد" % ["سمكتين" if n == 2 else "سمكة", got])
	else:
		message.emit("مخزن السمك ممتلئ")

func _process(d: float) -> void:
	if state == "idle":
		return
	if player != null and _d2(player.global_position, D.POND_C) > WATER_R + 6.0:
		_clear()
		message.emit("ابتعدتَ عن البحيرة فانقطع الخيط")
		return
	t -= d
	var now := Time.get_ticks_msec() * 0.001
	if bobber != null:
		var base: float = pond.base_y + 0.08
		bobber.position.y = base + sin(now * 3.0) * 0.02 - (0.07 + sin(now * 30.0) * 0.02 if state == "bite" else 0.0)
	if state == "wait" and t <= 0.0:
		state = "bite"
		t = 1.6
		message.emit("سمكة تأكل! اضغط «تفاعل» الآن")
	elif state == "bite" and t <= 0.0:
		_clear()
		message.emit("هربت السمكة — حاول مرة أخرى")
