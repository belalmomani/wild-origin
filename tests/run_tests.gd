extends SceneTree
## Run: godot --headless --script tests/run_tests.gd   (exit code 1 on failure)
func _init() -> void:
	var fails := 0
	var D = load("res://scripts/building_data.gd")
	var boards: Array = D.make_boards()
	if boards.size() != 29:
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
	# interior (phase 2): every part must lie inside the house shell; F0 keeps its legacy ids; door pieces are flagged
	var interior := 0
	var door_pieces := 0
	for b in boards:
		if not str(b.id).begins_with("I_"):
			continue
		interior += 1
		if b.pieces.size() < 6:
			print("FAIL interior board too small ", b.id); fails += 1
		for p in b.pieces:
			var o: Vector3 = p.xf.origin
			if absf(o.x) > 2.1 or o.z > 2.1 or o.z < -1.95 or o.y < 0.0 or o.y > 3.6:
				print("FAIL interior piece outside the house ", p.id, " ", o); fails += 1
			if str(p.get("door", "")) == "house":
				door_pieces += 1
	if interior != 9 or door_pieces < 15:
		print("FAIL interior boards: ", interior, " door pieces ", door_pieces); fails += 1
	for b in boards:
		if str(b.id) == "F0":
			var has0 := false
			for p in b.pieces:
				if p.id == "F0_0":
					has0 = true
			if not has0:
				print("FAIL F0 legacy ids lost"); fails += 1
			for p in b.pieces:
				var cx: float = (p.xf.origin as Vector3).x
				var cy: float = (p.xf.origin as Vector3).y
				if absf(cx) < 0.55 and cy < 2.3:
					print("FAIL piece left inside the widened doorway ", p.id); fails += 1
	# gates + farm: every gate piece knows its hinge, all parts stay in their place, farm is clear of the house fence
	var gate_pieces := 0
	for b in boards:
		var bid := str(b.id)
		if bid != "G_fence" and not bid.begins_with("M_"):
			continue
		for p in b.pieces:
			var o2: Vector3 = p.xf.origin
			if bid == "G_fence" and (absf(o2.x) > 2.0 or absf(o2.z - 6.0) > 0.2):
				print("FAIL fence gate piece misplaced ", p.id, " ", o2); fails += 1
			if bid.begins_with("M_") and (o2.x < -19.3 or o2.x > -8.7 or absf(o2.z) > 5.3):
				print("FAIL farm piece outside the farm ", p.id, " ", o2); fails += 1
			if str(p.get("door", "")) != "":
				gate_pieces += 1
				if not p.has("hinge") or not p.has("leaf") or not p.has("angle"):
					print("FAIL gate piece without hinge ", p.id); fails += 1
	if gate_pieces < 50:
		print("FAIL gate pieces: ", gate_pieces); fails += 1
	# difficulty: +1% per finished build (a fresh instance: autoloads do not exist inside _init)
	var gs = load("res://scripts/game_state.gd").new()
	var d0: float = gs.difficulty()
	gs.builds_done = 10
	if absf(d0 - 1.0) > 0.0001 or absf(float(gs.difficulty()) - 1.1046) > 0.001 or int(gs.difficulty_pct()) != 10:
		print("FAIL difficulty curve ", gs.difficulty()); fails += 1
	gs.free()
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
	var b_warn := -1.0
	var b_starve := -1.0
	var b_dead := -1.0
	now = 0.0
	for i in 600:
		now += 1.0 / 60.0
		var ev: String = B.step(an, now, 1.0 / 60.0, false)
		if ev == "hungry" and b_warn < 0.0:
			b_warn = now
		if ev == "starving" and b_starve < 0.0:
			b_starve = now
		if ev == "dead" and b_dead < 0.0:
			b_dead = now
	if b_warn < 0.7 or b_warn > 0.85 or b_starve < 0.95 or b_starve > 1.1 or b_dead < 4.0 or b_dead > 6.5:
		print("FAIL barn neglect: ", b_warn, " ", b_starve, " ", b_dead); fails += 1
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
	var TL = load("res://scripts/tech_logic.gd")
	var seen := {}
	for t in TL.TECHS:
		if seen.has(t["id"]):
			print("FAIL duplicate tech ", t["id"]); fails += 1
		seen[t["id"]] = true
	for t in TL.TECHS:
		for rq in t["req"]:
			if not seen.has(rq):
				print("FAIL tech ", t["id"], " requires unknown ", rq); fails += 1
	var tools: Dictionary = TL.by_id("tools")
	if TL.status(tools, [], 1, {"wood": 8, "stone": 4}) != "ready" or TL.status(tools, [], 1, {}) != "res" or TL.status(TL.by_id("axe2"), [], 5, {"wood": 99, "stone": 99}) != "req" or TL.status(TL.by_id("roads"), ["build_save"], 99, {}) != "future" or TL.status(tools, ["tools"], 1, {}) != "done":
		print("FAIL tech status"); fails += 1
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
	gs.reset()
	gs.xp = 100
	gs.add("wood", 500)
	gs.add("stone", 500)
	if gs.count("wood") != 150 or gs.research("axe2") == "" or gs.research("tools") != "" or not gs.has_tech("tools") or gs.cap_of("wood") != 150:
		print("FAIL capacity/research: ", gs.count("wood")); fails += 1
	gs.reset()
	if gs.spend("stone", 1):
		print("FAIL spend with no stone"); fails += 1
	print("TESTS ", "FAILED" if fails > 0 else "PASSED")
	quit(1 if fails > 0 else 0)
