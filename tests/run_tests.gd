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
	if gate_pieces < 40:
		print("FAIL gate pieces: ", gate_pieces); fails += 1
	# difficulty: +1% per finished build (a fresh instance: autoloads do not exist inside _init)
	var gs0 = load("res://scripts/game_state.gd").new()
	var d0: float = gs0.difficulty()
	gs0.builds_done = 10
	if absf(d0 - 1.0) > 0.0001 or absf(float(gs0.difficulty()) - 1.1046) > 0.001 or int(gs0.difficulty_pct()) != 10:
		print("FAIL difficulty curve ", gs0.difficulty()); fails += 1
	gs0.free()
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
	# animals (phase 4): generated deer / ibex rig data must be consistent (bone parents, index bounds, hit zones)
	for k in ["deer", "ibex"]:
		var ad: Dictionary = load("res://assets/animals/%s_data.gd" % k).data()
		var names := {}
		for bn in ad["bones"]:
			if str(bn["parent"]) != "" and not names.has(str(bn["parent"])):
				print("FAIL ", k, " bone parent order ", bn["name"]); fails += 1
			names[str(bn["name"])] = true
		var tris := 0
		for mk in ad["meshes"]:
			var m: Dictionary = ad["meshes"][mk]
			var vc: int = m["v"].size() / 3
			if not names.has(mk) or m["n"].size() != m["v"].size() or m["c"].size() != m["v"].size():
				print("FAIL ", k, " mesh arrays ", mk); fails += 1
			for ix in m["i"]:
				if ix < 0 or ix >= vc:
					print("FAIL ", k, " index out of range ", mk); fails += 1
					break
			tris += m["i"].size() / 3
		if tris < 1000 or tris > 20000:
			print("FAIL ", k, " triangle count ", tris); fails += 1
		for z in ["head", "body", "legs"]:
			if not ad["zones"].has(z):
				print("FAIL ", k, " zone ", z); fails += 1
		for bn in ["fl_up", "fr_up", "hl_up", "hr_up", "neck", "head"]:
			if not names.has(bn):
				print("FAIL ", k, " missing bone ", bn); fails += 1
	# phase 6: skinned elk from the Unity prefab (bone tree, per-vertex skin data, index bounds)
	var ed: Dictionary = load("res://assets/animals/elk_data.gd").data()
	var ecount: int = ed["v"].size() / 3
	var enb: int = ed["names"].size()
	if enb != 34 or ed["parent"].size() != enb or ed["rest"].size() != enb * 12:
		print("FAIL elk bones ", enb); fails += 1
	for ei in enb:
		if int(ed["parent"][ei]) >= ei:
			print("FAIL elk bone parent order ", ei); fails += 1
			break
	if ed["n"].size() != ecount * 3 or ed["uv"].size() != ecount * 2 or ed["bi"].size() != ecount * 4 or ed["bw"].size() != ecount * 4:
		print("FAIL elk vertex arrays"); fails += 1
	for ei in ed["bi"]:
		if ei < 0 or ei >= enb:
			print("FAIL elk bone index ", ei); fails += 1
			break
	for ei in ed["idx"]:
		if ei < 0 or ei >= ecount:
			print("FAIL elk index out of range"); fails += 1
			break
	if ed["idx"].size() < 3000 or ed["idx"].size() % 3 != 0:
		print("FAIL elk triangles"); fails += 1
	# phase 7: capture stages, predators, poultry, lives, well state
	var SH = load("res://scripts/hunt_logic.gd")
	if not SH.capturable(0, "elk") or SH.capturable(0, "deer") or not SH.capturable(1, "deer") or not SH.capturable(2, "turkey"):
		print("FAIL capture stages"); fails += 1
	if SH.capturable(0, "bear") or SH.capturable(9, "wolf") or SH.capturable(9, "bird") or not SH.capturable(9, "deer"):
		print("FAIL predators / birds are never caught alive"); fails += 1
	if not SH.is_predator("fox") or SH.is_predator("elk") or SH.LIVES != 5:
		print("FAIL predator flags"); fails += 1
	if int(SH.STAGES[0]["goal"]) != 5 or int(SH.STAGES[1]["goal"]) != 5 or int(SH.STAGES[2]["goal"]) != 10:
		print("FAIL stage goals"); fails += 1
	var BLx = load("res://scripts/barn_logic.gd")
	if not BLx.is_poultry("turkey") or BLx.is_poultry("elk") or BLx.MILK_PER_DAY != 24.0:
		print("FAIL poultry / milk rate"); fails += 1
	var ma: Dictionary = BLx.new_animal(1, "elk", 0.0)
	BLx.feed(ma, 0.0)
	BLx.step(ma, 1.0 / 24.0 + 0.0001, 1.0 / 24.0, false)
	if float(ma["milk"]) < 0.99 or float(ma["milk"]) > 1.1:
		print("FAIL one milk per game hour ", ma["milk"]); fails += 1
	var gs7 = load("res://scripts/game_state.gd").new()
	gs7.lives = 3
	gs7.hunt_stage = 2
	gs7.stage_n = 4
	gs7.well = 2
	gs7.bucket = 5
	gs7.pond = 0.6
	gs7.channel = true
	var gs8 = load("res://scripts/game_state.gd").new()
	gs8.from_dict(gs7.to_dict())
	if gs8.lives != 3 or gs8.hunt_stage != 2 or gs8.stage_n != 4 or gs8.well != 2 or gs8.bucket != 5 or absf(gs8.pond - 0.6) > 0.001 or not gs8.channel:
		print("FAIL save of lives / stage / well"); fails += 1
	# realistic speeds: the player (running) is slower than a fleeing deer / elk / ibex and the predators, faster than a wounded one
	var run_p: float = load("res://scripts/player.gd").SPEED
	for rk in ["deer", "ibex", "elk", "wolf", "bear", "fox"]:
		if float(SH.ANIMALS[rk]["run"]) <= run_p:
			print("FAIL ", rk, " must outrun the player"); fails += 1
	for rk in ["deer", "ibex", "elk"]:
		if float(SH.ANIMALS[rk]["run"]) * 0.4 >= run_p:
			print("FAIL wounded ", rk, " must be catchable"); fails += 1
	# fishing: the rod and dock are puzzle boards (crafted, not given)
	var fb := {}
	for bd in load("res://scripts/building_data.gd").make_boards():
		fb[str(bd.id)] = bd.pieces.size()
	if int(fb.get("R_rod", 0)) != 6 or int(fb.get("R_dock", 0)) != 6:
		print("FAIL fishing boards ", fb.get("R_rod", 0), " ", fb.get("R_dock", 0)); fails += 1
	if int(load("res://scripts/game_state.gd").new().inv.get("fish", -1)) != 0:
		print("FAIL fish item"); fails += 1
	gs7.free()
	gs8.free()
	var EH = load("res://scripts/hunt_logic.gd")
	if not EH.ANIMALS.has("elk") or float(EH.ANIMALS["elk"]["hp"]) <= 100.0:
		print("FAIL elk stats"); fails += 1
	var HL = load("res://scripts/hunt_logic.gd")
	if not HL.ANIMALS.has("ibex") or float(HL.ANIMALS["ibex"]["hp"]) <= 0.0:
		print("FAIL ibex stats"); fails += 1
	# phase 5: fodder farming and milk
	var FLg = load("res://scripts/farm_logic.gd")
	var fc: Dictionary = FLg.new_crop(1, 0.0, 0.0, 0.0, "fodder")
	for fi in 40:
		FLg.water(fc, fi * 0.05)
		FLg.step(fc, (fi + 1) * 0.05, 0.05, false)
	if not fc.fruit or FLg.stage(fc) != "علف جاهز":
		print("FAIL fodder did not ripen in 2 watered days ", fc); fails += 1
	var fd: Dictionary = FLg.new_crop(2, 0.0, 0.0, 0.0, "fodder")
	for fi in 100:
		FLg.step(fd, (fi + 1) * 0.05, 0.05, false)
	if not fd.dead:
		print("FAIL unwatered fodder should die ", fd); fails += 1
	var BLg = load("res://scripts/barn_logic.gd")
	var mq: Dictionary = BLg.new_animal(1, "deer", 0.0)
	for mi in 7:
		BLg.step(mq, 0.1 * (mi + 1), 0.1, false)
	if float(mq.milk) < 1.0:
		print("FAIL fed deer should give milk ", mq); fails += 1
	var mr: Dictionary = BLg.new_animal(2, "deer", 0.0)
	BLg.step(mr, 0.9, 0.1, false)
	if float(mr.milk) != 0.0:
		print("FAIL hungry deer must not give milk ", mr); fails += 1
	# phase 7.3: seasons and weather (rain is not daily; long gaps; summer dry, winter wet)
	var WLg = load("res://scripts/weather_logic.gd")
	var wet := [0, 0, 0, 0]
	var cnt := [0, 0, 0, 0]
	var consec := 0
	for wd in 3200:
		var sn: int = WLg.season(wd)
		cnt[sn] += 1
		if WLg.rains_on(wd):
			wet[sn] += 1
			if WLg.rains_on(wd - 1):
				consec += 1
			var ww: Vector3 = WLg.rain_window(wd)
			if ww.y - ww.x < 3.0 or ww.z <= 0.0:
				print("FAIL rain must last hours ", wd, ww); fails += 1
		elif WLg.rain_window(wd) != Vector3.ZERO:
			print("FAIL dry day has window ", wd); fails += 1
	var wtot: int = wet[0] + wet[1] + wet[2] + wet[3]
	if float(wet[1]) / cnt[1] > 0.12 or float(wet[3]) / cnt[3] < 0.30 or float(wtot) / 3200.0 > 0.35 or float(wtot) / 3200.0 < 0.12:
		print("FAIL season rain shares ", wet, cnt); fails += 1
	if consec * 3 > wtot:
		print("FAIL too many consecutive rainy days ", consec, "/", wtot); fails += 1
	if WLg.season(0) != 0 or WLg.season(8) != 1 or WLg.season(31) != 3 or WLg.season(32) != 0:
		print("FAIL season boundaries"); fails += 1
	var rd := -1
	for wd2 in 40:
		if WLg.rains_on(wd2):
			rd = wd2
			break
	if rd >= 0:
		var rw: Vector3 = WLg.rain_window(rd)
		if WLg.rain_at(rd * 24.0 + (rw.x + rw.y) * 0.5) <= 0.0:
			print("FAIL rain_at inside window ", rd, rw); fails += 1
		if WLg.forecast_text(rd * 24.0 + (rw.x + rw.y) * 0.5) != "تمطر الآن":
			print("FAIL forecast while raining"); fails += 1
	if WLg.evap_mult(8) <= WLg.evap_mult(24) or WLg.growth(24) >= WLg.growth(0):
		print("FAIL season multipliers"); fails += 1
	quit(1 if fails > 0 else 0)
