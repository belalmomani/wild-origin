extends Node3D
## Entry point: menu -> world/player/builder, day-night cycle, quests, save/load, quality.
const WorldS := preload("res://scripts/world.gd")
const HuntLogic := preload("res://scripts/hunt_logic.gd")
const PlayerS := preload("res://scripts/player.gd")
const UIS := preload("res://scripts/ui.gd")
const BuildS := preload("res://scripts/building.gd")
const FarmS := preload("res://scripts/farm.gd")
const ForageS := preload("res://scripts/forage.gd")
const HuntS := preload("res://scripts/hunt.gd")
const BarnS := preload("res://scripts/barn.gd")
const SfxS := preload("res://scripts/sfx.gd")
const HomeS := preload("res://scripts/home.gd")
const WellS := preload("res://scripts/well.gd")
const PondS := preload("res://scripts/pond.gd")
const FishS := preload("res://scripts/fishing.gd")
const WeatherS := preload("res://scripts/weather.gd")
const WL := preload("res://scripts/weather_logic.gd")

var world
var player
var ui
var builder
var farm
var hunt
var barn
var home
var well
var pond
var fishing
var weather
var sleeping := false
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
	ui.set_sens_text(GameState.sens_idx)
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
	GameState.well = 1
	farm.plant(cp)
	for day in 8:
		GameState.bucket = 4
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
	if get_tree().get_nodes_in_group("forage").size() < 10:
		print("SMOKE FAIL: no forage grass in the forest")
		get_tree().quit(1)
		return
	var fcrop: Dictionary = load("res://scripts/farm_logic.gd").new_crop(99, 3.0, 3.0, 0.0, "fodder")
	GameState.crops.append(fcrop)
	farm._spawn(fcrop)
	fcrop["fruit"] = true
	fcrop["g"] = 2.0
	farm._refresh(fcrop)
	var hay0 := GameState.count("hay")
	farm.interact(99)
	if GameState.count("hay") != hay0 + 4 or fcrop.fruit:
		print("SMOKE FAIL: fodder harvest")
		get_tree().quit(1)
		return
	GameState.crops.erase(fcrop)
	farm.nodes[99].queue_free()
	farm.nodes.erase(99)
	var ibx = hunt.first_of("ibex")
	if ibx == null or ibx.bones.is_empty():
		print("SMOKE FAIL: ibex model missing")
		get_tree().quit(1)
		return
	ibx.tick(0.1, player.global_position + Vector3(0, 0, 100), false, world)
	hunt.apply_hit(ibx, "head")
	hunt.apply_hit(ibx, "head")
	ibx.global_position = player.global_position + Vector3(0, 0, -1)
	meat0 = GameState.count("meat")
	if not ibx.dead or not hunt.interact_nearby() or GameState.count("meat") != meat0 + 5:
		print("SMOKE FAIL: ibex kill/loot")
		get_tree().quit(1)
		return
	var elk = hunt.first_of("elk")
	if elk == null or elk.elk == null:
		print("SMOKE FAIL: elk model missing")
		get_tree().quit(1)
		return
	elk.tick(0.1, player.global_position + Vector3(0, 0, 100), false, world)
	elk.tick(0.1, player.global_position + Vector3(0, 0, 100), false, world)
	for i in 3:
		hunt.apply_hit(elk, "head")
	elk.global_position = player.global_position + Vector3(0, 0, -1)
	meat0 = GameState.count("meat")
	if not elk.dead or not hunt.interact_nearby() or GameState.count("meat") != meat0 + 9:
		print("SMOKE FAIL: elk kill/loot")
		get_tree().quit(1)
		return
	print("SMOKE elk OK")
	for pk in ["wolf", "bear", "fox"]:
		hunt._spawn_pred(pk)
	var seen := 0
	for pa in hunt.animals:
		if is_instance_valid(pa) and pa.predator:
			seen += 1
			pa.tick(0.1, player.global_position, false, world)
			if pa.gl == null or pa.gl.ap == null or not pa.gl.has_clip("cycle_walk") or not pa.gl.has_clip("idle_breathe"):
				print("SMOKE FAIL: predator model ", pa.kind, " gl=", pa.gl != null, " ap=", pa.gl != null and pa.gl.ap != null, " clips=", pa.gl.clips.keys() if pa.gl != null else [])
				get_tree().quit(1)
				return
	var bird = hunt.first_of("bird")
	if seen != 3 or bird == null or bird.wings.size() != 2:
		print("SMOKE FAIL: predators / bird ", seen)
		get_tree().quit(1)
		return
	bird.tick(0.1, player.global_position, false, world)
	print("SMOKE predators OK")
	GameState.channel = true
	GameState.pond = 0.8
	await get_tree().create_timer(0.3).timeout
	hunt._pond_update()
	var dr = hunt.first_of("deer")
	if dr.pond_pos == Vector3.INF or pond.water == null:
		print("SMOKE FAIL: lake")
		get_tree().quit(1)
		return
	print("SMOKE lake OK")
	var rod_ok := true
	for rb in builder.boards:
		if str(rb.id) == "R_rod":
			if builder.available(builder.index_of("R_rod")) == false:
				rod_ok = false
			for rp in rb.pieces:
				GameState.placed[rp.id] = true
	var shore: Vector3 = load("res://scripts/building_data.gd").POND_C + Vector3(load("res://scripts/building_data.gd").POND_R + 0.9, 0, 0)
	var fish0 := GameState.count("fish")
	if not rod_ok or not fishing.has_rod() or not fishing.interact(shore) or fishing.state != "wait":
		print("SMOKE FAIL: fishing cast")
		get_tree().quit(1)
		return
	fishing.state = "bite"
	fishing.t = 1.0
	fishing.interact(shore)
	if GameState.count("fish") <= fish0:
		print("SMOKE FAIL: fish catch")
		get_tree().quit(1)
		return
	print("SMOKE fishing OK")
	var clock0: float = GameState.clock_hours
	var wd0 := 0
	while not WL.rains_on(wd0):
		wd0 += 1
	var ww0: Vector3 = WL.rain_window(wd0)
	GameState.clock_hours = wd0 * 24.0 + (ww0.x + ww0.y) * 0.5
	var pl0: float = GameState.pond
	GameState.pond = 0.3
	pond.tick(1.0)
	weather.strength = 1.0
	weather.update(0.1, GameState.clock_hours)
	if GameState.pond <= 0.3 or not weather.parts.emitting:
		print("SMOKE FAIL: rain should fill the lake and emit")
		get_tree().quit(1)
		return
	GameState.pond = pl0
	weather.strength = 0.0
	GameState.clock_hours = clock0
	print("SMOKE weather OK")
	GameState.hunt_stage = 3
	GameState.farm_built = true
	var dd = hunt.first_of("deer")
	GameState.add("wood", 8)
	hunt.apply_hit(dd, "legs")
	dd.global_position = player.global_position + Vector3(0, 0, -1)
	if not dd.wounded or not hunt.interact_nearby() or hunt.drag_node == null or GameState.drag_kind != "deer":
		print("SMOKE FAIL: deer drag start")
		get_tree().quit(1)
		return
	hunt._update_drag(0.1)
	player.speed_mult = 1.0
	GameState.drag_kind = ""
	hunt.drag_node.queue_free()
	hunt.drag_rope.queue_free()
	hunt.drag_node = null
	hunt.drag_rope = null
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
	if not cn.has_method("face_ready") or not cn.face_ready() or cn.pack_i < 0:
		print("SMOKE FAIL: hero face morph targets or pack bone missing")
		get_tree().quit(1)
		return
	for emo in ["smile", "surprise", "focus", "fear", "tired"]:
		player.emote(emo, 0.3)
		await get_tree().create_timer(0.35).timeout
	print("SMOKE face OK")
	GameState.barn_unlocked = true
	GameState.add("wood", 600)
	for bi in builder.boards.size():
		if str(builder.boards[bi].id).begins_with("B"):
			for pi in builder.boards[bi].pieces.size():
				builder.place(bi, pi)
	GameState.barn_built = builder.barn_done()
	GameState.farm_built = true
	GameState.pen.append(load("res://scripts/barn_logic.gd").new_animal(GameState.next_pen_id, "deer", GameState.clock_hours / 24.0))
	GameState.next_pen_id += 1
	barn.tick(0.1)
	GameState.clock_hours += 30.0
	barn.tick(0.1)
	GameState.add("apples", 3)
	var pen_a = GameState.pen[0]
	if not GameState.barn_built or not barn.interact(barn.nodes[int(pen_a.id)].global_position) or float(pen_a.fed) < GameState.clock_hours / 24.0 - 0.01:
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
	# interior phase: build every board, then check door / glass / lamp / fire / bed wiring
	for bi3 in builder.boards.size():
		var pcs: Array = builder.boards[bi3].pieces
		for pi3 in pcs.size():
			GameState.add(str(pcs[pi3].cost), 3)
			builder.place(bi3, pi3)
	home.refresh()
	if not builder.shell_done() or not builder.door_complete() or home.glass_count() != 2 or not home.lamp_ready() or not home.fire_lit():
		print("SMOKE FAIL: interior wiring")
		get_tree().quit(1)
		return
	if not home.interact(Vector3(0, 0, 3.0)) or not builder.is_open("house"):
		print("SMOKE FAIL: door interaction")
		get_tree().quit(1)
		return
	if not home.interact(Vector3(0, 0, 8.0)) or not builder.is_open("fence"):
		print("SMOKE FAIL: fence gate interaction")
		get_tree().quit(1)
		return
	if not builder.farm_done() or not home.interact(Vector3(-6.5, 0, 0)) or not builder.is_open("farm"):
		print("SMOKE FAIL: farm gate interaction")
		get_tree().quit(1)
		return
	if GameState.builds_done < 5 or GameState.difficulty() <= 1.0:
		print("SMOKE FAIL: difficulty does not grow: ", GameState.builds_done)
		get_tree().quit(1)
		return
	var fuel0: float = GameState.fire_fuel
	home.tick(1.0)
	if GameState.fire_fuel >= fuel0:
		print("SMOKE FAIL: fire fuel does not burn")
		get_tree().quit(1)
		return
	print("SMOKE interior OK")
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
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.32     # vivid, storybook colours
	env.adjustment_brightness = 1.03
	env.glow_enabled = true          # soft bloom on the lamp, fire and sun (ignored on renderers without glow)
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.85
	env.fog_sun_scatter = 0.18       # warm haze toward the sun
	env.tonemap_white = 5.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _update_sky() -> void:
	var t := GameState.time_of_day
	# long day (05:00-21:00 = half a turn over 16 h), short night (21:00-05:00 = the other half over 8 h)
	var ang: float
	if t >= GameState.NIGHT_END and t < GameState.NIGHT_START:
		ang = (t - GameState.NIGHT_END) / (GameState.NIGHT_START - GameState.NIGHT_END) * PI
	else:
		ang = PI + fposmod(t - GameState.NIGHT_START, 24.0) / (24.0 - GameState.NIGHT_START + GameState.NIGHT_END) * PI
	var elev := sin(ang)
	sun.rotation = Vector3(-ang, deg_to_rad(40.0), 0.0)
	sun.light_energy = clampf(elev * 1.6, 0.0, 1.5)
	sun.visible = elev > -0.05
	var day := smoothstep(-0.15, 0.35, elev)
	var dusk := clampf(1.0 - absf(elev - 0.05) * 3.5, 0.0, 1.0)
	sky.sky_top_color = Color(0.02, 0.03, 0.08).lerp(Color(0.14, 0.42, 0.96), day)
	var hor := Color(0.04, 0.05, 0.1).lerp(Color(0.62, 0.83, 1.0), day).lerp(Color(0.9, 0.45, 0.25), dusk * 0.7)
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor
	sky.ground_bottom_color = sky.sky_top_color * 0.5
	sun.light_color = Color(1.0, 0.96, 0.84).lerp(Color(1, 0.55, 0.3), dusk)
	env.ambient_light_energy = lerpf(0.15, 1.3, day)
	env.fog_light_color = hor
	env.fog_density = lerpf(0.015, 0.0022, day)
	var wet: float = weather.dim() if weather != null else 0.0
	if wet > 0.0:                                  # overcast: grey, dim, hazy
		var grey := Color(0.45, 0.48, 0.52) * lerpf(0.25, 1.0, day)
		sky.sky_top_color = sky.sky_top_color.lerp(grey, wet * 0.8)
		sky.sky_horizon_color = sky.sky_horizon_color.lerp(grey * 1.1, wet * 0.8)
		sky.ground_horizon_color = sky.sky_horizon_color
		sun.light_energy *= 1.0 - 0.6 * wet
		env.ambient_light_energy *= 1.0 - 0.3 * wet
		env.fog_light_color = sky.sky_horizon_color
		env.fog_density += 0.006 * wet

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
	pond = PondS.new()
	pond.world = world
	add_child(pond)
	weather = WeatherS.new()
	weather.target = player
	add_child(weather)
	fishing = FishS.new()
	fishing.world = world
	fishing.pond = pond
	fishing.builder = builder
	fishing.player = player
	add_child(fishing)
	fishing.message.connect(func(t): ui.toast(t, 3.5))
	fishing.action.connect(func(a): player.play_action(a, 0.8))
	well = WellS.new()
	well.world = world
	well.pond = pond
	add_child(well)
	well.message.connect(func(t): ui.toast(t, 4.0))
	well.action.connect(func(a): player.play_action(a, 1.2))
	farm.harvested.connect(well.on_harvest)
	var forage := ForageS.new()
	forage.world = world
	add_child(forage)
	hunt = HuntS.new()
	hunt.world = world
	hunt.player = player
	add_child(hunt)
	hunt.message.connect(func(t): ui.toast(t, 3.5))
	hunt.aim_changed.connect(ui.set_aim_mode)
	hunt.aim_color_changed.connect(ui.set_crosshair_color)
	hunt.player_hurt.connect(func(): sfx.play("hit", -2.0))
	hunt.player_down.connect(_on_player_down)
	hunt.gate_open_cb = func(): return builder.is_open("farm")
	hunt.pond = pond
	hunt.scope_changed.connect(ui.set_scope_mode)
	player.footstep.connect(func(): sfx.step(player.crouch))
	hunt.sound.connect(func(n): sfx.play(n, -2.0))
	barn = BarnS.new()
	barn.world = world
	add_child(barn)
	barn.message.connect(func(t): ui.toast(t, 4.0))
	hunt.barn = barn
	barn.player = player
	home = HomeS.new()
	home.builder = builder
	add_child(home)
	home.message.connect(func(t): ui.toast(t, 3.5))
	home.sleep_request.connect(_sleep)
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
		pond.tick(st)
		barn.tick(st, true)
		home.tick(st, true)
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
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 100.0 if q == 2 else 60.0
	sun.shadow_blur = 1.6 if q == 2 else 1.0
	env.glow_enabled = q >= 1
	if ui:
		ui.vignette.visible = q >= 1 and playing
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
				player.emote("smile", 2.0)
				ui.toast("تم التطوير: %s ✓" % preload("res://scripts/tech_logic.gd").by_id(tid)["name"], 3.0)
				_apply_techs()
			else:
				ui.toast(why, 2.5)
		"aim": hunt.toggle_aim()
		"fire": hunt.fire()
		"scope": hunt.toggle_scope()
		"weapon":
			# hands: nothing -> axe -> weapons (each in turn) -> nothing
			if GameState.equip == "none":
				GameState.equip = "axe"
			elif GameState.equip == "axe":
				GameState.equip = "weapon"
			elif GameState.weapons[GameState.weapon_idx] == "crossbow":
				GameState.equip = "none"
			else:
				var before: int = GameState.weapon_idx
				hunt.cycle_weapon()
				if GameState.weapon_idx == before:      # next one is locked: put the weapon away
					GameState.equip = "none"
			if GameState.equip != "weapon" and hunt.aiming:
				hunt.toggle_aim()
			_equip_text()
		"speed": hunt.speedup()
		"sens":
			GameState.sens_idx = (GameState.sens_idx + 1) % 3
			ui.set_sens_text(GameState.sens_idx)
			GameState.save_settings()
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
		"pnext": _next_board()
		"pleft": ui.puzzle.scroll_by(-1)
		"pright": ui.puzzle.scroll_by(1)
		"hint": _hint()
		"torch": _torch()
		"coat": _craft_coat()
		"home": _go_home()
		"save":
			if _save():
				ui.toast("تم الحفظ ✓")

