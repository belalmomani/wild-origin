extends Control
## Jigsaw board with DRAG & DROP: drag a stone piece from the tray and drop it on its matching hole.
## Slots are only faint outlines (no auto-fill). A limited "hint" blinks the correct hole.
signal dropped(pi: int)
const D := preload("res://scripts/building_data.gd")
const M := preload("res://scripts/mats.gd")
const CELL := 100.0
var board: Dictionary = {}
var tray: Array = []
var scroll := 0
var selected := -1
var dragging := false
var drag_idx := -1
var drag_pos := Vector2.ZERO
var hint_idx := -1
var hint_t := 0.0
var board_rect := Rect2()
var tray_rect := Rect2()
var bscale := 1.0

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func _fill(pts: PackedVector2Array, src: PackedVector2Array, col: Color, cost: String) -> void:
	var uvs := PackedVector2Array()
	for v in src:
		uvs.append(Vector2(v.x, -v.y) * 0.45)   # same grain whether in tray, in hand or placed
	draw_colored_polygon(pts, col, uvs, M.tex("rock_a" if cost == "stone" else "planks_a"))

func layout(vp: Vector2) -> void:
	position = Vector2.ZERO
	size = vp
	board_rect = Rect2(vp.x * 0.04, vp.y * 0.12, vp.x * 0.92, vp.y * 0.56)
	tray_rect = Rect2(vp.x * 0.04 + 64.0, vp.y * 0.7, vp.x * 0.92 - 128.0, 110.0)
	_update_scale()

func _update_scale() -> void:
	if not board.is_empty():
		bscale = minf(board_rect.size.x / board.w, board_rect.size.y / board.h)

func open(b: Dictionary) -> void:
	board = b
	selected = -1
	scroll = 0
	dragging = false
	_update_scale()
	refresh()
	visible = true

func visible_count() -> int:
	return maxi(1, int(tray_rect.size.x / CELL))

func refresh() -> void:
	tray.clear()
	for i in board.pieces.size():
		if not GameState.placed.has(board.pieces[i].id):
			tray.append(i)
	scroll = clampi(scroll, 0, maxi(0, tray.size() - visible_count()))
	if not tray.has(selected):
		selected = -1

func scroll_by(d: int) -> void:
	scroll = clampi(scroll + d * 3, 0, maxi(0, tray.size() - visible_count()))

func show_hint() -> void:
	hint_idx = selected if tray.has(selected) else (tray[0] if not tray.is_empty() else -1)
	hint_t = 4.0

func press(pos: Vector2) -> bool:
	if not tray_rect.has_point(pos):
		return false
	var ti := scroll + int((pos.x - tray_rect.position.x) / CELL)
	if ti >= tray.size():
		return false
	drag_idx = tray[ti]
	selected = drag_idx
	dragging = true
	drag_pos = pos
	return true

func drag(pos: Vector2) -> void:
	drag_pos = pos

func release(_pos: Vector2) -> void:
	if not dragging:
		return
	dragging = false
	var pi := drag_idx
	drag_idx = -1
	if _near(pi):
		dropped.emit(pi)

func _held_center() -> Vector2:
	return drag_pos - Vector2(0, 70)   # drawn above the finger so it stays visible

func _slot_center(pi: int) -> Vector2:
	var c := Vector2.ZERO
	var pts := _screen_poly(board.pieces[pi].poly)
	for v in pts:
		c += v
	return c / pts.size()

func _near(pi: int) -> bool:
	return _held_center().distance_to(_slot_center(pi)) < 42.0

func info_text() -> String:
	if board.is_empty():
		return ""
	var cost: String = board.pieces[0].cost
	return "%s — المتبقي %d من %d — %s: %d — تلميحات: %d" % [board.name, tray.size(), board.pieces.size(), "حجارة" if cost == "stone" else "خشب", GameState.count(cost), GameState.hints_left]

func _to_screen(p: Vector2) -> Vector2:
	var ox := board_rect.position.x + board_rect.size.x * 0.5
	var oy: float = board_rect.position.y + board_rect.size.y * 0.5 + board.h * bscale * 0.5
	return Vector2(ox + p.x * bscale, oy - p.y * bscale)

func _screen_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(_to_screen(v))
	return out

func _outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	draw_polyline(closed, col, w)

func _process(d: float) -> void:
	if not visible:
		return
	hint_t = maxf(0.0, hint_t - d)
	queue_redraw()

func _draw() -> void:
	if board.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.09, 0.11, 0.98))
	var bl := _to_screen(Vector2(-board.w * 0.5, 0.0))
	var trp := _to_screen(Vector2(board.w * 0.5, board.h))
	draw_rect(Rect2(bl.x, trp.y, trp.x - bl.x, bl.y - trp.y), Color(0.16, 0.18, 0.2))
	for o in board.openings:
		var r: Rect2 = o
		var a := _to_screen(r.position)
		var b := _to_screen(r.position + r.size)
		draw_rect(Rect2(a.x, b.y, b.x - a.x, a.y - b.y), Color(0.45, 0.3, 0.18, 0.7) if r.position.y < 0.01 else Color(0.5, 0.75, 0.95, 0.5))
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
	for i in board.pieces.size():
		var p: Dictionary = board.pieces[i]
		var pts := _screen_poly(p.poly)
		if GameState.placed.has(p.id):
			_fill(pts, p.poly, D.piece_color(p).lightened(0.45), p.cost)
			_outline(pts, Color(0, 0, 0, 0.6), 1.5)
		elif hint_t > 0.0 and i == hint_idx:
			draw_colored_polygon(pts, Color(1, 0.9, 0.2, 0.25 + 0.5 * blink))
			_outline(pts, Color(1, 0.9, 0.2), 3.0)
		elif dragging and i == drag_idx and _near(i):
			draw_colored_polygon(pts, Color(0.2, 1, 0.3, 0.3))
			_outline(pts, Color(0.2, 1, 0.3), 3.0)
		else:
			_outline(pts, Color(1, 1, 1, 0.25), 1.5)
	draw_rect(Rect2(tray_rect.position.x - 64.0, tray_rect.position.y - 8.0, tray_rect.size.x + 128.0, tray_rect.size.y + 16.0), Color(0.18, 0.13, 0.1, 0.95))
	for k in visible_count():
		var ti := scroll + k
		if ti >= tray.size():
			break
		var pi: int = tray[ti]
		if dragging and pi == drag_idx:
			continue
		var cc := Vector2(tray_rect.position.x + CELL * (k + 0.5), tray_rect.position.y + tray_rect.size.y * 0.5)
		_piece_at(board.pieces[pi], cc, 76.0, 1.0)
	if dragging and drag_idx >= 0:
		_piece_at(board.pieces[drag_idx], _held_center(), 0.0, 0.92)

## Draw a piece centred at ctr. fit>0: scale to fit that many px; fit==0: board scale.
func _piece_at(piece: Dictionary, ctr: Vector2, fit: float, alpha: float) -> void:
	var c := Vector2.ZERO
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for v in piece.poly:
		c += v
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	c /= piece.poly.size()
	var ts := bscale if fit <= 0.0 else fit / maxf(mx.x - mn.x, mx.y - mn.y)
	var pts := PackedVector2Array()
	for v in piece.poly:
		pts.append(Vector2((v.x - c.x) * ts, -(v.y - c.y) * ts) + ctr)
	var col := D.piece_color(piece).lightened(0.45)
	col.a = alpha
	if GameState.count(piece.cost) == 0:
		col.a *= 0.45
	_fill(pts, piece.poly, col, piece.cost)
	_outline(pts, Color(0, 0, 0, 0.75), 2.0)
