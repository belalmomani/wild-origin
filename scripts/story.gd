extends Node
## Story, chapter 1 — "The lost travellers".
## Once the lookout tower is finished and the player is near, two girls and a man appear lost in the forest with three
## wolves on their trail. The player must kill the wolves. The survivors then stay beside the tower, the settlers' cabin
## (boards C_1..C_5) opens and they build it together with the player: every few seconds each traveller puts a piece in.
signal message(text: String)
const BD := preload("res://scripts/building_data.gd")
const L := preload("res://scripts/hunt_logic.gd")
const AnimalS := preload("res://scripts/animal.gd")
const NpcS := preload("res://scripts/npc.gd")
const NAMES := ["ليلى", "سلمى", "سالم"]
const KINDS := ["girl", "girl", "man"]
const START_R := 75.0            # the player must be within this distance of the tower for the travellers to appear
const WOLF_BITE := 5.0
const WOLF_GAP := 3.0
const AGGRO_R := 13.0            # a wolf this close to the player forgets the traveller and goes for the player
const RETRY_HOURS := 48.0
const WORK_EVERY := 7.0          # seconds between two pieces of one traveller
var builder
var player
var hunt
var world
var tower
var npcs: Array = []             # index = traveller id (0..2); null when never spawned / gone
var wolves: Array = []
var _warn_t := 0.0
var _work_t := 0.0
var _ended_t := 0.0

func _ready() -> void:
	call_deferred("_restore")

## Loaded game: settled travellers come back to the camp.
func _restore() -> void:
	if GameState.story_stage >= 2:
		npcs = [null, null, null]
		for i in 3:
			if GameState.story_alive[i]:
				_make_npc(i, _camp_pos(i))

func camp_center() -> Vector3:
	return Vector3(BD.CABIN_C.x - 7.0, 0, BD.CABIN_C.z + 1.0)

func _camp_pos(i: int) -> Vector3:
	var c := camp_center()
	var a := TAU * float(i) / 3.0 + 0.6
	return _ground(c + Vector3(cos(a), 0, sin(a)) * 2.2)

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, world.height_at(p.x, p.z), p.z)

func _make_npc(i: int, pos: Vector3):
	var n := NpcS.new()
	n.setup(KINDS[i], i)
	n.position = pos
	add_child(n)
	npcs[i] = n
	return n

func active() -> bool:
	return GameState.story_stage == 1

func alive_count() -> int:
	var n := 0
	for x in npcs:
		if x != null and is_instance_valid(x) and not x.dead:
			n += 1
	return n

## Short line for the quest panel, "" when the story has nothing to say.
func quest_text() -> String:
	match GameState.story_stage:
		1:
			var w := 0
			for a in wolves:
				if is_instance_valid(a) and not a.dead:
					w += 1
			return "أنقذ التائهين — اقتل الذئاب (%d) — الناجون %d" % [w, alive_count()]
		2:
			var bi := _cabin_index()
			if bi >= 0:
				return "ابنِ الكوخ مع الناجين: %s (%d قطع)" % [str(builder.boards[bi].name), builder.remaining(bi)]
		3:
			return "الكوخ اكتمل — في انتظار الفصل التالي"
	return ""

func cabin_board_index() -> int:
	return _cabin_index()

## The cabin board to open when the player stands near the site (-1 when not available / too far).
func cabin_board_near(pos: Vector3) -> int:
	if GameState.story_stage < 2 or _flat(pos, BD.CABIN_C) > 25.0:
		return -1
	return _cabin_index()

func _cabin_index() -> int:
	for i in 5:
		var bi: int = builder.index_of("C_%d" % (i + 1))
		if bi >= 0 and builder.available(bi) and builder.remaining(bi) > 0:
			return bi
	return -1

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _process(d: float) -> void:
	if builder == null or player == null or hunt == null or world == null:
		return
	match GameState.story_stage:
		0:
			_maybe_start()
		1:
			_chapter_frame(d)
		_:
			_camp_frame(d)

func _maybe_start() -> void:
	if tower == null or not tower.done():
		return
	if GameState.story_clock >= 0.0 and GameState.clock_hours - GameState.story_clock < RETRY_HOURS:
		return
	if _flat(player.global_position, BD.TOWER_C) > START_R:
		return
	_start()

