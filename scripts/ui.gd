extends CanvasLayer
## Touch UI built in code: floating joystick, camera drag, buttons, Arabic RTL labels, menu, puzzle overlay.
## All touches go through _input so joystick + buttons work simultaneously (multi-touch).
signal action(name: String)
const PuzzleS := preload("res://scripts/puzzle_view.gd")
const TechS := preload("res://scripts/tech_view.gd")

var buttons := {}
var menu_btns: Array = []
var hud_btns: Array = []
var puzzle_btns: Array = []
var menu_panel: Panel
var puzzle  # puzzle_view.gd instance (untyped on purpose)
var title_label: Label
var res_label: Label
var quest_label: Label
var toast_label: Label
var puzzle_info: Label
var crop_label: Label
var hunt_label: Label
var crosshair: Label
var aim_on := false
var scope_on := false
var scope_img: TextureRect
var bar_l: ColorRect
var bar_r: ColorRect
var speed_on := false
var stick_base: Panel
var stick_knob: Panel
var stick_id := -1
var puzzle_id := -1
var bar_top: ColorRect
var bar_bot: ColorRect
var cam_id := -1
var stick_center := Vector2.ZERO
var in_menu := true
var in_puzzle := false
var in_tech := false
var tech
var tech_btns: Array = []
var _tween: Tween

func _ready() -> void:
	layer = 10
	menu_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.12, 0.07, 0.94)
	menu_panel.add_theme_stylebox_override("panel", sb)
	add_child(menu_panel)
	puzzle = PuzzleS.new()
	puzzle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	puzzle.visible = false
	add_child(puzzle)
	tech = TechS.new()
	tech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tech.visible = false
	add_child(tech)
	title_label = _label(64)
	title_label.text = "WILD ORIGIN\nبداية العالم"
	res_label = _label(26)
	quest_label = _label(26)
	toast_label = _label(30)
	puzzle_info = _label(28)
	crop_label = _label(24)
	hunt_label = _label(22)
	crosshair = _label(54)
	crosshair.text = "+"
	scope_img = TextureRect.new()
	scope_img.texture = load("res://assets/ui/scope.png")
	scope_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scope_img.stretch_mode = TextureRect.STRETCH_SCALE
	scope_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_img.visible = false
	add_child(scope_img)
	bar_l = ColorRect.new()
	bar_r = ColorRect.new()
	for side_bar in [bar_l, bar_r]:
		side_bar.color = Color.BLACK
		side_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side_bar.visible = false
		add_child(side_bar)
	bar_top = ColorRect.new()
	bar_bot = ColorRect.new()
	for bar in [bar_top, bar_bot]:
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		add_child(bar)
	stick_base = _circle(180, Color(1, 1, 1, 0.18))
	stick_knob = _circle(80, Color(1, 1, 1, 0.45))
	for n in [["new", "لعبة جديدة", "menu"], ["continue", "متابعة اللعبة", "menu"], ["quality", "الجودة", "menu"], ["sound", "الصوت", "menu"], ["day", "مدة اليوم", "menu"], ["gentle", "تخفيف المشاهد", "menu"],
			["jump", "قفز", "hud"], ["interact", "تفاعل", "hud"], ["build", "بناء", "hud"], ["torch", "مشعل", "hud"], ["crouch", "انحناء", "hud"], ["plant", "زرع", "hud"], ["water", "سقي", "hud"], ["tech", "تقنيات", "hud"], ["tresearch", "تطوير", "tech"], ["tclose", "إغلاق", "tech"], ["tup", "▲", "tech"], ["tdown", "▼", "tech"], ["aim", "تصويب", "hud"], ["weapon", "سلاح", "hud"], ["speed", "تسريع", "special"], ["scope", "عدسة", "special"], ["fire", "إطلاق", "special"], ["save", "حفظ", "hud"],
			["hint", "تلميح", "puzzle"], ["pclose", "إغلاق", "puzzle"], ["pleft", "◀", "puzzle"], ["pright", "▶", "puzzle"]]:
		_btn(n[0], n[1], n[2])
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_menu(false)

