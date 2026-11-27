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
var fade_rect: ColorRect
var prompt_label: Label
var vignette: TextureRect
var res_bg: Panel
var quest_bg: Panel
var _res_lines := 1

const GOLD := Color(0.96, 0.78, 0.28)
const CIRCLE_BTNS := ["pause", "interact", "fire", "jump", "crouch", "aim", "scope", "build", "more"]
const ICON_PATH := "res://assets/ui/icons/"
const ICON_BTNS := {"pause": "pause", "jump": "jump", "crouch": "crouch", "aim": "aim", "build": "build", "scope": "scope", "more": "menu", "fire": "fire", "interact": "hand"}
const DRAWER := ["torch", "plant", "water", "tech", "save", "home", "weapon", "coat"]
const STAT_KEYS := ["time", "xp", "apples", "wood", "stone", "meat", "fish", "pelt", "level"]
const STAT_MAIN := 4           # the first four sit in the big top bar (like the reference), the rest in a small row under it
const STAT_ICONS := {"time": "clock", "xp": "coin", "wood": "wood", "stone": "stone", "apples": "apple", "meat": "meat", "fish": "fish", "pelt": "pelt", "level": "star"}
var pill: Panel
var pill2: Panel
var avatar: TextureRect
var quest_title: Label
var quest_prog: Label
var quest_badge: Panel
var minimap
var stat_ic := {}
var stat_lb := {}
var stat_on := {}
var life_bg: Panel
var life_fill: Panel
var life_lb: Label
var life_heart: TextureRect
var drawer_bg: Panel
var drawer_btns: Array = []
var drawer_open := false
var _life_ratio := 1.0

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
	pill = _card(Color(0.04, 0.07, 0.07, 0.72))
	for k in STAT_KEYS:
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(ICON_PATH + STAT_ICONS[k] + ".png"):
			ic.texture = load(ICON_PATH + STAT_ICONS[k] + ".png")
		add_child(ic)
		stat_ic[k] = ic
		var lb := _label(32)
		lb.text_direction = Control.TEXT_DIRECTION_LTR
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		stat_lb[k] = lb
		stat_on[k] = true
	pill2 = _card(Color(0.04, 0.07, 0.07, 0.6))
	life_bg = _card(Color(0.04, 0.07, 0.07, 0.72))
	life_heart = TextureRect.new()
	life_heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	life_heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	life_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(ICON_PATH + "heart.png"):
		life_heart.texture = load(ICON_PATH + "heart.png")
	add_child(life_heart)
	var lback := Panel.new()
	lback.add_theme_stylebox_override("panel", _sbox(Color(0.1, 0.12, 0.1, 0.9), Color(0, 0, 0, 0.6), 12, 2))
	lback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lback.name = "LifeBack"
	add_child(lback)
	life_fill = Panel.new()
	life_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(life_fill)
	life_lb = _label(24)
	life_lb.text_direction = Control.TEXT_DIRECTION_LTR
	avatar = TextureRect.new()
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(ICON_PATH + "avatar.png"):
		avatar.texture = load(ICON_PATH + "avatar.png")
	add_child(avatar)
	minimap = load("res://scripts/minimap.gd").new()
	add_child(minimap)
	drawer_bg = _card(Color(0.04, 0.07, 0.07, 0.85))
	drawer_bg.visible = false
	res_bg = _card(Color(0.05, 0.08, 0.07, 0.62))
	quest_bg = _card(Color(0.05, 0.08, 0.07, 0.62))
	title_label = _label(64)
	title_label.text = "WILD ORIGIN\nبداية العالم"
	res_label = _label(21)
	quest_label = _label(24)
	quest_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_title = _label(27)
	quest_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_prog = _label(26)
	quest_prog.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	quest_prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_badge = Panel.new()
	quest_badge.add_theme_stylebox_override("panel", _sbox(Color(0.98, 0.78, 0.15), Color(1, 0.95, 0.7), 40, 3))
	quest_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quest_badge)
	var bl := _label(36)
	bl.text = "!"
	bl.name = "BadgeMark"
	bl.add_theme_color_override("font_color", Color(0.35, 0.2, 0.02))
	bl.add_theme_constant_override("outline_size", 0)
	toast_label = _label(30)
	puzzle_info = _label(28)
	crop_label = _label(24)
	hunt_label = _label(22)
	prompt_label = _label(26)
	prompt_label.visible = false
	vignette = TextureRect.new()      # soft dark edges: cheap cinematic look, drawn under the buttons
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.5, 1.0])
	vg.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.5)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 0.5)
	vt.width = 256
	vt.height = 256
	vignette.texture = vt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
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
	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	add_child(fade_rect)
	stick_base = _circle(190, Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.55), 4)
	stick_knob = _circle(84, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.9), 3)
	for ap in [[Vector2(95, 16), Vector2(80, 38), Vector2(110, 38)], [Vector2(95, 174), Vector2(80, 152), Vector2(110, 152)], [Vector2(16, 95), Vector2(38, 80), Vector2(38, 110)], [Vector2(174, 95), Vector2(152, 80), Vector2(152, 110)]]:
		var pg := Polygon2D.new()
		pg.polygon = PackedVector2Array(ap)
		pg.color = Color(1, 1, 1, 0.7)
		stick_base.add_child(pg)
	for n in [["new", "لعبة جديدة", "menu"], ["continue", "متابعة اللعبة", "menu"], ["quality", "الجودة", "menu"], ["sound", "الصوت", "menu"], ["day", "مدة اليوم", "menu"], ["gentle", "تخفيف المشاهد", "menu"], ["sens", "الحساسية", "menu"],
			["pause", "", "hud"], ["more", "", "hud"], ["coat", "معطف", "hud"], ["jump", "قفز", "hud"], ["interact", "تفاعل", "hud"], ["build", "بناء", "hud"], ["torch", "مشعل", "hud"], ["crouch", "انحناء", "hud"], ["plant", "زرع", "hud"], ["water", "سقي", "hud"], ["tech", "تقنيات", "hud"], ["tresearch", "تطوير", "tech"], ["tclose", "إغلاق", "tech"], ["tup", "▲", "tech"], ["tdown", "▼", "tech"], ["aim", "تصويب", "hud"], ["weapon", "سلاح", "hud"], ["speed", "تسريع", "special"], ["scope", "عدسة", "special"], ["fire", "إطلاق", "special"], ["save", "حفظ", "hud"], ["home", "🏠 المنزل", "hud"],
			["hint", "تلميح", "puzzle"], ["pnext", "لوحة أخرى ▸", "puzzle"], ["pclose", "إغلاق", "puzzle"], ["pleft", "◀", "puzzle"], ["pright", "▶", "puzzle"]]:
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