func _start() -> void:
	GameState.story_stage = 1
	GameState.story_alive = [true, true, true]
	for x in npcs:
		if x != null and is_instance_valid(x):
			x.queue_free()
	npcs = [null, null, null]
	wolves.clear()
	var tc := BD.TOWER_C
	var out := Vector3(tc.x, 0, tc.z).normalized()          # the forest side, away from the house
	var side := Vector3(-out.z, 0, out.x)
	for i in 3:
		var p := tc + out * 24.0 + side * (float(i) - 1.0) * 2.5
		p.x = clampf(p.x, -64.0, 64.0)
		p.z = clampf(p.z, -64.0, 64.0)
		_make_npc(i, _ground(p))
	for i in 3:
		var p2 := tc + out * 33.0 + side * (float(i) - 1.0) * 3.5
		p2.x = clampf(p2.x, -66.0, 66.0)
		p2.z = clampf(p2.z, -66.0, 66.0)
		var a := AnimalS.new()
		a.setup("wolf", 4000 + i)
		a.story = true
		a.position = _ground(p2)
		hunt.add_child(a)
		hunt.animals.append(a)
		wolves.append(a)
	_warn_t = 0.0
	message.emit("صرخات من جهة الغابة قرب برج المراقبة! ثلاثة تائهين تطاردهم الذئاب — أسرع لإنقاذهم!")

func _nearest_npc(pos: Vector3):
	var best = null
	var bd := 1e9
	for x in npcs:
		if x == null or not is_instance_valid(x) or x.dead:
			continue
		var dd := _flat(x.global_position, pos)
		if dd < bd:
			bd = dd
			best = x
	return best

func _chapter_frame(d: float) -> void:
	var pp: Vector3 = player.global_position
	var safe: bool = Vector2(pp.x, pp.z).length() < L.SAFE_R or hunt.grace_t > 0.0
	# --- wolves
	var wolves_left := 0
	for i in wolves.size():
		var w = wolves[i]
		if not is_instance_valid(w) or w.dead:
			continue
		wolves_left += 1
		w.fences = []
		if w.leave_t > 0.0:
			continue                                   # just bitten the player: backs off for a moment
		var wp: Vector3 = w.global_position
		var dpl := _flat(wp, pp)
		if dpl < AGGRO_R and not safe:
			w.target = pp
			w.has_target = true
			w.chasing = true
			if dpl < float(L.ANIMALS["wolf"]["reach"]) + 0.5 and w.atk_t <= 0.0 and hunt.inv_t <= 0.0:
				hunt._attack_player(w)
			continue
		var tgt = null
		if i < npcs.size() and npcs[i] != null and is_instance_valid(npcs[i]) and not npcs[i].dead:
			tgt = npcs[i]                              # each wolf hunts "its" traveller, then the nearest one
		else:
			tgt = _nearest_npc(wp)
		if tgt == null:
			w.has_target = false
			continue
		w.target = tgt.global_position
		w.has_target = true
		w.chasing = true
		if _flat(wp, tgt.global_position) < 2.4 and w.atk_t <= 0.0:
			w.atk_t = WOLF_GAP
			tgt.hit(WOLF_BITE)
	# --- travellers
	var near_wolf := false
	for x in npcs:
		if x == null or not is_instance_valid(x):
			continue
		if x.dead:
			x.animate(d, 0.0, "idle")
			continue
		var ground := Vector3(x.position.x, 0, x.position.z)
		var threat = null
		var td := 1e9
		for w in wolves:
			if is_instance_valid(w) and not w.dead:
				var dd := _flat(w.global_position, x.global_position)
				if dd < td:
					td = dd
					threat = w
		var mode := "idle"
		var spd := 0.0
		var dir := Vector3.ZERO
		if threat != null and td < 16.0:
			near_wolf = true
			mode = "scared"
			var away: Vector3 = x.global_position - threat.global_position
			away.y = 0.0
			var tp := Vector3(BD.TOWER_C.x, 0, BD.TOWER_C.z)
			# run around the tower, not into the lake: pull gently toward the tower
			dir = (away.normalized() * 0.8 + (tp - ground).normalized() * 0.2).normalized()
			spd = 3.0 if td < 6.0 else 4.2
		else:
			var tpd := _flat(x.global_position, BD.TOWER_C)
			var goal := Vector3(BD.TOWER_C.x, 0, BD.TOWER_C.z)
			if _flat(pp, BD.TOWER_C) < 40.0 and _flat(x.global_position, pp) > 4.0:
				goal = Vector3(pp.x, 0, pp.z)          # seek the player's protection
			var to := goal - ground
			if to.length() > 3.0 and tpd > 0.0:
				dir = to.normalized()
				spd = 4.0
				mode = "run"
		if spd > 0.0:
			var np: Vector3 = x.position + dir * spd * d
			np.x = clampf(np.x, -66.0, 66.0)
			np.z = clampf(np.z, -66.0, 66.0)
			if world.height_at(np.x, np.z) > BD.WATER_Y + 0.6 and not _wet(np):
				x.position.x = np.x
				x.position.z = np.z
			x.rotation.y = lerp_angle(x.rotation.y, atan2(-dir.x, -dir.z), 8.0 * d)
		x.position.y = world.height_at(x.position.x, x.position.z)
		x.animate(d, spd, mode)
	# --- warnings and endings
	_warn_t -= d
	if _warn_t <= 0.0 and wolves_left > 0:
		_warn_t = 25.0
		message.emit("أنقذ التائهين! الذئاب قرب برج المراقبة (%d ذئب — الناجون %d)" % [wolves_left, alive_count()])
	if wolves_left == 0:
		_rescued()
	elif alive_count() == 0:
		_failed()

