extends Node3D
## Hunting: animals roam the forest; aim (over-the-shoulder zoom + crosshair) and fire with a ray from the
## screen centre. Damage depends on the hit zone (head / body / legs). Killed animals give food;
## wounded ones limp, tire out, and can be caught and carried to the farm (3 min trip, optional ad speed-up).
signal message(text: String)
signal aim_changed(on: bool)
signal sound(name: String)
signal scope_changed(on: bool)
signal aim_color_changed(c: Color)
signal player_hurt
signal player_down
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
var pond                            # the lake (set by main): wild animals and birds gather there to drink
var gate_open_cb := Callable()     # set by main: is the farm gate open? (predators can walk in then)
var grace_t := 0.0                  # no attacks for a while after returning home
var _bear_alive := false
var _bear_dead_clock := -999.0
var inv_t := 0.0                    # the player cannot lose another life for a moment after an attack
var _aim_t := 0.0
var _pred_t := 3.0
const WILD := {"deer": 8, "ibex": 5, "elk": 6, "chicken": 10, "turkey": 6, "bird": 6}
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
	for i in 6:
		_spawn("elk")
	for i in 6:
		_spawn("turkey")
	for i in 6:
		_spawn("bird")
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
	if kind == "bird":
		var c := Vector3(_rng.randf_range(-50, 50), 0, _rng.randf_range(-50, 50))
		a.circ_c = Vector3(c.x, world.height_at(c.x, c.z), c.z)
		a.circ_r = _rng.randf_range(9.0, 16.0)
		a.circ_a = _rng.randf() * TAU
		a.alt = _rng.randf_range(13.0, 20.0)
	add_child(a)
	animals.append(a)

func first_of(kind: String):
	for a in animals:
		if is_instance_valid(a) and a.kind == kind and not a.dead:
			return a
	return null

func _process(d: float) -> void:
	cooldown -= d
	inv_t -= d
	_update_drag(d)
	_pred_frame(d)
	_aim_t -= d
	if aiming and _aim_t <= 0.0:
		_aim_t = 0.1
		aim_color_changed.emit(aim_color())
	for a in animals:
		if is_instance_valid(a):
			a.tick(d, player.global_position, player.crouch, world)
	_t += d
	if _t > 0.5:
		_t = 0.0
		_cleanup()
		_transit()
		_maintain()
		_pred_manage()
		_pond_update()

func _cleanup() -> void:
	for a in animals.duplicate():
		if not is_instance_valid(a):
			animals.erase(a)
		elif a.dead and a.corpse_t > 45.0:
			var k: String = a.kind
			animals.erase(a)
			a.queue_free()
			if not L.is_predator(k):
				_spawn(k)

func _transit() -> void:
	var now := Time.get_unix_time_from_system()
	for e in GameState.livestock.duplicate():
		if now >= float(e.eta):
			GameState.livestock.erase(e)
			var k: String = str(e.kind)
			GameState.pen.append(BL.new_animal(GameState.next_pen_id, k, GameState.clock_hours / 24.0))
			GameState.next_pen_id += 1
			message.emit("وصل %s إلى %s ✓" % [L.ANIMALS[k]["name"], "الحظيرة" if BL.is_poultry(k) else "المزرعة"])
			_stage_progress(k)

func transit_text() -> String:
	if drag_node != null:
		if near_barn():
			return "في المزرعة — اضغط «تفاعل» لفكّ %s" % L.ANIMALS[GameState.drag_kind]["name"]
		var left := 0.0
		if barn != null:
			left = Vector2(drag_node.global_position.x - barn.farm_center.x, drag_node.global_position.z - barn.farm_center.z).length()
		return ("تجرّ %s إلى المزرعة — تبقّى %d م" % [L.ANIMALS[GameState.drag_kind]["name"], int(left)]) + ("" if GameState.farm_built else "\nأكمل بناء سور المزرعة وبوابتها أولًا")
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
	var h := _aim_ray()
	if h.is_empty():
		message.emit("أخطأت")
		return
	apply_hit(h["a"], str(h["zone"]))

## What the crosshair points at: {"a": animal, "zone": "head"/"body"/"legs"} or {}.
func _aim_ray() -> Dictionary:
	var w: Dictionary = L.WEAPONS[GameState.weapons[GameState.weapon_idx]]
	var cam: Camera3D = player.cam
	var c := cam.get_viewport().get_visible_rect().size * 0.5
	var o := cam.project_ray_origin(c)
	var q := PhysicsRayQueryParameters3D.create(o, o + cam.project_ray_normal(c) * float(w["range"]), 3)
	q.collide_with_areas = true
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is Area3D):
		return {}
	var area := hit["collider"] as Area3D
	var a = area.get_parent()
	if a == null or not a.is_in_group("animal") or a.dead:
		return {}
	return {"a": a, "zone": str(area.get_meta("zone"))}

