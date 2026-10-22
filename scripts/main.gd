extends Node3D
## Entry point: menu -> world/player/builder, day-night cycle, quests, save/load, quality.
const WorldS := preload("res://scripts/world.gd")
const PlayerS := preload("res://scripts/player.gd")
const UIS := preload("res://scripts/ui.gd")
const BuildS := preload("res://scripts/building.gd")
const FarmS := preload("res://scripts/farm.gd")
const HuntS := preload("res://scripts/hunt.gd")
const BarnS := preload("res://scripts/barn.gd")
const SfxS := preload("res://scripts/sfx.gd")

var world
var player
var ui
var builder
var farm
var hunt
var barn
var sfx
var _cluck_t := 4.0
var sun: DirectionalLight3D
var sky: ProceduralSkyMaterial
var env: Environment
var playing := false
var hud_t := 0.0
var save_t := 0.0

func _ready() -> void:
	GameState.load_settings()
	_apply_volume()
	sfx = SfxS.new()
	add_child(sfx)
	_setup_env()
	ui = UIS.new()
	add_child(ui)
	ui.action.connect(_on_action)
	ui.puzzle.dropped.connect(_on_drop)
	Ads.reward_granted.connect(func(pl): if pl == "hint": ui.puzzle.show_hint())
	ui.set_quality_text(GameState.quality)
	ui.set_sound_text(GameState.volume_idx)
	ui.set_day_text(GameState.day_seconds)
	ui.set_gentle_text(GameState.gentle)
	ui.show_menu(GameState.has_save())
	_update_sky()
	if OS.get_environment("WILD_SMOKE") == "1":
		_smoke()

func _smoke() -> void:
	# CI-only: start a new game headless, place a few pieces, then exit. Prints SMOKE OK on success.
	_start(true)
	await get_tree().create_timer(1.0).timeout
	GameState.add("stone", 60)
	ui.open_puzzle(builder.boards[0])
	for i in 6:
		_on_drop(ui.puzzle.tray[0])
	for a in ["chop", "gather", "build", "aim"]:
		player.play_action(a, 0.3)
		await get_tree().create_timer(0.4).timeout
	player.crouch = true
	var cp: Vector3 = player.global_position + Vector3(0, 0, -3)
	farm.plant(cp)
	for day in 8:
		farm.water_near(cp)
		GameState.clock_hours += 24.0
		farm.tick(24.0)
	if GameState.crops.is_empty() or not GameState.crops[0].fruit:
		print("SMOKE FAIL: apple tree did not bear fruit")
		get_tree().quit(1)
		return
	print("SMOKE farm OK")
	var deer = hunt.first_of("deer")
	hunt.apply_hit(deer, "head")
	hunt.apply_hit(deer, "head")
	deer.global_position = player.global_position + Vector3(0, 0, -1)
	var meat0 := GameState.count("meat")
	if not deer.dead or not hunt.interact_nearby() or GameState.count("meat") != meat0 + 6:
		print("SMOKE FAIL: deer kill/loot")
		get_tree().quit(1)
		return
	var hen = hunt.first_of("chicken")
	hunt.apply_hit(hen, "legs")
	hen.global_position = player.global_position + Vector3(0, 0, -1)
	if not hen.wounded or not hunt.interact_nearby() or GameState.livestock.size() != 1:
		print("SMOKE FAIL: wounded chicken capture")
		get_tree().quit(1)
		return
	hunt.toggle_aim()
	hunt.fire()
	GameState.weapons = ["slingshot", "bow", "crossbow"]
	GameState.weapon_idx = 1
	hunt.toggle_scope()
	await get_tree().create_timer(0.4).timeout
	GameState.weapon_idx = 2
	hunt.fire()
	await get_tree().create_timer(0.3).timeout
	hunt.toggle_scope()
	hunt.toggle_aim()
	GameState.weapon_idx = 0
	print("SMOKE hunt OK")
	var cn = player.char_node
	if cn == null or not cn.has_method("is_skinned_ok") or not cn.is_skinned_ok():
		print("SMOKE FAIL: skinned hero not loaded (hero.glb)")
		get_tree().quit(1)
		return
	print("SMOKE hero OK")
	GameState.barn_unlocked = true
	GameState.add("wood", 600)
	for bi in builder.boards.size():
		if str(builder.boards[bi].id).begins_with("B"):
			for pi in builder.boards[bi].pieces.size():
				builder.place(bi, pi)
	GameState.barn_built = builder.barn_done()
	GameState.pen.append(load("res://scripts/barn_logic.gd").new_animal(GameState.next_pen_id, "deer", GameState.clock_hours / 24.0))
	GameState.next_pen_id += 1
	barn.tick(0.1)
	GameState.clock_hours += 30.0
	barn.tick(0.1)
	GameState.add("apples", 3)
	var pen_a = GameState.pen[0]
	if not GameState.barn_built or not barn.interact(barn.center) or float(pen_a.fed) < GameState.clock_hours / 24.0 - 0.01:
		print("SMOKE FAIL: barn feeding")
		get_tree().quit(1)
		return
	print("SMOKE barn OK")
	GameState.xp = 400
	GameState.add("wood", 300)
	GameState.add("stone", 150)
	GameState.add("apples", 30)
	for tid in ["tools", "stealth", "axe2", "pick2", "lamps", "storage", "build_save", "lantern", "compost", "hay2"]:
		var why := GameState.research(tid)
		if why != "":
			print("SMOKE FAIL: research ", tid, " -> ", why)
			get_tree().quit(1)
			return
		GameState.add("wood", 40)
		GameState.add("stone", 20)
		GameState.add("apples", 6)
	_apply_techs()
	if lamp_lights.size() != 6 or GameState.cap_of("wood") != 400:
		print("SMOKE FAIL: tech effects")
		get_tree().quit(1)
		return
	print("SMOKE tech OK")
	if not sfx.is_ready():
		print("SMOKE FAIL: audio files missing")
		get_tree().quit(1)
		return
	print("SMOKE audio OK")
	await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(1.0).timeout
	print("SMOKE OK pieces placed: ", GameState.placed.size())
	get_tree().quit(0)

