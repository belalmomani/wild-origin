extends RefCounted
## Pure tech-tree data and rules (unit-testable). Data-driven: add an entry to TECHS to extend the tree.
## "future": true entries are placeholders for later stages (roads, workshop, village) and are NOT implemented.
const TECHS := [
	{"id": "tools", "name": "أدوات حجرية", "desc": "قطع الأشجار وتكسير الصخور بضربتين بدل ثلاث", "tier": 1, "req": [], "level": 1, "cost": {"wood": 8, "stone": 4}},
	{"id": "stealth", "name": "خطوات هادئة", "desc": "الحيوانات تلاحظك من مسافة أقل بـ30%", "tier": 1, "req": [], "level": 1, "cost": {"wood": 5, "apples": 2}},
	{"id": "axe2", "name": "فأس محسّن", "desc": "كل شجرة تعطي 8 خشب بدل 5", "tier": 2, "req": ["tools"], "level": 2, "cost": {"wood": 12, "stone": 6}},
	{"id": "pick2", "name": "معول محسّن", "desc": "كل صخرة تعطي 9 حجارة بدل 6", "tier": 2, "req": ["tools"], "level": 2, "cost": {"wood": 6, "stone": 12}},
	{"id": "lamps", "name": "مصابيح المخيم", "desc": "أعمدة إنارة حول المنزل والحظيرة تضيء ليلًا", "tier": 2, "req": ["tools"], "level": 3, "cost": {"wood": 15, "stone": 10}},
	{"id": "storage", "name": "التخزين", "desc": "سعة الحقيبة 400 خشب/حجر (بدل 150) و100 طعام (بدل 40)", "tier": 2, "req": ["tools"], "level": 3, "cost": {"wood": 20, "stone": 10}},
	{"id": "build_save", "name": "تحسين البناء", "desc": "كل قطعة ثانية في البناء تُركَّب مجانًا", "tier": 3, "req": ["axe2"], "level": 4, "cost": {"wood": 25, "stone": 15}},
	{"id": "lantern", "name": "فانوس", "desc": "المشعل أقوى وأبعد مدى", "tier": 3, "req": ["lamps"], "level": 5, "cost": {"wood": 10, "stone": 8}},
	{"id": "compost", "name": "سماد عضوي", "desc": "كل قطف تفاح يعطي 4 بدل 3", "tier": 3, "req": ["storage"], "level": 4, "cost": {"wood": 10, "apples": 4}},
	{"id": "hay2", "name": "تخزين العلف", "desc": "3 خشب تصنع 6 قش بدل 4", "tier": 3, "req": ["compost"], "level": 5, "cost": {"wood": 12, "apples": 4}},
	{"id": "roads", "name": "الطرق", "desc": "قريبًا — غير مُنفَّذ بعد", "tier": 4, "req": ["build_save"], "level": 99, "cost": {}, "future": true},
	{"id": "workshop", "name": "الورشة", "desc": "قريبًا — غير مُنفَّذ بعد", "tier": 4, "req": ["build_save"], "level": 99, "cost": {}, "future": true},
	{"id": "village", "name": "توسعة القرية", "desc": "قريبًا — غير مُنفَّذ بعد", "tier": 5, "req": ["roads", "workshop"], "level": 99, "cost": {}, "future": true},
]

static func by_id(id: String) -> Dictionary:
	for t in TECHS:
		if t["id"] == id:
			return t
	return {}

## "done", "future", "req", "level", "res" or "ready".
static func status(t: Dictionary, unlocked: Array, level: int, inv: Dictionary) -> String:
	if unlocked.has(t["id"]):
		return "done"
	if t.get("future", false):
		return "future"
	for r in t["req"]:
		if not unlocked.has(r):
			return "req"
	if level < int(t["level"]):
		return "level"
	var cost: Dictionary = t["cost"]
	for k in cost:
		if int(inv.get(k, 0)) < int(cost[k]):
			return "res"
	return "ready"

static func reason_text(st: String, t: Dictionary) -> String:
	match st:
		"req": return "يحتاج تقنية سابقة"
		"level": return "يحتاج المستوى %d" % int(t["level"])
		"res": return "موارد غير كافية"
		"future": return "قريبًا — غير مُنفَّذ بعد"
		"done": return "مُطوَّرة بالفعل"
	return ""

static func cost_text(t: Dictionary) -> String:
	var names := {"wood": "خشب", "stone": "حجر", "apples": "تفاح", "meat": "طعام", "seeds": "بذور"}
	var parts: Array = []
	var cost: Dictionary = t["cost"]
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), names.get(k, k)])
	return "، ".join(parts)
