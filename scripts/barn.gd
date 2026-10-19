extends Node3D
## Barn pen: caught animals live here (once the barn is built), wander in the yard, and need feeding
## once per game day (hay or apples). State lives in GameState.pen.
signal message(text: String)
const L := preload("res://scripts/barn_logic.gd")
const HL := preload("res://scripts/hunt_logic.gd")
const AnimalS := preload("res://scripts/animal.gd")
const BD := preload("res://scripts/building_data.gd")
var world
var nodes := {}
var center := BD.BARN + Vector3(0, 0, 6.5)
var _t := 0.0

func _ready() -> void:
	for a in GameState.pen:
		_spawn(a)

func _now() -> float:
	return GameState.clock_hours / 24.0

func _spawn(a: Dictionary) -> void:
	var n := AnimalS.new()
	n.setup(str(a.kind), int(a.id) * 13 + 5)
	n.make_tame(center, 3.5)
	var r := RandomNumberGenerator.new()
	r.seed = int(a.id)
	var p := center + Vector3(r.randf_range(-2.5, 2.5), 0, r.randf_range(-2.5, 2.5))
	if world != null:
		p.y = world.height_at(p.x, p.z)
	n.position = p
	add_child(n)
	nodes[int(a.id)] = n

func _sync() -> void:
	for a in GameState.pen:
		if not nodes.has(int(a.id)):
			_spawn(a)

func tick(dt_hours: float, offline: bool = false) -> void:
	var now := _now()
	var dt := dt_hours / 24.0
	if not GameState.barn_built:
		for a in GameState.pen:
			a.fed = now          # no hunger until a barn exists: fair to the player
		return
	for a in GameState.pen.duplicate():
		var ev := L.step(a, now, dt, offline)
		if offline:
			continue
		var nm: String = HL.ANIMALS[str(a.kind)]["name"]
		match ev:
			"hungry": message.emit("%s يحتاج إلى طعام اليوم — اذهب إلى الحظيرة واضغط «تفاعل»" % nm)
			"starving": message.emit("%s جائع ويتدهور! أطعمه فورًا." % nm)
			"dead":
				message.emit("مات %s من الجوع." % nm)
				var n: Node3D = nodes.get(int(a.id))
				if n:
					n.queue_free()
				nodes.erase(int(a.id))
				GameState.pen.erase(a)
	_t += dt_hours
	if _t > 0.2:
		_t = 0.0
		_sync()

func notify_after_offline() -> void:
	for a in GameState.pen:
		if not a.dead and (float(a.h) < 1.0 or L.hunger(a, _now()) >= L.WARN):
			message.emit("مرّ وقت أثناء غيابك: تحقّق من حيوانات الحظيرة وأطعمها.")
			return

func _feed_item() -> String:
	if GameState.count("hay") > 0:
		return "hay"
	if GameState.count("apples") > 0:
		return "apples"
	if GameState.spend("wood", 3):
		GameState.add("hay", 4)
		message.emit("صنعتَ قشًّا للعلف (3 خشب → 4)")
		return "hay"
	return ""

## Feed every hungry animal (most hungry first). Returns true if the player was near the pen.
func interact(pos: Vector3) -> bool:
	if not GameState.barn_built or GameState.pen.is_empty() or pos.distance_to(center) > 9.0:
		return false
	var now := _now()
	var list: Array = GameState.pen.duplicate()
	list.sort_custom(func(x, y): return L.hunger(x, now) > L.hunger(y, now))
	var fed := 0
	for a in list:
		if a.dead or L.hunger(a, now) < 0.2:
			continue
		var item := _feed_item()
		if item == "":
			message.emit("لا يوجد علف — اجمع تفاحًا أو خشبًا لصنع القش")
			break
		GameState.spend(item, 1)
		L.feed(a, now)
		fed += 1
	if fed > 0:
		message.emit("أطعمتَ %d حيوانًا ✓" % fed)
	elif GameState.pen.size() > 0:
		message.emit("الحيوانات شبعانة الآن")
	return true

func _bar(v: float) -> String:
	var n := int(round(clampf(v, 0.0, 1.0) * 10.0))
	return "█".repeat(n) + "░".repeat(10 - n)

func info_text(pos: Vector3) -> String:
	if GameState.pen.is_empty() or pos.distance_to(center) > 10.0:
		return ""
	var deer := 0
	var hens := 0
	var worst := 1.0
	var hung := 0.0
	var now := _now()
	for a in GameState.pen:
		if str(a.kind) == "deer":
			deer += 1
		else:
			hens += 1
		worst = minf(worst, float(a.h))
		hung = maxf(hung, L.hunger(a, now))
	var state := "" if GameState.barn_built else " (ابنِ الحظيرة ليبدأ الاعتناء بها)"
	return "الحظيرة: غزلان %d، دجاج %d%s\nالجوع %s | الصحة %s | علف: تفاح %d، قش %d" % [deer, hens, state, _bar(clampf(hung / L.GRACE, 0.0, 1.0)), _bar(worst), GameState.count("apples"), GameState.count("hay")]