func _wet(p: Vector3) -> bool:
	return Vector2(p.x - BD.POND_C.x, p.z - BD.POND_C.z).length() < BD.POND_R + 0.5

func _rescued() -> void:
	GameState.story_stage = 2
	for i in 3:
		var x = npcs[i] if i < npcs.size() else null
		GameState.story_alive[i] = x != null and is_instance_valid(x) and not x.dead
	GameState.xp += 10
	var names: Array = []
	for i in 3:
		if GameState.story_alive[i]:
			names.append(NAMES[i])
	message.emit("نجوتم! شكرًا لك — %s ينضمّون إليك" % "، ".join(PackedStringArray(names)))
	get_tree().create_timer(5.0).timeout.connect(func(): message.emit("قرّر الناجون البقاء هنا. ابنِ معهم كوخًا قرب البرج — افتح لوح البناء"))

func _failed() -> void:
	GameState.story_stage = 0
	GameState.story_clock = GameState.clock_hours
	for w in wolves:
		if is_instance_valid(w) and not w.dead:
			w.story = false                            # the ordinary hunt rules take over; they wander off at dawn
			w.leave_t = 60.0
	for x in npcs:
		if x != null and is_instance_valid(x):
			get_tree().create_timer(4.0).timeout.connect(x.queue_free)
	npcs.clear()
	wolves.clear()
	message.emit("لم ينجُ أحد... سيمرّ مسافرون آخرون بعد يومين")

func _camp_frame(d: float) -> void:
	var stage := GameState.story_stage
	if stage == 2 and builder.cabin_done():
		GameState.story_stage = 3
		stage = 3
		GameState.xp += 15
		message.emit("اكتمل الكوخ! تعيش مع الناجين هنا. أخبرني ما التالي")
	var bi := _cabin_index()
	_work_t -= d
	var working := stage == 2 and bi >= 0
	if working and _work_t <= 0.0:
		_work_t = WORK_EVERY / maxf(1.0, float(alive_count()))
		builder.place_free(bi)
	for i in npcs.size():
		var x = npcs[i]
		if x == null or not is_instance_valid(x) or x.dead:
			continue
		var home := _camp_pos(i)
		var goal := home
		if working:
			var a := TAU * float(i) / 3.0 + 1.0
			goal = _ground(Vector3(BD.CABIN_C.x - 4.6, 0, BD.CABIN_C.z) + Vector3(cos(a), 0, sin(a)) * 1.6)
		var to := Vector3(goal.x - x.position.x, 0, goal.z - x.position.z)
		var mode := "idle"
		var spd := 0.0
		if to.length() > 0.7:
			var dir := to.normalized()
			spd = 3.0
			mode = "run"
			var np: Vector3 = x.position + dir * spd * d
			if world.height_at(np.x, np.z) > BD.WATER_Y + 0.6 and not _wet(np):
				x.position.x = np.x
				x.position.z = np.z
			x.rotation.y = lerp_angle(x.rotation.y, atan2(-dir.x, -dir.z), 8.0 * d)
		elif working:
			mode = "work"
			var face := Vector3(BD.CABIN_C.x - x.position.x, 0, BD.CABIN_C.z - x.position.z)
			x.rotation.y = lerp_angle(x.rotation.y, atan2(-face.x, -face.z), 5.0 * d)
		x.position.y = world.height_at(x.position.x, x.position.z)
		x.animate(d, spd, mode)
