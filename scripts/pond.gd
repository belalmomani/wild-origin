extends Node3D
## Small lake where birds and wild animals come to drink. It is filled from the well by a wooden channel
## (hollowed-log trough) fed by a hand lever (shaduf): the cheapest "pump" — only wood. An upgraded well pumps by itself.
signal message(text: String)
const M := preload("res://scripts/mats.gd")
const WL := preload("res://scripts/weather_logic.gd")
const WellP := preload("res://scripts/well.gd")
const D := preload("res://scripts/building_data.gd")
const CENTER := D.POND_C
const RADIUS := D.POND_R
const EVAP_PER_HOUR := 0.012       # the lake slowly dries out without water from the well
const AUTO_PER_HOUR := 0.06        # an upgraded well keeps it filled
const PUMP_STEP := 0.25            # one lever stroke by hand
const DRINK_MIN := 0.12            # below this level animals stay away
var world
var water: MeshInstance3D
var mud: MeshInstance3D
var channel_node: Node3D
var flow: MeshInstance3D
var base_y := 0.0
var fish: Array = []
var center := CENTER

func _ready() -> void:
	call_deferred("_build")

func _ground(x: float, z: float) -> float:
	return world.height_at(x, z) if world != null else 0.0

func _build() -> void:
	base_y = D.WATER_Y
	center = Vector3(CENTER.x, base_y, CENTER.z)
	mud = MeshInstance3D.new()                    # flat dark lake bed at the bottom of the basin
	var mc := CylinderMesh.new()
	mc.top_radius = RADIUS - 0.5
	mc.bottom_radius = RADIUS - 0.5
	mc.height = 0.05
	mc.radial_segments = 32
	mud.mesh = mc
	mud.material_override = M.flat(Color(0.12, 0.17, 0.15), 1.0)
	mud.position = Vector3(CENTER.x, -D.POND_DEPTH + 0.35, CENTER.z)
	add_child(mud)
	water = MeshInstance3D.new()
	var wc := CylinderMesh.new()
	wc.top_radius = RADIUS
	wc.bottom_radius = RADIUS
	wc.height = 0.06
	wc.radial_segments = 32
	water.mesh = wc
	var wm := ShaderMaterial.new()
	wm.shader = load("res://assets/shaders/water.gdshader")
	wm.set_shader_parameter("radius", RADIUS)
	water.material_override = wm
	water.position = Vector3(CENTER.x, base_y, CENTER.z)
	add_child(water)
	for i in 16:                                  # stones around the shore
		var a := TAU * float(i) / 16.0 + 0.3
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28 + 0.12 * float(i % 3)
		sm.height = sm.radius * 1.4
		rock.mesh = sm
		rock.material_override = M.flat(Color(0.5, 0.49, 0.46), 0.95)
		var rx := CENTER.x + cos(a) * (RADIUS + 0.9 + 0.5 * float(i % 2))
		var rz := CENTER.z + sin(a) * (RADIUS + 0.9 + 0.5 * float(i % 2))
		rock.position = Vector3(rx, _ground(rx, rz) + 0.05, rz)
		add_child(rock)
	_make_fish()
	_refresh()

func _make_fish() -> void:
	var skin := [Color(0.75, 0.78, 0.82), Color(0.85, 0.5, 0.2), Color(0.5, 0.62, 0.45)]
	for i in 26:
		var f := Node3D.new()
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		body.mesh = sm
		body.scale = Vector3(0.55, 0.65, 1.7)
		body.material_override = M.flat(skin[i % 3], 0.5)
		f.add_child(body)
		var tail := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.02, 0.2, 0.16)
		tail.mesh = tm
		tail.position = Vector3(0, 0, 0.36)
		tail.material_override = body.material_override
		f.add_child(tail)
		add_child(f)
		fish.append({"n": f, "a": randf() * TAU, "r": 0.2 + 0.4 * randf(), "v": (0.12 + 0.12 * randf()) * (1.0 if i % 2 == 0 else -1.0), "y": 0.5 + 1.0 * randf(), "ph": randf() * TAU})

func _process(d: float) -> void:
	var lvl := clampf(GameState.pond, 0.0, 1.0)
	var show := lvl > 0.12 and water != null
	var sr := RADIUS * (0.45 + 0.55 * lvl)
	for f in fish:
		var n: Node3D = f["n"]
		n.visible = show
		if not show:
			continue
		f["a"] = float(f["a"]) + float(f["v"]) * d
		f["ph"] = float(f["ph"]) + d * 1.5
		var a: float = f["a"]
		var r: float = sr * float(f["r"]) * 1.2
		n.position = Vector3(CENTER.x + cos(a) * r, base_y - float(f["y"]) + sin(float(f["ph"])) * 0.08, CENTER.z + sin(a) * r)
		var tang := Vector3(-sin(a), 0, cos(a)) * signf(float(f["v"]))
		n.rotation.y = atan2(-tang.x, -tang.z)