## Sews a coat from bear / wolf / fox pelts: +2 lives for good.
func _craft_coat() -> void:
	if GameState.coat:
		ui.toast("لديك معطف من الجلد بالفعل (+2 روح)", 2.5)
		return
	var have := GameState.count("pelt")
	if have < HuntLogic.COAT_PELTS:
		ui.toast("المعطف يحتاج %d جلود (لديك %d). اصطد الدب والذئب والثعلب واجمع جلودها" % [HuntLogic.COAT_PELTS, have], 4.0)
		return
	GameState.spend("pelt", HuntLogic.COAT_PELTS)
	GameState.coat = true
	GameState.lives += HuntLogic.COAT_LIVES
	ui.toast("صنعتَ معطفًا من الجلد! +2 روح (الحد الأقصى %d)" % GameState.max_lives(), 4.0)
	player.play_action("gather", 0.8)

func _open_build() -> void:
	var bi: int = builder.current_index()
	if bi < 0:
		ui.toast("اكتمل المنزل والسور!")
		return
	ui.open_puzzle(builder.boards[bi])

## Switch the open puzzle to the next unfinished board (walls, door, bed, ...).
func _next_board() -> void:
	var cur: int = builder.index_of(str(ui.puzzle.board.get("id", "")))
	var n: int = builder.next_available(cur)
	if n < 0 or n == cur:
		ui.toast("لا توجد لوحات أخرى متاحة الآن", 1.8)
		return
	ui.open_puzzle(builder.boards[n])
	ui.toast("اللوحة: %s" % builder.boards[n].name, 1.8)

