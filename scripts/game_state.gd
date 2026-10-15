extends Node
## Global state + local save/load (autoload "GameState").
const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"

var inv := {"wood": 0, "stone": 0}
var placed := {}      # slot id -> true
var removed := {}     # harvested world object id -> true
var player_pos := Vector3(0, 1, 6)
var time_of_day := 8.0
var hints_left := 3
var phase := 0
var xp := 0
var torch_owned := false
var quality := 1
var muted := false
var tutorial_done := false
var move := Vector2.ZERO
var cam_delta := Vector2.ZERO

func reset() -> void:
	inv = {"wood": 0, "stone": 0}
	placed = {}
	removed = {}
	player_pos = Vector3(0, 1, 6)
	time_of_day = 8.0
	hints_left = 3
	phase = 0
	xp = 0
	torch_owned = false

func add(k: String, n: int) -> void:
	inv[k] = int(inv.get(k, 0)) + n

func count(k: String) -> int:
	return int(inv.get(k, 0))

func spend(k: String, n: int) -> bool:
	if count(k) < n:
		return false
	inv[k] = count(k) - n
	return true

func level() -> int:
	return 1 + xp / 20

func to_dict() -> Dictionary:
	return {"v": 1, "inv": inv, "placed": placed.keys(), "removed": removed.keys(),
		"pos": [player_pos.x, player_pos.y, player_pos.z], "t": time_of_day,
		"hints": hints_left, "phase": phase, "xp": xp, "torch": torch_owned}

func from_dict(d: Dictionary) -> void:
	reset()
	var i: Dictionary = d.get("inv", {})
	inv = {"wood": int(i.get("wood", 0)), "stone": int(i.get("stone", 0))}
	for k in d.get("placed", []):
		placed[str(k)] = true
	for k in d.get("removed", []):
		removed[int(k)] = true
	var p: Array = d.get("pos", [0, 1, 6])
	player_pos = Vector3(float(p[0]), float(p[1]) + 0.5, float(p[2]))
	time_of_day = float(d.get("t", 8.0))
	hints_left = int(d.get("hints", 3))
	phase = int(d.get("phase", 0))
	xp = int(d.get("xp", 0))
	torch_owned = bool(d.get("torch", false))

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> bool:
	# write to a temp file first so a crash never corrupts the save
	var tmp := "user://save.tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	var dir := DirAccess.open("user://")
	if dir.file_exists("save.json"):
		dir.remove("save.json")
	return dir.rename("save.tmp", "save.json") == OK

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	from_dict(data)
	return true

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"q": quality, "mute": muted, "tut": tutorial_done}))

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var data = JSON.parse_string(FileAccess.open(SETTINGS_PATH, FileAccess.READ).get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		quality = clampi(int(data.get("q", 1)), 0, 2)
		muted = bool(data.get("mute", false))
		tutorial_done = bool(data.get("tut", false))
