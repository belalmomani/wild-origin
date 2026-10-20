extends Node3D
## Wild animal (deer / chicken): procedural 3D body with walking legs, wander/flee AI, hit zones for shooting.
const M := preload("res://scripts/mats.gd")
const L := preload("res://scripts/hunt_logic.gd")
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
	if k == "deer":
		_build_deer()
	else:
		_build_chicken()
	state_t = rng.randf_range(0.5, 3.0)

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
	var white := rng.randf() < 0.5
	var body_m := M.flat(Color(0.93, 0.92, 0.88) if white else Color(0.55, 0.32, 0.17), 0.9)
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

func tick(d: float, ppos: Vector3, crouch: bool, world) -> void:
	if dead:
		corpse_t += d
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
	var spd := 0.0
	match state:
		"flee":
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
	if wounded:
		spd *= 0.4
	var p := global_position + dir * spd * d
	p.x = clampf(p.x, -68.0, 68.0)
	p.z = clampf(p.z, -68.0, 68.0)
	if world != null:
		p.y = world.height_at(p.x, p.z)
	global_position = p
	if spd > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * d)
	phase += d * spd * 3.5
	var sw := sin(phase) * 0.6 * clampf(spd / 3.0, 0.0, 1.0)
	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sw if (i % 3 == 0) else -sw   # diagonal gait

func die(gentle: bool) -> void:
	dead = true
	for c in get_children():
		if c is Area3D:
			(c as Area3D).collision_layer = 0
	if gentle:
		# gentle mode: no lying body, the animal simply fades away leaving the food behind
		var t := create_tween()
		t.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	else:
		rotation.z = PI / 2.0
		position.y += 0.25
