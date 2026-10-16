extends Control
## Jigsaw-style board: target wall on top, tray of loose pieces below. "Auto place" flies the
## selected piece to its slot. Pure 2D drawing, no external textures.
const D := preload("res://scripts/building_data.gd")
const CELL := 100.0
var board: Dictionary = {}
var tray: Array = []
var scroll := 0
var selected := -1
var fly_idx := -1
var fly_t := 1.0
var fly_from := Vector2.ZERO
var board_rect := Rect2()
var tray_rect := Rect2()
var bscale := 1.0

func layout(vp: Vector2) -> void:
	position = Vector2.ZERO
	size = vp
	board_rect = Rect2(vp.x * 0.04, vp.y * 0.12, vp.x * 0.92, vp.y * 0.56)
	tray_rect = Rect2(vp.x * 0.04 + 64.0, vp.y * 0.7, vp.x * 0.92 - 128.0, 110.0)

func open(b: Dictionary) -> void:
	board = b
	selected = -1
	scroll = 0
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
		selected = tray[0] if not tray.is_empty() else -1

func scroll_by(d: int) -> void:
	scroll = clampi(scroll + d * 3, 0, maxi(0, tray.size() - visible_count()))

func tray_hit(pos: Vector2) -> bool:
	if not tray_rect.has_point(pos):
		return false
	var ti := scroll + int((pos.x - tray_rect.position.x) / CELL)
	if ti < tray.size():
		selected = tray[ti]
	return true

func capture_fly_from(pi: int) -> void:
	var ti := tray.find(pi)
	var k := clampi(ti - scroll, 0, visible_count() - 1)
	fly_from = Vector2(tray_rect.position.x + CELL * (k + 0.5), tray_rect.position.y + tray_rect.size.y * 0.5)

func start_fly(pi: int) -> void:
	fly_idx = pi
	fly_t = 0.0

func info_text() -> String:
	if board.is_empty():
		return ""
	var cost: String = board.pieces[0].cost
	return "%s — المتبقي %d من %d — %s: %d" % [board.name, tray.size(), board.pieces.size(), "حجارة" if cost == "stone" else "خشب", GameState.count(cost)]

func _to_screen(p: Vector2) -> Vector2:
	var ox := board_rect.position.x + board_rect.size.x * 0.5
	var oy := board_rect.position.y + board_rect.size.y * 0.5 + board.h * bscale * 0.5
	return Vector2(ox + p.x * bscale, oy - p.y * bscale)

func _screen_poly(poly: PackedVector2Array, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(_to_screen(v) + off)
	return out

func _outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	draw_polyline(closed, col, w)

func _process(d: float) -> void:
	if not visible:
		return
	if fly_t < 1.0:
		fly_t = minf(1.0, fly_t + d / 0.35)
		if fly_t >= 1.0:
			fly_idx = -1
	queue_redraw()

func _draw() -> void:
	if board.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.09, 0.11, 0.98))
	bscale = minf(board_rect.size.x / board.w, board_rect.size.y / board.h)
	var bl := _to_screen(Vector2(-board.w * 0.5, 0.0))
	var trp := _to_screen(Vector2(board.w * 0.5, board.h))
	draw_rect(Rect2(bl.x, trp.y, trp.x - bl.x, bl.y - trp.y), Color(0.16, 0.18, 0.2))
	for o in board.openings:
		var r: Rect2 = o
		var a := _to_screen(r.position)
		var b := _to_screen(r.position + r.size)
		draw_rect(Rect2(a.x, b.y, b.x - a.x, a.y - b.y), Color(0.45, 0.3, 0.18, 0.7) if r.position.y < 0.01 else Color(0.5, 0.75, 0.95, 0.5))
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
	for i in board.pieces.size():
		var p: Dictionary = board.pieces[i]
		var pts := _screen_poly(p.poly)
		if i == fly_idx:
			var ctr := Vector2.ZERO
			for v in pts:
				ctr += v
			ctr /= pts.size()
			var e := 1.0 - pow(1.0 - fly_t, 2.0)
			var moved := _screen_poly(p.poly, (fly_from - ctr) * (1.0 - e))
			draw_colored_polygon(moved, D.piece_color(p))
			_outline(moved, Color(1, 1, 1, 0.9), 2.0)
		elif GameState.placed.has(p.id):
			draw_colored_polygon(pts, D.piece_color(p))
			_outline(pts, Color(0, 0, 0, 0.6), 1.5)
		elif i == selected:
			draw_colored_polygon(pts, Color(1, 0.9, 0.2, 0.2 + 0.4 * blink))
			_outline(pts, Color(1, 0.9, 0.2), 3.0)
		else:
			_outline(pts, Color(1, 1, 1, 0.22), 1.5)
	draw_rect(Rect2(tray_rect.position.x - 64.0, tray_rect.position.y - 8.0, tray_rect.size.x + 128.0, tray_rect.size.y + 16.0), Color(0.18, 0.13, 0.1, 0.95))
	for k in visible_count():
		var ti := scroll + k
		if ti >= tray.size():
			break
		var pi: int = tray[ti]
		var piece: Dictionary = board.pieces[pi]
		var cc := Vector2(tray_rect.position.x + CELL * (k + 0.5), tray_rect.position.y + tray_rect.size.y * 0.5)
		if pi == selected:
			draw_rect(Rect2(cc - Vector2(CELL * 0.5 - 4.0, 52.0), Vector2(CELL - 8.0, 104.0)), Color(1, 0.9, 0.2, 0.3))
		_tray_piece(piece, cc)

func _tray_piece(piece: Dictionary, ctr: Vector2) -> void:
	var c := Vector2.ZERO
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for v in piece.poly:
		c += v
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	c /= piece.poly.size()
	var ts := 76.0 / maxf(mx.x - mn.x, mx.y - mn.y)
	var pts := PackedVector2Array()
	for v in piece.poly:
		pts.append(Vector2((v.x - c.x) * ts, -(v.y - c.y) * ts) + ctr)
	var col := D.piece_color(piece)
	if GameState.count(piece.cost) == 0:
		col.a = 0.4
	draw_colored_polygon(pts, col)
	_outline(pts, Color(0, 0, 0, 0.7), 1.5)
