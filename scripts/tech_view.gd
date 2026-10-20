extends Control
## Tech tree screen: scrollable cards (status colour), tap to select; research via the "تطوير" button.
const TL := preload("res://scripts/tech_logic.gd")
const ROW := 92.0
var scroll := 0
var selected := 0
var top := 70.0
var area := Rect2()

func layout(vp: Vector2) -> void:
	position = Vector2.ZERO
	size = vp
	area = Rect2(vp.x * 0.04, top, vp.x * 0.92, vp.y - top - 130.0)

func open() -> void:
	selected = clampi(selected, 0, TL.TECHS.size() - 1)
	visible = true

func rows() -> int:
	return maxi(1, int(area.size.y / ROW))

func scroll_by(d: int) -> void:
	scroll = clampi(scroll + d * 3, 0, maxi(0, TL.TECHS.size() - rows()))

func selected_id() -> String:
	return str(TL.TECHS[selected]["id"])

func tap(pos: Vector2) -> void:
	if not area.has_point(pos):
		return
	var i := scroll + int((pos.y - area.position.y) / ROW)
	if i >= 0 and i < TL.TECHS.size():
		selected = i

func _process(_d: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.09, 0.11, 0.98))
	var font := get_theme_default_font()
	var done := 0
	for t in TL.TECHS:
		if GameState.techs.has(t["id"]):
			done += 1
	draw_string(font, Vector2(area.position.x, 44), "شجرة التقنيات — المستوى %d — مُطوَّر %d من %d" % [GameState.level(), done, TL.TECHS.size()], HORIZONTAL_ALIGNMENT_RIGHT, area.size.x, 30, Color.WHITE)
	for k in rows():
		var i := scroll + k
		if i >= TL.TECHS.size():
			break
		var t: Dictionary = TL.TECHS[i]
		var st := TL.status(t, GameState.techs, GameState.level(), GameState.inv)
		var palette := {"done": Color(0.2, 0.55, 0.25), "ready": Color(0.25, 0.4, 0.7), "future": Color(0.22, 0.22, 0.25)}
		var col: Color = palette.get(st, Color(0.3, 0.28, 0.2))
		var r := Rect2(area.position.x, area.position.y + k * ROW, area.size.x, ROW - 8.0)
		draw_rect(r, col)
		if i == selected:
			draw_rect(r, Color(1, 0.9, 0.2), false, 4.0)
		var tags := {"done": "✓ تم", "ready": "جاهز للتطوير", "future": "قريبًا"}
		var tag: String = tags.get(st, TL.reason_text(st, t))
		draw_string(font, r.position + Vector2(12, 32), "%s  (المرحلة %d)" % [t["name"], int(t["tier"])], HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24.0, 28, Color.WHITE)
		draw_string(font, r.position + Vector2(12, 58), str(t["desc"]), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24.0, 21, Color(0.9, 0.9, 0.9))
		var ctext := ("الكلفة: " + TL.cost_text(t) + " — ") if not t["cost"].is_empty() else ""
		draw_string(font, r.position + Vector2(12, 80), ctext + tag, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24.0, 20, Color(1, 0.95, 0.7))
