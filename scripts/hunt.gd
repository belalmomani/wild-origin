extends Node3D
## Hunting: animals roam the forest; aim (over-the-shoulder zoom + crosshair) and fire with a ray from the
## screen centre. Damage depends on the hit zone (head / body / legs). Killed animals give food;
## wounded ones limp, tire out, and can be caught and carried to the farm (3 min trip, optional ad speed-up).
signal message(text: String)
signal aim_changed(on: bool)
signal sound(name: String)
signal scope_changed(on: bool)
const L := preload("res://scripts/hunt_logic.gd")
const AnimalS := preload("res://scripts/animal.gd")
const BL := preload("res://scripts/barn_logic.gd")
const M := preload("res://scripts/mats.gd")
var world
var player
var barn                    # set by main: where the dragged animal is delivered
var drag_node: Node3D = null
var drag_animal = null
var drag_rope: MeshInstance3D = null
var drag_busy := false
var animals: Array = []
var aiming := false
var scoped := false
var cooldown := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 2026
	for i in 8:
		_spawn("deer")
	for i in 5:
		_spawn("ibex")
	for i in 10:
		_spawn("chicken")
	Ads.reward_granted.connect(_on_reward)
	if GameState.drag_kind != "":
		_make_drag(GameState.drag_kind)

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
	_update_drag(d)
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
	if drag_node != null:
		if near_barn():
			return "في الحظيرة — اضغط «تفاعل» لربط الغزال"
		var left := 0.0
		if barn != null:
			left = Vector2(drag_node.global_position.x - barn.center.x, drag_node.global_position.z - barn.center.z).length()
		return "تجرّ غزالًا إلى الحظيرة — تبقّى %d م" % int(left)
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
	if aiming:
		GameState.equip = "weapon"
	if not aiming and scoped:
		_set_scope(false)
	player.set_aim(aiming)
	aim_changed.emit(aiming)

func _weapon_id() -> String:
	return GameState.weapons[GameState.weapon_idx]

## Aim style: normal (over-the-shoulder zoom) or through the scope (bow / crossbow only).
func toggle_scope() -> void:
	if not aiming:
		message.emit("اضغط «تصويب» أولًا")
		return
	if _weapon_id() == "slingshot":
		message.emit("المقلاع لا يدعم العدسة — بدّل السلاح")
		return
	_set_scope(not scoped)
	message.emit("التصويب بالعدسة" if scoped else "التصويب العادي")

func _set_scope(on: bool) -> void:
	scoped = on
	player.set_scope(on, 28.0 if _weapon_id() == "bow" else 16.0)
	scope_changed.emit(on)

func cycle_weapon() -> void:
	var cur: String = GameState.weapons[GameState.weapon_idx]
	var nxt: String = L.ORDER[(L.ORDER.find(cur) + 1) % L.ORDER.size()]
	if GameState.weapons.has(nxt):
		GameState.weapon_idx = GameState.weapons.find(nxt)
		message.emit("السلاح: %s" % L.WEAPONS[nxt]["name"])
		_check_scope()
	elif GameState.level() >= int(L.WEAPONS[nxt]["level"]):
		_unlock(nxt)
	elif Ads.is_available():
		message.emit("%s مقفل (المستوى %d) — شاهد إعلان مكافأة لفتحه%s" % [L.WEAPONS[nxt]["name"], L.WEAPONS[nxt]["level"], " (محاكاة تطوير)" if Ads.is_simulated() else ""])
		Ads.show_rewarded("weapon_" + nxt)
	else:
		message.emit("%s مقفل — يُفتح بالمستوى %d" % [L.WEAPONS[nxt]["name"], L.WEAPONS[nxt]["level"]])

func _check_scope() -> void:
	if scoped and _weapon_id() == "slingshot":
		_set_scope(false)
	elif scoped:
		player.set_scope(true, 28.0 if _weapon_id() == "bow" else 16.0)

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
	sound.emit("shot_sling" if wid == "slingshot" else "shot_bow")
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
	if not r["dead"]:
		a.flinch()
	sound.emit("hit")
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
	elif best.kind == "deer":
		_start_drag(best)
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

# ---------------------------------------------------------------- dragging a caught deer to the barn
const SLED_WOOD := 8
const ROPE_LEN := 2.6
const DRAG_SPEED := 0.42        # walking speed while pulling the sled

## A wounded deer caught by hand: build a sled (wood) + rope, tie the deer onto it and drag it to the barn.
func _start_drag(a) -> void:
	if drag_node != null:
		message.emit("أنت تجرّ غزالًا بالفعل — أوصله إلى الحظيرة أولًا")
		return
	if not GameState.spend("wood", SLED_WOOD):
		message.emit("لجرّ الغزال تحتاج زلاجة وحبلًا: اقطع %d قطع خشب ثم عُد إليه" % SLED_WOOD)
		return
	animals.erase(a)
	a.queue_free()
	GameState.drag_kind = "deer"
	GameState.xp += 2
	_make_drag("deer")
	message.emit("صنعتَ زلاجة وربطتَ الغزال بالحبل (-%d خشب). اسحبه إلى الحظيرة — الجرّ بطيء" % SLED_WOOD)
	if not GameState.barn_unlocked:
		GameState.barn_unlocked = true
		message.emit("فُتحت مهمة بناء الحظيرة! اضغط «بناء».")

