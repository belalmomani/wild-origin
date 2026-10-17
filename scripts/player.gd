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
var arm: SpringArm3D
var intro_lock := false
const HERO_PATH := "res://assets/hero/hero.glb"
var hero: Node3D
var hero_anim: AnimationPlayer
var a_idle := ""
var a_walk := ""
var a_run := ""
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

func _try_hero() -> bool:
	# Optional realistic character: put a rigged .glb at assets/hero/hero.glb (see assets/hero/README.md)
	if not ResourceLoader.exists(HERO_PATH):
		return false
	var scn = load(HERO_PATH)
	if not (scn is PackedScene):
		return false
	hero = scn.instantiate()
	hero.rotation.y = PI   # most models face +Z, the game moves toward -Z
	body.add_child(hero)
	var aps := hero.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		hero_anim = aps[0]
		var names := hero_anim.get_animation_list()
		for n in names:
			var l := String(n).to_lower()
			if a_idle == "" and "idle" in l:
				a_idle = n
			elif a_walk == "" and "walk" in l:
				a_walk = n
			elif a_run == "" and "run" in l:
				a_run = n
		if a_walk == "" and names.size() > 0:
			a_walk = names[0]
	return true

func _hero_anim(spd: float) -> void:
	if hero_anim == null:
		return
	var moving := spd > 0.4
	var want := a_walk
	if moving and spd > SPEED * 0.85 and a_run != "":
		want = a_run
	elif not moving and a_idle != "":
		want = a_idle
	if want == "":
		return
	if hero_anim.current_animation != want:
		hero_anim.get_animation(want).loop_mode = Animation.LOOP_LINEAR
		hero_anim.play(want, 0.2)
	hero_anim.speed_scale = 1.0 if (moving or want == a_idle) else 0.0

func play_intro() -> void:
	# cinematic fly-in: wide high shot swinging to the over-the-shoulder view
	intro_lock = true
	cam_yaw = 1.4
	cam_pitch = -0.12
	arm.spring_length = 11.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "cam_yaw", 0.0, 3.5)
	t.tween_property(self, "cam_pitch", -0.3, 3.5)
	t.tween_property(arm, "spring_length", 4.2, 3.5)
	t.finished.connect(func(): intro_lock = false)

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
	if not _try_hero():
		_build_body()
	arm = SpringArm3D.new()
	arm.position.y = 1.55
	arm.spring_length = 4.2
	var ss := SphereShape3D.new()
	ss.radius = 0.25
	arm.shape = ss
	arm.margin = 0.1
	add_child(arm)
	arm.add_excluded_object(get_rid())
	pivot = arm
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 300.0
	cam.h_offset = 0.45   # over-the-shoulder framing
	cam.v_offset = 0.1
	arm.add_child(cam)
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
	if not intro_lock:
		cam_yaw -= cd.x * 0.006
		cam_pitch = clampf(cam_pitch - cd.y * 0.006, -1.2, 0.3)
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	var m := GameState.move if not intro_lock else Vector2.ZERO
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
	if hero:
		_hero_anim(spd)
	else:
		var sw := sin(anim_t) * 0.75 * amp
		legL.rotation.x = sw
		legR.rotation.x = -sw
		armL.rotation.x = -sw
		armR.rotation.x = sw * 0.6 - 0.25
	position.x = clampf(position.x, -96.0, 96.0)
	position.z = clampf(position.z, -96.0, 96.0)
	if position.y < -30.0:
		position = Vector3(0, 2, 6)
