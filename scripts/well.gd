extends Node3D
## The well: dig it with wooden gear (wood), fill the bucket, water the crops by hand; upgrade (reward ad or 15 harvests)
## and it waters the crops by itself. State lives in GameState.well (0 none, 1 dug, 2 automatic) and GameState.bucket.
signal message(text: String)
signal action(name: String)
const BD := preload("res://scripts/building_data.gd")
const M := preload("res://scripts/mats.gd")
const POS := Vector3(-9.5, 0.0, 7.5)       # just south-east of the farm gate
const CHANNEL_WOOD := 20                     # shaduf lever + hollow-log channel to the lake
const DIG_WOOD := 20                         # wooden digging gear
const BUCKET_CAP := [0, 4, 6]               # bucket size per well level
const HARVEST_REWARD := 15                   # harvests that upgrade the well for free
var world
var pond                                       # the lake (set by main)
var visual: Node3D
var marker: Node3D
var digging := false
var _confirm_until := 0.0

func _ready() -> void:
	Ads.reward_granted.connect(_on_reward)
	_refresh()

func _y() -> float:
	return world.height_at(POS.x, POS.z) if world != null else 0.0

func _refresh() -> void:
	if marker != null:
		marker.queue_free()
		marker = null
	if visual != null:
		visual.queue_free()
		visual = null
	if GameState.well <= 0:
		marker = _make_marker()
		add_child(marker)
		marker.position = Vector3(POS.x, _y(), POS.z)
	else:
		visual = _make_well(GameState.well >= 2)
		add_child(visual)
		visual.position = Vector3(POS.x, _y(), POS.z)

func _make_marker() -> Node3D:
	var n := Node3D.new()
	var wood := M.flat(Color(0.55, 0.38, 0.22), 0.9)
	var earth := M.flat(Color(0.32, 0.24, 0.16), 1.0)
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.06
	ring.mesh = cm
	ring.material_override = earth
	ring.position.y = 0.03
	n.add_child(ring)
	for a in [0.0, 1.57, 3.14, 4.71]:               # four stakes around the planned well
		var s := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.1, 0.9, 0.1)
		s.mesh = b
		s.material_override = wood
		s.position = Vector3(cos(a) * 1.0, 0.45, sin(a) * 1.0)
		n.add_child(s)
	return n

func _make_well(auto: bool) -> Node3D:
	var n := Node3D.new()
	var stone := M.flat(Color(0.52, 0.5, 0.47), 0.95)
	var wood := M.flat(Color(0.5, 0.34, 0.2), 0.9)
	var water := M.flat(Color(0.12, 0.3, 0.45), 0.2)
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.95
	cm.bottom_radius = 1.0
	cm.height = 0.95
	cm.radial_segments = 16
	ring.mesh = cm
	ring.material_override = stone
	ring.position.y = 0.47
	n.add_child(ring)
	var w := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.72
	wm.bottom_radius = 0.72
	wm.height = 0.02
	w.mesh = wm
	w.material_override = water
	w.position.y = 0.9
	n.add_child(w)
	for sx in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.14, 2.0, 0.14)
		p.mesh = pb
		p.material_override = wood
		p.position = Vector3(sx * 0.95, 1.45, 0)
		n.add_child(p)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(2.2, 0.12, 0.12)
	beam.mesh = bb
	beam.material_override = wood
	beam.position = Vector3(0, 2.3, 0)
	n.add_child(beam)
	for sx in [-1.0, 1.0]:                              # little pitched roof
		var r := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(1.4, 0.06, 1.5)
		r.mesh = rb
		r.material_override = wood
		r.position = Vector3(sx * 0.55, 2.45, 0)
		r.rotation.z = sx * -0.35
		n.add_child(r)
	var bucket := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.2
	bm.bottom_radius = 0.15
	bm.height = 0.3
	bucket.mesh = bm
	bucket.material_override = M.flat(Color(0.35, 0.25, 0.15), 0.9)
	bucket.position = Vector3(0, 1.6, 0)
	n.add_child(bucket)
	if auto:                                            # upgraded: a copper pipe with a sprinkler head
		var pipe := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.05
		pm.height = 1.4
		pipe.mesh = pm
		pipe.material_override = M.flat(Color(0.72, 0.45, 0.25), 0.4)
		pipe.position = Vector3(0, 1.8, 1.0)
		n.add_child(pipe)
	return n

func cap() -> int:
	return int(BUCKET_CAP[clampi(GameState.well, 0, 2)])

func near(pos: Vector3) -> bool:
	return Vector2(pos.x - POS.x, pos.z - POS.z).length() < 3.6

