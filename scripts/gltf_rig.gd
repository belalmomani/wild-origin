extends RefCounted
## Original Unity wolf / bear models (exported to GLB with their skeletons, textures and animation clips).
## Controller: finds the imported AnimationPlayer and plays clips by short name ("cycle_walk", "idle_breathe", ...).
const SCENES := {
	"wolf": preload("res://assets/animals/wolf.glb"),
	"bear": preload("res://assets/animals/bear.glb"),
}
const BEAR_TEX := preload("res://assets/animals/bear_albedo_fix.png")
const KNOWN := ["cycle_walk", "cycle_run", "cycle_trot", "cycle_sneak", "death_neutral", "idle_breathe", "idle_specific_01"]
const LOOPING := ["cycle_walk", "cycle_run", "cycle_trot", "cycle_sneak", "idle_breathe", "idle_specific_01"]
var holder: Node3D
var ap: AnimationPlayer
var clips := {}          # short name -> real animation name
var current := ""

## Instantiates the model under `parent`. `scale_f` shrinks the (large) original; `tint` multiplies the albedo.
static func build(kind: String, parent: Node3D, scale_f: float, tint: Color = Color(1, 1, 1)):
	var r = load("res://scripts/gltf_rig.gd").new()
	var inst: Node = (SCENES[kind] as PackedScene).instantiate()
	var h := Node3D.new()
	h.rotation.y = PI                       # the glTF faces +Z, the game's animals face -Z
	h.scale = Vector3.ONE * scale_f
	parent.add_child(h)
	h.add_child(inst)
	r.holder = h
	r.ap = _find_player(inst)
	if r.ap != null:
		for n in r.ap.get_animation_list():
			var low := String(n).to_lower()
			var short := low.get_slice("@", 1) if low.contains("@") else low
			for kn in KNOWN:                   # the importer may have rewritten "@": match by suffix
				if low.ends_with(kn):
					short = kn
					break
			r.clips[short] = n
			var an: Animation = r.ap.get_animation(n)
			an.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(short) else Animation.LOOP_NONE
	if kind == "bear":                      # the original claws / mouth are bright pink: shown red on the raised paws
		_retex(inst, BEAR_TEX)
	if tint != Color(1, 1, 1):
		_tint(inst, tint)
	r.play("idle_breathe")
	return r

static func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_player(c)
		if f != null:
			return f
	return null

static func _retex(n: Node, tex: Texture2D) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D:
				var d := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				d.albedo_texture = tex
				mi.set_surface_override_material(i, d)
	for ch in n.get_children():
		_retex(ch, tex)

static func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D:
				var d := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				d.albedo_color = c
				mi.set_surface_override_material(i, d)
	for ch in n.get_children():
		_tint(ch, c)

func has_clip(short: String) -> bool:
	return clips.has(short)

func play(short: String, speed: float = 1.0) -> void:
	if ap == null or not clips.has(short):
		return
	if current == short:
		ap.speed_scale = speed
		return
	current = short
	ap.play(clips[short], 0.25)
	ap.speed_scale = speed