func _sleep() -> void:
	if sleeping:
		return
	sleeping = true
	ui.fade_black(1.2)
	await get_tree().create_timer(0.7).timeout
	_offline(fposmod(6.0 - GameState.time_of_day, 24.0))
	GameState.time_of_day = fposmod(GameState.clock_hours, 24.0)
	_update_sky()
	_save()
	ui.toast("نمتَ حتى الصباح — استيقظتَ مرتاحًا", 3.0)
	player.emote("smile", 2.5)
	sleeping = false

func _on_drop(pi: int) -> void:
	var bi: int = builder.index_of(str(ui.puzzle.board.get("id", "")))
	if bi < 0:
		return
	if builder.place(bi, pi):
		sfx.play("place", -2.0, randf_range(0.9, 1.1))
		home.refresh()
		ui.puzzle.refresh()
		_save()
		if builder.remaining(bi) == 0:
			ui.toast("اكتملت: %s ✓" % builder.boards[bi].name, 3.0)
			player.emote("smile", 2.5)
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

func _on_player_down() -> void:
	GameState.lives = GameState.max_lives()
	hunt.grace_t = 25.0
	hunt.clear_near_predators()
	_go_home()

func _interact() -> void:
	if hunt.try_deliver():
		return
	if well.interact(player.global_position):
		return
	if fishing.interact(player.global_position):
		return
	if home.interact(player.global_position):
		player.play_action("gather", 0.8)
		return
	if barn.interact(player.global_position):
		player.play_action("gather", 0.8)
		return
	if hunt.interact_nearby():
		player.play_action("gather", 0.8)
		return
	var best = null
	var bd := 4.0
	for g in ["tree", "rock", "crop", "forage"]:
		for n in get_tree().get_nodes_in_group(g):
			var d: float = n.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = n
	if best == null:
		ui.toast("لا يوجد شيء قريب للتفاعل")
		return
	if best.is_in_group("forage"):
		player.play_action("gather", 0.8)
		var ns := randi_range(1, 3)
		GameState.add("gseeds", ns)
		GameState.removed[int(best.get_meta("id"))] = true
		GameState.xp += 1
		ui.toast("+%d بذور علف — ازرعها في المزرعة المسوّرة" % ns, 2.5)
		sfx.play("harvest", -6.0)
		best.queue_free()
		return
	if best.is_in_group("crop"):
		player.play_action("gather", 0.8)
		farm.interact(int(best.get_meta("cid")))
		return
	if best.is_in_group("tree"):
		GameState.equip = "axe"
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
	weather.update(d, GameState.clock_hours)
	farm.tick(dh)
	pond.tick(dh)
	barn.tick(dh)
	home.tick(dh)
	_update_sky()
	hud_t += d
	if hud_t > 0.25:
		hud_t = 0.0
		_hud()
	save_t += d
	if save_t > 10.0:
		save_t = 0.0
		_save()