func hint(pos: Vector3) -> String:
	if not near(pos):
		return ""
	if digging:
		return ""
	if GameState.well <= 0:
		return "تفاعل: احفر بئرًا (معدات خشبية: %d خشب)" % DIG_WOOD
	if GameState.bucket < cap():
		return "تفاعل: املأ الدلو (%d/%d)" % [GameState.bucket, cap()]
	if not GameState.channel:
		return "تفاعل: ابنِ قناة خشبية ورافعة لضخ الماء إلى البحيرة (%d خشب)" % CHANNEL_WOOD
	if GameState.pond < 0.95 and GameState.well == 1:
		return "تفاعل: اضخّ الماء إلى البحيرة (%d%%)" % int(GameState.pond * 100.0)
	if GameState.well == 1:
		return "تفاعل: طوّر البئر لسقاية تلقائية (إعلان)"
	return "البئر يسقي المزروعات وحده"

func info_text(pos: Vector3) -> String:
	if not near(pos) or GameState.well <= 0:
		return ""
	return "البئر: %s | الدلو %d/%d | تطوير مجاني بعد %d حصاد (%d)" % ["سقاية تلقائية" if GameState.well >= 2 else "يدوي", GameState.bucket, cap(), HARVEST_REWARD, GameState.harvests] if GameState.well == 1 else "البئر: سقاية تلقائية — المزروعات تُسقى وحدها"

func interact(pos: Vector3) -> bool:
	if not near(pos) or digging:
		return false
	if GameState.well <= 0:
		_dig()
		return true
	if GameState.bucket < cap():
		GameState.bucket = cap()
		message.emit("ملأتَ الدلو من البئر (%d/%d) — اضغط «سقي» قرب المزروعات" % [GameState.bucket, cap()])
		return true
	if not GameState.channel:
		if not GameState.spend("wood", CHANNEL_WOOD):
			message.emit("القناة الخشبية والرافعة (شادوف) من الخشب فقط: تحتاج %d خشب (لديك %d)" % [CHANNEL_WOOD, GameState.count("wood")])
			return true
		action.emit("place")
		pond.build_channel()
		GameState.xp += 4
		message.emit("بنيتَ رافعة وقناة خشبية من جذوع مجوّفة إلى البحيرة ✓ اضغط «تفاعل» عند البئر لضخ الماء بالرافعة — والبئر المطوّر يضخّ وحده")
		return true
	if GameState.well == 1 and GameState.pond < 0.95:
		action.emit("gather")
		pond.pump_by_hand()
		message.emit("قمتَ بضخّ الماء بالرافعة عبر القناة — البحيرة %d%%" % int(GameState.pond * 100.0))
		return true
	if GameState.well == 1:
		var now := Time.get_ticks_msec() * 0.001
		if now < _confirm_until:
			_confirm_until = 0.0
			message.emit("جارٍ عرض الإعلان لتطوير البئر...")
			Ads.show_rewarded("well_upgrade")
		else:
			_confirm_until = now + 6.0
			message.emit("الدلو ممتلئ. اضغط «تفاعل» مرة أخرى خلال 6 ثوانٍ لمشاهدة إعلان وتطوير البئر إلى سقاية تلقائية (أو احصد %d مرة)" % HARVEST_REWARD)
	else:
		message.emit("البئر مطوّر: المزروعات تُسقى وحدها")
	return true

func _dig() -> void:
	if not GameState.spend("wood", DIG_WOOD):
		message.emit("معدات الحفر من الخشب: تحتاج %d خشب (لديك %d)" % [DIG_WOOD, GameState.count("wood")])
		return
	digging = true
	message.emit("صنعتَ معدات الحفر من الخشب (-%d). تحفر البئر..." % DIG_WOOD)
	for i in 4:
		action.emit("chop")
		await get_tree().create_timer(1.3).timeout
		message.emit("حفر البئر... %d%%" % ((i + 1) * 25))
	GameState.well = 1
	GameState.bucket = BUCKET_CAP[1]
	GameState.xp += 5
	digging = false
	_refresh()
	message.emit("انتهى حفر البئر ✓ الدلو ممتلئ — اسقِ المزروعات بزر «سقي» وعُد لتعبئته")

func _on_reward(placement: String) -> void:
	if placement == "well_upgrade":
		upgrade("شاهدتَ الإعلان")

func upgrade(why: String) -> void:
	if GameState.well >= 2:
		return
	GameState.well = 2
	GameState.bucket = BUCKET_CAP[2]
	_refresh()
	message.emit("%s — تطوّر البئر! أصبح يسقي المزروعات وحده ✓" % why)

## Called after every harvest: enough work on the farm upgrades the well for free.
func on_harvest() -> void:
	GameState.harvests += 1
	if GameState.well == 1 and GameState.harvests >= HARVEST_REWARD:
		upgrade("مكافأة العمل في المزرعة")
