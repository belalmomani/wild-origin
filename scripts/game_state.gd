extends Node
## Global state + local save/load (autoload "GameState").
const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"

var inv := {"wood": 0, "stone": 0, "seeds": 2, "apples": 0, "arrows": 15, "meat": 0, "hay": 0, "gseeds": 0, "milk": 0, "fish": 0, "pelt": 0}
var clock_hours := 8.0        # total game hours (time_of_day = clock_hours mod 24)
var crops: Array = []
var next_crop_id := 1
var day_seconds := 1440.0      # real seconds per game day (24 min); setting
const NIGHT_START := 21.0       # the day is long (05:00-21:00), the night short
const NIGHT_END := 5.0

func is_night() -> bool:
	return time_of_day < NIGHT_END or time_of_day >= NIGHT_START
var placed := {}      # slot id -> true
var removed := {}     # harvested world object id -> true
var player_pos := Vector3(0, 1, 11)
var time_of_day := 8.0
var hints_left := 3
var phase := 0
var xp := 0
var torch_owned := false
var drag_kind := ""            # animal currently being dragged to the barn ("" = none)
var equip := "none"           # what the hands hold: "none" | "axe" | "weapon"
var saved_unix := 0.0
var weapons: Array = ["slingshot"]
var weapon_idx := 0
var livestock: Array = []      # animals being carried to the farm: {kind, eta(unix)}
var animals := {"deer": 0, "ibex": 0, "elk": 0, "chicken": 0}   # arrived at the farm
var barn_unlocked := false     # first live animal caught -> barn quest opens
var barn_built := false
var builds_done := 0           # finished builds since this save was first seen (each = +1% difficulty)
var diff_base := -1            # builds that were already finished when difficulty started; -1 = not set yet
var cost_acc := 0.0            # fractional piece cost carried over between pieces
var farm_built := false
var lives := 5                 # player lives: a predator attack costs one
var hunt_stage := 0            # capture stage (see HuntLogic.STAGES)
var stage_n := 0               # animals delivered in the current stage
var well := 0                  # 0 none, 1 dug (manual watering), 2 upgraded (waters by itself)
var bucket := 0                # water charges in the bucket
var pond := 0.0                # lake water level 0..1
var channel := false           # the wooden channel well -> lake is built
var harvests := 0              # crops harvested (rewards the well upgrade)
var story_stage := 0           # 0 nothing, 1 travellers hunted by wolves, 2 saved (cabin opens), 3 cabin finished
var story_alive := [true, true, true]
var story_clock := -1.0        # game hour when the last attempt failed (retry after two days)
var coat := false              # coat sewn from bear / wolf pelts: +2 lives
var sens_idx := 1              # camera sensitivity: 0 low, 1 normal, 2 high
var fire_fuel := 0.0           # game hours of fire left in the hearth
var hearth_init := false       # the first fire has been lit (gift of 8 hours)
var pen: Array = []             # animals housed at the barn (see barn_logic.gd)
var next_pen_id := 1
const TL := preload("res://scripts/tech_logic.gd")
var techs: Array = []           # unlocked tech ids
var volume_idx := 0            # 0 high, 1 medium, 2 low, 3 muted
var gentle := false             # softened hunting visuals
var quality := 1
var muted := false
var tutorial_done := false
var move := Vector2.ZERO
var cam_delta := Vector2.ZERO

func reset() -> void:
	inv = {"wood": 0, "stone": 0, "seeds": 2, "apples": 0, "arrows": 15, "meat": 0, "hay": 0, "gseeds": 0, "milk": 0, "fish": 0, "pelt": 0}
	barn_unlocked = false
	barn_built = false
	fire_fuel = 0.0
	hearth_init = false
	drag_kind = ""
	equip = "none"
	builds_done = 0
	diff_base = -1
	cost_acc = 0.0
	farm_built = false
	lives = 5
	hunt_stage = 0
	stage_n = 0
	well = 0
	bucket = 0
	harvests = 0
	coat = false
	story_stage = 0
	story_alive = [true, true, true]
	story_clock = -1.0
	pond = 0.0
	channel = false
	pen = []
	techs = []
	next_pen_id = 1
	weapons = ["slingshot"]
	weapon_idx = 0
	livestock = []
	animals = {"deer": 0, "ibex": 0, "elk": 0, "chicken": 0}
	crops = []
	next_crop_id = 1
	clock_hours = 8.0
	placed = {}
	removed = {}
	player_pos = Vector3(0, 1, 11)
	time_of_day = 8.0
	hints_left = 3
	phase = 0
	xp = 0
	torch_owned = false

func has_tech(id: String) -> bool:
	return techs.has(id)

func max_lives() -> int:
	return 5 + (2 if coat else 0)

func cap_of(k: String) -> int:
	match k:
		"wood", "stone":
			return 400 if has_tech("storage") else 150
		"apples", "meat", "hay", "milk", "fish", "pelt":
			return 100 if has_tech("storage") else 40
	return 99999

## Adds up to the carry capacity. Returns how many were actually added.
func add(k: String, n: int) -> int:
	var cur := int(inv.get(k, 0))
	var nv := mini(cap_of(k), cur + n)
	inv[k] = maxi(cur, nv)
	return int(inv[k]) - cur