func _label(sz: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_RTL
	l.language = "ar"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _circle(sz: float, c: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(sz, sz)
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(int(sz / 2))
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	add_child(p)
	return p

func _btn(n: String, text: String, group: String) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_font_size_override("font_size", 28)
	add_child(b)
	buttons[n] = b
	match group:
		"menu": menu_btns.append(b)
		"hud": hud_btns.append(b)
		"special": pass
		"tech": tech_btns.append(b)
		_: puzzle_btns.append(b)

func _put(n: String, pos: Vector2, sz: Vector2) -> void:
	buttons[n].position = pos
	buttons[n].size = sz

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	menu_panel.position = Vector2.ZERO
	menu_panel.size = vp
	title_label.position = Vector2(0, vp.y * 0.06)
	title_label.size = Vector2(vp.x, 200)
	for l in [res_label, quest_label, puzzle_info]:
		l.size = Vector2(vp.x, 40)
	res_label.position = Vector2(0, 8)
	quest_label.position = Vector2(0, 52)
	puzzle_info.position = Vector2(0, 14)
	toast_label.position = Vector2(0, vp.y * 0.55)
	toast_label.size = Vector2(vp.x, 60)
	var cx := vp.x / 2.0 - 190.0
	for i in 6:
		var nm: String = ["new", "continue", "quality", "sound", "day", "gentle"][i]
		_put(nm, Vector2(cx, vp.y * 0.26 + i * 74.0), Vector2(380, 64))
	hunt_label.position = Vector2(0, 166)
	hunt_label.size = Vector2(vp.x, 30)
	crosshair.position = Vector2(vp.x * 0.5 - 30.0, vp.y * 0.5 - 38.0)
	crosshair.size = Vector2(60, 60)
	_put("tech", Vector2(vp.x - 600, vp.y - 220), Vector2(130, 100))
	_put("tresearch", Vector2(vp.x / 2.0 - 170.0, vp.y - 110.0), Vector2(340, 90))
	_put("tclose", Vector2(20, vp.y - 110.0), Vector2(160, 90))
	_put("tup", Vector2(vp.x - 200.0, vp.y - 110.0), Vector2(80, 90))
	_put("tdown", Vector2(vp.x - 100.0, vp.y - 110.0), Vector2(80, 90))
	tech.layout(vp)
	_put("aim", Vector2(vp.x - 320, vp.y - 340), Vector2(130, 100))
	_put("weapon", Vector2(vp.x - 600, vp.y - 110), Vector2(130, 100))
	_put("speed", Vector2(20, 84), Vector2(170, 64))
	_put("fire", Vector2(vp.x - 170, vp.y - 410), Vector2(140, 120))
	_put("scope", Vector2(vp.x - 330, vp.y - 410), Vector2(140, 120))
	scope_img.position = Vector2((vp.x - vp.y) * 0.5, 0)
	scope_img.size = Vector2(vp.y, vp.y)
	bar_l.position = Vector2.ZERO
	bar_l.size = Vector2(maxf(0.0, (vp.x - vp.y) * 0.5), vp.y)
	bar_r.position = Vector2((vp.x + vp.y) * 0.5, 0)
	bar_r.size = bar_l.size
	crop_label.position = Vector2(0, 96)
	crop_label.size = Vector2(vp.x, 70)
	_put("plant", Vector2(vp.x - 460, vp.y - 220), Vector2(130, 100))
	_put("water", Vector2(vp.x - 460, vp.y - 330), Vector2(130, 100))
	_put("jump", Vector2(vp.x - 160, vp.y - 160), Vector2(130, 130))
	_put("interact", Vector2(vp.x - 300, vp.y - 110), Vector2(130, 100))
	_put("build", Vector2(vp.x - 170, vp.y - 280), Vector2(140, 100))
	_put("torch", Vector2(vp.x - 320, vp.y - 230), Vector2(130, 100))
	_put("crouch", Vector2(vp.x - 460, vp.y - 110), Vector2(130, 100))
	_put("save", Vector2(20, 10), Vector2(110, 60))
	bar_top.position = Vector2.ZERO
	bar_top.size = Vector2(vp.x, vp.y * 0.12)
	bar_bot.position = Vector2(0, vp.y * 0.88)
	bar_bot.size = Vector2(vp.x, vp.y * 0.12)
	_put("hint", Vector2(vp.x / 2.0 - 170.0, vp.y - 110.0), Vector2(340, 90))
	_put("pclose", Vector2(20, vp.y - 110.0), Vector2(160, 90))
	_put("pleft", Vector2(vp.x * 0.04, vp.y * 0.7), Vector2(56, 110))
	_put("pright", Vector2(vp.x * 0.96 - 56.0, vp.y * 0.7), Vector2(56, 110))
	puzzle.layout(vp)

func show_menu(has_save: bool) -> void:
	in_menu = true
	_set_mode()
	buttons["continue"].disabled = not has_save

func hide_menu() -> void:
	in_menu = false
	_set_mode()

func open_puzzle(board: Dictionary) -> void:
	in_puzzle = true
	_layout()
	puzzle.open(board)
	_set_mode()

func open_tech() -> void:
	in_tech = true
	_layout()
	tech.open()
	_set_mode()

func close_tech() -> void:
	in_tech = false
	tech.visible = false
	_set_mode()

func close_puzzle() -> void:
	in_puzzle = false
	puzzle.visible = false
	_set_mode()

func _set_mode() -> void:
	menu_panel.visible = in_menu
	title_label.visible = in_menu
	for b in menu_btns:
		b.visible = in_menu
	for b in hud_btns:
		b.visible = not in_menu and not in_puzzle and not in_tech
	for b in tech_btns:
		b.visible = in_tech
	for b in puzzle_btns:
		b.visible = in_puzzle
	puzzle_info.visible = in_puzzle
	for l in [res_label, quest_label, crop_label, hunt_label]:
		l.visible = not in_menu and not in_puzzle and not in_tech
	_special()

func set_quality_text(q: int) -> void:
	buttons["quality"].text = "الجودة: " + ["منخفضة", "متوسطة", "عالية"][q]

func set_sound_text(idx: int) -> void:
	buttons["sound"].text = "الصوت: " + ["عالٍ", "متوسط", "منخفض", "مكتوم"][idx]

func set_gentle_text(on: bool) -> void:
	buttons["gentle"].text = "تخفيف المشاهد: " + ("مفعّل" if on else "معطّل")

func set_aim_mode(on: bool) -> void:
	aim_on = on
	if not on:
		scope_on = false
	_special()

func set_scope_mode(on: bool) -> void:
	scope_on = on
	_special()

func set_speed_visible(on: bool) -> void:
	speed_on = on
	_special()

func set_hunt(text: String) -> void:
	hunt_label.text = text

func _special() -> void:
	var show_hud := not in_menu and not in_puzzle and not in_tech
	buttons["fire"].visible = show_hud and aim_on
	buttons["speed"].visible = show_hud and speed_on
	buttons["scope"].visible = show_hud and aim_on
	crosshair.visible = show_hud and aim_on and not scope_on
	scope_img.visible = show_hud and scope_on
	bar_l.visible = show_hud and scope_on
	bar_r.visible = show_hud and scope_on

func set_day_text(secs: float) -> void:
	buttons["day"].text = "مدة اليوم: %d دقيقة" % int(round(secs / 60.0))

func set_crop(text: String) -> void:
	crop_label.text = text

func set_hud(res: String, quest: String) -> void:
	res_label.text = res
	quest_label.text = quest

func cinematic_bars(secs: float) -> void:
	for bar in [bar_top, bar_bot]:
		bar.visible = true
		bar.modulate.a = 1.0
		var t := create_tween()
		t.tween_interval(secs)
		t.tween_property(bar, "modulate:a", 0.0, 0.8)
		t.tween_callback(func(): bar.visible = false)

func toast(msg: String, secs: float = 2.5) -> void:
	toast_label.text = msg
	toast_label.modulate.a = 1.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(secs)
	_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func _process(_d: float) -> void:
	if in_puzzle:
		puzzle_info.text = puzzle.info_text()

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_press(e.index, e.position)
		else:
			_release(e.index, e.position)
	elif e is InputEventScreenDrag:
		if e.index == puzzle_id:
			puzzle.drag(e.position)
		elif e.index == stick_id:
			_stick(e.position)
		elif e.index == cam_id:
			GameState.cam_delta += e.relative

func _press(idx: int, pos: Vector2) -> void:
	for n in buttons:
		var b: Button = buttons[n]
		if b.is_visible_in_tree() and not b.disabled and b.get_global_rect().has_point(pos):
			action.emit(n)
			return
	if in_menu:
		return
	if in_tech:
		tech.tap(pos)
		return
	if in_puzzle:
		if puzzle.press(pos):
			puzzle_id = idx
		return
	var vp := get_viewport().get_visible_rect().size
	if pos.x < vp.x * 0.4 and pos.y > vp.y * 0.35 and stick_id == -1:
		stick_id = idx
		stick_center = pos
		stick_base.position = pos - stick_base.size / 2.0
		stick_base.visible = true
		stick_knob.visible = true
		_stick(pos)
	elif cam_id == -1:
		cam_id = idx

func _release(idx: int, pos: Vector2) -> void:
	if idx == puzzle_id:
		puzzle_id = -1
		puzzle.release(pos)
	elif idx == stick_id:
		stick_id = -1
		GameState.move = Vector2.ZERO
		stick_base.visible = false
		stick_knob.visible = false
	elif idx == cam_id:
		cam_id = -1

func _stick(p: Vector2) -> void:
	var r := 90.0
	var d := p - stick_center
	if d.length() > r:
		d = d.normalized() * r
	GameState.move = d / r
	stick_knob.position = stick_center + d - stick_knob.size / 2.0