## «🏠 المنزل»: fade out, stand in front of the house door looking at it (to see what has been built).
func _go_home() -> void:
	if sleeping or not playing or player.intro_lock:
		return
	sleeping = true                        # reuse the flag as "busy" so nothing else moves us meanwhile
	ui.fade_black(0.9)
	await get_tree().create_timer(0.7).timeout
	var c: Vector3 = load("res://scripts/building_data.gd").DOORS["house"]["c"]
	var p := c + Vector3(0, 0, 3.4)
	player.global_position = Vector3(p.x, world.height_at(p.x, p.z) + 0.3, p.z)
	player.velocity = Vector3.ZERO
	player.cam_yaw = 0.0
	player.cam_pitch = -0.12
	player.body.rotation.y = 0.0
	ui.toast("أنت أمام المنزل", 1.5)
	sleeping = false

func _equip_text() -> void:
	ui.set_equip_text(GameState.equip, str(HuntLogic.WEAPONS[GameState.weapons[GameState.weapon_idx]]["name"]))

func _hud() -> void:
	_equip_text()
	var g := GameState
	var q := ""
	var bi: int = builder.current_index()
	if bi < 0:
		q = "اصطد واحصل على حيوان حي لفتح الحظيرة (أصِب الساق ثم تفاعل)" if not GameState.barn_unlocked else "الحظيرة جاهزة: أطعم الحيوانات كل يوم (اقترب واضغط «تفاعل»)"
	else:
		var b: Dictionary = builder.boards[bi]
		var cost: String = builder.next_cost(bi)
		q = "%s — متبقي %d قطعة — لديك %d %s. اجمع ثم اضغط «بناء»" % [b.name, builder.remaining(bi), g.count(cost), "حجارة" if cost == "stone" else "خشب"]
	var hr := int(g.time_of_day)
	ui.set_stats({"time": "%02d:%02d" % [hr, int((g.time_of_day - hr) * 60.0)], "wood": g.count("wood"), "stone": g.count("stone"), "apples": g.count("apples"), "meat": g.count("meat"), "fish": g.count("fish"), "pelt": g.count("pelt"), "level": g.level()})
	ui.set_lives(g.lives, g.max_lives())
	var res := ""
	if g.count("seeds") + g.count("gseeds") + g.count("hay") + g.count("milk") > 0:
		res = "بذور %d | بذور علف %d | علف %d | حليب %d" % [g.count("seeds"), g.count("gseeds"), g.count("hay"), g.count("milk")]
	var night := GameState.is_night()
	for l in lamp_lights:
		l.visible = night
	home.set_night(night)
	GameState.barn_built = GameState.barn_unlocked and builder.barn_done()
	if builder.farm_done() and not GameState.farm_built:
		ui.toast("اكتملت المزرعة! الأشجار داخلها تنمو أسرع بنسبة 25%", 4.0)
	GameState.farm_built = builder.farm_done()
	ui.set_prompt(_prompt())
	var ct: String = farm.info_text(player.global_position)
	if ct == "":
		ct = barn.info_text(player.global_position)
	if ct == "":
		ct = well.info_text(player.global_position)
	if ct == "":
		ct = fishing.info_text(player.global_position)
	if ct == "":
		ct = pond.info_text(player.global_position)
	if ct == "":
		ct = home.info_text(player.global_position)
	ui.set_crop(ct)
	res += ("\n" if res != "" else "") + hunt.stage_text()
	var tt: String = hunt.transit_text()
	ui.set_hunt(hunt.weapon_text() + ("\n" + tt if tt != "" else ""))
	ui.set_speed_visible(tt != "")
	res += "\n" + WL.hud_text(GameState.clock_hours)
	ui.set_hud(res, q)

