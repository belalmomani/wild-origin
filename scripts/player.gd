extends CharacterBody3D
## Third-person player with cinematic over-the-shoulder camera. Uses character.gd (procedural survivor),
## or a user-supplied rigged model at assets/hero/hero.glb if present.
const SPEED := 6.0          # full-stick run speed; walking = partial stick
const CROUCH_SPEED := 2.0
const JUMP := 6.0
const CharacterS := preload("res://scripts/character.gd")
const HeroRigS := preload("res://scripts/hero_rig.gd")
const HeroSkinnedS := preload("res://scripts/hero_skinned.gd")
const HERO_PATH := "res://assets/hero/hero.glb"
var cam_yaw := 0.0
var cam_pitch := -0.3
var jump_req := false
var crouch := false
var action := ""
var action_left := 0.0
var carry_t := 0.0
var intro_lock := false
signal footstep
var aiming := false
var scoped := false
var scope_fov := 20.0
var sway_t := 0.0
var body: Node3D
var arm: SpringArm3D
var cam: Camera3D
var torch: OmniLight3D
var char_node   # character.gd instance (untyped: custom methods)
var hero: Node3D
var hero_anim: AnimationPlayer
var a_idle := ""
var a_walk := ""
var a_run := ""

func _try_hero() -> bool:
	if not ResourceLoader.exists(HERO_PATH):
		return false
	var scn = load(HERO_PATH)
	if not (scn is PackedScene):
		return false
	var inst: Node3D = scn.instantiate()
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty() and (sks[0] as Skeleton3D).find_bone("chest") >= 0 and (sks[0] as Skeleton3D).find_bone("shL") >= 0:
		# our skinned explorer: bones named like character.gd joints -> procedural pose driver
		inst.free()
		char_node = HeroSkinnedS.new()
		body.add_child(char_node)
		return true
	if inst.find_child("Pelvis", true, false) != null and inst.find_children("*", "Skeleton3D", true, false).is_empty():
		# segmented, un-skinned model (no skeleton/animations): rig it at runtime
		inst.free()
		char_node = HeroRigS.new()
		body.add_child(char_node)
		return true
	hero = inst
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
	if moving and spd > SPEED * 0.7 and a_run != "":
		want = a_run
	elif not moving and a_idle != "":
		want = a_idle
	if want == "":
		return
	if hero_anim.current_animation != want:
		hero_anim.get_animation(want).loop_mode = Animation.LOOP_LINEAR
		hero_anim.play(want, 0.2)
	hero_anim.speed_scale = 1.0 if (moving or want == a_idle) else 0.0

func set_aim(on: bool) -> void:
	aiming = on

## Scope view: strong zoom from the head, character hidden, slower look sensitivity, slight breathing sway.
func set_scope(on: bool, fov: float) -> void:
	scoped = on
	scope_fov = fov
	body.visible = not on
	if char_node != null and char_node.has_method("set_scoped"):
		char_node.set_scoped(on)

func play_action(a: String, secs: float) -> void:
	action = a
	action_left = secs

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
		char_node = CharacterS.new()
		body.add_child(char_node)
	if char_node != null:
		char_node.footstep.connect(func(): footstep.emit())
	arm = SpringArm3D.new()
	arm.position.y = 1.55
	arm.spring_length = 4.2
	var ss := SphereShape3D.new()
	ss.radius = 0.25
	arm.shape = ss
	arm.margin = 0.1
	add_child(arm)
	arm.add_excluded_object(get_rid())
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
		var sens := 0.3 if scoped else 1.0
		cam_yaw -= cd.x * 0.006 * sens
		cam_pitch = clampf(cam_pitch - cd.y * 0.006 * sens, -1.2, 0.3)
	arm.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	if scoped:
		sway_t += d
		arm.rotation += Vector3(sin(sway_t * 1.7) * 0.0012, sin(sway_t * 1.1) * 0.001, 0.0)
	if action_left > 0.0:
		action_left -= d
		if action_left <= 0.0:
			action = ""
	if carry_t > 0.0:
		carry_t -= d
	var locked := intro_lock or action != ""
	var m := GameState.move if not locked else Vector2.ZERO
	var top := (CROUCH_SPEED if crouch else SPEED) * (0.5 if aiming else 1.0)
	if not intro_lock:
		var k := clampf(8.0 * d, 0.0, 1.0)
		arm.spring_length = lerpf(arm.spring_length, 0.25 if scoped else (2.3 if aiming else 4.2), k)
		cam.fov = lerpf(cam.fov, scope_fov if scoped else (46.0 if aiming else 62.0), k)
		cam.h_offset = lerpf(cam.h_offset, 0.0 if scoped else (0.65 if aiming else 0.45), k)
		cam.v_offset = lerpf(cam.v_offset, 0.0 if scoped else 0.1, k)
	var dir := Vector3(m.x, 0, m.y).rotated(Vector3.UP, cam_yaw)
	var speed := m.length() * top
	if m.length() > 0.01:
		dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * d
	elif jump_req and not crouch and not locked:
		velocity.y = JUMP
	else:
		velocity.y = -1.0
	jump_req = false
	if aiming:
		body.rotation.y = lerp_angle(body.rotation.y, cam_yaw, 10.0 * d)
	elif speed > 0.2:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 10.0 * d)
	move_and_slide()
	var spd := Vector2(velocity.x, velocity.z).length()
	if hero:
		_hero_anim(spd)
	elif char_node:
		char_node.set_weapon(GameState.weapons[GameState.weapon_idx])
		char_node.animate(d, spd, is_on_floor(), velocity.y, crouch, action if action != "" else ("aim" if aiming else ""), carry_t > 0.0)
		char_node.set_carrying(carry_t > 0.0)
	position.x = clampf(position.x, -96.0, 96.0)
	position.z = clampf(position.z, -96.0, 96.0)
	if position.y < -30.0:
		position = Vector3(0, 2, 11)