func _setup_env() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	sky = ProceduralSkyMaterial.new()
	var s := Sky.new()
	s.sky_material = sky
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _update_sky() -> void:
	var t := GameState.time_of_day
	var ang := (t - 6.0) / 24.0 * TAU
	var elev := sin(ang)
	sun.rotation = Vector3(-ang, deg_to_rad(40.0), 0.0)
	sun.light_energy = clampf(elev * 1.3, 0.0, 1.2)
	sun.visible = elev > -0.05
	var day := clampf(elev * 3.0 + 0.5, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0)
	sky.sky_top_color = Color(0.02, 0.03, 0.08).lerp(Color(0.25, 0.5, 0.9), day)
	var hor := Color(0.04, 0.05, 0.1).lerp(Color(0.65, 0.78, 0.9), day).lerp(Color(0.9, 0.45, 0.25), dusk * 0.7)
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor
	sky.ground_bottom_color = sky.sky_top_color * 0.5
	sun.light_color = Color(1, 0.95, 0.85).lerp(Color(1, 0.55, 0.3), dusk)
	env.ambient_light_energy = lerpf(0.15, 1.0, day)
	env.fog_light_color = hor
	env.fog_density = lerpf(0.015, 0.003, day)

func _start(is_new: bool) -> void:
	if is_new:
		GameState.reset()
	else:
		GameState.load_game()
	world = WorldS.new()
	add_child(world)
	world.build(GameState.removed)
	player = PlayerS.new()
	player.position = GameState.player_pos
	add_child(player)
	builder = BuildS.new()
	add_child(builder)
	builder.message.connect(ui.toast)
	farm = FarmS.new()
	farm.world = world
	add_child(farm)
	farm.message.connect(func(t): ui.toast(t, 4.0))
	hunt = HuntS.new()
	hunt.world = world
	hunt.player = player
	add_child(hunt)
	hunt.message.connect(func(t): ui.toast(t, 3.5))
	hunt.aim_changed.connect(ui.set_aim_mode)
	hunt.scope_changed.connect(ui.set_scope_mode)
	player.footstep.connect(func(): sfx.step(player.crouch))
	hunt.sound.connect(func(n): sfx.play(n, -2.0))
	barn = BarnS.new()
	barn.world = world
	add_child(barn)
	barn.message.connect(func(t): ui.toast(t, 4.0))
	if not is_new and GameState.saved_unix > 0.0:
		var away := maxf(0.0, Time.get_unix_time_from_system() - GameState.saved_unix)
		_offline(away * 24.0 / GameState.day_seconds)
	_apply_quality()
	_apply_techs()
	ui.hide_menu()
	player.play_intro()
	ui.cinematic_bars(3.5)
	playing = true
	if not GameState.tutorial_done:
		_tutorial()

