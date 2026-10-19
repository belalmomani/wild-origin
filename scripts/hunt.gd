extends Node3D
## Hunting: animals roam the forest; aim (over-the-shoulder zoom + crosshair) and fire with a ray from the
## screen centre. Damage depends on the hit zone (head / body / legs). Killed animals give food;
## wounded ones limp, tire out, and can be caught and carried to the farm (3 min trip, optional ad speed-up).
signal message(text: String)
signal aim_changed(on: bool)
const L := preload("res://scripts/hunt_logic.gd")
const AnimalS := preload("res://scripts/animal.gd")
const BL := preload("res://scripts/barn_logic.gd")
var world
var player
var animals: Array = []
var aiming := false
var cooldown := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 2026
	for i in 8:
		_spawn("deer")
	for i in 10:
		_spawn("chicken")
	Ads.reward_granted.connect(_on_reward)

func _spawn(kind: String) -> void:
	var a := AnimalS.new()
	a.setup(kind, _rng.randi())
	var p := Vector2(_rng.randf_range(-62, 62), _rng.randf_range(-62, 62))
	if p.length() < 20.0:
		p = Vector2(20.0 + _rng.randf() * 20.0, 0.0).rotated(_rng.randf() * TAU)
	if player != null and Vector2(p.x - player.global_position.x, p.y - player.global_position.z).length() < 25.0:
		p = -p
	a.position = Vector3(p.x, world.height_at(p.x, p.y), p.y)
	a.rotation.y = _rng.randf() * TAU
	add_child(a)
	animals.append(a)

func first_of(kind: String):
	for a in animals:
		if is_instance_valid(a) and a.kind == kind and not a.dead:
			return a
	return null

func _process(d: float) -> void:
	cooldown -= d
	for a in animals:
		if is_instance_valid(a):
			a.tick(d, player.global_position, player.crouch, world)
	_t += d
	if _t > 0.5:
		_t = 0.0
		_cleanup()
		_transit()

func _cleanup() -> void:
	for a in animals.duplicate():
		if not is_instance_valid(a):
			animals.erase(a)
		elif a.dead and a.corpse_t > 45.0:
			var k: String = a.kind
			animals.erase(a)
			a.queue_free()
			_spawn(k)

func _transit() -> void:
	var now := Time.get_unix_time_from_system()
	for e in GameState.livestock.duplicate():
		if now >= float(e.eta):
			GameState.livestock.erase(e)
			var k: String = str(e.kind)
			GameState.pen.append(BL.new_animal(GameState.next_pen_id, k, GameState.clock_hours / 24.0))
			GameState.next_pen_id += 1
			message.emit("وصل %s إلى الحظيرة ✓" % L.ANIMALS[k]["name"])

func transit_text() -> String:
	if GameState.livestock.is_empty():
		return ""
	var e: Dictionary = GameState.livestock[0]
	var left := maxi(0, int(float(e.eta) - Time.get_unix_time_from_system()))
	return "في الطريق إلى المزرعة: %s — %d:%02d" % [L.ANIMALS[str(e.kind)]["name"], left / 60, left % 60]

func weapon_text() -> String:
	var wid: String = GameState.weapons[GameState.weapon_idx]
	var w: Dictionary = L.WEAPONS[wid]
	var ammo: String = w["ammo"]
	return "السلاح: %s | %s: %d" % [w["name"], "حجارة" if ammo == "stone" else "سهام", GameState.count(ammo)]

func toggle_aim() -> void:
	aiming = not aiming
	player.set_aim(aiming)
	aim_changed.emit(aiming)

func cycle_weapon() -> void:
	var cur: String = GameState.weapons[GameState.weapon_idx]
	var nxt: String = L.ORDER[(L.ORDER.find(cur) + 1) % L.ORDER.size()]
	if GameState.weapons.has(nxt):
		GameState.weapon_idx = GameState.weapons.find(nxt)
		message.emit("السلاح: %s" % L.WEAPONS[nxt]["name"])
	elif GameState.level() >= int(L.WEAPONS[nxt]["level"]):
		_unlock(nxt)
	elif Ads.is_available():
		message.emit("%s مقفل (المستوى %d) — شاهد إعلان مكافأة لفتحه%s" % [L.WEAPONS[nxt]["name"], L.WEAPONS[nxt]["level"], " (محاكاة تطوير)" if Ads.is_simulated() else ""])
		Ads.show_rewarded("weapon_" + nxt)
	else:
		message.emit("%s مقفل — يُفتح بالمستوى %d" % [L.WEAPONS[nxt]["name"], L.WEAPONS[nxt]["level"]])