## Hint for the interact button: what pressing it would do right here.
func _prompt() -> String:
	if player.intro_lock or ui.in_puzzle:
		return ""
	var pos: Vector3 = player.global_position
	if hunt.near_barn() and not hunt.drag_busy:
		return "تفاعل: فكّ الحيوان داخل المزرعة"
	var wh: String = well.hint(pos)
	if wh != "":
		return wh
	var fh: String = fishing.hint(pos)
	if fh != "":
		return fh
	var h: String = home.hint(pos)
	if h != "":
		return h
	var best = null
	var bd := 3.2
	for g in ["tree", "rock", "crop", "forage"]:
		for n in get_tree().get_nodes_in_group(g):
			var d: float = n.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = n
	if best == null:
		return ""
	if best.is_in_group("forage"):
		return "تفاعل: اجمع بذور العشب"
	if best.is_in_group("crop"):
		return "تفاعل: اعتنِ بالمزروعات (حصاد / فحص)"
	return "تفاعل: اقطع الشجرة" if best.is_in_group("tree") else "تفاعل: كسّر الصخرة"

func _save() -> bool:
	if not playing:
		return false
	GameState.player_pos = player.global_position
	var ok := GameState.save_game()
	if not ok:
		ui.toast("تعذّر الحفظ على هذا الجهاز!", 3.0)
	return ok

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save()