## Time spent away: crops grow, animals may weaken but nothing dies (cap: 2 game days).
func _offline(hours: float) -> void:
	var left := minf(hours, 48.0)
	while left > 0.0:
		var st := minf(1.0, left)
		GameState.clock_hours += st
		farm.tick(st, true)
		barn.tick(st, true)
		left -= st
	farm.refresh_all()
	farm.notify_after_offline()
	barn.notify_after_offline()

func _tutorial() -> void:
	GameState.tutorial_done = true
	GameState.save_settings()
	for m in ["مرحبًا! اسحب في الجهة اليسرى للحركة، واسحب يمينًا لتدوير الكاميرا",
			"اقترب من صخرة أو شجرة واضغط «تفاعل» عدة مرات لجمع الحجارة والخشب",
			"اجمع حجارة ثم اضغط «بناء»: اسحب القطعة من الأسفل وأفلتها في مكانها"]:
		ui.toast(m, 4.0)
		await get_tree().create_timer(4.6).timeout

func _apply_quality() -> void:
	var q := GameState.quality
	sun.shadow_enabled = q >= 1
	get_viewport().msaa_3d = Viewport.MSAA_2X if q == 2 else Viewport.MSAA_DISABLED
	if world:
		world.apply_quality(q)

func _apply_volume() -> void:
	var lv := [1.0, 0.6, 0.3, 0.0]
	var v: float = lv[GameState.volume_idx]
	AudioServer.set_bus_mute(0, v <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))

func _on_action(a: String) -> void:
	if a == "jump":
		sfx.play("jump", -8.0)
	elif a != "interact" and a != "fire":
		sfx.play("click", -10.0)
	match a:
		"new": _start(true)
		"continue": _start(false)
		"quality":
			GameState.quality = (GameState.quality + 1) % 3
			ui.set_quality_text(GameState.quality)
			GameState.save_settings()
			_apply_quality()
		"sound":
			GameState.volume_idx = (GameState.volume_idx + 1) % 4
			_apply_volume()
			ui.set_sound_text(GameState.volume_idx)
			GameState.save_settings()
		"jump": player.jump_req = true
		"tech": ui.open_tech()
		"tclose": ui.close_tech()
		"tup": ui.tech.scroll_by(-1)
		"tdown": ui.tech.scroll_by(1)
		"tresearch":
			var tid: String = ui.tech.selected_id()
			var why := GameState.research(tid)
			if why == "":
				sfx.play("chime", -4.0)
				ui.toast("تم التطوير: %s ✓" % preload("res://scripts/tech_logic.gd").by_id(tid)["name"], 3.0)
				_apply_techs()
			else:
				ui.toast(why, 2.5)
		"aim": hunt.toggle_aim()
		"fire": hunt.fire()
		"scope": hunt.toggle_scope()
		"weapon": hunt.cycle_weapon()
		"speed": hunt.speedup()
		"gentle":
			GameState.gentle = not GameState.gentle
			ui.set_gentle_text(GameState.gentle)
			GameState.save_settings()
		"plant":
			var fwd := Vector3(0, 0, -1.4).rotated(Vector3.UP, player.body.rotation.y)
			if farm.plant(player.global_position + fwd):
				player.play_action("gather", 1.0)
				sfx.play("harvest", -6.0, 0.8)
		"water":
			if farm.water_near(player.global_position):
				player.play_action("gather", 0.8)
				sfx.play("water", -4.0)
		"day":
			var cur := GameState.day_seconds
			GameState.day_seconds = 1440.0 if cur < 1000.0 else (2880.0 if cur < 2000.0 else 720.0)
			ui.set_day_text(GameState.day_seconds)
			GameState.save_settings()
		"crouch":
			player.crouch = not player.crouch
			ui.toast("انحناء" if player.crouch else "وقوف", 1.0)
		"interact": _interact()
		"build": _open_build()
		"pclose": ui.close_puzzle()
		"pleft": ui.puzzle.scroll_by(-1)
		"pright": ui.puzzle.scroll_by(1)
		"hint": _hint()
		"torch": _torch()
		"save":
			_save()
			ui.toast("تم الحفظ")

