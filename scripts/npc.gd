extends Node3D
## A lost traveller of the story (two girls and a man): simple procedural person, animated by walking, fear and work.
## Forward is -Z like every other model in the game. Hand-built, not a scanned asset.
const M := preload("res://scripts/mats.gd")
var kind := "girl"             # "girl" | "man"
var look := 0                  # colour variant
var hp := 100.0
var dead := false
var legs: Array = []
var arms: Array = []
var _t := 0.0
var _hurt := 0.0
var _down_t := 0.0

func setup(k: String, l: int) -> void:
	kind = k
	look = l

func _mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s

func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.001)
	c.radial_segments = 12
	c.rings = 4
	return c

func _cone(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 14
	return c

func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j

func _ready() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.66, 0.52) if look != 2 else Color(0.78, 0.58, 0.44)
	skin.roughness = 0.8
	var dark := M.pbr("fabric", Color(0.2, 0.17, 0.15), 3.0, 0.95)
	var boots := M.pbr("leather", Color(0.3, 0.2, 0.12), 3.0, 0.7)
	var top_c := Color(0.75, 0.3, 0.3) if look == 0 else (Color(0.3, 0.5, 0.7) if look == 1 else Color(0.45, 0.5, 0.3))
	var low_c := Color(0.6, 0.42, 0.25) if look == 0 else (Color(0.85, 0.75, 0.5) if look == 1 else Color(0.34, 0.28, 0.22))
	var hair_c := Color(0.22, 0.12, 0.07) if look == 0 else (Color(0.82, 0.62, 0.25) if look == 1 else Color(0.25, 0.17, 0.1))
	var top := M.pbr("fabric", top_c, 3.0, 0.95)
	var low := M.pbr("fabric", low_c, 3.0, 0.95)
	var hair := M.pbr("fabric", hair_c, 3.0, 0.95)
	var girl := kind == "girl"
	var hip_y := 0.92
	# legs (girls: hidden under a skirt but still swing slightly)
	for sx in [-1.0, 1.0]:
		var hip := _joint(self, Vector3(sx * 0.11, hip_y, 0))
		_mesh(hip, _cap(0.07, 0.8), low if not girl else skin, Vector3(0, -0.4, 0))
		_mesh(hip, _sph(0.085), boots, Vector3(0, -0.84, -0.05), Vector3(1, 0.8, 1.5))
		legs.append(hip)
	# torso
	_mesh(self, _cap(0.17, 0.62), top, Vector3(0, 1.28, 0), Vector3(1.0, 1.0, 0.72))
	if girl:
		_mesh(self, _cone(0.17, 0.4, 0.62), low, Vector3(0, 0.78, 0))          # skirt
	else:
		_mesh(self, _cap(0.18, 0.3), low, Vector3(0, 0.98, 0), Vector3(1.0, 1.0, 0.75))
		_mesh(self, _cap(0.04, 0.9), dark, Vector3(0.12, 1.3, 0.1), Vector3(1, 1, 1)).rotation.z = 0.2   # strap
	# arms
	for sx in [-1.0, 1.0]:
		var sh := _joint(self, Vector3(sx * 0.23, 1.5, 0))
		_mesh(sh, _cap(0.055, 0.62), top, Vector3(0, -0.28, 0))
		_mesh(sh, _sph(0.06), skin, Vector3(0, -0.6, 0))
		arms.append(sh)
	# head
	var head := _joint(self, Vector3(0, 1.68, 0))
	_mesh(head, _sph(0.13), skin, Vector3(0, 0.04, 0), Vector3(0.95, 1.08, 1.0))
	_mesh(head, _sph(0.02), dark, Vector3(-0.045, 0.06, -0.12))
	_mesh(head, _sph(0.02), dark, Vector3(0.045, 0.06, -0.12))
	_mesh(head, _sph(0.14), hair, Vector3(0, 0.1, 0.03), Vector3(1.0, 0.8, 1.0))   # cap of hair
	if girl:
		_mesh(head, _cap(0.12, 0.5), hair, Vector3(0, -0.14, 0.1), Vector3(1.0, 1.0, 0.7))   # long hair down the back
		if look == 1:
			_mesh(head, _sph(0.05), M.pbr("fabric", Color(0.8, 0.2, 0.25), 3.0, 0.9), Vector3(0.12, 0.2, 0.04))   # hair bow
	else:
		_mesh(head, _sph(0.11), hair, Vector3(0, -0.07, -0.05), Vector3(1.0, 0.8, 0.9))        # beard
		_mesh(head, _cone(0.15, 0.2, 0.05), M.pbr("leather", Color(0.4, 0.28, 0.16), 3.0, 0.7), Vector3(0, 0.2, 0))   # hat brim
	# a little scale difference so they do not look like clones
	scale = Vector3.ONE * (0.96 if girl else 1.04)

func hit(dmg: float) -> void:
	if dead:
		return
	hp -= dmg
	_hurt = 0.5
	if hp <= 0.0:
		dead = true
		_down_t = 0.0

## mode: "idle" | "run" | "scared" | "work"
func animate(d: float, spd: float, mode: String) -> void:
	_t += d
	_hurt = maxf(0.0, _hurt - d)
	if dead:
		_down_t += d
		rotation.x = lerpf(rotation.x, -PI / 2.0, clampf(6.0 * d, 0.0, 1.0))
		return
	var sw := sin(_t * (6.0 + spd * 1.2)) * clampf(spd / 4.0, 0.0, 1.0) * 0.8
	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sw if i == 0 else -sw
	for i in arms.size():
		var a := arms[i] as Node3D
		match mode:
			"scared":
				a.rotation.x = -2.6 + sin(_t * 9.0 + float(i) * 2.0) * 0.25      # hands up, trembling
				a.rotation.z = (0.3 if i == 1 else -0.3)
			"work":
				a.rotation.x = -0.9 + sin(_t * 5.0 + float(i) * PI) * 0.7        # hammering / lifting
				a.rotation.z = 0.0
			_:
				a.rotation.x = -sw if i == 0 else sw
				a.rotation.z = 0.0
	rotation.z = sin(_t * 30.0) * 0.06 if _hurt > 0.0 else 0.0
