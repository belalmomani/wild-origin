extends Node3D
## Wild seed grass scattered through the forest. «تفاعل» next to a plant gathers grass seeds (for the fodder farm).
## Collected plants are remembered in GameState.removed (ids 5000+) so they do not come back after loading.
const G := preload("res://scripts/mesh_gen.gd")
const COUNT := 70
var world

func _ready() -> void:
	var mesh := G.tuft()
	var seed_mat := StandardMaterial3D.new()
	seed_mat.albedo_color = Color(0.9, 0.78, 0.3)
	seed_mat.roughness = 0.8
	var head := CapsuleMesh.new()
	head.radius = 0.03
	head.height = 0.18
	head.radial_segments = 6
	head.rings = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var made := 0
	var guard := 0
	while made < COUNT and guard < 2000:
		guard += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(24.0, 62.0)
		var p := Vector2(cos(a), sin(a)) * r
		var id := 5000 + made
		made += 1
		if GameState.removed.has(id):
			continue
		var n := Node3D.new()
		n.position = Vector3(p.x, world.height_at(p.x, p.y) if world != null else 0.0, p.y)
		n.add_to_group("forage")
		n.set_meta("id", id)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = Vector3.ONE * 1.5
		n.add_child(mi)
		for i in 5:                                           # golden seed heads show it can be gathered
			var h := MeshInstance3D.new()
			h.mesh = head
			h.material_override = seed_mat
			var b := rng.randf() * TAU
			h.position = Vector3(cos(b) * 0.18, 0.75 + rng.randf() * 0.25, sin(b) * 0.18)
			n.add_child(h)
		add_child(n)
