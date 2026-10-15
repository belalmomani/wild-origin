extends Node3D
## Entry point: menu -> world/player/builder, day-night cycle, quests, save/load, quality.
const WorldS := preload("res://scripts/world.gd")
const PlayerS := preload("res://scripts/player.gd")
const UIS := preload("res://scripts/ui.gd")
const BuildS := preload("res://scripts/building.gd")
const DAY_SECONDS := 720.0  # one in-game day = 12 real minutes

var world
var player
var ui
var builder
var sun: DirectionalLight3D
var sky: ProceduralSkyMaterial
var env: Environment
var playing := false
var hud_t := 0.0
var save_t := 0.0

func _ready() -> void:
	GameState.load_settings()
	AudioServer.set_bus_mute(0, GameState.muted)
	_setup_env()
	ui = UIS.new()
	add_child(ui)
	ui.action.connect(_on_action)
	ui.set_quality_text(GameState.quality)
	ui.set_sound_text(not GameState.muted)
	ui.show_menu(GameState.has_save())
	_update_sky()

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
	builder.player = player
	add_child(builder)
	builder.message.connect(ui.toast)
	builder.state_changed.connect(func(): ui.set_build_mode(builder.active))
	_apply_quality()
	ui.hide_menu()
	playing = true
	if not GameState.tutorial_done:
		_tutorial()

func _tutorial() -> void:
	GameState.tutorial_done = true
	GameState.save_settings()
	for m in ["مرحبًا! اسحب في الجهة اليسرى للحركة، واسحب يمينًا لتدوير الكاميرا",
			"اقترب من شجرة واضغط «تفاعل» عدة مرات لجمع الخشب",
			"اجمع 20 خشبة ثم اضغط «بناء» لتركيب أول منزل قطعة قطعة"]:
		ui.toast(m, 4.0)
		await get_tree().create_timer(4.6).timeout

func _apply_quality() -> void:
	var q := GameState.quality
	sun.shadow_enabled = q >= 1
	get_viewport().msaa_3d = Viewport.MSAA_2X if q == 2 else Viewport.MSAA_DISABLED
	if world:
		world.apply_quality(q)

func _on_action(a: String) -> void:
	match a:
		"new": _start(true)
		"continue": _start(false)
		"quality":
			GameState.quality = (GameState.quality + 1) % 3
			ui.set_quality_text(GameState.quality)
			GameState.save_settings()
			_apply_quality()
		"sound":
			GameState.muted = not GameState.muted
			AudioServer.set_bus_mute(0, GameState.muted)
			ui.set_sound_text(not GameState.muted)
			GameState.save_settings()
		"jump": player.jump_req = true
		"interact": _interact()
		"build":
			builder.toggle()
			ui.set_build_mode(builder.active)
		"rotate": builder.rotate_step()
		"up": builder.change_lift(1)
		"down": builder.change_lift(-1)
		"next": builder.next_type()
		"place": builder.place()
		"hint": builder.hint()
		"torch": _torch()
		"save":
			_save()
			ui.toast("تم الحفظ")

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
	var best = null
	var bd := 4.0
	for g in ["tree", "rock"]:
		for n in get_tree().get_nodes_in_group(g):
			var d: float = n.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = n
	if best == null:
		ui.toast("لا يوجد شيء قريب للتفاعل")
		return
	var hp: int = int(best.get_meta("hp")) - 1
	if hp > 0:
		best.set_meta("hp", hp)
		ui.toast("ضربة! متبقي %d" % hp, 1.0)
		return
	GameState.removed[int(best.get_meta("id"))] = true
	if best.is_in_group("tree"):
		GameState.add("wood", 3)
		ui.toast("+3 خشب")
	else:
		GameState.add("stone", 2)
		ui.toast("+2 حجر")
	GameState.xp += 1
	best.queue_free()

func _process(d: float) -> void:
	if not playing:
		return
	GameState.time_of_day = fposmod(GameState.time_of_day + d * 24.0 / DAY_SECONDS, 24.0)
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
	match g.phase:
		0:
			q = "اجمع الخشب: %d/20" % g.count("wood")
			if g.count("wood") >= 20:
				g.phase = 1
				ui.toast("ممتاز! اضغط «بناء» وابدأ بتركيب المنزل", 4.0)
		1:
			var r: int = builder.remaining("h")
			q = "ابنِ المنزل — قطع متبقية: %d" % r
			if r == 0:
				g.phase = 2
				ui.toast("اكتمل المنزل! اجمع الحجارة لبناء السور", 4.0)
		2:
			q = "اجمع الحجارة: %d/19" % g.count("stone")
			if g.count("stone") >= 19:
				g.phase = 3
				ui.toast("اضغط «بناء» لتركيب أحجار السور", 4.0)
		3:
			var r2: int = builder.remaining("f")
			q = "ابنِ السور — أحجار متبقية: %d" % r2
			if r2 == 0:
				g.phase = 4
		_:
			q = "اكتملت المرحلة الأولى (الصيد والمزرعة قيد التطوير)"
	var hr := int(g.time_of_day)
	var res := "خشب %d | حجر %d | مستوى %d | الوقت %02d:%02d | الصحة 100" % [g.count("wood"), g.count("stone"), g.level(), hr, int((g.time_of_day - hr) * 60.0)]
	ui.set_hud(res, q, builder.info_text())

func _save() -> void:
	if not playing:
		return
	GameState.player_pos = player.global_position
	GameState.save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
