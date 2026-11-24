extends Node3D
## Wild animal (deer / chicken): procedural 3D body with walking legs, wander/flee AI, hit zones for shooting.
const M := preload("res://scripts/mats.gd")
const L := preload("res://scripts/hunt_logic.gd")
const Rig := preload("res://scripts/animal_rig.gd")
const ElkRig := preload("res://scripts/elk_rig.gd")
const GltfRig := preload("res://scripts/gltf_rig.gd")
var kind := "deer"
var hp := 100.0
var max_hp := 100.0
var wounded := false
var dead := false
var wound_t := 0.0
var state := "wander"
var state_t := 0.0
var dir := Vector3.ZERO
var phase := 0.0
var legs: Array = []
var bones := {}            # rigged models (deer / ibex): bone name -> Node3D
var predator := false      # wolf / bear / fox: hunts the player and the penned animals (driven by hunt.gd)
var gl = null              # original Unity wolf / bear model controller (GltfRig)
var target := Vector3.ZERO
var has_target := false
var atk_t := 0.0           # cooldown between attacks on the player
var stuck_t := 0.0         # time spent pushing against the fence
var leave_t := 0.0         # walking away after an attack / giving up on the fence
var fences: Array = []   # closed enclosures that stop predators: [{"c": Vector3, "h": half-size}] (set by hunt.gd)
var chasing := false       # currently going for the player
var circ_c := Vector3.ZERO # birds: centre / radius / altitude / angle of their circling flight
var circ_r := 12.0
var circ_a := 0.0
var alt := 16.0
var wings: Array = []
var pond_bird := false     # one of the birds that circle low over the lake while it has water
var pond_ok := false
var pond_pos := Vector3.INF   # lake centre while it has water (set by hunt.gd), INF otherwise
var pond_r := 4.3
var thirst_t := 30.0
var drink_left := 0.0
var elk = null             # skinned wapiti model controller (ElkRig instance), null for the other animals
var _nx := 0.0
var _hx := 0.0
var _hy := 0.0
var idle_mode := ""        # "", "eat", "look", "alert"
var idle_t := 0.0
var hurt_t := 0.0
var _moving := 0.0
var rng := RandomNumberGenerator.new()
var corpse_t := 0.0
var tame := false
var home := Vector3.ZERO
var home_r := 0.0

