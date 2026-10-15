extends RefCounted
## Pure data: piece types and slot layouts for house / fence (no autoload deps -> testable).
const TYPES := {
	"pillar": {"shape": "hex", "dim": Vector3(0.5, 2.4, 0.5), "cost": "wood", "sym": true},
	"wall_a": {"shape": "box", "dim": Vector3(1.4, 1.8, 0.3), "cost": "wood", "sym": false},
	"lintel": {"shape": "box", "dim": Vector3(4.0, 0.6, 0.3), "cost": "wood", "sym": false},
	"gable": {"shape": "tri", "dim": Vector3(4.0, 1.2, 0.3), "cost": "wood", "sym": false},
	"slab": {"shape": "box", "dim": Vector3(4.6, 0.15, 2.5), "cost": "wood", "sym": false},
	"st0": {"shape": "box", "dim": Vector3(1.8, 0.9, 0.5), "cost": "stone", "sym": false},
	"st1": {"shape": "box", "dim": Vector3(2.0, 1.0, 0.5), "cost": "stone", "sym": false},
	"st2": {"shape": "box", "dim": Vector3(2.2, 1.2, 0.6), "cost": "stone", "sym": false},
	"st3": {"shape": "box", "dim": Vector3(1.6, 0.8, 0.5), "cost": "stone", "sym": false},
}
const NAMES := {"pillar": "عمود سداسي", "wall_a": "لوح جدار", "lintel": "عتبة طويلة",
	"gable": "مثلث الجملون", "slab": "لوح سقف", "st0": "حجر صغير", "st1": "حجر متوسط",
	"st2": "حجر كبير", "st3": "حجر مسطح"}

static func _slot(id: String, type: String, pos: Vector3, yaw: float, pitch: float) -> Dictionary:
	return {"id": id, "type": type, "pos": pos, "yaw": yaw, "pitch": pitch}

static func make_slots(o: Vector3) -> Array:
	var out: Array = []
	var n := 0
	for k in 4:
		var yk := k * 90.0
		var b := Basis(Vector3.UP, deg_to_rad(yk))
		out.append(_slot("h%d" % n, "pillar", o + b * Vector3(2, 1.2, 2), 0.0, 0.0)); n += 1
		for lx in [-1.3, 1.3]:
			out.append(_slot("h%d" % n, "wall_a", o + b * Vector3(lx, 0.9, 2), yk, 0.0)); n += 1
		out.append(_slot("h%d" % n, "lintel", o + b * Vector3(0, 2.1, 2), yk, 0.0)); n += 1
		if k % 2 == 1:
			out.append(_slot("h%d" % n, "gable", o + b * Vector3(0, 3.0, 2), yk, 0.0)); n += 1
	out.append(_slot("h%d" % n, "slab", o + Vector3(0, 3.0, 1.0), 0.0, 31.0)); n += 1
	out.append(_slot("h%d" % n, "slab", o + Vector3(0, 3.0, -1.0), 0.0, -31.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var f := 0
	for s in 4:
		var bs := Basis(Vector3.UP, deg_to_rad(s * 90.0))
		for i in 5:
			if s == 0 and i == 2:
				continue  # gate gap
			var v := rng.randi_range(0, 3)
			var d: Vector3 = TYPES["st%d" % v]["dim"]
			out.append(_slot("f%d" % f, "st%d" % v, o + bs * Vector3(-4.4 + i * 2.2, d.y * 0.5, 6.0), s * 90.0, 0.0))
			f += 1
	return out
