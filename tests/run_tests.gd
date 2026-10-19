extends SceneTree
## Run: godot --headless --script tests/run_tests.gd   (exit code 1 on failure)
func _init() -> void:
	var fails := 0
	var D = load("res://scripts/building_data.gd")
	var boards: Array = D.make_boards()
	if boards.size() != 14:
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
	var G = load("res://scripts/mesh_gen.gd")
	for sp in 5:
		var tm: ArrayMesh = G.tree(sp, 1)
		if tm.get_surface_count() != 2:
			print("FAIL tree species ", sp, " surfaces ", tm.get_surface_count()); fails += 1
	var rm: ArrayMesh = G.rock(500, 2)
	if rm.get_surface_count() != 1 or rm.get_faces().size() < 300:
		print("FAIL rock mesh"); fails += 1
	print("pieces per board: ", boards.map(func(b): return b.pieces.size()))
	var F = load("res://scripts/farm_logic.gd")
	var c = F.new_crop(1, 0.0, 0.0, 0.0)
	var now := 0.0
	var fruit_day := -1.0
	for i in 600:
		now += 1.0 / 60.0
		if now - float(c.lw) >= 0.8:
			F.water(c, now)
		if F.step(c, now, 1.0 / 60.0, false) == "fruit" and fruit_day < 0.0:
			fruit_day = now
	if fruit_day < 6.9 or fruit_day > 7.2 or c.dead:
		print("FAIL watered tree: fruit at day ", fruit_day, " dead=", c.dead); fails += 1
	var n = F.new_crop(2, 0.0, 0.0, 0.0)
	var dry_day := -1.0
	var dead_day := -1.0
	now = 0.0
	for i in 900:
		now += 1.0 / 60.0
		var ev: String = F.step(n, now, 1.0 / 60.0, false)
		if ev == "dry" and dry_day < 0.0:
			dry_day = now
		if ev == "dead" and dead_day < 0.0:
			dead_day = now
	if dry_day < 1.9 or dry_day > 2.2 or dead_day < 3.5 or dead_day > 8.0:
		print("FAIL neglected tree: dry ", dry_day, " dead ", dead_day); fails += 1
	var o = F.new_crop(3, 0.0, 0.0, 0.0)
	now = 0.0
	for i in 900:
		now += 1.0 / 60.0
		F.step(o, now, 1.0 / 60.0, true)
	if o.dead or float(o.h) < 0.34:
		print("FAIL offline tree must not die: ", o.h); fails += 1
	var H = load("res://scripts/hunt_logic.gd")
	var r1: Dictionary = H.shot("slingshot", "head", 100.0, 100.0)
	var r2: Dictionary = H.shot("bow", "head", 100.0, 100.0)
	var r3: Dictionary = H.shot("slingshot", "legs", 30.0, 30.0)
	var r4: Dictionary = H.shot("slingshot", "body", 100.0, 100.0)
	if r1["dead"] or not r1["wound"] or not r2["dead"] or r3["dead"] or not r3["wound"] or r4["dead"] or r4["wound"]:
		print("FAIL hunt outcomes ", r1, r2, r3, r4); fails += 1
	var B = load("res://scripts/barn_logic.gd")
	var an = B.new_animal(1, "deer", 0.0)
	var warn_day := -1.0
	var starve_day := -1.0
	var dead_day := -1.0
	now = 0.0
	for i in 600:
		now += 1.0 / 60.0
		var ev: String = B.step(an, now, 1.0 / 60.0, false)
		if ev == "hungry" and warn_day < 0.0:
			warn_day = now
		if ev == "starving" and starve_day < 0.0:
			starve_day = now
		if ev == "dead" and dead_day < 0.0:
			dead_day = now
	if warn_day < 0.7 or warn_day > 0.85 or starve_day < 0.95 or starve_day > 1.1 or dead_day < 4.0 or dead_day > 6.5:
		print("FAIL barn neglect: ", warn_day, " ", starve_day, " ", dead_day); fails += 1
	var fed = B.new_animal(2, "chicken", 0.0)
	now = 0.0
	for i in 600:
		now += 1.0 / 60.0
		if B.hunger(fed, now) >= 0.8:
			B.feed(fed, now)
		B.step(fed, now, 1.0 / 60.0, false)
	if fed.dead or float(fed.h) < 0.99:
		print("FAIL fed animal degraded"); fails += 1
	var off = B.new_animal(3, "deer", 0.0)
	now = 0.0
	for i in 900:
		now += 1.0 / 60.0
		B.step(off, now, 1.0 / 60.0, true)
	if off.dead or float(off.h) < 0.34:
		print("FAIL offline animal must not die"); fails += 1
	var gs = load("res://scripts/game_state.gd").new()
	gs.add("wood", 5)
	gs.placed["F0_1"] = true
	gs.removed[1003] = true
	gs.crops.append(F.new_crop(9, 1.0, 2.0, 0.5))
	gs.clock_hours = 100.5
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.reset()
	gs.from_dict(d)
	if gs.count("wood") != 5 or not gs.placed.has("F0_1") or not gs.removed.has(1003) or gs.crops.size() != 1 or absf(gs.clock_hours - 100.5) > 0.01 or int(gs.crops[0].id) != 9:
		print("FAIL save round-trip"); fails += 1
	if gs.spend("stone", 1):
		print("FAIL spend with no stone"); fails += 1
	print("TESTS ", "FAILED" if fails > 0 else "PASSED")
	quit(1 if fails > 0 else 0)
