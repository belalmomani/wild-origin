extends Node3D
## Visual rain (particles that follow the player) and the smoothed "wetness" used to darken sky and fog.
## What the weather IS comes from weather_logic.gd (pure function of the game clock).
const WL := preload("res://scripts/weather_logic.gd")
var strength := 0.0           # smoothed rain intensity 0..1
var parts: CPUParticles3D
var target: Node3D
var _last_msg := -1

func _ready() -> void:
	parts = CPUParticles3D.new()
	parts.amount = 900
	parts.lifetime = 0.8
	parts.emitting = false
	parts.local_coords = false
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	parts.emission_box_extents = Vector3(16, 0.1, 16)
	parts.direction = Vector3(0.12, -1, 0.05)
	parts.spread = 3.0
	parts.initial_velocity_min = 20.0
	parts.initial_velocity_max = 24.0
	parts.gravity = Vector3.ZERO
	var m := BoxMesh.new()
	m.size = Vector3(0.012, 0.55, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.82, 0.95, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	parts.mesh = m
	parts.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	add_child(parts)

## Call every frame. Returns the new smoothed strength.
func update(d: float, hours: float) -> float:
	var want := WL.rain_at(hours)
	strength = move_toward(strength, want, d * 0.25)
	if parts != null:
		parts.emitting = strength > 0.05
		if target != null and is_instance_valid(target):
			parts.global_position = target.global_position + Vector3(0, 13.0, 0)
	return strength

## 0 = clear, 1 = full overcast darkness factor for light.
func dim() -> float:
	return clampf(strength, 0.0, 1.0)
