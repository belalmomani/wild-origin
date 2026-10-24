extends "res://scripts/character.gd"
## Rigs the user's static, segmented assets/hero/hero.glb at runtime. The GLB has no skeleton/animations,
## so each named part is attached to a joint node (same joint names as character.gd) and animated with the
## SAME procedural poses (idle, walk, run, jump, crouch, chop, gather, carry, aim, build).
## Tool sockets: ToolSocket_R / ToolSocket_L (hands). equip() shows axe / pickaxe / hammer there.
const HERO_PATH := "res://assets/hero/hero.glb"
# joint -> [parent, pivot in the GLB's own coordinates (front = +Z)]
const SPEC := {
	"hips": ["", Vector3(0, 0.95, 0)], "spine": ["hips", Vector3(0, 0.98, 0)], "chest": ["spine", Vector3(0, 1.2, 0)],
	"head": ["chest", Vector3(0, 1.43, 0)],
	"shL": ["chest", Vector3(-0.225, 1.31, 0)], "elL": ["shL", Vector3(-0.34, 1.08, 0)], "handL": ["elL", Vector3(-0.40, 0.87, 0.03)],
	"shR": ["chest", Vector3(0.225, 1.31, 0)], "elR": ["shR", Vector3(0.34, 1.08, 0)], "handR": ["elR", Vector3(0.40, 0.87, 0.03)],
	"hipL": ["hips", Vector3(-0.106, 0.87, 0)], "knL": ["hipL", Vector3(-0.118, 0.49, 0)], "anL": ["knL", Vector3(-0.115, 0.15, 0)],
	"hipR": ["hips", Vector3(0.106, 0.87, 0)], "knR": ["hipR", Vector3(0.118, 0.49, 0)], "anR": ["knR", Vector3(0.115, 0.15, 0)],
}
const ORDER := ["hips", "spine", "chest", "head", "shL", "elL", "handL", "shR", "elR", "handR", "hipL", "knL", "anL", "hipR", "knR", "anR"]
const ASSIGN := {
	"hips": ["Pelvis", "Utility_Belt", "Belt_Buckle", "Hip_Pouch"],
	"spine": ["Torso_Shirt"],
	"chest": ["Jacket_Chest", "Jacket_Zipper", "Chest_Pocket_L", "Chest_Pocket_R", "Backpack_Main", "Backpack_Pocket", "Backpack_Strap_L", "Backpack_Strap_R"],
	"head": ["Neck", "Head", "Ear_L", "Ear_R", "Hair_Cap", "Hair_Front", "Eye_L", "Eye_R", "Brow_L", "Brow_R", "Nose", "Mouth"],
	"shL": ["Shoulder_L", "UpperArm_L"], "elL": ["Elbow_L", "Forearm_L"], "handL": ["Hand_L"],
	"shR": ["Shoulder_R", "UpperArm_R"], "elR": ["Elbow_R", "Forearm_R"], "handR": ["Hand_R"],
	"hipL": ["HipJoint_L", "Thigh_L"], "knL": ["Knee_L", "LowerLeg_L"], "anL": ["Boot_L"],
	"hipR": ["HipJoint_R", "Thigh_R"], "knR": ["Knee_R", "LowerLeg_R"], "anR": ["Boot_R"],
}
var socket_r: Node3D
var socket_l: Node3D
var tool_axe: Node3D
var tool_pick: Node3D
var tool_hammer: Node3D
var mats := {}

func _mat(kind: String) -> Material:
	if mats.has(kind):
		return mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	if kind == "cloth" or kind == "gear":
		var tn := "fabric" if kind == "cloth" else "leather"
		m.albedo_texture = M.tex(tn + "_a")
		m.normal_enabled = true
		m.normal_texture = M.tex(tn + "_n")
		m.normal_scale = 0.7
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(3, 3, 3)
		m.albedo_color = Color(1.25, 1.25, 1.25)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	elif kind == "skin":
		m.roughness = 0.6
	mats[kind] = m
	return m

func _kind(p: String) -> String:
	for k in ["Torso_Shirt", "Jacket_Chest", "Shoulder", "UpperArm", "Forearm", "Elbow", "Thigh", "Knee", "LowerLeg", "HipJoint", "Pelvis", "Chest_Pocket"]:
		if p.begins_with(k):
			return "cloth"
	for k in ["Boot", "Utility_Belt", "Backpack", "Hip_Pouch"]:
		if p.begins_with(k):
			return "gear"
	return "skin"

