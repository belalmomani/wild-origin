extends RefCounted
## Builds a rigid bone-hierarchy model (Node3D per bone, one merged vertex-coloured mesh per bone) from the generated
## assets/animals/<name>_data.gd files (made by tools/build_animals.py from the supplied deer / ibex models).
const DATA := {
	"deer": preload("res://assets/animals/deer_data.gd"),
	"ibex": preload("res://assets/animals/ibex_data.gd"),
}
static var _cache := {}
static var _mat: StandardMaterial3D

static func has_model(kind: String) -> bool:
	return DATA.has(kind)

static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.88
		_mat.rim_enabled = true            # soft fur-like edge light: reads as a volume, not a flat colour
		_mat.rim = 0.35
		_mat.rim_tint = 0.6
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat

static func _mesh(m: Dictionary) -> ArrayMesh:
	var v: PackedFloat32Array = m["v"]
	var n: PackedFloat32Array = m["n"]
	var c: PackedFloat32Array = m["c"]
	var cnt := v.size() / 3
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pc := PackedColorArray()
	pv.resize(cnt)
	pn.resize(cnt)
	pc.resize(cnt)
	for i in cnt:
		pv[i] = Vector3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2])
		pn[i] = Vector3(n[i * 3], n[i * 3 + 1], n[i * 3 + 2])
		pc[i] = Color(c[i * 3], c[i * 3 + 1], c[i * 3 + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pv
	arr[Mesh.ARRAY_NORMAL] = pn
	arr[Mesh.ARRAY_COLOR] = pc
	arr[Mesh.ARRAY_INDEX] = m["i"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

static func _data(kind: String) -> Dictionary:
	if not _cache.has(kind):
		var d: Dictionary = DATA[kind].data()
		var meshes := {}
		for k in d["meshes"]:
			meshes[k] = _mesh(d["meshes"][k])
		_cache[kind] = {"bones": d["bones"], "meshes": meshes, "zones": d["zones"]}
	return _cache[kind]

## Adds the model under `parent`. Returns {"bones": {name: Node3D}, "zones": {head/body/legs: {pos,size}}}.
static func build(kind: String, parent: Node3D) -> Dictionary:
	var d := _data(kind)
	var bones := {}
	for b in d["bones"]:
		var n := Node3D.new()
		n.name = str(b["name"])
		n.position = b["pos"]
		var par := str(b["parent"])
		(bones[par] if par != "" else parent).add_child(n)
		bones[str(b["name"])] = n
		if d["meshes"].has(b["name"]):
			var mi := MeshInstance3D.new()
			mi.mesh = d["meshes"][b["name"]]
			mi.material_override = _material()
			n.add_child(mi)
	return {"bones": bones, "zones": d["zones"]}
