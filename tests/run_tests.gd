extends SceneTree
## Run: godot --headless --script tests/run_tests.gd   (exit code 1 on failure)
func _init() -> void:
	var fails := 0
	var D = load("res://scripts/building_data.gd")
	var s: Array = D.make_slots(Vector3.ZERO)
	var h := s.filter(func(x): return x.id.begins_with("h")).size()
	var f := s.filter(func(x): return x.id.begins_with("f")).size()
	if h != 20:
		print("FAIL house slots: ", h); fails += 1
	if f != 19:
		print("FAIL fence slots: ", f); fails += 1
	var gs = load("res://scripts/game_state.gd").new()
	gs.add("wood", 5)
	gs.placed["h1"] = true
	gs.removed[1003] = true
	gs.phase = 2
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.reset()
	gs.from_dict(d)
	if gs.count("wood") != 5 or not gs.placed.has("h1") or not gs.removed.has(1003) or gs.phase != 2:
		print("FAIL save round-trip"); fails += 1
	if gs.spend("stone", 1):
		print("FAIL spend with no stone"); fails += 1
	print("TESTS ", "FAILED" if fails > 0 else "PASSED")
	quit(1 if fails > 0 else 0)