## Rounded translucent card with a thin golden edge (HUD backgrounds).
func _card(c: Color) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _sbox(c, Color(GOLD.r, GOLD.g, GOLD.b, 0.75), 22, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p

func _sbox(bg: Color, border: Color, radius: int, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s

func _style_button(b: Button, n: String, group: String) -> void:
	var bg := Color(0.07, 0.1, 0.08, 0.6)
	var edge := GOLD
	var radius := 30
	var bw := 3
	if group == "menu" or group == "puzzle" or group == "tech":
		bg = Color(0.1, 0.28, 0.16, 0.92)
		radius = 22
	if n == "interact":
		bg = Color(0.86, 0.6, 0.1, 0.9)
		edge = Color(1, 0.95, 0.75)
		bw = 5
	elif n == "fire":
		bg = Color(0.8, 0.18, 0.12, 0.9)
		edge = Color(1, 0.85, 0.75)
		bw = 5
	elif n == "build":
		bg = Color(0.18, 0.4, 0.22, 0.88)
	elif n == "weapon" or n == "aim":
		bw = 4
	if CIRCLE_BTNS.has(n) and group == "hud":
		radius = 48
	b.add_theme_stylebox_override("normal", _sbox(bg, edge, radius, bw))
	b.add_theme_stylebox_override("hover", _sbox(bg.lightened(0.1), edge, radius, bw))
	b.add_theme_stylebox_override("pressed", _sbox(bg.lightened(0.25), Color(1, 1, 1), radius, bw))
	b.add_theme_stylebox_override("disabled", _sbox(Color(0.2, 0.2, 0.2, 0.5), Color(0.5, 0.5, 0.5, 0.6), radius, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 5)

func _circle(sz: float, c: Color, edge: Color = Color(0, 0, 0, 0), bw: int = 0) -> Panel:
	var p := Panel.new()
	p.size = Vector2(sz, sz)
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = edge
	s.set_border_width_all(bw)
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
	_style_button(b, n, group)
	if ICON_BTNS.has(n) and ResourceLoader.exists(ICON_PATH + str(ICON_BTNS[n]) + ".png"):
		b.icon = load(ICON_PATH + str(ICON_BTNS[n]) + ".png")
		b.expand_icon = true
		if n != "interact" and n != "fire":
			b.text = ""
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.add_theme_constant_override("icon_max_width", 64)
	add_child(b)
	buttons[n] = b
	if DRAWER.has(n):
		drawer_btns.append(b)
	match group:
		"menu": menu_btns.append(b)
		"hud": hud_btns.append(b)
		"special": pass
		"tech": tech_btns.append(b)
		_: puzzle_btns.append(b)

func _put(n: String, pos: Vector2, sz: Vector2) -> void:
	var b: Button = buttons[n]
	b.position = pos
	b.size = sz
	if b.icon != null and b.text == "":
		b.add_theme_constant_override("icon_max_width", int(minf(sz.x, sz.y) * 0.6))

func _circ(n: String, cx: float, cy: float, r: float) -> void:
	_put(n, Vector2(cx - r, cy - r), Vector2(r * 2.0, r * 2.0))

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
	for i in 7:
		var nm: String = ["new", "continue", "quality", "sound", "day", "gentle", "sens"][i]
		_put(nm, Vector2(cx, vp.y * 0.22 + i * 68.0), Vector2(380, 60))
	prompt_label.position = Vector2(vp.x * 0.25, vp.y - 62.0)
	prompt_label.size = Vector2(vp.x * 0.5, 40)
	vignette.position = Vector2.ZERO
	vignette.size = vp
	hunt_label.position = Vector2(0, 166)
	hunt_label.size = Vector2(vp.x, 30)
	crosshair.position = Vector2(vp.x * 0.5 - 30.0, vp.y * 0.5 - 38.0)
	crosshair.size = Vector2(60, 60)
	_put("tresearch", Vector2(vp.x / 2.0 - 170.0, vp.y - 110.0), Vector2(340, 90))
	_put("tclose", Vector2(20, vp.y - 110.0), Vector2(160, 90))
	_put("tup", Vector2(vp.x - 200.0, vp.y - 110.0), Vector2(80, 90))
	_put("tdown", Vector2(vp.x - 100.0, vp.y - 110.0), Vector2(80, 90))
	tech.layout(vp)
	scope_img.position = Vector2((vp.x - vp.y) * 0.5, 0)
	scope_img.size = Vector2(vp.y, vp.y)
	bar_l.position = Vector2.ZERO
	bar_l.size = Vector2(maxf(0.0, (vp.x - vp.y) * 0.5), vp.y)
	bar_r.position = Vector2((vp.x + vp.y) * 0.5, 0)
	bar_r.size = bar_l.size
	crop_label.position = Vector2(0, 96)
	crop_label.size = Vector2(vp.x, 70)
	# right-hand cluster, tidy grid: big «تفاعل» at the corner, jump/crouch beside it, the rest in rows above
	bar_top.position = Vector2.ZERO
	bar_top.size = Vector2(vp.x, vp.y * 0.12)
	bar_bot.position = Vector2(0, vp.y * 0.88)
	bar_bot.size = Vector2(vp.x, vp.y * 0.12)
	_put("hint", Vector2(vp.x / 2.0 - 170.0, vp.y - 110.0), Vector2(340, 90))
	_put("pclose", Vector2(20, vp.y - 110.0), Vector2(160, 90))
	_put("pnext", Vector2(vp.x - 280.0, vp.y - 110.0), Vector2(260, 90))
	fade_rect.position = Vector2.ZERO
	fade_rect.size = vp
	_put("pleft", Vector2(vp.x * 0.04, vp.y * 0.7), Vector2(56, 110))
	_put("pright", Vector2(vp.x * 0.96 - 56.0, vp.y * 0.7), Vector2(56, 110))
	puzzle.layout(vp)
	# --- touch controls: a few big round buttons on the right thumb; everything else lives in the ☰ drawer
	var k := clampf(vp.y / 1080.0, 0.55, 1.25)
	var w := vp.x
	var h := vp.y
	_circ("interact", w - 135 * k, h - 135 * k, 98 * k)
	_circ("aim", w - 345 * k, h - 105 * k, 64 * k)
	_circ("crouch", w - 490 * k, h - 95 * k, 52 * k)
	_circ("jump", w - 120 * k, h - 345 * k, 64 * k)
	_circ("build", w - 330 * k, h - 255 * k, 58 * k)
	_circ("fire", w - 330 * k, h - 255 * k, 82 * k)
	_circ("scope", w - 120 * k, h - 500 * k, 56 * k)
	_circ("pause", w - 62 * k, 58 * k, 42 * k)
	_circ("more", w - 62 * k, 160 * k, 38 * k)
	_put("speed", Vector2(20, 520 * k), Vector2(170, 64))
	var dx := w - 440 * k
	var dy := 215 * k
	var order := ["torch", "plant", "water", "tech", "save", "home", "weapon", "coat"]
	for i in order.size():
		_put(order[i], Vector2(dx + float(i % 2) * 200.0 * k, dy + float(i / 2) * 90.0 * k), Vector2(190.0 * k, 80.0 * k))
	drawer_bg.position = Vector2(dx - 14, dy - 14)
	drawer_bg.size = Vector2(400.0 * k + 28.0, 4.0 * 90.0 * k + 18.0)
	_place_hud()

func set_stats(d: Dictionary) -> void:
	for key in STAT_KEYS:
		var v = d.get(key, 0)
		stat_lb[key].text = str(v)
		stat_on[key] = not ((key == "fish" or key == "pelt") and str(v) == "0")
	_place_hud()

## Lives bar (top-left): hearts icon + a bar that shrinks from green to red.
func set_lives(cur: int, mx: int) -> void:
	_life_ratio = clampf(float(cur) / float(maxi(1, mx)), 0.0, 1.0)
	life_lb.text = "%d / %d" % [cur, mx]
	_place_hud()

## Stacks the HUD cards: resources on top, the quest card under it, then crop / hunt lines.
func _place_hud() -> void:
	var vp := get_viewport().get_visible_rect().size
	var k := clampf(vp.y / 1080.0, 0.55, 1.25)
	var show := not in_menu and not in_puzzle and not in_tech
	# --- top bar: clock | coin | apple | wood (like the reference), a smaller row under it for the rest
	var main_keys: Array = STAT_KEYS.slice(0, STAT_MAIN)
	var sub_keys: Array = STAT_KEYS.slice(STAT_MAIN)
	var ph := 72.0 * k
	var total := 30.0 * k
	for key in main_keys:
		total += (205.0 if key == "time" else 150.0) * k
	var px := maxf(430.0 * k, (vp.x - total) * 0.5)
	pill.position = Vector2(px, 8)
	pill.size = Vector2(total, ph)
	pill.visible = show
	var sx := px + 15.0 * k
	for key in main_keys:
		var sw := (205.0 if key == "time" else 150.0) * k
		_place_stat(key, sx, 8.0, sw, ph, k, 1.0, show)
		sx += sw
	var k2 := 0.68
	var ph2 := 56.0 * k
	var total2 := 24.0 * k
	for key in sub_keys:
		if stat_on[key]:
			total2 += 118.0 * k
	var vis2 := false
	var sx2 := px + (total - total2) * 0.5 + 12.0 * k
	for key in sub_keys:
		if stat_on[key]:
			vis2 = true
			_place_stat(key, sx2, 8.0 + ph + 6.0, 118.0 * k, ph2, k, k2, show)
			sx2 += 118.0 * k
		else:
			_place_stat(key, 0.0, 0.0, 0.0, 0.0, k, k2, false)
	pill2.position = Vector2(px + (total - total2) * 0.5, 8.0 + ph + 6.0)
	pill2.size = Vector2(total2, ph2)
	pill2.visible = show and vis2
	# --- avatar + lives bar (top-left)
	life_bg.position = Vector2(60.0 * k, 28.0 * k)
	life_bg.size = Vector2(300.0 * k, 58.0 * k)
	avatar.position = Vector2(10, 6)
	avatar.size = Vector2(104.0 * k, 104.0 * k)
	life_heart.position = Vector2(124.0 * k, 33.0 * k)
	life_heart.size = Vector2(46.0 * k, 46.0 * k)
	var bx := 176.0 * k
	var bw := 172.0 * k
	var back := get_node_or_null("LifeBack") as Panel
	if back != null:
		back.position = Vector2(bx, 44.0 * k)
		back.size = Vector2(bw, 26.0 * k)
		back.visible = show
		life_fill.position = back.position + Vector2(3, 3)
	life_fill.size = Vector2(maxf(0.0, (bw - 6.0) * _life_ratio), 20.0 * k)
	life_fill.add_theme_stylebox_override("panel", _sbox(Color(0.85, 0.2, 0.15).lerp(Color(0.3, 0.8, 0.2), _life_ratio), Color(0, 0, 0, 0), 9, 0))
	life_fill.visible = show and _life_ratio > 0.01
	life_lb.position = Vector2(bx, 44.0 * k)
	life_lb.size = Vector2(bw, 26.0 * k)
	life_lb.add_theme_font_size_override("font_size", int(20.0 * k))
	life_bg.visible = show
	avatar.visible = show
	life_heart.visible = show
	life_lb.visible = show
	# --- quest card (left, under the avatar): badge, gold title, text, progress
	var qx := 14.0
	var qy := 122.0 * k
	var qw := 340.0 * k
	var qh := 150.0 * k
	quest_bg.position = Vector2(qx, qy)
	quest_bg.size = Vector2(qw, qh)
	quest_badge.position = Vector2(qx + 14.0 * k, qy + 14.0 * k)
	quest_badge.size = Vector2(54.0 * k, 54.0 * k)
	var mark := get_node_or_null("BadgeMark") as Label
	if mark != null:
		mark.position = quest_badge.position
		mark.size = quest_badge.size
		mark.visible = show and quest_label.text != ""
	quest_title.position = Vector2(qx + 76.0 * k, qy + 16.0 * k)
	quest_title.size = Vector2(qw - 90.0 * k, 40.0 * k)
	quest_label.position = Vector2(qx + 12.0 * k, qy + 62.0 * k)
	quest_label.size = Vector2(qw - 26.0 * k, 50.0 * k)
	quest_prog.position = Vector2(qx + 12.0 * k, qy + qh - 44.0 * k)
	quest_prog.size = Vector2(qw - 26.0 * k, 34.0 * k)
	var has_q := show and quest_label.text != ""
	quest_bg.visible = has_q
	quest_badge.visible = has_q
	quest_title.visible = has_q
	quest_label.visible = has_q
	quest_prog.visible = has_q and quest_prog.text != ""
	# --- info line + crop / hunt hints under the top bar
	var w := minf(vp.x * 0.5, 980.0)
	var x := (vp.x - w) * 0.5
	var ry := 8.0 + ph + (6.0 + ph2 + 6.0 if vis2 else 8.0)
	var rh := 12.0 + 26.0 * float(_res_lines)
	res_bg.position = Vector2(x, ry)
	res_bg.size = Vector2(w, rh)
	res_label.position = Vector2(0, ry + 6.0)
	res_label.size = Vector2(vp.x, rh)
	res_bg.visible = show and res_label.text != ""
	res_label.visible = show and res_label.text != ""
	crop_label.position = Vector2(0, ry + rh + 8.0)
	hunt_label.position = Vector2(0, ry + rh + 78.0)
	crop_label.visible = show
	hunt_label.visible = show
	drawer_bg.visible = show and drawer_open
	# --- mini-map (top-right, left of the pause button)
	var ms := 176.0 * k
	minimap.position = Vector2(vp.x - 62.0 * k - 42.0 * k - 14.0 * k - ms, 10)
	minimap.size = Vector2(ms, ms)
	minimap.visible = show
	# --- static joystick (bottom-left) while idle
	if stick_id == -1:
		stick_center = Vector2(190.0 * k, vp.y - 200.0 * k)
		stick_base.position = stick_center - stick_base.size * 0.5
		stick_knob.position = stick_center - stick_knob.size * 0.5
		stick_base.modulate.a = 0.75
		stick_base.visible = show
		stick_knob.visible = show

func _place_stat(key: String, x: float, y: float, sw: float, h: float, k: float, sc: float, vis: bool) -> void:
	var on: bool = stat_on[key] and vis
	stat_ic[key].visible = on
	stat_lb[key].visible = on
	if not on:
		return
	var isz := 48.0 * k * sc
	stat_ic[key].position = Vector2(x, y + h * 0.5 - isz * 0.5)
	stat_ic[key].size = Vector2(isz, isz)
	stat_lb[key].add_theme_font_size_override("font_size", int(32.0 * k * sc))
	stat_lb[key].position = Vector2(x + isz + 8.0 * k * sc, y + h * 0.5 - 22.0 * k * sc)
	stat_lb[key].size = Vector2(sw - isz - 12.0 * k * sc, 44.0 * k * sc)

func show_menu(has_save: bool) -> void:
	in_menu = true
	drawer_open = false
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
		b.visible = not in_menu and not in_puzzle and not in_tech and (not drawer_btns.has(b) or drawer_open)
	for b in tech_btns:
		b.visible = in_tech
	for b in puzzle_btns:
		b.visible = in_puzzle
	puzzle_info.visible = in_puzzle
	_place_hud()
	vignette.visible = not in_menu and not in_puzzle and not in_tech and GameState.quality >= 1
	if in_menu or in_puzzle or in_tech:
		prompt_label.visible = false
	_special()

func set_equip_text(e: String, weapon_name: String) -> void:
	buttons["weapon"].text = {"none": "يدان فارغتان", "axe": "فأس", "weapon": weapon_name}[e]

func set_sens_text(idx: int) -> void:
	buttons["sens"].text = "الحساسية: " + ["منخفضة", "متوسطة", "عالية"][idx]

## Context hint above the bottom edge ("تفاعل: افتح الباب" ...). "" hides it.
func set_prompt(t: String) -> void:
	prompt_label.text = t
	prompt_label.visible = t != "" and not in_menu and not in_puzzle and not in_tech

func set_quality_text(q: int) -> void:
	buttons["quality"].text = "الجودة: " + ["منخفضة", "متوسطة", "عالية"][q]

func set_sound_text(idx: int) -> void:
	buttons["sound"].text = "الصوت: " + ["عالٍ", "متوسط", "منخفض", "مكتوم"][idx]

func set_gentle_text(on: bool) -> void:
	buttons["gentle"].text = "تخفيف المشاهد: " + ("مفعّل" if on else "معطّل")

func set_crosshair_color(c: Color) -> void:
	crosshair.add_theme_color_override("font_color", c)

func set_aim_mode(on: bool) -> void:
	aim_on = on
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1))
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
	buttons["build"].visible = show_hud and not aim_on
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

func set_hud(res: String, quest: String, progress: String = "") -> void:
	res_label.text = res
	var parts := quest.split(" — ", true, 1)
	quest_title.text = parts[0] if parts.size() > 1 else "المهمة"
	quest_label.text = parts[1] if parts.size() > 1 else quest
	quest_prog.text = progress
	var lines := res.count("\n") + 1
	if lines != _res_lines:
		_res_lines = lines
	_place_hud()

func cinematic_bars(secs: float) -> void:
	for bar in [bar_top, bar_bot]:
		bar.visible = true
		bar.modulate.a = 1.0
		var t := create_tween()
		t.tween_interval(secs)
		t.tween_property(bar, "modulate:a", 0.0, 0.8)
		t.tween_callback(func(): bar.visible = false)

## Fade to black, hold, fade back (used when sleeping).
func fade_black(hold: float) -> void:
	fade_rect.visible = true
	fade_rect.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", 1.0, 0.6)
	t.tween_interval(hold)
	t.tween_property(fade_rect, "modulate:a", 0.0, 0.8)
	t.tween_callback(func(): fade_rect.visible = false)

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
			if n == "more":
				drawer_open = not drawer_open
				_set_mode()
				return
			action.emit(n)
			if drawer_open and drawer_btns.has(b):
				drawer_open = false
				_set_mode()
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
	if pos.x < vp.x * 0.45 and pos.y > vp.y * 0.3 and stick_id == -1:
		stick_id = idx
		stick_center = pos
		stick_base.position = pos - stick_base.size / 2.0
		stick_base.modulate.a = 1.0
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
		_place_hud()
	elif idx == cam_id:
		cam_id = -1

func _stick(p: Vector2) -> void:
	var r := 90.0
	var d := p - stick_center
	if d.length() > r:
		# the base follows the thumb when it is dragged past the rim, so you never run out of stick
		stick_center += d - d.normalized() * r
		stick_base.position = stick_center - stick_base.size / 2.0
		d = d.normalized() * r
	var v := d / r
	var l := v.length()
	if l < 0.12:
		GameState.move = Vector2.ZERO      # dead zone
	else:
		GameState.move = v.normalized() * pow((l - 0.12) / 0.88, 1.25)   # gentle start, full speed at the rim
	stick_knob.position = stick_center + d - stick_knob.size / 2.0
