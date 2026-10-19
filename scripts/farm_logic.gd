extends RefCounted
## Pure apple-tree rules (no scene/autoload deps -> unit-testable). Time unit = GAME DAYS.
## Clear system: first growth sign after 1 game day, fruit after 7 game days of growth,
## watering needed daily, 3 days dry => tree deteriorates, health 0 => dies and must be replaced.
const FIRST_SIGN_DAYS := 1.0
const FRUIT_DAYS := 7.0
const WARN_DAYS := 2.0
const DRY_LIMIT := 3.0
const DECAY_PER_DAY := 0.34
const OFFLINE_FLOOR := 0.35     # offline time can hurt a tree but never kill it (fairness)
const REFRUIT_DAYS := 2.0

static func new_crop(id: int, x: float, z: float, now: float) -> Dictionary:
	return {"id": id, "x": x, "z": z, "g": 0.0, "lw": now, "h": 1.0, "fruit": false, "nf": 0.0, "dead": false, "warn": 0}

static func moisture(c: Dictionary, now: float) -> float:
	return clampf(1.0 - (now - float(c.lw)) / DRY_LIMIT, 0.0, 1.0)

static func scale_of(c: Dictionary) -> float:
	return lerpf(0.18, 1.0, clampf((float(c.g) - FIRST_SIGN_DAYS) / (FRUIT_DAYS - FIRST_SIGN_DAYS), 0.0, 1.0))

static func stage(c: Dictionary) -> String:
	var g := float(c.g)
	if c.dead:
		return "ميتة"
	if g < FIRST_SIGN_DAYS:
		return "بذرة"
	if g < 3.0:
		return "برعم"
	if g < 5.0:
		return "شتلة"
	if g < FRUIT_DAYS:
		return "شجرة فتية"
	return "ناضجة"

static func water(c: Dictionary, now: float) -> void:
	c.lw = now
	c.warn = 0

static func harvest(c: Dictionary, now: float) -> void:
	c.fruit = false
	c.nf = now + REFRUIT_DAYS

## Advance one crop. Returns an event: "", "dry", "dying", "dead" or "fruit".
static func step(c: Dictionary, now: float, dt: float, offline: bool) -> String:
	if c.dead:
		return ""
	var since := now - float(c.lw)
	var m := clampf(1.0 - since / DRY_LIMIT, 0.0, 1.0)
	c.g = float(c.g) + dt * clampf(m * 2.0, 0.0, 1.0)
	var h := float(c.h)
	if since > DRY_LIMIT:
		var nh := h - dt * DECAY_PER_DAY
		if offline:
			nh = maxf(nh, minf(h, OFFLINE_FLOOR))
		c.h = maxf(0.0, nh)
	elif since < 1.5 and h < 1.0:
		c.h = minf(1.0, h + dt * 0.2)
	if float(c.h) <= 0.0:
		c.dead = true
		c.fruit = false
		return "dead"
	var ev := ""
	if float(c.g) >= FRUIT_DAYS and not c.fruit and float(c.h) > 0.5 and now >= float(c.nf):
		c.fruit = true
		ev = "fruit"
	if since >= DRY_LIMIT and int(c.warn) < 2:
		c.warn = 2
		ev = "dying"
	elif since >= WARN_DAYS and int(c.warn) < 1:
		c.warn = 1
		ev = "dry"
	return ev