func _unlock(id: String) -> void:
	if not GameState.weapons.has(id):
		GameState.weapons.append(id)
	GameState.weapon_idx = GameState.weapons.find(id)
	message.emit("فُتح السلاح: %s ✓" % L.WEAPONS[id]["name"])

func speedup() -> void:
	if GameState.livestock.is_empty():
		return
	if Ads.is_available():
		message.emit("جارٍ تحميل إعلان المكافأة%s" % (" (محاكاة تطوير)" if Ads.is_simulated() else ""))
		Ads.show_rewarded("speedup")
	else:
		message.emit("لا يتوفر إعلان الآن — الحيوان سيصل بعد انتهاء الوقت")

func _on_reward(pl: String) -> void:
	if pl == "speedup":
		for e in GameState.livestock:
			e.eta = Time.get_unix_time_from_system()
		message.emit("تم تسريع الرحلة")
	elif pl.begins_with("weapon_"):
		_unlock(pl.substr(7))

func fire() -> void:
	if not aiming:
		message.emit("اضغط «تصويب» أولًا")
		return
	if cooldown > 0.0:
		return
	var wid: String = GameState.weapons[GameState.weapon_idx]
	var w: Dictionary = L.WEAPONS[wid]
	var ammo: String = w["ammo"]
	if GameState.count(ammo) < 1:
		if ammo == "arrows" and GameState.spend("wood", 1):
			GameState.add("arrows", 5)
			message.emit("صنعتَ 5 سهام (1 خشب)")
		else:
			message.emit("لا توجد ذخيرة (%s)" % ("حجارة" if ammo == "stone" else "سهام"))
			return
	GameState.spend(ammo, 1)
	cooldown = 0.7
	var cam: Camera3D = player.cam
	var c := cam.get_viewport().get_visible_rect().size * 0.5
	var o := cam.project_ray_origin(c)
	var q := PhysicsRayQueryParameters3D.create(o, o + cam.project_ray_normal(c) * float(w["range"]), 3)
	q.collide_with_areas = true
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is Area3D):
		message.emit("أخطأت")
		return
	var area := hit["collider"] as Area3D
	var a = area.get_parent()
	if a == null or not a.is_in_group("animal") or a.dead:
		message.emit("أخطأت")
		return
	apply_hit(a, str(area.get_meta("zone")))

func apply_hit(a, zone: String) -> void:
	var wid: String = GameState.weapons[GameState.weapon_idx]
	var r := L.shot(wid, zone, a.hp, a.max_hp)
	a.hp = r["hp"]
	var nm: String = L.ANIMALS[a.kind]["name"]
	var names := {"head": "الرأس", "body": "الجسم", "legs": "الساق"}
	var zn: String = names[zone]
	if r["dead"]:
		GameState.xp += 3
		a.die(GameState.gentle)
		if GameState.gentle:
			_loot(a)
			message.emit("إصابة في %s — حصلتَ على الطعام" % zn)
		else:
			message.emit("إصابة في %s — %s سقط. اقترب واضغط «تفاعل» لجمع الطعام" % [zn, nm])
	elif r["wound"]:
		a.wounded = true
		a.state = "flee"
		a.state_t = 3.0
		message.emit("إصابة في %s — %s مصاب! تتبّعه والتقطه (تفاعل) قبل أن يبتعد" % [zn, nm])
	else:
		a.state = "flee"
		a.state_t = 3.5
		message.emit("إصابة خفيفة في %s" % zn)

func _loot(a) -> void:
	var n: int = L.ANIMALS[a.kind]["meat"]
	GameState.add("meat", n)
	GameState.xp += 1
	animals.erase(a)
	get_tree().create_timer(0.7).timeout.connect(a.queue_free)
	message.emit("+%d طعام" % n)

## Loot a dead animal or catch a wounded one that is close. Returns true if something was handled.
func interact_nearby() -> bool:
	var best = null
	var bd := 3.2
	for a in animals:
		if is_instance_valid(a) and (a.dead or a.wounded):
			var dd: float = a.global_position.distance_to(player.global_position)
			if dd < bd:
				bd = dd
				best = a
	if best == null:
		return false
	if best.dead:
		_loot(best)
	else:
		GameState.livestock.append({"kind": best.kind, "eta": Time.get_unix_time_from_system() + L.TRANSIT_SECONDS})
		message.emit("التقطتَ %s. رحلة النقل إلى المزرعة 3 دقائق." % L.ANIMALS[best.kind]["name"])
		if not GameState.barn_unlocked:
			GameState.barn_unlocked = true
			message.emit("فُتحت مهمة بناء الحظيرة! اضغط «بناء».")
		animals.erase(best)
		best.queue_free()
		GameState.xp += 2
	return true