## Crosshair colour: RED when this shot would kill, GREEN when it would only wound an animal you can catch alive.
func aim_color() -> Color:
	var h := _aim_ray()
	if h.is_empty():
		return Color(1, 1, 1)
	var a = h["a"]
	var r := L.shot(GameState.weapons[GameState.weapon_idx], str(h["zone"]), a.hp, a.max_hp)
	if r["dead"]:
		return Color(1.0, 0.15, 0.1)
	if r["wound"] and L.capturable(GameState.hunt_stage, a.kind):
		return Color(0.2, 1.0, 0.25)
	return Color(1.0, 0.9, 0.3)

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
		GameState.xp += 10 if L.is_predator(a.kind) else 3
		a.die(GameState.gentle)
		a.has_target = false
		if a.kind == "bird":
			a.global_position.y = world.height_at(a.global_position.x, a.global_position.z) + 0.15
		if GameState.gentle:
			_loot(a)
			message.emit("إصابة في %s — حصلتَ على الطعام" % zn)
		else:
			message.emit("إصابة في %s — %s سقط. اقترب واضغط «تفاعل» لجمع الطعام" % [zn, nm])
	elif L.is_predator(a.kind):
		a.leave_t = 0.0
		message.emit("إصابة في %s — %s غاضب ويهاجم!" % [zn, nm])
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
	var pn: int = int(L.ANIMALS[a.kind].get("pelt", 0))
	if pn > 0:
		GameState.add("pelt", pn)
	GameState.xp += 1
	animals.erase(a)
	get_tree().create_timer(0.7).timeout.connect(a.queue_free)
	message.emit("+%d طعام" % n + (" و+%d جلد" % pn if pn > 0 else ""))

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
	elif not L.capturable(GameState.hunt_stage, best.kind):
		message.emit("لا يمكن التقاط %s حيًّا الآن — مرحلتك: %s. ويمكنك قتله للحصول على لحمه" % [L.ANIMALS[best.kind]["name"], _stage_name()])
	elif best.kind == "deer" or best.kind == "elk":
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
		message.emit("أنت تجرّ حيوانًا بالفعل — أوصله إلى الحظيرة أولًا")
		return
	if not GameState.farm_built:
		message.emit("أكمل بناء سور المزرعة وبوابتها أولًا — هناك يعيش %s" % L.ANIMALS[a.kind]["name"])
		return
	if not GameState.spend("wood", SLED_WOOD):
		message.emit("لجرّ %s تحتاج زلاجة وحبلًا: اقطع %d قطع خشب ثم عُد إليه" % [L.ANIMALS[a.kind]["name"], SLED_WOOD])
		return
	animals.erase(a)
	a.queue_free()
	var kd: String = a.kind
	GameState.drag_kind = kd
	GameState.xp += 2
	_make_drag(kd)
	message.emit("صنعتَ زلاجة وربطتَ %s بالحبل (-%d خشب). اسحبه إلى الحظيرة — الجرّ بطيء" % [L.ANIMALS[kd]["name"], SLED_WOOD])
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
	if not GameState.farm_built:
		return false
	var c: Vector3 = barn.farm_center
	return Vector2(dp.x - c.x, dp.z - c.z).length() < 10.0 or Vector2(pp.x - c.x, pp.z - c.z).length() < 9.0

## «تفاعل» near the barn while pulling the sled: tie the animal up right away.
func try_deliver() -> bool:
	if drag_node == null or drag_busy or not near_barn():
		return false
	_deliver_drag()
	return true

func _deliver_drag() -> void:
	drag_busy = true
	message.emit("وصلتَ المزرعة — تفكّ الحبل...")
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
	message.emit("فككتَ الحبل ووضعتَ %s داخل سور المزرعة ✓ — أطعمه كل يوم واحلبه كل ساعة" % L.ANIMALS[k]["name"])
	GameState.xp += 4
	_stage_progress(k)

# ---------------------------------------------------------------- the lake
## Tells wild animals where the water is (only while it has water), lets 3 birds circle low over it and lowers the level as animals drink.
func _pond_update() -> void:
	if pond == null or pond.water == null:
		return
	var ok: bool = pond.ok()
	var pbirds := 0
	var drinkers := 0
	for a in animals:
		if not is_instance_valid(a) or a.dead or a.predator:
			continue
		if a.kind == "bird":
			if a.pond_bird or pbirds < 3:
				if not a.pond_bird:
					a.pond_bird = true
					a.circ_c = pond.center
				pbirds += 1
				a.pond_ok = ok
			continue
		a.pond_pos = pond.center if ok else Vector3.INF
		a.pond_r = pond.RADIUS
		if a.state == "drink" and a.idle_mode == "eat":
			drinkers += 1
	if drinkers > 0:
		pond.drink(0.004 * float(drinkers))

