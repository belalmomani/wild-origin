extends RefCounted
## Skinned wapiti (elk) model: Skeleton3D + one textured mesh with per-vertex bone weights (GPU skinning).
## Data comes from assets/animals/elk_data.gd (converted from the supplied Unity prefab, see tools/unity/elk_export.py).
## Bones are posed procedurally: every bone gets a rotation expressed about the WORLD axes (x = swing forward/back,
## y = turn, z = sideways), converted here to the bone's own local frame because the imported bones have arbitrary axes.
const Data := preload("res://assets/animals/elk_data.gd")
const ALBEDO := preload("res://assets/animals/elk_albedo.jpg")

static var _mesh: ArrayMesh
static var _skin: Skin
static var _mat: StandardMaterial3D
static var _names: Array = []
static var _parent := PackedInt32Array()
static var _rest_g: Array = []     # rest GLOBAL transforms (Transform3D)
static var _rest_l: Array = []     # rest LOCAL bases (Basis)
static var _rest_lp: Array = []    # rest LOCAL positions (Vector3)

var skel: Skeleton3D
var index := {}                    # bone name -> index
var rot: Array = []                # wanted world-axis rotation per bone (Vector3, radians)
var _set: Array = []               # bones that were rotated last frame (must be reset when they return to 0)
var _cur: Array = []               # current global Basis per bone (scratch)

static func _prepare() -> void:
	if _mesh != null:
		return
	var d: Dictionary = Data.data()
	_names = d["names"]
	_parent = d["parent"]
	var rest: PackedFloat32Array = d["rest"]
	_rest_g = []
	for i in _names.size():
		var o := i * 12
		var b := Basis(Vector3(rest[o], rest[o + 1], rest[o + 2]), Vector3(rest[o + 3], rest[o + 4], rest[o + 5]), Vector3(rest[o + 6], rest[o + 7], rest[o + 8]))
		_rest_g.append(Transform3D(b.orthonormalized(), Vector3(rest[o + 9], rest[o + 10], rest[o + 11])))
	_rest_l = []
	_rest_lp = []
	for i in _names.size():
		var t: Transform3D = _rest_g[i]
		if _parent[i] >= 0:
			t = (_rest_g[_parent[i]] as Transform3D).affine_inverse() * t
		_rest_l.append(t.basis)
		_rest_lp.append(t.origin)
	var v: PackedFloat32Array = d["v"]
	var n: PackedFloat32Array = d["n"]
	var uv: PackedFloat32Array = d["uv"]
	var cnt := v.size() / 3
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pu := PackedVector2Array()
	pv.resize(cnt)
	pn.resize(cnt)
	pu.resize(cnt)
	for i in cnt:
		pv[i] = Vector3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2])
		pn[i] = Vector3(n[i * 3], n[i * 3 + 1], n[i * 3 + 2])
		pu[i] = Vector2(uv[i * 2], uv[i * 2 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pv
	arr[Mesh.ARRAY_NORMAL] = pn
	arr[Mesh.ARRAY_TEX_UV] = pu
	arr[Mesh.ARRAY_BONES] = d["bi"]
	arr[Mesh.ARRAY_WEIGHTS] = d["bw"]
	arr[Mesh.ARRAY_INDEX] = d["idx"]
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_skin = Skin.new()
	for i in _names.size():
		_skin.add_bind(i, (_rest_g[i] as Transform3D).affine_inverse())
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = ALBEDO
	_mat.roughness = 0.92
	_mat.rim_enabled = true
	_mat.rim = 0.25
	_mat.rim_tint = 0.5
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

static func vertex_count() -> int:
	_prepare()
	return _mesh.surface_get_array_len(0)

static func bone_count() -> int:
	_prepare()
	return _names.size()

## Adds the model under `parent` and returns the rig controller.
static func build(parent: Node3D):
	_prepare()
	var r = load("res://scripts/elk_rig.gd").new()
	var sk := Skeleton3D.new()
	sk.name = "ElkSkeleton"
	parent.add_child(sk)
	for i in _names.size():
		sk.add_bone(str(_names[i]))
		r.index[str(_names[i])] = i
	for i in _names.size():
		sk.set_bone_parent(i, _parent[i])
		var t := Transform3D(_rest_l[i], _rest_lp[i])
		sk.set_bone_rest(i, t)
		sk.set_bone_pose_position(i, t.origin)
		sk.set_bone_pose_rotation(i, (_rest_l[i] as Basis).get_rotation_quaternion())
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.skin = _skin
	mi.material_override = _mat
	mi.extra_cull_margin = 1.5
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	r.skel = sk
	r.rot.resize(_names.size())
	r._set.resize(_names.size())
	r._cur.resize(_names.size())
	for i in _names.size():
		r.rot[i] = Vector3.ZERO
		r._set[i] = false
		r._cur[i] = Basis.IDENTITY
	return r

func clear() -> void:
	for i in rot.size():
		rot[i] = Vector3.ZERO

func add(bone: String, v: Vector3) -> void:
	var i: int = index.get(bone, -1)
	if i >= 0:
		rot[i] += v

## Applies the wanted rotations to the skeleton (parents first, as the bones are stored).
func apply() -> void:
	for i in rot.size():
		var p: int = _parent[i]
		var pb: Basis = Basis.IDENTITY if p < 0 else (_cur[p] as Basis)
		var base: Basis = pb * (_rest_l[i] as Basis)
		var r: Vector3 = rot[i]
		if r == Vector3.ZERO:
			_cur[i] = base
			if _set[i]:
				skel.set_bone_pose_rotation(i, (_rest_l[i] as Basis).get_rotation_quaternion())
				_set[i] = false
			continue
		var w := Basis.from_euler(Vector3(r.x, r.y, r.z), EULER_ORDER_YXZ)
		_cur[i] = w * base
		var local: Basis = (_rest_l[i] as Basis) * (base.inverse() * w * base)
		skel.set_bone_pose_rotation(i, local.orthonormalized().get_rotation_quaternion())
		_set[i] = true

## Hit zones (local to the animal) matching the scaled model.
static func zones() -> Dictionary:
	return {
		"head": {"pos": Vector3(0, 1.25, -1.0), "size": Vector3(0.45, 0.55, 0.8)},
		"body": {"pos": Vector3(0, 1.0, 0.25), "size": Vector3(0.7, 0.65, 1.5)},
		"legs": {"pos": Vector3(0, 0.38, 0.25), "size": Vector3(0.7, 0.75, 1.4)},
	}
