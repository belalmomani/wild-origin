extends Control
## Round mini-map (top-right): lake, house, farm, barn, well, the player's arrow and nearby animals (predators in red).
const D := preload("res://scripts/building_data.gd")
var range_m := 75.0                 # metres from the centre to the rim (grows once the lookout tower stands)
var player: Node3D
var hunt
var story                           # story.gd: the travellers show as blue dots
var features: Array = []            # [{"p": Vector2 (x, z), "c": Color, "s": half size in px}]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _clamp(p: Vector2, c: Vector2, r: float) -> Vector2:
	var o := p - c
	return c + o.normalized() * r if o.length() > r else p

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 5.0
	draw_circle(c, r, Color(0.22, 0.46, 0.22, 0.94))
	if player == null:
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var s := r / range_m
	var lp := PackedVector2Array()                  # lake (clipped to the circle)
	var lc := Vector2(D.POND_C.x, D.POND_C.z)
	for i in 40:
		var a := TAU * float(i) / 40.0
		lp.append(_clamp(c + (lc + Vector2(cos(a), sin(a)) * D.POND_R * 0.9 - pp) * s, c, r))
	draw_colored_polygon(lp, Color(0.25, 0.6, 0.85))
	for f in features:
		var q: Vector2 = c + ((f["p"] as Vector2) - pp) * s
		if (q - c).length() < r - 4.0:
			var h: float = f["s"]
			draw_rect(Rect2(q - Vector2(h, h), Vector2(h, h) * 2.0), f["c"])
			draw_rect(Rect2(q - Vector2(h, h), Vector2(h, h) * 2.0), Color(0, 0, 0, 0.6), false, 1.0)
	if hunt != null:
		for a in hunt.animals:
			if not is_instance_valid(a) or a.dead or a.kind == "bird":
				continue
			var q: Vector2 = c + (Vector2(a.global_position.x, a.global_position.z) - pp) * s
			if (q - c).length() < r - 3.0:
				draw_circle(q, 3.5 if a.predator else 2.5, Color(0.9, 0.15, 0.1) if a.predator else Color(0.97, 0.9, 0.7))
	if story != null:
		for x in story.npcs:
			if x == null or not is_instance_valid(x) or x.dead:
				continue
			var q2: Vector2 = c + (Vector2(x.global_position.x, x.global_position.z) - pp) * s
			if (q2 - c).length() < r - 3.0:
				draw_circle(q2, 4.0, Color(0.25, 0.6, 1.0))
				draw_arc(q2, 4.0, 0.0, TAU, 12, Color(1, 1, 1), 1.0)
	var yaw: float = player.cam_yaw
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([c + fwd * 11.0, c - fwd * 7.0 + side * 7.0, c - fwd * 3.0, c - fwd * 7.0 - side * 7.0]), Color(1.0, 0.82, 0.25))
	draw_arc(c, r, 0.0, TAU, 56, Color(0.96, 0.78, 0.28), 4.0, true)
