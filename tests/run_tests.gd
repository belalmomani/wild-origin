extends SceneTree
## Run: godot --headless --script tests/run_tests.gd   (exit code 1 on failure)
func _init() -> void:
	var fails := 0
	var D = load("res://scripts/building_data.gd")
	var boards: Array = D.make_boards()
	if boards.size() != 9:
		print("FAIL boards: ", boards.size()); fails += 1
	if boards[2].pieces.size() != 50:
		print("FAIL back facade should have 50 pieces: ", boards[2].pieces.size()); fails += 1
	var ids := {}
	for b in boards:
		for p in b.pieces:
			if ids.has(p.id):
				print("FAIL duplicate id ", p.id); fails += 1
			ids[p.id] = true
			if Geometry2D.triangulate_polygon(p.mesh_poly).size() < 3:
				print("FAIL cannot triangulate ", p.id); fails += 1
	print("pieces per board: ", boards.map(func(b): return b.pieces.size()))
	var gs = load("res://scripts/game_state.gd").new()
	gs.add("wood", 5)
	gs.placed["F0_1"] = true
	gs.removed[1003] = true
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.reset()
	gs.from_dict(d)
	if gs.count("wood") != 5 or not gs.placed.has("F0_1") or not gs.removed.has(1003):
		print("FAIL save round-trip"); fails += 1
	if gs.spend("stone", 1):
		print("FAIL spend with no stone"); fails += 1
	print("TESTS ", "FAILED" if fails > 0 else "PASSED")
	quit(1 if fails > 0 else 0)