## Spend resources and unlock a tech. Returns "" on success, otherwise the reason text.
func research(id: String) -> String:
	var t: Dictionary = TL.by_id(id)
	if t.is_empty():
		return "تقنية غير موجودة"
	var st: String = TL.status(t, techs, level(), inv)
	if st != "ready":
		return TL.reason_text(st, t)
	var cost: Dictionary = t["cost"]
	for k in cost:
		spend(k, int(cost[k]))
	techs.append(id)
	return ""

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
		"hints": hints_left, "phase": phase, "xp": xp, "torch": torch_owned,
		"clock": clock_hours, "weapons": weapons, "widx": weapon_idx, "livestock": livestock, "animals": animals, "pen": pen, "techs": techs, "npid": next_pen_id, "barn_u": barn_unlocked, "fuel": fire_fuel, "dbase": diff_base, "cacc": cost_acc, "hinit": hearth_init, "drag": drag_kind, "crops": crops, "ncid": next_crop_id, "lives": lives, "hstage": hunt_stage, "stn": stage_n, "well": well, "bucket": bucket, "harv": harvests, "pond": pond, "channel": channel, "coat": coat, "sst": story_stage, "salive": story_alive, "sclk": story_clock, "saved": Time.get_unix_time_from_system()}

func from_dict(d: Dictionary) -> void:
	reset()
	var i: Dictionary = d.get("inv", {})
	for k in i:
		inv[k] = int(i[k])
	crops = []
	for c in d.get("crops", []):
		if typeof(c) == TYPE_DICTIONARY:
			crops.append(c)
	weapons = []
	for w in d.get("weapons", ["slingshot"]):
		weapons.append(str(w))
	if weapons.is_empty():
		weapons = ["slingshot"]
	weapon_idx = clampi(int(d.get("widx", 0)), 0, weapons.size() - 1)
	livestock = []
	for e in d.get("livestock", []):
		if typeof(e) == TYPE_DICTIONARY:
			livestock.append(e)
	var an: Dictionary = d.get("animals", {})
	animals = {"deer": int(an.get("deer", 0)), "ibex": int(an.get("ibex", 0)), "elk": int(an.get("elk", 0)), "chicken": int(an.get("chicken", 0))}
	techs = []
	for tid in d.get("techs", []):
		techs.append(str(tid))
	pen = []
	for e in d.get("pen", []):
		if typeof(e) == TYPE_DICTIONARY:
			pen.append(e)
	next_pen_id = int(d.get("npid", 1))
	barn_unlocked = bool(d.get("barn_u", false))
	fire_fuel = float(d.get("fuel", 0.0))
	diff_base = int(d.get("dbase", -1))
	cost_acc = float(d.get("cacc", 0.0))
	hearth_init = bool(d.get("hinit", false))
	drag_kind = str(d.get("drag", ""))
	next_crop_id = int(d.get("ncid", 1))
	lives = clampi(int(d.get("lives", 5)), 1, 5)
	hunt_stage = int(d.get("hstage", 0))
	stage_n = int(d.get("stn", 0))
	well = int(d.get("well", 0))
	bucket = int(d.get("bucket", 0))
	harvests = int(d.get("harv", 0))
	coat = bool(d.get("coat", false))
	story_stage = int(d.get("sst", 0))
	if story_stage == 1:
		story_stage = 0                       # an interrupted rescue starts again
	var sa: Array = d.get("salive", [true, true, true])
	story_alive = [true, true, true]
	for si in mini(3, sa.size()):
		story_alive[si] = bool(sa[si])
	story_clock = float(d.get("sclk", -1.0))
	pond = clampf(float(d.get("pond", 0.0)), 0.0, 1.0)
	channel = bool(d.get("channel", false))
	clock_hours = float(d.get("clock", 8.0))
	time_of_day = fposmod(clock_hours, 24.0)
	saved_unix = float(d.get("saved", 0.0))
	for k in d.get("placed", []):
		placed[str(k)] = true
	for k in d.get("removed", []):
		removed[int(k)] = true
	var p: Array = d.get("pos", [0, 1, 6])
	player_pos = Vector3(float(p[0]), float(p[1]) + 0.5, float(p[2]))
	hints_left = int(d.get("hints", 3))
	phase = int(d.get("phase", 0))
	xp = int(d.get("xp", 0))
	torch_owned = bool(d.get("torch", false))

const SAVE_BAK := "user://save.bak"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_BAK)

func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).length() == text.length()

## Writes the main save and a backup copy (a failed/aborted write of one never loses the other).
func save_game() -> bool:
	var text := JSON.stringify(to_dict())
	var ok1 := _write(SAVE_PATH, text)
	var ok2 := _write(SAVE_BAK, text)
	if not (ok1 or ok2):
		push_error("save failed: " + str(FileAccess.get_open_error()))
	return ok1 or ok2

func _read_save(path: String):
	if not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else null

func load_game() -> bool:
	var data = _read_save(SAVE_PATH)
	if data == null:
		data = _read_save(SAVE_BAK)
	if data == null:
		return false
	from_dict(data)
	return true

## Every finished build makes the following ones 1% harder (compounding): piece price and snap tolerance.
func difficulty() -> float:
	return pow(1.01, float(builds_done))

func difficulty_pct() -> int:
	return int(round((difficulty() - 1.0) * 100.0))

func sens_mult() -> float:
	var m: Array = [0.6, 1.0, 1.5]
	return float(m[sens_idx])

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"q": quality, "mute": muted, "tut": tutorial_done, "day2": day_seconds, "gentle": gentle, "vol": volume_idx, "sens": sens_idx}))

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var data = JSON.parse_string(FileAccess.open(SETTINGS_PATH, FileAccess.READ).get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		quality = clampi(int(data.get("q", 1)), 0, 2)
		muted = bool(data.get("mute", false))
		tutorial_done = bool(data.get("tut", false))
		gentle = bool(data.get("gentle", false))
		volume_idx = clampi(int(data.get("vol", 0)), 0, 3)
		sens_idx = clampi(int(data.get("sens", 1)), 0, 2)
		day_seconds = clampf(float(data.get("day2", 1440.0)), 300.0, 5000.0)
