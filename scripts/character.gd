extends Node3D
## Detailed survivor (bearded man: olive shirt, leather straps, cargo pants, boots, fingerless gloves,
## scarf, backpack with bedroll, axe). One consistent model with a full joint hierarchy, animated procedurally:
## idle, walk, run, jump/fall, crouch, chop, gather, carry stone, aim, build (kneel).
## NOTE: this is a hand-built procedural model, not a scanned/photoreal asset. See assets/hero/README.md.
const M := preload("res://scripts/mats.gd")
const G := preload("res://scripts/mesh_gen.gd")
var J := {}              # joint name -> Node3D
var stone: Node3D
var axe: Node3D
signal footstep
var weapon := "slingshot"
var walk_w := 0.0
var prev_cs := 1.0
var was_air := false
var air_vy := 0.0
var land_t := 0.0
var land_amp := 0.0
var phase := 0.0
var t := 0.0
var action_t := 0.0
var last_action := ""

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _caps(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.001)
	c.radial_segments = 14
	c.rings = 5
	return _mi(parent, c, mat, pos, rot, scl)

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(parent, b, mat, pos, rot)

func _sph(parent: Node3D, r: float, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _mi(parent, s, mat, pos, Vector3.ZERO, scl)

func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return _mi(parent, c, mat, pos, rot)

func _joint(parent: Node3D, jn: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	J[jn] = n
	return n

func _ready() -> void:
	var shirt := M.pbr("fabric", Color(0.5, 0.58, 0.38), 3.0, 0.95)
	var pants := M.pbr("fabric", Color(0.36, 0.29, 0.21), 3.0, 0.95)
	var leather := M.pbr("leather", Color(0.62, 0.38, 0.2), 3.0, 0.7)
	var dark_leather := M.pbr("leather", Color(0.36, 0.22, 0.12), 3.0, 0.7)
	var canvas := M.pbr("fabric", Color(0.55, 0.47, 0.3), 3.0, 0.95)
	var scarf := M.pbr("fabric", Color(0.62, 0.5, 0.36), 3.0, 0.95)
	var glove := M.flat(Color(0.1, 0.09, 0.08), 0.8)
	var skin := M.flat(Color(0.8, 0.6, 0.46), 0.55)
	var skin_dark := M.flat(Color(0.7, 0.5, 0.38), 0.6)
	var hair := M.flat(Color(0.2, 0.12, 0.07), 0.6)
	var stubble := M.flat(Color(0.3, 0.21, 0.15), 0.9)
	var metal := M.flat(Color(0.62, 0.64, 0.68), 0.35)
	var wood := M.pbr("bark", Color(0.9, 0.8, 0.65), 1.5, 0.9)

	var hips := _joint(self, "hips", Vector3(0, 0.95, 0))
	_caps(hips, 0.17, 0.34, pants, Vector3(0, 0.0, 0), Vector3(1.15, 0.7, 0.8))
	# belt + pouches + knife
	_cyl(hips, 0.2, 0.06, dark_leather, Vector3(0, 0.1, 0)).scale = Vector3(1.05, 1, 0.78)
	_box(hips, Vector3(0.05, 0.05, 0.02), metal, Vector3(0, 0.1, -0.165))
	for sx in [-1.0, 1.0]:
		_box(hips, Vector3(0.09, 0.12, 0.07), leather, Vector3(sx * 0.19, 0.04, -0.03))
	_box(hips, Vector3(0.04, 0.2, 0.025), dark_leather, Vector3(0.2, -0.1, 0.02), Vector3(0, 0, 0.1))
	_box(hips, Vector3(0.025, 0.14, 0.01), metal, Vector3(0.2, -0.12, 0.02), Vector3(0, 0, 0.1))
	var spine := _joint(hips, "spine", Vector3(0, 0.1, 0))
	_caps(spine, 0.17, 0.66, shirt, Vector3(0, 0.28, 0), Vector3(1.3, 1.0, 0.82))
	var chest := _joint(spine, "chest", Vector3(0, 0.5, 0))
	# chest pockets, suspenders, harness strap
	for sx in [-1.0, 1.0]:
		_box(chest, Vector3(0.1, 0.075, 0.02), shirt, Vector3(sx * 0.1, -0.02, -0.158))
		_box(chest, Vector3(0.045, 0.62, 0.03), leather, Vector3(sx * 0.12, -0.14, -0.15), Vector3(0, 0, -sx * 0.07))
		_box(chest, Vector3(0.045, 0.42, 0.03), leather, Vector3(sx * 0.13, 0.02, 0.15), Vector3(0, 0, -sx * 0.1))
	_box(chest, Vector3(0.28, 0.035, 0.03), leather, Vector3(0, -0.05, -0.16))
	# backpack with bedroll
	_box(chest, Vector3(0.38, 0.5, 0.2), canvas, Vector3(0, -0.05, 0.24))
	_box(chest, Vector3(0.36, 0.1, 0.22), leather, Vector3(0, 0.22, 0.24))
	_box(chest, Vector3(0.12, 0.22, 0.09), canvas, Vector3(-0.22, -0.12, 0.25))
	_box(chest, Vector3(0.12, 0.22, 0.09), canvas, Vector3(0.22, -0.12, 0.25))
	_cyl(chest, 0.085, 0.46, M.pbr("fabric", Color(0.45, 0.4, 0.3), 3.0), Vector3(0, -0.34, 0.27), Vector3(0, 0, PI / 2.0))
	_box(chest, Vector3(0.03, 0.2, 0.01), dark_leather, Vector3(0, -0.05, 0.345))
	# neck, scarf
	_cyl(chest, 0.055, 0.1, skin, Vector3(0, 0.2, 0))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.075
	tor.outer_radius = 0.135
	_mi(chest, tor, scarf, Vector3(0, 0.17, 0), Vector3(0, 0, 0), Vector3(1, 1.2, 1))
	_box(chest, Vector3(0.12, 0.26, 0.025), scarf, Vector3(0.03, 0.02, -0.17), Vector3(0.1, 0, 0.12))
	# head
	var head := _joint(chest, "head", Vector3(0, 0.34, 0))
	_sph(head, 0.105, skin, Vector3(0, 0, 0), Vector3(0.92, 1.18, 1.05))
	_sph(head, 0.075, skin, Vector3(0, -0.07, -0.035), Vector3(1.0, 0.8, 0.9))   # jaw
	_box(head, Vector3(0.15, 0.022, 0.035), skin_dark, Vector3(0, 0.035, -0.092))   # brow
	for sx in [-1.0, 1.0]:
		_sph(head, 0.013, M.flat(Color(0.95, 0.95, 0.92), 0.4), Vector3(sx * 0.038, 0.012, -0.098))
		_sph(head, 0.0075, M.flat(Color(0.18, 0.26, 0.32), 0.3), Vector3(sx * 0.038, 0.012, -0.108))
		_sph(head, 0.022, skin_dark, Vector3(sx * 0.098, -0.005, 0.0), Vector3(0.5, 1.0, 0.8))   # ears
	_caps(head, 0.014, 0.075, skin, Vector3(0, -0.015, -0.105), Vector3(1, 1, 1), Vector3(-0.35, 0, 0))   # nose
	_box(head, Vector3(0.06, 0.012, 0.012), M.flat(Color(0.45, 0.2, 0.18), 0.6), Vector3(0, -0.075, -0.104))
	_sph(head, 0.1, stubble, Vector3(0, -0.062, -0.028), Vector3(0.97, 0.55, 0.9))   # beard
	_box(head, Vector3(0.07, 0.015, 0.012), hair, Vector3(0, -0.052, -0.108))     # moustache
	_sph(head, 0.112, hair, Vector3(0, 0.035, 0.018), Vector3(0.97, 0.78, 1.06))   # hair cap
	for i in 9:
		var a := TAU * i / 9.0
		_sph(head, 0.04, hair, Vector3(cos(a) * 0.085, 0.07 + (i % 3) * 0.012, sin(a) * 0.085 + 0.02), Vector3(1, 0.7, 1.2))
	_sph(head, 0.05, hair, Vector3(0.02, 0.1, -0.045), Vector3(1.3, 0.8, 1.1))     # swept fringe
	# arms
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var sh := _joint(chest, "sh" + side, Vector3(sx * 0.255, 0.08, 0))
		_sph(sh, 0.075, shirt, Vector3.ZERO)
		_caps(sh, 0.062, 0.34, shirt, Vector3(0, -0.15, 0))
		var el := _joint(sh, "el" + side, Vector3(0, -0.3, 0))
		_sph(el, 0.055, shirt, Vector3.ZERO)
		_caps(el, 0.052, 0.3, skin, Vector3(0, -0.13, 0))         # rolled sleeves: bare forearm
		_cyl(el, 0.062, 0.05, shirt, Vector3(0, -0.015, 0))        # rolled cuff
		var hand := _joint(el, "hand" + side, Vector3(0, -0.29, 0))
		_box(hand, Vector3(0.085, 0.085, 0.045), glove, Vector3(0, -0.035, 0))
		for f in 4:
			_box(hand, Vector3(0.017, 0.055, 0.02), skin, Vector3(-0.031 + f * 0.0205, -0.1, -0.004))
		_box(hand, Vector3(0.025, 0.05, 0.022), skin, Vector3(-sx * 0.05, -0.04, -0.015), Vector3(0, 0, -sx * 0.5))
		_box(hand, Vector3(0.09, 0.03, 0.05), dark_leather, Vector3(0, 0.0, 0))   # wrist strap
		if side == "R":
			axe = Node3D.new()
			axe.position = Vector3(0, -0.04, 0)
			hand.add_child(axe)
			_cyl(axe, 0.016, 0.72, wood, Vector3(0, -0.18, 0))
			_box(axe, Vector3(0.03, 0.11, 0.17), metal, Vector3(0, -0.5, -0.07))
			_box(axe, Vector3(0.036, 0.04, 0.05), dark_leather, Vector3(0, -0.45, 0.0))
	# legs
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var hp := _joint(hips, "hip" + side, Vector3(sx * 0.105, -0.02, 0))
		_caps(hp, 0.1, 0.5, pants, Vector3(0, -0.22, 0))
		_box(hp, Vector3(0.05, 0.17, 0.12), pants, Vector3(sx * 0.1, -0.2, 0.0))      # cargo pocket
		_box(hp, Vector3(0.056, 0.05, 0.125), leather, Vector3(sx * 0.1, -0.12, 0.0)) # flap
		var kn := _joint(hp, "kn" + side, Vector3(0, -0.46, 0))
		_sph(kn, 0.085, pants, Vector3.ZERO)
		_caps(kn, 0.078, 0.5, pants, Vector3(0, -0.21, 0))
		var an := _joint(kn, "an" + side, Vector3(0, -0.45, 0))
		_cyl(an, 0.083, 0.17, dark_leather, Vector3(0, 0.07, 0))                       # boot shaft
		_box(an, Vector3(0.115, 0.085, 0.27), dark_leather, Vector3(0, -0.04, -0.06))  # boot
		_box(an, Vector3(0.12, 0.035, 0.285), M.flat(Color(0.1, 0.08, 0.07), 0.9), Vector3(0, -0.095, -0.06))   # sole
		_box(an, Vector3(0.11, 0.02, 0.1), leather, Vector3(0, 0.0, -0.1))            # toe cap
	# carried stone (hidden unless carrying)
	stone = Node3D.new()
	stone.position = Vector3(0, -0.1, -0.33)
	stone.visible = false
	chest.add_child(stone)
	_mi(stone, G.rock(77, 1), M.pbr("rock", Color.WHITE, 0.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.2)

func set_carrying(on: bool) -> void:
	stone.visible = on

func _rot(jn: String, target: Vector3, k: float) -> void:
	var n: Node3D = J[jn]
	n.rotation = n.rotation.lerp(target, k)

## state inputs come from player.gd every physics frame
func set_weapon(id: String) -> void:
	weapon = id

func set_scoped(_on: bool) -> void:
	pass

## turn = body yaw rate (rad/s): leans into turns and steps the feet when turning on the spot.
func animate(d: float, spd: float, on_floor: bool, vy: float, crouch: bool, action: String, carrying: bool, turn: float = 0.0) -> void:
	t += d
	if on_floor and spd < 0.5 and absf(turn) > 1.0 and action == "":
		spd = 0.8 * clampf(absf(turn) / 3.0, 0.3, 1.0)       # pivot with small steps instead of sliding
	if action != last_action:
		action_t = 0.0
		last_action = action
	action_t += d
	var k := clampf(d * 14.0, 0.0, 1.0)
	var amp := clampf(spd / 6.0, 0.0, 1.0)
	var t_run := clampf((spd - 1.6) / 4.2, 0.0, 1.0)
	var stride := lerpf(0.62, 1.25, amp)
	phase += d * spd / stride * PI           # one step per PI: foot speed matches ground speed (no sliding)
	var sw := sin(phase)
	var cs := cos(phase)
	var hip_y := 0.95
	var wt := clampf((spd - 0.2) / 1.0, 0.0, 1.0) if on_floor else 0.0
	walk_w = lerpf(walk_w, wt, clampf(d * 8.0, 0.0, 1.0))      # smooth idle <-> walk <-> run blend
	if on_floor and walk_w > 0.4 and cs * prev_cs < 0.0:
		footstep.emit()                       # heel strike
	prev_cs = cs
	var tg := {"spine": Vector3.ZERO, "chest": Vector3.ZERO, "head": Vector3.ZERO, "hips": Vector3.ZERO,
		"shL": Vector3.ZERO, "shR": Vector3.ZERO, "elL": Vector3.ZERO, "elR": Vector3.ZERO,
		"hipL": Vector3.ZERO, "hipR": Vector3.ZERO, "knL": Vector3.ZERO, "knR": Vector3.ZERO}
	# --- locomotion: idle pose blended with a biomechanical gait (arms opposite legs, pelvis twist, knee flexion) ---
	var shift := sin(t * 0.45)                                   # slow weight shift between the legs
	var idle := {"spine": Vector3(sin(t * 1.6) * 0.012, 0, shift * 0.02), "head": Vector3(sin(t * 0.7) * 0.03, sin(t * 0.45) * 0.1, -shift * 0.02),
		"hips": Vector3(0, 0, shift * 0.025), "knL": Vector3(-0.05 * maxf(0.0, shift), 0, 0), "knR": Vector3(-0.05 * maxf(0.0, -shift), 0, 0),
		"shL": Vector3(0.03, 0, 0.09 + sin(t * 1.6) * 0.012), "shR": Vector3(0.03, 0, -0.09 - sin(t * 1.6) * 0.012),
		"elL": Vector3(0.18, 0, 0), "elR": Vector3(0.18, 0, 0)}
	var A := lerpf(0.28, 0.42, clampf(spd / 2.2, 0.0, 1.0)) + 0.33 * t_run      # hip swing
	var K := 0.9 + 0.6 * t_run                                                 # swing-phase knee flexion
	var arm := 0.30 + 0.35 * t_run
	var tw := 0.5 + t_run
	var el := 0.22 + 1.0 * t_run
	var walk := {
		"hipL": Vector3(sw * A, 0, 0), "hipR": Vector3(-sw * A, 0, 0),
		"knL": Vector3(-(0.08 + K * pow(maxf(0.0, cs), 1.4) + 0.14 * pow(maxf(0.0, sw), 2.0)), 0, 0),
		"knR": Vector3(-(0.08 + K * pow(maxf(0.0, -cs), 1.4) + 0.14 * pow(maxf(0.0, -sw), 2.0)), 0, 0),
		"shL": Vector3(-sw * arm - 0.04, 0, 0.05), "shR": Vector3(sw * arm - 0.04, 0, -0.05),
		"elL": Vector3(el + (0.25 + 0.4 * t_run) * maxf(0.0, -sw), 0, 0), "elR": Vector3(el + (0.25 + 0.4 * t_run) * maxf(0.0, sw), 0, 0),
		"hips": Vector3(0, sw * 0.10 * tw, 0), "spine": Vector3(-(0.03 + 0.2 * t_run), -sw * 0.08 * tw, 0),
		"head": Vector3(0.03 + 0.15 * t_run, sw * 0.03, 0)}
	for key in walk:
		tg[key] = (idle.get(key, Vector3.ZERO) as Vector3).lerp(walk[key], walk_w)
	for key in idle:
		if not walk.has(key):
			tg[key] = idle[key]
	hip_y = lerpf(0.95 + sin(t * 1.6) * 0.004, 0.95 - (0.02 + 0.035 * t_run) * (1.0 - absf(cs)), walk_w)
	# --- jump: push-off -> flight -> landing, blended by vertical speed (no pops between poses) ---
	if not on_floor:
		was_air = true
		air_vy = minf(air_vy, vy)
		var up := clampf(vy / 5.0, 0.0, 1.0)
		tg["hipL"] = Vector3(0.35, 0, 0).lerp(Vector3(0.7, 0, 0), up)
		tg["hipR"] = Vector3(-0.25, 0, 0).lerp(Vector3(-0.2, 0, 0), up)
		tg["knL"] = Vector3(-0.7, 0, 0).lerp(Vector3(-1.1, 0, 0), up)
		tg["knR"] = Vector3(-0.4, 0, 0).lerp(Vector3(-0.5, 0, 0), up)
		tg["shL"] = Vector3(1.0, 0, 0.55).lerp(Vector3(2.2, 0, 0.3), up)
		tg["shR"] = Vector3(1.0, 0, -0.55).lerp(Vector3(2.2, 0, -0.3), up)
		tg["elL"] = Vector3(0.25, 0, 0)
		tg["elR"] = Vector3(0.25, 0, 0)
		tg["spine"] = Vector3(-0.05, 0, 0).lerp(Vector3(-0.12, 0, 0), up)
	elif was_air:
		was_air = false
		land_amp = clampf(-air_vy / 9.0, 0.25, 1.0)
		land_t = 1.0
		air_vy = 0.0
		footstep.emit()                          # landing thud
	land_t = maxf(0.0, land_t - d * 3.0)
	if land_t > 0.0 and on_floor and action == "":
		var lw := land_t * land_amp               # absorb the impact: knees and hips bend, torso leans, arms balance
		tg["hipL"] = (tg["hipL"] as Vector3) + Vector3(0.55 * lw, 0, 0)
		tg["hipR"] = (tg["hipR"] as Vector3) + Vector3(0.55 * lw, 0, 0)
		tg["knL"] = (tg["knL"] as Vector3) + Vector3(-1.0 * lw, 0, 0)
		tg["knR"] = (tg["knR"] as Vector3) + Vector3(-1.0 * lw, 0, 0)
		tg["spine"] = (tg["spine"] as Vector3) + Vector3(-0.2 * lw, 0, 0)
		tg["shL"] = (tg["shL"] as Vector3) + Vector3(0.4 * lw, 0, 0.1 * lw)
		tg["shR"] = (tg["shR"] as Vector3) + Vector3(0.4 * lw, 0, -0.1 * lw)
		hip_y -= 0.10 * lw
	# --- crouch ---
	if crouch and on_floor:
		hip_y = 0.62
		tg["hipL"] = Vector3(1.25 + sw * 0.25 * amp, 0, 0)
		tg["hipR"] = Vector3(1.25 - sw * 0.25 * amp, 0, 0)
		tg["knL"] = Vector3(-2.15, 0, 0)
		tg["knR"] = Vector3(-2.15, 0, 0)
		tg["spine"] = Vector3(-0.4, 0, 0)
		tg["head"] = Vector3(0.35, 0, 0)
		tg["shL"] = Vector3(0.5, 0, 0.1)
		tg["shR"] = Vector3(0.5, 0, -0.1)
		tg["elL"] = Vector3(0.7, 0, 0)
		tg["elR"] = Vector3(0.7, 0, 0)
	# --- carry stone ---
	if carrying and action == "":
		tg["shL"] = Vector3(1.1, 0, 0.3)
		tg["shR"] = Vector3(1.1, 0, -0.3)
		tg["elL"] = Vector3(1.55, 0, 0)
		tg["elR"] = Vector3(1.55, 0, 0)
		tg["spine"] = Vector3(0.1 - 0.1 * amp, 0, 0)
	# --- actions ---
	match action:
		"chop":
			var p := fposmod(action_t * 1.5, 1.0)
			var swing := smoothstep(0.0, 0.55, p) * (1.0 - smoothstep(0.55, 0.72, p))
			var a := lerpf(0.35, 2.6, swing)
			tg["shL"] = Vector3(a, 0, 0.18)
			tg["shR"] = Vector3(a, 0, -0.18)
			tg["elL"] = Vector3(lerpf(0.9, 0.6, swing), 0, 0)
			tg["elR"] = Vector3(lerpf(0.9, 0.6, swing), 0, 0)
			tg["spine"] = Vector3(lerpf(-0.45, 0.2, swing), 0.2, 0)
			tg["hipL"] = Vector3(0.35, 0, 0)
			tg["hipR"] = Vector3(-0.25, 0, 0)
			tg["knL"] = Vector3(-0.45, 0, 0)
			tg["knR"] = Vector3(-0.3, 0, 0)
			hip_y = 0.9
		"gather":
			hip_y = 0.6
			tg["hipL"] = Vector3(1.3, 0, 0)
			tg["hipR"] = Vector3(1.3, 0, 0)
			tg["knL"] = Vector3(-2.2, 0, 0)
			tg["knR"] = Vector3(-2.2, 0, 0)
			tg["spine"] = Vector3(-0.85, 0, 0)
			tg["head"] = Vector3(0.6, 0, 0)
			var dig := sin(action_t * 8.0) * 0.25
			tg["shL"] = Vector3(1.25 + dig, 0, 0.12)
			tg["shR"] = Vector3(1.25 - dig, 0, -0.12)
			tg["elL"] = Vector3(0.45, 0, 0)
			tg["elR"] = Vector3(0.45, 0, 0)
		"aim":
			tg["hipL"] = Vector3(0.2, 0, 0)
			tg["hipR"] = Vector3(-0.2, 0, 0)
			match weapon:
				"bow":       # left arm holds the bow out, right hand draws the string to the cheek
					tg["shL"] = Vector3(1.55, 0, 0.1)
					tg["elL"] = Vector3(0.12, 0, 0)
					tg["shR"] = Vector3(1.2, 0, 0.55)
					tg["elR"] = Vector3(2.35, 0, 0)
					tg["spine"] = Vector3(-0.04, 0.0, 0)
					tg["head"] = Vector3(0.0, -0.25, 0)
				"crossbow":  # two hands on the stock
					tg["shL"] = Vector3(1.45, 0, 0.14)
					tg["elL"] = Vector3(0.5, 0, 0)
					tg["shR"] = Vector3(1.5, 0, -0.12)
					tg["elR"] = Vector3(0.35, 0, 0)
					tg["spine"] = Vector3(-0.05, 0.0, 0)
					tg["head"] = Vector3(0.05, 0.0, 0)
				_:           # slingshot: right arm holds the fork, left hand pulls the band back
					tg["shR"] = Vector3(1.55, 0, -0.08)
					tg["elR"] = Vector3(0.1, 0, 0)
					tg["shL"] = Vector3(1.15, 0, 0.3)
					tg["elL"] = Vector3(2.15, 0, 0)
					tg["spine"] = Vector3(-0.04, 0.25, 0)
					tg["head"] = Vector3(0.0, -0.25, 0)
		"build":
			hip_y = 0.55
			tg["hipR"] = Vector3(1.35, 0, 0)
			tg["knR"] = Vector3(-1.45, 0, 0)
			tg["hipL"] = Vector3(0.2, 0, 0)
			tg["knL"] = Vector3(-2.3, 0, 0)
			tg["spine"] = Vector3(-0.6, 0, 0)
			tg["head"] = Vector3(0.4, 0, 0)
			var pat := sin(action_t * 6.0) * 0.18
			tg["shL"] = Vector3(1.25 + pat, 0, 0.15)
			tg["shR"] = Vector3(1.25 - pat, 0, -0.15)
			tg["elL"] = Vector3(0.7, 0, 0)
			tg["elR"] = Vector3(0.7, 0, 0)
	if action == "" and on_floor:
		var lean := clampf(turn * 0.035, -0.12, 0.12)      # bank into the turn
		tg["spine"] = (tg["spine"] as Vector3) + Vector3(0, 0, lean)
		tg["hips"] = (tg["hips"] as Vector3) + Vector3(0, 0, -lean * 0.5)
		tg["head"] = (tg["head"] as Vector3) + Vector3(0, clampf(turn * 0.03, -0.15, 0.15), 0)
	for jn in tg:
		_rot(jn, tg[jn], k)
	var hp: Node3D = J["hips"]
	hp.position.y = lerpf(hp.position.y, hip_y, k)
	# keep feet flat: ankle counter-rotates thigh+shin
	for s in ["L", "R"]:
		var h: Node3D = J["hip" + s]
		var kn: Node3D = J["kn" + s]
		var an: Node3D = J["an" + s]
		var sgn := 1.0 if s == "L" else -1.0
		var behind := maxf(0.0, -sw * sgn)        # leg behind the body -> toe-off (toes down)
		var ahead := maxf(0.0, sw * sgn)          # leg ahead -> heel strike (toes up)
		an.rotation.x = clampf(-(h.rotation.x + kn.rotation.x) * 0.8 - 0.35 * behind * walk_w + 0.14 * pow(ahead, 3.0) * walk_w, -0.9, 0.9)
	axe.visible = not carrying or action == "chop"
