extends RefCounted
## Pure barn-animal care rules (unit-testable). Time unit = GAME DAYS.
## One feeding per game day. Warn at 0.75 day since the last meal, 1 day of grace, then health drops
## 25%/day (death after ~4 more days). Offline time can weaken an animal but never kill it.
const WARN := 0.75
const GRACE := 1.0
const DECAY_PER_DAY := 0.25
const OFFLINE_FLOOR := 0.35
const MILK_PER_DAY := 24.0     # one milk per GAME HOUR for a well-fed animal (none while hungry)
const MILK_CAP := 6.0

static func is_poultry(kind: String) -> bool:
	return kind == "chicken" or kind == "turkey"

static func new_animal(id: int, kind: String, now: float) -> Dictionary:
	return {"id": id, "kind": kind, "h": 1.0, "fed": now, "warn": 0, "dead": false, "milk": 0.0}

static func hunger(a: Dictionary, now: float) -> float:
	return now - float(a.fed)

static func feed(a: Dictionary, now: float) -> void:
	a.fed = now
	a.warn = 0

## Returns "", "hungry", "starving" or "dead".
static func step(a: Dictionary, now: float, dt: float, offline: bool) -> String:
	if a.dead:
		return ""
	var hg := now - float(a.fed)
	var h := float(a.h)
	if not is_poultry(str(a.kind)) and hg < WARN and h >= 0.7:
		a["milk"] = minf(MILK_CAP, float(a.get("milk", 0.0)) + dt * MILK_PER_DAY)
	if hg > GRACE:
		var nh := h - dt * DECAY_PER_DAY
		if offline:
			nh = maxf(nh, minf(h, OFFLINE_FLOOR))
		a.h = maxf(0.0, nh)
	elif hg < 0.5 and h < 1.0:
		a.h = minf(1.0, h + dt * 0.3)
	if float(a.h) <= 0.0:
		a.dead = true
		return "dead"
	if hg >= GRACE and int(a.warn) < 2:
		a.warn = 2
		return "starving"
	if hg >= WARN and int(a.warn) < 1:
		a.warn = 1
		return "hungry"
	return ""