func _make_drag(kind: String) -> void:
	var wood := M.pbr("bark", Color(0.9, 0.8, 0.65), 1.5, 0.9)
	var rope_m := M.flat(Color(0.75, 0.62, 0.38), 0.9)
	drag_node = Node3D.new()
	add_child(drag_node)
	var back := Vector3(0, 0, ROPE_LEN).rotated(Vector3.UP, player.body.rotation.y)
	var p: Vector3 = player.global_position + back
	drag_node.global_position = Vector3(p.x, world.height_at(p.x, p.z), p.z)
	drag_node.rotation.y = player.body.rotation.y
	for sx in [-0.28, 0.28]:                       # two runners + planks
		var r := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.08, 0.08, 2.0)
		r.mesh = rb
		r.material_override = wood
		r.position = Vector3(sx, 0.06, 0)
		drag_node.add_child(r)
	for i in 5:
		var pl := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.78, 0.05, 0.28)
		pl.mesh = pb
		pl.material_override = wood
		pl.position = Vector3(0, 0.13, -0.78 + i * 0.39)
		drag_node.add_child(pl)
	drag_animal = AnimalS.new()
	drag_animal.setup(kind, 7)
	drag_animal.tame = true
	for c in drag_animal.get_children():
		if c is Area3D:
			(c as Area3D).collision_layer = 0
	drag_animal.rotation = Vector3(0, 0, PI / 2.0)       # lying on its side, head toward the rope (-Z)
	drag_animal.position = Vector3(1.0, 0.42, 0.0)
	drag_node.add_child(drag_animal)
	var strap := MeshInstance3D.new()                   # rope band holding it down
	var sb := BoxMesh.new()
	sb.size = Vector3(0.9, 0.04, 0.05)
	strap.mesh = sb
	strap.material_override = rope_m
	strap.position = Vector3(0, 0.62, 0.1)
	drag_node.add_child(strap)
	drag_rope = MeshInstance3D.new()
	var rb2 := BoxMesh.new()
	rb2.size = Vector3(0.03, 0.03, 1.0)
	drag_rope.mesh = rb2
	drag_rope.material_override = rope_m
	drag_rope.top_level = true
	add_child(drag_rope)
	player.speed_mult = DRAG_SPEED

func _update_drag(d: float) -> void:
	if drag_node == null or drag_busy:
		return
	var pp: Vector3 = player.global_position
	var dp: Vector3 = drag_node.global_position
	var v := Vector3(pp.x - dp.x, 0, pp.z - dp.z)
	var dist := v.length()
	if dist > ROPE_LEN:
		dp += v.normalized() * (dist - ROPE_LEN)
	dp.y = world.height_at(dp.x, dp.z)
	drag_node.global_position = dp
	if dist > 0.3:
		drag_node.rotation.y = lerp_angle(drag_node.rotation.y, atan2(-v.x, -v.z), 6.0 * d)
	# the rope runs from the player's hands to the front of the sled
	var a := pp + Vector3(0, 0.95, 0)
	var front: Vector3 = drag_node.global_transform * Vector3(0, 0.2, -1.0)
	var ln := a.distance_to(front)
	if ln > 0.05:
		(drag_rope.mesh as BoxMesh).size = Vector3(0.03, 0.03, ln)
		drag_rope.global_position = (a + front) * 0.5
		drag_rope.look_at(front, Vector3.UP)
	if near_barn():
		_deliver_drag()

## True when the sled (or the player) is in the barn yard.
func near_barn() -> bool:
	if drag_node == null or barn == null:
		return false
	var dp: Vector3 = drag_node.global_position
	var pp: Vector3 = player.global_position
	var c: Vector3 = barn.center
	return Vector2(dp.x - c.x, dp.z - c.z).length() < 10.0 or Vector2(pp.x - c.x, pp.z - c.z).length() < 9.0

## «تفاعل» near the barn while pulling the sled: tie the animal up right away.
func try_deliver() -> bool:
	if drag_node == null or drag_busy or not near_barn():
		return false
	_deliver_drag()
	return true

func _deliver_drag() -> void:
	drag_busy = true
	message.emit("وصلتَ الحظيرة — تفكّ الحبل...")
	player.speed_mult = 1.0
	await get_tree().create_timer(1.0).timeout
	var k := GameState.drag_kind
	GameState.drag_kind = ""
	GameState.pen.append(BL.new_animal(GameState.next_pen_id, k, GameState.clock_hours / 24.0))
	GameState.next_pen_id += 1
	if barn != null:
		barn._sync()                                  # the animal appears in the yard right away
	if is_instance_valid(drag_node):
		drag_node.queue_free()
	if is_instance_valid(drag_rope):
		drag_rope.queue_free()
	drag_node = null
	drag_rope = null
	drag_animal = null
	drag_busy = false
	message.emit("فككتَ الحبل ووضعتَ الغزال في الحظيرة ✓ — أطعمه كل يوم ليعطيك حليبًا")
	GameState.xp += 4
