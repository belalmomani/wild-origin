extends CharacterBody3D
## Third-person player. Input comes from GameState.move / cam_delta (set by ui.gd).
const SPEED := 5.5
const JUMP := 6.0
var cam_yaw := 0.0
var cam_pitch := -0.35
var jump_req := false
var pivot: Node3D
var body: Node3D
var cam: Camera3D
var torch: OmniLight3D

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	body = Node3D.new()
	add_child(body)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.7
	mi.mesh = cm
	mi.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.5, 0.2)
	mi.material_override = mat
	body.add_child(mi)
	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.3)
	nose.mesh = bm
	nose.position = Vector3(0, 1.4, -0.35)
	body.add_child(nose)
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
	position.x = clampf(position.x, -96.0, 96.0)
	position.z = clampf(position.z, -96.0, 96.0)
	if position.y < -30.0:
		position = Vector3(0, 2, 6)
