extends CanvasLayer
## Touch UI built in code: floating joystick, camera drag, buttons, Arabic RTL labels, menu, puzzle overlay.
## All touches go through _input so joystick + buttons work simultaneously (multi-touch).
signal action(name: String)
const PuzzleS := preload("res://scripts/puzzle_view.gd")

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
var stick_base: Panel
var stick_knob: Panel
var stick_id := -1
var cam_id := -1
var stick_center := Vector2.ZERO
var in_menu := true
var in_puzzle := false
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
	title_label = _label(64)
	title_label.text = "WILD ORIGIN\nبداية العالم"
	res_label = _label(26)
	quest_label = _label(26)
	toast_label = _label(30)
	puzzle_info = _label(28)
	stick_base = _circle(180, Color(1, 1, 1, 0.18))
	stick_knob = _circle(80, Color(1, 1, 1, 0.45))
	for n in [["new", "لعبة جديدة", "menu"], ["continue", "متابعة اللعبة", "menu"], ["quality", "الجودة", "menu"], ["sound", "الصوت", "menu"],
			["jump", "قفز", "hud"], ["interact", "تفاعل", "hud"], ["build", "بناء", "hud"], ["torch", "مشعل", "hud"], ["save", "حفظ", "hud"],
			["autoplace", "تثبيت تلقائي", "puzzle"], ["pclose", "إغلاق", "puzzle"], ["pleft", "◀", "puzzle"], ["pright", "▶", "puzzle"]]:
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
	for i in 4:
		var nm: String = ["new", "continue", "quality", "sound"][i]
		_put(nm, Vector2(cx, vp.y * 0.36 + i * 95.0), Vector2(380, 80))
	_put("jump", Vector2(vp.x - 160, vp.y - 160), Vector2(130, 130))
	_put("interact", Vector2(vp.x - 300, vp.y - 110), Vector2(130, 100))
	_put("build", Vector2(vp.x - 170, vp.y - 280), Vector2(140, 100))
	_put("torch", Vector2(vp.x - 320, vp.y - 230), Vector2(130, 100))
	_put("save", Vector2(20, 10), Vector2(110, 60))
	_put("autoplace", Vector2(vp.x / 2.0 - 170.0, vp.y - 110.0), Vector2(340, 90))
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
		b.visible = not in_menu and not in_puzzle
	for b in puzzle_btns:
		b.visible = in_puzzle
	puzzle_info.visible = in_puzzle
	for l in [res_label, quest_label]:
		l.visible = not in_menu and not in_puzzle

func set_quality_text(q: int) -> void:
	buttons["quality"].text = "الجودة: " + ["منخفضة", "متوسطة", "عالية"][q]

func set_sound_text(on: bool) -> void:
	buttons["sound"].text = "الصوت: " + ("مفعّل" if on else "مكتوم")

func set_hud(res: String, quest: String) -> void:
	res_label.text = res
	quest_label.text = quest

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
			_release(e.index)
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
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
	if in_puzzle:
		puzzle.tray_hit(pos)
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

func _release(idx: int) -> void:
	if idx == stick_id:
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
