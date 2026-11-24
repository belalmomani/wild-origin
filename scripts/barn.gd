extends Node3D
## Barn pen: caught animals live here (once the barn is built), wander in the yard, and need feeding
## once per game day (hay or apples). State lives in GameState.pen.
signal message(text: String)
const L := preload("res://scripts/barn_logic.gd")
const HL := preload("res://scripts/hunt_logic.gd")
const AnimalS := preload("res://scripts/animal.gd")
const BD := preload("res://scripts/building_data.gd")
var world
var player                       # set by main: penned animals wander / animate every frame
var nodes := {}
var center := BD.BARN + Vector3(0, 0, 6.5)      # barn yard (poultry)
var barn_center := BD.BARN                     # the barn building: poultry live inside once it is built
var farm_center := BD.FARM_C                    # inside the fenced farm (deer, ibex, elk)
var _t := 0.0

func _ready() -> void:
	for a in GameState.pen:
		_spawn(a)

func _process(d: float) -> void:
	var pp: Vector3 = player.global_position if player != null else Vector3(0, 0, 999)
	for id in nodes.keys():
		var n = nodes[id]
		if is_instance_valid(n):
			n.tick(d, pp, false, world)

func _now() -> float:
	return GameState.clock_hours / 24.0

func _spawn(a: Dictionary) -> void:
	var n := AnimalS.new()
	n.setup(str(a.kind), int(a.id) * 13 + 5)
	var c := pen_center(str(a.kind))
	n.make_tame(c, (2.6 if GameState.barn_built else 3.5) if L.is_poultry(str(a.kind)) else 3.2)
	var r := RandomNumberGenerator.new()
	r.seed = int(a.id)
	var p := c + Vector3(r.randf_range(-2.4, 2.4), 0, r.randf_range(-2.4, 2.4))
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
	_house_poultry()
	var now := _now()
	var dt := dt_hours / 24.0
	_sync()                      # animals appear in the yard as soon as they arrive, built barn or not
	for a in GameState.pen.duplicate():
		var housed: bool = GameState.barn_built if L.is_poultry(str(a.kind)) else GameState.farm_built
		if not housed:
			a.fed = now          # no hunger until their home (barn / fenced farm) exists: fair to the player
			continue
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

## Once the barn is finished the hens and turkeys move into it (safe from predators).
func _house_poultry() -> void:
	if not GameState.barn_built:
		return
	for a in GameState.pen:
		if L.is_poultry(str(a.kind)):
			var n = nodes.get(int(a.id))
			if n != null and is_instance_valid(n) and n.home.distance_to(barn_center) > 0.5:
				n.make_tame(barn_center, 2.6)
				n.global_position = barn_center + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))

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
		var hay := 6 if GameState.has_tech("hay2") else 4
		GameState.add("hay", hay)
		message.emit("صنعتَ قشًّا للعلف (3 خشب → %d)" % hay)
		return "hay"
	return ""

const REACH := 3.2             # how close the player must be to feed / milk an animal

## Where an animal of this kind lives: poultry in the barn yard, everything else inside the fenced farm.
func pen_center(kind: String) -> Vector3:
	if L.is_poultry(kind):
		return barn_center if GameState.barn_built else center
	return farm_center

## Animals of the pen within reach of the player, nearest first.
func _near(pos: Vector3) -> Array:
	var out: Array = []
	for a in GameState.pen:
		var n: Node3D = nodes.get(int(a.id))
		if n != null and is_instance_valid(n):
			var d := Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length()
			if d <= REACH:
				out.append({"a": a, "d": d})
	out.sort_custom(func(x, y): return x.d < y.d)
	return out

## Feeds / milks the animal standing right next to the player. Returns false when no animal is within reach.
func interact(pos: Vector3) -> bool:
	var near := _near(pos)
	if near.is_empty():
		return false
	var now := _now()
	var a: Dictionary = near[0].a
	var nm: String = HL.ANIMALS[str(a.kind)]["name"]
	var did := false
	var whole := int(floor(float(a.get("milk", 0.0))))
	if whole > 0 and not L.is_poultry(str(a.kind)):
		a["milk"] = float(a.get("milk", 0.0)) - whole
		var got := GameState.add("milk", whole)
		GameState.xp += 1
		message.emit("حلبتَ %s: +%d حليب ✓" % [nm, got] if got > 0 else "مخزن الحليب ممتلئ")
		did = true
	if not a.dead and L.hunger(a, now) >= 0.2:
		var item := _feed_item()
		if item == "":
			message.emit("لا يوجد علف — اجمع تفاحًا أو خشبًا لصنع القش")
			return true
		GameState.spend(item, 1)
		L.feed(a, now)
		message.emit("أطعمتَ %s ✓" % nm)
		did = true
	if not did:
		if L.is_poultry(str(a.kind)):
			message.emit("%s شبعان" % nm)
		else:
			var left := (1.0 - float(a.get("milk", 0.0))) / L.MILK_PER_DAY * 24.0 * 60.0
			message.emit("%s شبعان — الحليب القادم بعد %d دقيقة (وقت اللعبة)" % [nm, int(ceil(left))])
	return true

func _bar(v: float) -> String:
	var n := int(round(clampf(v, 0.0, 1.0) * 10.0))
	return "█".repeat(n) + "░".repeat(10 - n)

func info_text(pos: Vector3) -> String:
	if GameState.pen.is_empty() or (pos.distance_to(center) > 10.0 and pos.distance_to(farm_center) > 9.0):
		return ""
	var deer := 0
	var ibex := 0
	var elks := 0
	var hens := 0
	var worst := 1.0
	var hung := 0.0
	var now := _now()
	for a in GameState.pen:
		if str(a.kind) == "deer":
			deer += 1
		elif str(a.kind) == "ibex":
			ibex += 1
		elif str(a.kind) == "elk":
			elks += 1
		else:
			hens += 1
		worst = minf(worst, float(a.h))
		hung = maxf(hung, L.hunger(a, now))
	var state := "" if (GameState.barn_built and GameState.farm_built) else " (أكمل بناء الحظيرة وسور المزرعة ليبدأ الاعتناء بها)"
	var milk := 0.0
	var dry := 0
	for a in GameState.pen:
		milk += float(a.get("milk", 0.0))
		if L.hunger(a, now) >= L.WARN and not L.is_poultry(str(a.kind)):
			dry += 1
	var mt := "حليب جاهز: %d" % int(milk) if dry == 0 else "لا حليب: %d جائع!" % dry
	return "الحظيرة: غزلان %d، وعول %d، أيائل %d، دجاج %d%s\nالجوع %s | الصحة %s | علف: تفاح %d، قش %d | %s" % [deer, ibex, elks, hens, state, _bar(clampf(hung / L.GRACE, 0.0, 1.0)), _bar(worst), GameState.count("apples"), GameState.count("hay"), mt]