# ---------------------------------------------------------------- capture stages
func _stage_name() -> String:
	var st: int = GameState.hunt_stage
	return L.STAGES[st]["name"] if st < L.STAGES.size() else "كل الحيوانات متاحة"

func stage_text() -> String:
	var st: int = GameState.hunt_stage
	if st >= L.STAGES.size():
		return "الاصطياد الحي: كل المراحل مكتملة"
	return "مرحلة الاصطياد: %s %d/%d" % [L.STAGES[st]["name"], GameState.stage_n, int(L.STAGES[st]["goal"])]

func _stage_progress(kind: String) -> void:
	if not L.stage_counts(GameState.hunt_stage, kind):
		return
	GameState.stage_n += 1
	var st: Dictionary = L.STAGES[GameState.hunt_stage]
	if GameState.stage_n >= int(st["goal"]):
		GameState.hunt_stage += 1
		GameState.stage_n = 0
		GameState.xp += 10
		if GameState.hunt_stage < L.STAGES.size():
			message.emit("أنهيتَ مرحلة %s ✓ المرحلة التالية: %s (%d)" % [st["name"], L.STAGES[GameState.hunt_stage]["name"], int(L.STAGES[GameState.hunt_stage]["goal"])])
		else:
			message.emit("أنهيتَ كل مراحل الاصطياد الحي ✓")
	else:
		message.emit("تقدّم المرحلة: %d/%d" % [GameState.stage_n, int(st["goal"])])

## Keeps the wild population up (animals that were caught are replaced by new ones elsewhere).
func _maintain() -> void:
	var counts := {}
	for a in animals:
		if is_instance_valid(a) and not a.dead:
			counts[a.kind] = int(counts.get(a.kind, 0)) + 1
	for k in WILD:
		if int(counts.get(k, 0)) < int(WILD[k]):
			_spawn(k)
			return

# ---------------------------------------------------------------- predators (bear by day and night, wolves and foxes at night)
func _fences() -> Array:
	var out: Array = []
	if barn == null:
		return out
	if GameState.farm_built and not (gate_open_cb.is_valid() and gate_open_cb.call()):
		out.append({"c": barn.farm_center, "h": 5.7})
	if GameState.barn_built:
		out.append({"c": barn.barn_center, "h": 4.6})
	return out

## Is a penned animal of this kind safe from predators right now?
func _protected(kind: String) -> bool:
	if BL.is_poultry(kind):
		return GameState.barn_built
	return GameState.farm_built and not (gate_open_cb.is_valid() and gate_open_cb.call())

func _pred_manage() -> void:
	var night := GameState.is_night()
	var cnt := {"bear": 0, "wolf": 0, "fox": 0}
	for a in animals:
		if is_instance_valid(a) and a.predator and not a.dead:
			cnt[a.kind] = int(cnt[a.kind]) + 1
			if (a.kind != "bear") and not night:
				a.leave_t = 30.0                     # night hunters go back to the forest at dawn
				if Vector2(a.global_position.x - player.global_position.x, a.global_position.z - player.global_position.z).length() > 45.0:
					animals.erase(a)
					a.queue_free()
	if int(cnt["bear"]) > 0:
		_bear_alive = true
	elif _bear_alive:
		_bear_alive = false
		_bear_dead_clock = GameState.clock_hours      # a killed bear does not come back for two days
	_pred_t -= 0.5
	if _pred_t > 0.0:
		return
	_pred_t = 20.0
	var started := not GameState.pen.is_empty() or GameState.level() >= 3
	if not started:
		return
	if int(cnt["bear"]) < 1 and GameState.clock_hours - _bear_dead_clock >= L.BEAR_RESPAWN_HOURS:
		_spawn_pred("bear")
	if night and int(cnt["wolf"]) < 2:
		_spawn_pred("wolf")
	if night and int(cnt["fox"]) < 1:
		_spawn_pred("fox")