func _open_build() -> void:
	var bi: int = builder.current_index()
	if bi < 0:
		ui.toast("اكتمل المنزل والسور!")
		return
	ui.open_puzzle(builder.boards[bi])

func _on_drop(pi: int) -> void:
	var bi: int = builder.current_index()
	if bi < 0:
		return
	if builder.place(bi, pi):
		sfx.play("place", -2.0, randf_range(0.9, 1.1))
		ui.puzzle.refresh()
		if builder.remaining(bi) == 0:
			ui.toast("اكتملت: %s ✓" % builder.boards[bi].name, 3.0)
			await get_tree().create_timer(0.8).timeout
			ui.close_puzzle()
			player.play_action("build", 1.6)

func _hint() -> void:
	if GameState.hints_left > 0:
		GameState.hints_left -= 1
		ui.puzzle.show_hint()
		ui.toast("الموضع الصحيح يومض — تبقى %d تلميحات" % GameState.hints_left)
	elif Ads.is_available():
		ui.toast("جارٍ تحميل إعلان المكافأة%s" % (" (محاكاة تطوير)" if Ads.is_simulated() else ""))
		Ads.show_rewarded("hint")
	else:
		ui.toast("نفدت التلميحات ولا يتوفر إعلان الآن — جرّب بنفسك!")

var lamp_lights: Array = []

## Apply tech effects that need scene objects (lamp posts, torch strength). Safe to call repeatedly.
func _apply_techs() -> void:
	player.torch.light_energy = 4.0 if GameState.has_tech("lantern") else 2.5
	player.torch.omni_range = 18.0 if GameState.has_tech("lantern") else 12.0
	if GameState.has_tech("lamps") and lamp_lights.is_empty():
		var BD := preload("res://scripts/building_data.gd")
		var pts: Array = [Vector3(-6.8, 0, 6.8), Vector3(6.8, 0, 6.8), Vector3(-6.8, 0, -6.8), Vector3(6.8, 0, -6.8),
			BD.BARN + Vector3(-3.0, 0, 3.2), BD.BARN + Vector3(3.0, 0, 3.2)]
		for p in pts:
			var base := Vector3(p.x, world.height_at(p.x, p.z), p.z)
			var pole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.07
			cm.height = 2.6
			pole.mesh = cm
			pole.position = base + Vector3(0, 1.3, 0)
			pole.material_override = preload("res://scripts/mats.gd").pbr("bark", Color(0.8, 0.7, 0.6), 1.5, 0.9)
			add_child(pole)
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.12
			sm.height = 0.24
			bulb.mesh = sm
			bulb.position = base + Vector3(0, 2.7, 0)
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(1.0, 0.85, 0.5)
			bm.emission_enabled = true
			bm.emission = Color(1.0, 0.75, 0.35)
			bm.emission_energy_multiplier = 2.0
			bulb.material_override = bm
			add_child(bulb)
			var l := OmniLight3D.new()
			l.omni_range = 9.0
			l.light_energy = 1.6
			l.light_color = Color(1.0, 0.8, 0.5)
			l.position = base + Vector3(0, 2.8, 0)
			l.visible = false
			add_child(l)
			lamp_lights.append(l)

func _torch() -> void:
	if not GameState.torch_owned:
		if GameState.spend("wood", 2):
			GameState.torch_owned = true
			ui.toast("صنعتَ مشعلًا (2 خشب)")
		else:
			ui.toast("المشعل يحتاج 2 خشب")
			return
	player.torch.visible = not player.torch.visible

