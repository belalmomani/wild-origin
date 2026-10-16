extends CharacterBody3D
## Third-person hero with a procedural body: arms and legs swing while walking.
const SPEED := 5.5
const JUMP := 6.0
var cam_yaw := 0.0
var cam_pitch := -0.35
var jump_req := false
var pivot: Node3D
var body: Node3D
var cam: Camera3D
var torch: OmniLight3D
var legL: Node3D
var legR: Node3D
var armL: Node3D
var armR: Node3D
var anim_t := 0.0

func _box(parent: Node3D, sz: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	mi.material_override = m
	parent.add_child(mi)
	return mi

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _build_body() -> void:
	var shirt := Color(0.33, 0.38, 0.27)
	var pants := Color(0.25, 0.2, 0.15)
	var skin := Color(0.85, 0.65, 0.5)
	var leather := Color(0.4, 0.27, 0.16)
	_box(body, Vector3(0.5, 0.62, 0.28), Vector3(0, 1.15, 0), shirt)
	_box(body, Vector3(0.52, 0.1, 0.3), Vector3(0, 0.88, 0), leather)   # belt
	_box(body, Vector3(0.42, 0.5, 0.16), Vector3(0, 1.2, 0.22), leather)  # backpack
	_box(body, Vector3(0.3, 0.12, 0.3), Vector3(0, 1.5, 0), Color(0.45, 0.33, 0.2))  # scarf
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.34
	head.mesh = sm
	head.position = Vector3(0, 1.68, 0)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = skin
	head.material_override = hm
	body.add_child(head)
	_box(body, Vector3(0.3, 0.1, 0.3), Vector3(0, 1.82, 0.02), Color(0.2, 0.13, 0.08))  # hair
	legL = _pivot(body, Vector3(-0.13, 0.85, 0))
	legR = _pivot(body, Vector3(0.13, 0.85, 0))
	for l in [legL, legR]:
		_box(l, Vector3(0.2, 0.8, 0.22), Vector3(0, -0.4, 0), pants)
		_box(l, Vector3(0.22, 0.12, 0.32), Vector3(0, -0.82, -0.05), leather)
	armL = _pivot(body, Vector3(-0.34, 1.42, 0))
	armR = _pivot(body, Vector3(0.34, 1.42, 0))
	for a in [armL, armR]:
		_box(a, Vector3(0.14, 0.6, 0.15), Vector3(0, -0.3, 0), shirt)
		_box(a, Vector3(0.15, 0.12, 0.16), Vector3(0, -0.64, 0), skin)
	_box(armR, Vector3(0.05, 0.7, 0.05), Vector3(0, -0.7, -0.08), Color(0.5, 0.33, 0.18))  # axe handle
	_box(armR, Vector3(0.05, 0.16, 0.28), Vector3(0, -1.0, -0.2), Color(0.6, 0.6, 0.65))   # axe head

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	body = Node3D.new()
	add_child(body)
	_build_body()
	pivot = Node3D.new()
	pivot.position.y = 1.5
	add_child(pivot)
	cam = Camera3D.new()
	cam.position.z = 5.0
	cam.far = 300.0
	pivot.add_child(cam)
	cam.make_current()
	torch = OmniLight3D.new()
	torch.omni_range = 12.0
	torch.light_energy = 2.5
	torch.position.y = 1.8
	torch.visible = false
	add_child(torch)

func _physics_process(d: float) -> void:
	var cd := GameState.cam_delta
	GameState.cam_delta = Vector2.ZERO
	cam_yaw -= cd.x * 0.006
	cam_pitch = clampf(cam_pitch - cd.y * 0.006, -1.2, 0.3)
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	var m := GameState.move
	var dir := Vector3(m.x, 0, m.y).rotated(Vector3.UP, cam_yaw)
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if not is_on_floor():
		velocity.y -= 18.0 * d
	elif jump_req:
		velocity.y = JUMP
	else:
		velocity.y = -1.0
	jump_req = false
	if dir.length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 10.0 * d)
	move_and_slide()
	var spd := Vector2(velocity.x, velocity.z).length()
	var amp := clampf(spd / SPEED, 0.0, 1.0)
	anim_t += d * (4.0 + spd * 1.3)
	var sw := sin(anim_t) * 0.75 * amp
	legL.rotation.x = sw
	legR.rotation.x = -sw
	armL.rotation.x = -sw
	armR.rotation.x = sw * 0.6 - 0.25
	position.x = clampf(position.x, -96.0, 96.0)
	position.z = clampf(position.z, -96.0, 96.0)
	if position.y < -30.0:
		position = Vector3(0, 2, 6)
