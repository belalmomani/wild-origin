extends RefCounted
## Pure hunting rules (no scene deps -> unit-testable): weapons, animals, hit outcomes by hit zone.
const WEAPONS := {
	"slingshot": {"name": "مقلاع", "ammo": "stone", "dmg": {"head": 60.0, "body": 20.0, "legs": 15.0}, "range": 30.0, "level": 1},
	"bow": {"name": "قوس", "ammo": "arrows", "dmg": {"head": 100.0, "body": 55.0, "legs": 30.0}, "range": 45.0, "level": 3},
	"crossbow": {"name": "قوس نشاب", "ammo": "arrows", "dmg": {"head": 100.0, "body": 80.0, "legs": 40.0}, "range": 60.0, "level": 8},
}
const ORDER := ["slingshot", "bow", "crossbow"]
const ANIMALS := {
	"deer": {"name": "غزال", "hp": 100.0, "walk": 1.3, "run": 7.0, "flee": 16.0, "meat": 6},
	"chicken": {"name": "دجاجة", "hp": 30.0, "walk": 0.8, "run": 3.8, "flee": 8.0, "meat": 2},
}
const TRANSIT_SECONDS := 180.0   # carrying a live animal to the farm takes 3 minutes

## Result of one hit. wound = survived but hurt (limps, slows, gets tired -> can be caught).
static func shot(weapon_id: String, zone: String, hp: float, max_hp: float) -> Dictionary:
	var dmg: float = WEAPONS[weapon_id]["dmg"][zone]
	var nh := hp - dmg
	return {"hp": nh, "dead": nh <= 0.0, "wound": nh > 0.0 and (zone == "legs" or nh < max_hp * 0.5)}