func ok() -> bool:
	return GameState.pond >= DRINK_MIN

func _refresh() -> void:
	if water == null:
		return
	var lvl := clampf(GameState.pond, 0.0, 1.0)
	water.visible = lvl > 0.03
	var s := 0.45 + 0.55 * lvl
	water.scale = Vector3(s, 1.0, s)
	if flow != null:
		flow.visible = GameState.channel and GameState.pond < 0.99 and GameState.well >= 2
	_build_channel()

## The trough runs from the well to the lake; built once with wood.
func _build_channel() -> void:
	if channel_node != null or not GameState.channel or water == null:
		return
	channel_node = Node3D.new()
	add_child(channel_node)
	var wood := M.flat(Color(0.5, 0.34, 0.2), 0.9)
	var a: Vector3 = WellP.POS + Vector3(-1.0, 0, 0.3)
	var b: Vector3 = Vector3(CENTER.x + (WellP.POS.x - CENTER.x) * 0.0, 0, CENTER.z) + (Vector3(WellP.POS.x, 0, WellP.POS.z) - Vector3(CENTER.x, 0, CENTER.z)).normalized() * (RADIUS + 0.3)
	var span := b - a
	span.y = 0.0
	var n := int(ceil(span.length() / 1.5))
	var yaw := atan2(-span.x, -span.z)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := a + span * t
		var seg := Node3D.new()
		seg.position = Vector3(p.x, _ground(p.x, p.z) + 0.3, p.z)
		seg.rotation.y = yaw
		channel_node.add_child(seg)
		var seg_len := span.length() / float(n) + 0.05
		for part in [[Vector3(0.36, 0.06, seg_len), Vector3(0, 0, 0)], [Vector3(0.06, 0.2, seg_len), Vector3(-0.18, 0.1, 0)], [Vector3(0.06, 0.2, seg_len), Vector3(0.18, 0.1, 0)]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[0]
			mi.mesh = bm
			mi.material_override = wood
			mi.position = part[1]
			seg.add_child(mi)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.1, 0.3, 0.1)
		leg.mesh = lm
		leg.material_override = wood
		leg.position = Vector3(0, -0.15, 0)
		seg.add_child(leg)
	flow = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.26, 0.02, span.length())
	flow.mesh = fm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.5, 0.7, 0.8)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flow.material_override = wm
	var mid := a + span * 0.5
	flow.position = Vector3(mid.x, _ground(mid.x, mid.z) + 0.34, mid.z)
	flow.rotation.y = yaw
	flow.visible = false
	add_child(flow)

func channel_ready() -> bool:
	return GameState.channel

func build_channel() -> void:
	GameState.channel = true
	_build_channel()
	_refresh()

func pump_by_hand() -> void:
	GameState.pond = minf(1.0, GameState.pond + PUMP_STEP)
	_refresh()

func tick(dt_hours: float) -> void:
	var before := GameState.pond
	var day := WL.day_of(GameState.clock_hours)
	var rain := WL.rain_at(GameState.clock_hours)
	var lvl := GameState.pond - EVAP_PER_HOUR * WL.evap_mult(day) * dt_hours * (0.0 if rain > 0.0 else 1.0)
	lvl += WL.RAIN_FILL_PER_HOUR * rain * dt_hours
	if GameState.well >= 2 and GameState.channel:
		lvl += AUTO_PER_HOUR * dt_hours
	GameState.pond = clampf(lvl, 0.0, 1.0)
	if absf(before - GameState.pond) > 0.001:
		_refresh()

func drink(amount: float) -> void:
	GameState.pond = maxf(0.0, GameState.pond - amount)
	_refresh()

func near(pos: Vector3) -> bool:
	return Vector2(pos.x - CENTER.x, pos.z - CENTER.z).length() < RADIUS + 3.0

func info_text(pos: Vector3) -> String:
	if not near(pos):
		return ""
	if not GameState.channel:
		return "البحيرة: جافة — ابنِ قناة خشبية من البئر (تفاعل عند البئر)"
	return "البحيرة: الماء %d%% — %s" % [int(GameState.pond * 100.0), "الحيوانات والطيور تشرب منها" if ok() else "جافة تقريبًا: اضخّ الماء من البئر"]