func _spawn_pred(kind: String) -> void:
	var a := AnimalS.new()
	a.setup(kind, _rng.randi())
	var ang := _rng.randf() * TAU
	var p := Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(54.0, 66.0)     # far out in the forest, never near the house
	if Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() < 40.0:
		p = -p
	p.x = clampf(p.x, -66.0, 66.0)
	p.z = clampf(p.z, -66.0, 66.0)
	a.position = Vector3(p.x, world.height_at(p.x, p.z), p.z)
	add_child(a)
	animals.append(a)
	message.emit("سُمع زئير %s قريبًا!" % L.ANIMALS[kind]["name"] if kind == "bear" else "اقترب %s من المزرعة في الظلام!" % L.ANIMALS[kind]["name"])

## Removes predators close to the house (used when the player is carried home after being downed).
func clear_near_predators() -> void:
	for a in animals.duplicate():
		if is_instance_valid(a) and a.predator and not a.dead and Vector2(a.global_position.x, a.global_position.z).length() < 45.0:
			animals.erase(a)
			a.queue_free()

func _pred_frame(d: float) -> void:
	grace_t = maxf(0.0, grace_t - d)
	var fc := _fences()
	var pp: Vector3 = player.global_position
	var safe := Vector2(pp.x, pp.z).length() < L.SAFE_R
	for a in animals:
		if not is_instance_valid(a) or not a.predator or a.dead:
			continue
		a.fences = fc
		var info: Dictionary = L.ANIMALS[a.kind]
		var gp: Vector3 = a.global_position
		var dp := Vector2(gp.x - pp.x, gp.z - pp.z).length()
		if a.leave_t > 0.0:
			a.has_target = false
			continue
		if safe or grace_t > 0.0:                  # the yard is safe: hunters neither wait at the door nor follow you in
			a.has_target = false
			if Vector2(gp.x, gp.z).length() < L.SAFE_R + 4.0:
				a.leave_t = 6.0
			continue
		var det := float(info["detect"]) * (0.5 if player.crouch else 1.0)
		if det > 0.0 and dp < det:
			a.target = pp
			a.has_target = true
			a.chasing = true
			var rear := float(info.get("rear", 0.0))
			if rear > 0.0:
				if a.rear_state == 1 and a.rear_t <= 0.0:         # finished standing up: strike if still close
					a.rear_state = 0
					if dp < float(info["reach"]) + 0.5 and inv_t <= 0.0:
						_attack_player(a)
					else:
						a.atk_t = 1.0
				elif a.rear_state == 0 and dp < float(info["reach"]) and a.atk_t <= 0.0 and inv_t <= 0.0:
					a.rear_state = 1
					a.rear_t = rear
			elif dp < float(info["reach"]) and a.atk_t <= 0.0 and inv_t <= 0.0:
				_attack_player(a)
			continue
		a.chasing = false
		var best = null
		var bd := 1e9
		for pa in GameState.pen:
			var k := str(pa.kind)
			if a.kind == "fox" and not BL.is_poultry(k):
				continue
			var n = barn.nodes.get(int(pa.id)) if barn != null else null
			if n == null or not is_instance_valid(n):
				continue
			var dd := Vector2(n.global_position.x - gp.x, n.global_position.z - gp.z).length()
			if dd < bd:
				bd = dd
				best = {"pa": pa, "n": n}
		if best == null:
			a.has_target = false
			continue
		a.target = best["n"].global_position
		a.has_target = true
		if bd < float(info["reach"]) + 0.6 and not _protected(str(best["pa"].kind)):
			_eat_pen_animal(a, best["pa"])

func _attack_player(a) -> void:
	if grace_t > 0.0:
		return
	a.atk_t = 3.0
	inv_t = 2.5
	GameState.lives -= 1
	var away: Vector3 = player.global_position - a.global_position
	away.y = 0.0
	if away.length() > 0.1:
		player.global_position += away.normalized() * 1.2
	a.leave_t = 2.5
	player_hurt.emit()
	if GameState.lives <= 0:
		message.emit("أسقطك %s! تعود إلى المنزل بأرواح جديدة" % L.ANIMALS[a.kind]["name"])
		for o in animals:
			if is_instance_valid(o) and o.predator:
				o.leave_t = 15.0
		player_down.emit()
	else:
		message.emit("هجم عليك %s! خسرتَ روحًا — المتبقي %d" % [L.ANIMALS[a.kind]["name"], GameState.lives])

func _eat_pen_animal(pred, pa: Dictionary) -> void:
	var nm: String = L.ANIMALS[str(pa.kind)]["name"]
	var n = barn.nodes.get(int(pa.id))
	if n != null and is_instance_valid(n):
		n.queue_free()
	barn.nodes.erase(int(pa.id))
	GameState.pen.erase(pa)
	pred.leave_t = 25.0
	pred.has_target = false
	message.emit("هجم %s على %s والتهمه! أغلق السور والبوابة لحمايتها" % [L.ANIMALS[pred.kind]["name"], nm])