func _interact() -> void:
	if barn.interact(player.global_position):
		player.play_action("gather", 0.8)
		return
	if hunt.interact_nearby():
		player.play_action("gather", 0.8)
		return
	var best = null
	var bd := 4.0
	for g in ["tree", "rock", "crop"]:
		for n in get_tree().get_nodes_in_group(g):
			var d: float = n.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = n
	if best == null:
		ui.toast("لا يوجد شيء قريب للتفاعل")
		return
	if best.is_in_group("crop"):
		player.play_action("gather", 0.8)
		farm.interact(int(best.get_meta("cid")))
		return
	player.play_action("chop" if best.is_in_group("tree") else "gather", 0.9)
	sfx.play("chop" if best.is_in_group("tree") else "rock", -3.0, randf_range(0.92, 1.08))
	var hp: int = int(best.get_meta("hp")) - (2 if GameState.has_tech("tools") else 1)
	if hp > 0:
		best.set_meta("hp", hp)
		ui.toast("ضربة! متبقي %d" % hp, 1.0)
		return
	GameState.removed[int(best.get_meta("id"))] = true
	if best.is_in_group("tree"):
		var wn := 8 if GameState.has_tech("axe2") else 5
		var gw := GameState.add("wood", wn)
		ui.toast("+%d خشب" % gw if gw == wn else "الحقيبة ممتلئة! (+%d خشب) — طوّر التخزين" % gw)
	else:
		var sn := 9 if GameState.has_tech("pick2") else 6
		var gs2 := GameState.add("stone", sn)
		player.carry_t = 6.0
		ui.toast("+%d حجارة" % gs2 if gs2 == sn else "الحقيبة ممتلئة! (+%d حجارة) — طوّر التخزين" % gs2)
	GameState.xp += 1
	sfx.play("harvest", -6.0)
	best.queue_free()

func _process(d: float) -> void:
	sfx.update(d, GameState.time_of_day, playing)
	if not playing:
		return
	_cluck_t -= d
	if _cluck_t <= 0.0:
		_cluck_t = randf_range(5.0, 12.0)
		for a in hunt.animals:
			if is_instance_valid(a) and a.kind == "chicken" and not a.dead and a.global_position.distance_to(player.global_position) < 30.0:
				sfx.play_at(a.global_position + Vector3(0, 0.4, 0))
				break
	var dh := d * 24.0 / GameState.day_seconds
	GameState.clock_hours += dh
	GameState.time_of_day = fposmod(GameState.clock_hours, 24.0)
	farm.tick(dh)
	barn.tick(dh)
	_update_sky()
	hud_t += d
	if hud_t > 0.25:
		hud_t = 0.0
		_hud()
	save_t += d
	if save_t > 30.0:
		save_t = 0.0
		_save()

func _hud() -> void:
	var g := GameState
	var q := ""
	var bi: int = builder.current_index()
	if bi < 0:
		q = "اصطد واحصل على حيوان حي لفتح الحظيرة (أصِب الساق ثم تفاعل)" if not GameState.barn_unlocked else "الحظيرة جاهزة: أطعم الحيوانات كل يوم (اقترب واضغط «تفاعل»)"
	else:
		var b: Dictionary = builder.boards[bi]
		var cost: String = b.pieces[0].cost
		q = "%s — متبقي %d قطعة — لديك %d %s. اجمع ثم اضغط «بناء»" % [b.name, builder.remaining(bi), g.count(cost), "حجارة" if cost == "stone" else "خشب"]
	var hr := int(g.time_of_day)
	var res := "خشب %d | حجر %d | بذور %d | تفاح %d | مستوى %d | الوقت %02d:%02d" % [g.count("wood"), g.count("stone"), g.count("seeds"), g.count("apples"), g.level(), hr, int((g.time_of_day - hr) * 60.0)]
	var night := GameState.time_of_day < 6.0 or GameState.time_of_day >= 18.5
	for l in lamp_lights:
		l.visible = night
	GameState.barn_built = GameState.barn_unlocked and builder.barn_done()
	var ct: String = farm.info_text(player.global_position)
	if ct == "":
		ct = barn.info_text(player.global_position)
	ui.set_crop(ct)
	var tt: String = hunt.transit_text()
	ui.set_hunt(hunt.weapon_text() + ("\n" + tt if tt != "" else ""))
	ui.set_speed_visible(tt != "")
	ui.set_hud(res, q)

func _save() -> void:
	if not playing:
		return
	GameState.player_pos = player.global_position
	GameState.save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