func _m(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _caps(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.001)
	c.radial_segments = 12
	c.rings = 4
	return c

func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s

func _bx(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

func _cy(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c

func _zone(zn: String, size: Vector3, pos: Vector3) -> void:
	var a := Area3D.new()
	a.collision_layer = 2
	a.collision_mask = 0
	a.set_meta("zone", zn)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.position = pos
	a.add_child(cs)
	add_child(a)

## Domestic animal living in the barn pen: never flees, stays near home, cannot be shot.
func make_tame(h: Vector3, r: float) -> void:
	tame = true
	home = h
	home_r = r
	for c in get_children():
		if c is Area3D:
			(c as Area3D).collision_layer = 0

func setup(k: String, seed_v: int) -> void:
	kind = k
	rng.seed = seed_v
	var info: Dictionary = L.ANIMALS[k]
	hp = info["hp"]
	max_hp = hp
	add_to_group("animal")
	predator = L.is_predator(k)
	if k == "elk":
		_build_elk()
	elif k == "wolf" or k == "bear" or k == "fox":
		_build_gltf(k)
	elif k == "bird":
		_build_bird()
	elif Rig.has_model(k):
		_build_model(k)
	elif k == "chicken" or k == "turkey":
		_build_chicken()
	else:
		_build_deer()
	state_t = rng.randf_range(0.5, 3.0)

## Rigged model from the supplied assets (forest deer / Nubian ibex). Falls back to the simple procedural deer.
func _build_model(k: String) -> void:
	var r: Dictionary = Rig.build(k, self)
	bones = r["bones"]
	if bones.is_empty():
		_build_deer()
		return
	var z: Dictionary = r["zones"]
	_zone("head", z["head"]["size"], z["head"]["pos"])
	_zone("body", z["body"]["size"], z["body"]["pos"])
	_zone("legs", z["legs"]["size"], z["legs"]["pos"])

## Original Unity wolf / bear (the fox reuses the wolf model, smaller and red-brown tinted: no fox asset was supplied).
func _build_gltf(k: String) -> void:
	var sc := {"wolf": 0.7, "bear": 0.7, "fox": 0.42}[k] as float
	var base := "wolf" if k == "fox" else k
	gl = GltfRig.build(base, self, sc, Color(1.25, 0.72, 0.4) if k == "fox" else Color(1, 1, 1))
	var zs := {
		"wolf": [Vector3(0.35, 0.35, 0.5), Vector3(0, 0.85, -0.8), Vector3(0.5, 0.55, 1.1), Vector3(0, 0.65, 0.05), Vector3(0.5, 0.6, 1.0), Vector3(0, 0.3, 0.05)],
		"bear": [Vector3(0.5, 0.5, 0.6), Vector3(0, 0.85, -0.85), Vector3(0.85, 0.8, 1.4), Vector3(0, 0.7, 0.0), Vector3(0.85, 0.6, 1.1), Vector3(0, 0.3, 0.0)],
		"fox": [Vector3(0.22, 0.22, 0.3), Vector3(0, 0.5, -0.5), Vector3(0.3, 0.32, 0.65), Vector3(0, 0.38, 0.05), Vector3(0.3, 0.35, 0.6), Vector3(0, 0.18, 0.05)],
	}[k] as Array
	_zone("head", zs[0], zs[1])
	_zone("body", zs[2], zs[3])
	_zone("legs", zs[4], zs[5])

func _build_bird() -> void:
	var feather := M.flat(Color(0.32, 0.27, 0.22), 0.9)
	var light := M.flat(Color(0.8, 0.76, 0.66), 0.9)
	_m(self, _sph(0.14), feather, Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 0.7, 1.7))
	_m(self, _sph(0.07), light, Vector3(0, 0.03, -0.26))
	for sx in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(sx * 0.1, 0.03, -0.02)
		add_child(w)
		_m(w, _bx(0.62, 0.02, 0.28), feather, Vector3(sx * 0.31, 0, 0.02))
		wings.append(w)
	_m(self, _bx(0.12, 0.02, 0.22), feather, Vector3(0, 0, 0.32))
	_zone("head", Vector3(0.2, 0.2, 0.25), Vector3(0, 0.03, -0.26))
	_zone("body", Vector3(0.9, 0.3, 0.8), Vector3.ZERO)

## Skinned elk from the Unity prefab (textured mesh + 34 bones).
func _build_elk() -> void:
	elk = ElkRig.build(self)
	var z: Dictionary = ElkRig.zones()
	for zn in ["head", "body", "legs"]:
		_zone(zn, z[zn]["size"], z[zn]["pos"])

func flinch() -> void:
	hurt_t = 0.5

func _b(n: String) -> Node3D:
	return bones.get(n)

## Procedural pose for rigged models: diagonal gait with knee fold, spine bounce, tail/ears, idle behaviours.
func _animate(d: float, spd: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + float(get_instance_id() % 97)
	var run := clampf(spd / 3.0, 0.0, 1.0)
	_moving = lerpf(_moving, run, clampf(8.0 * d, 0.0, 1.0))
	var amp := 0.42 * _moving + 0.1 * clampf(spd / 7.0, 0.0, 1.0)
	for lab in ["f", "h"]:
		for side in ["l", "r"]:
			var up := _b("%s%s_up" % [lab, side])
			var lo := _b("%s%s_lo" % [lab, side])
			var ft := _b("%s%s_ft" % [lab, side])
			if up == null:
				continue
			# diagonal pairs: front-left moves with hind-right
			var ph := phase + (0.0 if ((lab == "f" and side == "l") or (lab == "h" and side == "r")) else PI)
			up.rotation.x = sin(ph) * amp
			var fold := maxf(0.0, cos(ph)) * 0.9 * _moving
			if lo != null:
				lo.rotation.x = -fold * (1.0 if lab == "f" else 0.8)
			if ft != null:
				ft.rotation.x = fold * 0.4
	var bounce := sin(phase * 2.0) * 0.04 * _moving
	var sp := _b("spine")
	if sp != null:
		sp.rotation.x = bounce
	var nk := _b("neck")
	var hd := _b("head")
	var nx := -sin(phase * 2.0) * 0.06 * _moving
	var hx := 0.0
	var hy := 0.0
	var ear := 0.0
	match idle_mode:
		"eat":
			nx += -0.75 + sin(t * 5.0) * 0.06
			hx += -0.35
		"look":
			hy = sin(t * 1.6) * 0.5
			hx = -0.05
		"alert":
			nx += 0.12
			hx = 0.1
			ear = 0.25
	if state == "flee":
		nx += 0.15
		hx += 0.1
	if hurt_t > 0.0:
		hurt_t -= d
		nx += 0.25 * sin(hurt_t * 12.0)
		hy += 0.3 * sin(hurt_t * 18.0)
	if nk != null:
		nk.rotation.x = lerpf(nk.rotation.x, nx, clampf(10.0 * d, 0.0, 1.0))
	if hd != null:
		hd.rotation.x = lerpf(hd.rotation.x, hx, clampf(10.0 * d, 0.0, 1.0))
		hd.rotation.y = lerpf(hd.rotation.y, hy, clampf(6.0 * d, 0.0, 1.0))
	var tl := _b("tail")
	if tl != null:
		tl.rotation.z = sin(t * 4.0) * 0.12
	for n in ["ear_l", "ear_r"]:
		var e := _b(n)
		if e != null:
			var tw := 0.18 * maxf(0.0, sin(t * 0.7 + (1.0 if n == "ear_l" else 3.0)) - 0.8) * 5.0
			e.rotation.z = (ear + tw) * (-1.0 if n == "ear_l" else 1.0)

## Procedural pose for the skinned elk: same behaviour as _animate (diagonal gait, knee/hock fold, neck, idle moods).
func _animate_elk(d: float, spd: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + float(get_instance_id() % 97)
	var run := clampf(spd / 3.0, 0.0, 1.0)
	_moving = lerpf(_moving, run, clampf(8.0 * d, 0.0, 1.0))
	var amp := 0.42 * _moving + 0.1 * clampf(spd / 7.0, 0.0, 1.0)
	elk.clear()
	for lab in ["f", "h"]:
		for side in ["L", "R"]:
			var ph := phase + (0.0 if ((lab == "f" and side == "L") or (lab == "h" and side == "R")) else PI)
			var sw := sin(ph) * amp
			var fold := maxf(0.0, cos(ph)) * _moving
			if lab == "h":
				elk.add("hip." + side, Vector3(sw, 0, 0))
				elk.add("thigh." + side, Vector3(-0.5 * fold, 0, 0))
				elk.add("shin." + side, Vector3(0.7 * fold, 0, 0))
			else:
				elk.add("clavicle." + side, Vector3(sw * 0.6, 0, 0))
				elk.add("arm." + side, Vector3(sw * 0.4, 0, 0))
				elk.add("forearm." + side, Vector3(-fold, 0, 0))
	elk.add("spine", Vector3(sin(phase * 2.0) * 0.03 * _moving, 0, 0))
	var nx := -sin(phase * 2.0) * 0.05 * _moving
	var hx := 0.0
	var hy := 0.0
	var ear := 0.0
	match idle_mode:
		"eat":
			nx += -1.0 + sin(t * 5.0) * 0.05
			hx += -0.25
		"look":
			hy = sin(t * 1.6) * 0.5
			hx = -0.05
		"alert":
			nx += 0.1
			hx = 0.1
			ear = 0.25
	if state == "flee":
		nx += 0.12
		hx += 0.1
	if hurt_t > 0.0:
		hurt_t -= d
		nx += 0.25 * sin(hurt_t * 12.0)
		hy += 0.3 * sin(hurt_t * 18.0)
	_nx = lerpf(_nx, nx, clampf(10.0 * d, 0.0, 1.0))
	_hx = lerpf(_hx, hx, clampf(10.0 * d, 0.0, 1.0))
	_hy = lerpf(_hy, hy, clampf(6.0 * d, 0.0, 1.0))
	elk.add("neck_01", Vector3(_nx * 0.4, 0, 0))
	elk.add("neck_02", Vector3(_nx * 0.35, 0, 0))
	elk.add("neck_03", Vector3(_nx * 0.25, 0, 0))
	elk.add("head", Vector3(_hx, _hy, 0))
	elk.add("tail_base", Vector3(0, sin(t * 4.0) * 0.15, 0))
	for side in ["L", "R"]:
		var tw := 0.18 * maxf(0.0, sin(t * 0.7 + (1.0 if side == "L" else 3.0)) - 0.8) * 5.0
		elk.add("ear." + side, Vector3(0, 0, (ear + tw) * (-1.0 if side == "L" else 1.0)))
	elk.apply()

func _leg(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material, hoof: Material) -> void:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	_m(p, _cy(r, h), mat, Vector3(0, -h * 0.5, 0))
	_m(p, _bx(r * 2.4, r * 1.6, r * 2.8), hoof, Vector3(0, -h, -r * 0.3))
	legs.append(p)

func _build_deer() -> void:
	var hide := M.pbr("leather", Color(0.95, 0.68, 0.42), 2.0, 0.9)
	var light := M.flat(Color(0.86, 0.78, 0.62), 0.9)
	var dark := M.flat(Color(0.12, 0.09, 0.07), 0.7)
	var horn := M.flat(Color(0.8, 0.72, 0.55), 0.8)
	_m(self, _caps(0.25, 1.05), hide, Vector3(0, 0.98, 0), Vector3(PI / 2.0, 0, 0))
	_m(self, _caps(0.2, 0.9), light, Vector3(0, 0.85, 0), Vector3(PI / 2.0, 0, 0), Vector3(0.9, 1, 0.8))   # pale belly
	_m(self, _caps(0.085, 0.55), hide, Vector3(0, 1.32, -0.52), Vector3(-0.75, 0, 0))
	_m(self, _sph(0.12), hide, Vector3(0, 1.58, -0.8), Vector3.ZERO, Vector3(0.85, 0.85, 1.45))
	_m(self, _bx(0.08, 0.07, 0.1), dark, Vector3(0, 1.55, -0.97))
	for sx in [-1.0, 1.0]:
		_m(self, _caps(0.03, 0.2), hide, Vector3(sx * 0.1, 1.7, -0.72), Vector3(0.3, 0, sx * 0.6))
		_m(self, _cy(0.014, 0.5), horn, Vector3(sx * 0.14, 1.9, -0.75), Vector3(0, 0, -sx * 0.35))
		_m(self, _cy(0.01, 0.22), horn, Vector3(sx * 0.2, 2.0, -0.8), Vector3(0.5, 0, -sx * 0.7))
		_m(self, _cy(0.01, 0.22), horn, Vector3(sx * 0.2, 1.98, -0.68), Vector3(-0.5, 0, -sx * 0.7))
		_m(self, _sph(0.02), dark, Vector3(sx * 0.07, 1.62, -0.88))
	_m(self, _sph(0.07), light, Vector3(0, 1.1, 0.58), Vector3.ZERO, Vector3(1, 1.2, 0.8))   # tail
	for sx in [-1.0, 1.0]:
		_leg(self, Vector3(sx * 0.14, 0.78, -0.38), 0.035, 0.78, hide, dark)
		_leg(self, Vector3(sx * 0.14, 0.78, 0.4), 0.04, 0.78, hide, dark)
	_zone("head", Vector3(0.3, 0.3, 0.45), Vector3(0, 1.58, -0.82))
	_zone("body", Vector3(0.55, 0.5, 1.15), Vector3(0, 1.0, 0))
	_zone("legs", Vector3(0.5, 0.7, 0.9), Vector3(0, 0.37, 0))

func _build_chicken() -> void:
	var big := kind == "turkey"
	var white := rng.randf() < 0.5
	var body_m := M.flat(Color(0.93, 0.92, 0.88) if white else Color(0.55, 0.32, 0.17), 0.9)
	if big:
		body_m = M.flat(Color(0.3, 0.2, 0.13) if white else Color(0.42, 0.28, 0.16), 0.9)
	var red := M.flat(Color(0.8, 0.1, 0.1), 0.6)
	var yellow := M.flat(Color(0.95, 0.75, 0.15), 0.6)
	var dark := M.flat(Color(0.08, 0.07, 0.06), 0.6)
	_m(self, _sph(0.17), body_m, Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.92, 1.3))
	_m(self, _sph(0.065), body_m, Vector3(0, 0.52, -0.2))
	_m(self, _bx(0.04, 0.03, 0.06), yellow, Vector3(0, 0.5, -0.28))
	_m(self, _bx(0.02, 0.06, 0.07), red, Vector3(0, 0.6, -0.2))
	_m(self, _bx(0.03, 0.04, 0.02), red, Vector3(0, 0.45, -0.25))
	_m(self, _bx(0.04, 0.2, 0.16), body_m, Vector3(0, 0.4, 0.24), Vector3(0.6, 0, 0))
	for sx in [-1.0, 1.0]:
		_m(self, _bx(0.03, 0.14, 0.22), body_m.duplicate(), Vector3(sx * 0.16, 0.32, 0.0))
		_m(self, _sph(0.012), dark, Vector3(sx * 0.045, 0.54, -0.235))
		_leg(self, Vector3(sx * 0.06, 0.2, 0.0), 0.012, 0.2, yellow, yellow)
	_zone("head", Vector3(0.16, 0.16, 0.18), Vector3(0, 0.54, -0.22))
	_zone("body", Vector3(0.3, 0.28, 0.42), Vector3(0, 0.32, 0.02))
	_zone("legs", Vector3(0.2, 0.2, 0.2), Vector3(0, 0.1, 0))
	if big:
		scale = Vector3.ONE * 1.7

func _play(short: String, speed: float = 1.0) -> void:
	if gl != null:
		gl.play(short, speed)

## Predator AI body (the target is chosen by hunt.gd): sneaks / runs to the target, waits at a closed fence, walks away after an attack.
func _predator_tick(d: float, ppos: Vector3, world) -> void:
	var info: Dictionary = L.ANIMALS[kind]
	atk_t -= d
	var spd := 0.0
	var v := target - global_position
	v.y = 0.0
	var dist := v.length()
	if leave_t > 0.0:
		leave_t -= d
		var away := global_position - ppos
		away.y = 0.0
		if away.length() > 0.1:
			dir = away.normalized()
		spd = float(info["walk"]) * 1.6
	elif has_target:
		if dist > float(info["reach"]) * 0.8:
			dir = v.normalized()
			spd = float(info["run"]) if dist < 30.0 else float(info["walk"]) * 1.6
		else:
			spd = 0.0
			if dist > 0.05:
				dir = v.normalized()
	else:
		state_t -= d
		if state_t <= 0.0:
			state_t = rng.randf_range(3.0, 7.0)
			if rng.randf() < 0.4:
				dir = Vector3.ZERO
			else:
				var a := rng.randf() * TAU
				dir = Vector3(cos(a), 0, sin(a))
		spd = float(info["walk"]) * 0.8 if dir != Vector3.ZERO else 0.0
	var old := global_position
	var p := old + dir * spd * d
	p.x = clampf(p.x, -68.0, 68.0)
	p.z = clampf(p.z, -68.0, 68.0)
	if not fences.is_empty():
		var blocked := false
		for f in fences:                          # closed fence / barn walls: predators cannot enter
			var fc: Vector3 = f["c"]
			var fh: float = f["h"]
			var in_new := absf(p.x - fc.x) < fh and absf(p.z - fc.z) < fh
			var in_old := absf(old.x - fc.x) < fh and absf(old.z - fc.z) < fh
			if in_new and not in_old:
				blocked = true
		if blocked:
			p = old
			stuck_t += d
		else:
			stuck_t = maxf(0.0, stuck_t - d)
		if stuck_t > 6.0:
			leave_t = 14.0
			stuck_t = 0.0
			has_target = false
	if world != null:
		p.y = world.height_at(p.x, p.z)
	global_position = p
	if dir != Vector3.ZERO and (spd > 0.05 or has_target):
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * d)
	if spd > 4.5:
		_play("cycle_run", 1.0)
	elif spd > 2.4:
		_play("cycle_trot", 1.0)
	elif spd > 0.3:
		_play("cycle_walk", 1.0)
	else:
		_play("idle_breathe", 1.0)

## Birds circle high above the forest.
func _bird_tick(d: float, world) -> void:
	if dead:
		return
	if pond_bird:
		circ_r = lerpf(circ_r, 5.5 if pond_ok else 16.0, clampf(0.4 * d, 0.0, 1.0))
		alt = lerpf(alt, 4.5 if pond_ok else 16.0, clampf(0.4 * d, 0.0, 1.0))
	circ_a += d * 6.0 / circ_r
	var da := Vector3(-sin(circ_a), 0, cos(circ_a))
	global_position = circ_c + Vector3(cos(circ_a) * circ_r, alt + sin(circ_a * 3.0) * 0.8, sin(circ_a) * circ_r)
	rotation.y = atan2(-da.x, -da.z)
	var t := Time.get_ticks_msec() * 0.001
	for i in wings.size():
		(wings[i] as Node3D).rotation.z = sin(t * 9.0 + float(get_instance_id() % 7)) * 0.55 * (1.0 if i == 0 else -1.0)

func tick(d: float, ppos: Vector3, crouch: bool, world) -> void:
	if dead:
		corpse_t += d
		return
	if kind == "bird":
		_bird_tick(d, world)
		return
	if predator:
		_predator_tick(d, ppos, world)
		return
	var info: Dictionary = L.ANIMALS[kind]
	state_t -= d
	var away := global_position - ppos
	away.y = 0.0
	var dist := away.length()
	var alert: float = info["flee"] * (0.5 if crouch else 1.0) * (0.7 if GameState.has_tech("stealth") else 1.0)
	if wounded:
		wound_t += d
		if wound_t > 25.0:
			state = "tired"
	if not tame and state != "tired" and state != "flee" and dist < alert:
		state = "flee"
		state_t = 3.5
		dir = (away.normalized() + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))).normalized()
	if state == "wander" and not tame and not wounded and pond_pos != Vector3.INF:
		thirst_t -= d
		if thirst_t <= 0.0:
			state = "drink"
			state_t = 45.0
			drink_left = 7.0
	var spd := 0.0
	match state:
		"drink":
			var to := pond_pos - global_position
			to.y = 0.0
			if pond_pos == Vector3.INF or state_t <= 0.0:
				state = "wander"
				idle_mode = ""
				thirst_t = rng.randf_range(40.0, 90.0)
			elif to.length() - pond_r > 1.0:
				dir = to.normalized()
				spd = float(info["walk"]) * 1.8
				idle_mode = ""
			else:
				dir = Vector3.ZERO
				idle_mode = "eat"                   # head down at the water's edge
				rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 4.0 * d)
				drink_left -= d
				if drink_left <= 0.0:
					state = "wander"
					idle_mode = ""
					thirst_t = rng.randf_range(40.0, 90.0)
		"flee":
			idle_mode = ""
			spd = info["run"]
			if state_t <= 0.0:
				state = "wander"
				state_t = 0.0
		"wander":
			if state_t <= 0.0:
				state_t = rng.randf_range(2.5, 6.0)
				var to_home := home - global_position
				to_home.y = 0.0
				if tame and to_home.length() > home_r:
					dir = to_home.normalized()
				elif rng.randf() < 0.45:
					dir = Vector3.ZERO
				else:
					var a := rng.randf() * TAU
					dir = Vector3(cos(a), 0, sin(a))
			spd = info["walk"] if dir != Vector3.ZERO else 0.0
			if dir == Vector3.ZERO and (not bones.is_empty() or elk != null):
				idle_t -= d
				if idle_t <= 0.0:
					idle_t = rng.randf_range(2.0, 5.0)
					idle_mode = ["eat", "look", "", "alert"][rng.randi() % 4]
			else:
				idle_mode = ""
	if wounded:
		spd *= 0.4
	var p := global_position + dir * spd * d
	p.x = clampf(p.x, -68.0, 68.0)
	p.z = clampf(p.z, -68.0, 68.0)
	if world != null:
		p.y = world.height_at(p.x, p.z)
	if tame and home_r > 0.0:                       # penned animals can never leave their enclosure
		var off := Vector3(p.x - home.x, 0.0, p.z - home.z)
		if off.length() > home_r:
			var e := off.normalized() * home_r
			p.x = home.x + e.x
			p.z = home.z + e.z
			if world != null:
				p.y = world.height_at(p.x, p.z)
	global_position = p
	if spd > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * d)
	phase += d * spd * 3.5
	if elk != null:
		_animate_elk(d, spd)
		return
	if not bones.is_empty():
		_animate(d, spd)
		return
	var sw := sin(phase) * 0.6 * clampf(spd / 3.0, 0.0, 1.0)
	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sw if (i % 3 == 0) else -sw   # diagonal gait

func die(gentle: bool) -> void:
	dead = true
	for c in get_children():
		if c is Area3D:
			(c as Area3D).collision_layer = 0
	if gl != null and not gentle:
		_play("death_neutral")
		return
	if gentle:
		# gentle mode: no lying body, the animal simply fades away leaving the food behind
		var t := create_tween()
		t.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	else:
		rotation.z = PI / 2.0
		position.y += 0.25