func _ready() -> void:
	var scn = load(HERO_PATH)
	if not (scn is PackedScene):
		push_error("hero.glb missing or not importable")
		return
	var model: Node = scn.instantiate()
	var parts := {}
	for c in model.find_children("*", "MeshInstance3D", true, false):
		parts[String(c.name)] = c
	var flip := Basis(Vector3.UP, PI)   # GLB front is +Z; the game's forward is -Z
	var gpos := {}
	for jn in ORDER:
		var spec: Array = SPEC[jn]
		var p: Vector3 = spec[1]
		var g := Vector3(-p.x, p.y, -p.z)
		gpos[jn] = g
		var par: Node3D = self
		var pg := Vector3.ZERO
		if spec[0] != "":
			par = J[spec[0]]
			pg = gpos[spec[0]]
		_joint(par, jn, g - pg)
	var missing: Array = []
	for jn in ASSIGN:
		for pn in ASSIGN[jn]:
			var mi: MeshInstance3D = parts.get(pn)
			if mi == null:
				missing.append(pn)
				continue
			mi.get_parent().remove_child(mi)
			(J[jn] as Node3D).add_child(mi)
			mi.transform = Transform3D(flip, -(gpos[jn] as Vector3))
			mi.material_override = _mat(_kind(pn))
	if not missing.is_empty():
		push_warning("hero.glb parts not found: %s" % str(missing))
	model.free()
	# tool sockets in the hands
	socket_r = Node3D.new()
	socket_r.name = "ToolSocket_R"
	socket_r.position = Vector3(0, -0.03, 0)
	(J["handR"] as Node3D).add_child(socket_r)
	socket_l = Node3D.new()
	socket_l.name = "ToolSocket_L"
	socket_l.position = Vector3(0, -0.03, 0)
	(J["handL"] as Node3D).add_child(socket_l)
	var wood := M.pbr("bark", Color(0.9, 0.8, 0.65), 1.5, 0.9)
	var metal := M.flat(Color(0.62, 0.64, 0.68), 0.35)
	tool_axe = Node3D.new()
	socket_r.add_child(tool_axe)
	_cyl(tool_axe, 0.016, 0.72, wood, Vector3(0, -0.18, 0))
	_box(tool_axe, Vector3(0.03, 0.11, 0.17), metal, Vector3(0, -0.5, -0.07))
	tool_pick = Node3D.new()
	socket_r.add_child(tool_pick)
	_cyl(tool_pick, 0.017, 0.8, wood, Vector3(0, -0.2, 0))
	_box(tool_pick, Vector3(0.03, 0.04, 0.42), metal, Vector3(0, -0.58, 0))
	_box(tool_pick, Vector3(0.03, 0.06, 0.06), metal, Vector3(0, -0.58, -0.22), Vector3(0.5, 0, 0))
	_box(tool_pick, Vector3(0.03, 0.06, 0.06), metal, Vector3(0, -0.58, 0.22), Vector3(-0.5, 0, 0))
	tool_hammer = Node3D.new()
	socket_r.add_child(tool_hammer)
	_cyl(tool_hammer, 0.018, 0.5, wood, Vector3(0, -0.12, 0))
	_box(tool_hammer, Vector3(0.07, 0.07, 0.15), metal, Vector3(0, -0.4, 0))
	axe = tool_axe
	tool_pick.visible = false
	tool_hammer.visible = false
	# carried stone (hidden unless carrying)
	stone = Node3D.new()
	stone.position = Vector3(0, -0.1, -0.3)
	stone.visible = false
	(J["chest"] as Node3D).add_child(stone)
	_mi(stone, G.rock(77, 1), M.pbr("rock", Color.WHITE, 0.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.2)

func animate(d: float, spd: float, on_floor: bool, vy: float, crouch: bool, action: String, carrying: bool, turn: float = 0.0) -> void:
	super.animate(d, spd, on_floor, vy, crouch, action, carrying, turn)
	# this model's legs are shorter than the procedural body's: exaggerate hip drop so feet stay on the ground
	var hp: Node3D = J["hips"]
	hp.position.y = maxf(0.45, 0.95 + (hp.position.y - 0.95) * 1.3)
	var show_pick := action == "gather"
	var show_hammer := action == "build"
	var show_axe := not carrying and not show_pick and not show_hammer
	tool_axe.visible = show_axe or action == "chop"
	tool_pick.visible = show_pick
	tool_hammer.visible = show_hammer
