extends RefCounted
## Pure hunting rules (no scene deps -> unit-testable): weapons, animals, hit outcomes by hit zone.
const WEAPONS := {
	"slingshot": {"name": "مقلاع", "ammo": "stone", "dmg": {"head": 60.0, "body": 20.0, "legs": 15.0}, "range": 30.0, "level": 1},
	"bow": {"name": "قوس", "ammo": "arrows", "dmg": {"head": 100.0, "body": 55.0, "legs": 30.0}, "range": 45.0, "level": 3},
	"crossbow": {"name": "قوس نشاب", "ammo": "arrows", "dmg": {"head": 100.0, "body": 80.0, "legs": 40.0}, "range": 60.0, "level": 8},
}
const ORDER := ["slingshot", "bow", "crossbow"]
const ANIMALS := {
	"deer": {"name": "غزال", "hp": 100.0, "walk": 1.4, "run": 12.0, "flee": 16.0, "meat": 6},
	"ibex": {"name": "وعل", "hp": 80.0, "walk": 1.2, "run": 10.0, "flee": 18.0, "meat": 5},
	"elk": {"name": "أيل", "hp": 160.0, "walk": 1.3, "run": 11.0, "flee": 20.0, "meat": 9},
	"turkey": {"name": "ديك رومي", "hp": 45.0, "walk": 0.8, "run": 4.8, "flee": 10.0, "meat": 3},
	"bird": {"name": "طائر", "hp": 20.0, "walk": 0.0, "run": 0.0, "flee": 0.0, "meat": 1},
	"bear": {"name": "دب", "hp": 260.0, "walk": 1.6, "run": 9.0, "flee": 0.0, "meat": 14, "predator": true, "reach": 2.3, "detect": 24.0},
	"wolf": {"name": "ذئب", "hp": 90.0, "walk": 1.8, "run": 11.0, "flee": 0.0, "meat": 6, "predator": true, "reach": 1.9, "detect": 26.0},
	"fox": {"name": "ثعلب", "hp": 40.0, "walk": 1.6, "run": 10.0, "flee": 0.0, "meat": 3, "predator": true, "reach": 1.2, "detect": 0.0},
	"chicken": {"name": "دجاجة", "hp": 30.0, "walk": 0.8, "run": 4.2, "flee": 8.0, "meat": 2},
}
## Capture stages: only the current stage's animals can be caught alive (others can only be killed for meat).
const STAGES := [
	{"kinds": ["elk"], "goal": 5, "name": "الأيل"},
	{"kinds": ["deer", "ibex"], "goal": 5, "name": "الغزال والوعل"},
	{"kinds": ["chicken", "turkey"], "goal": 10, "name": "الدجاج والديك الرومي"},
]
const LIVES := 5

static func is_predator(kind: String) -> bool:
	return bool(ANIMALS[kind].get("predator", false))

static func stage_counts(stage: int, kind: String) -> bool:
	return stage >= 0 and stage < STAGES.size() and (STAGES[stage]["kinds"] as Array).has(kind)

## Can this animal be caught alive at the given stage? (predators and birds never; after the last stage everything else.)
static func capturable(stage: int, kind: String) -> bool:
	if is_predator(kind) or kind == "bird":
		return false
	return stage >= STAGES.size() or stage_counts(stage, kind)

const TRANSIT_SECONDS := 180.0   # carrying a live animal to the farm takes 3 minutes

## Result of one hit. wound = survived but hurt (limps, slows, gets tired -> can be caught).
static func shot(weapon_id: String, zone: String, hp: float, max_hp: float) -> Dictionary:
	var dmg: float = WEAPONS[weapon_id]["dmg"][zone]
	var nh := hp - dmg
	return {"hp": nh, "dead": nh <= 0.0, "wound": nh > 0.0 and (zone == "legs" or nh < max_hp * 0.5)}
