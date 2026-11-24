extends RefCounted
## Seasons and weather (pure functions of the game clock, so nothing needs saving and offline time stays consistent).
## A year = 32 days = 4 seasons of 8 days. Rain is NOT a daily routine: most days are dry; when it does rain it lasts
## hours (a front), and rainy days seldom follow each other. Summer is mostly dry, winter is the wet season.
const DAYS_PER_SEASON := 8
const SEASONS := ["الربيع", "الصيف", "الخريف", "الشتاء"]
const RAIN_CHANCE := [0.30, 0.06, 0.32, 0.55]
const EVAP_MULT := [1.0, 2.5, 1.0, 0.5]       # lake evaporation per season
const GROWTH := [1.2, 0.9, 1.0, 0.6]          # crop growth speed per season
const RAIN_FILL_PER_HOUR := 0.07              # lake level gained per hour of full rain

static func hash01(day: int, k: int) -> float:
	var x: int = (day * 374761393 + k * 668265263 + 12345) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = x ^ (x >> 16)
	return float(x % 100003) / 100003.0

static func day_of(hours: float) -> int:
	return int(floor(hours / 24.0))

static func season(day: int) -> int:
	return posmod(day / DAYS_PER_SEASON, 4)

static func season_name(day: int) -> String:
	return SEASONS[season(day)]

static func evap_mult(day: int) -> float:
	return EVAP_MULT[season(day)]

static func growth(day: int) -> float:
	return GROWTH[season(day)]

static func rains_on(day: int) -> bool:
	var c: float = RAIN_CHANCE[season(day)]
	if hash01(day - 1, 0) < RAIN_CHANCE[season(day - 1)]:
		c *= 0.35                                 # a wet day is rarely followed by another
	return hash01(day, 0) < c

## (start hour, end hour (may pass 24 = spills into next day), intensity 0.4..1); zero vector if dry.
static func rain_window(day: int) -> Vector3:
	if not rains_on(day):
		return Vector3.ZERO
	var start := 4.0 + hash01(day, 1) * 12.0
	var dur := 3.0 + hash01(day, 2) * 6.0
	var inten := 0.4 + hash01(day, 3) * 0.6
	return Vector3(start, start + dur, inten)

## Rain intensity (0 = none) at the absolute game clock `hours`; includes spill-over from the previous day.
static func rain_at(hours: float) -> float:
	var day := day_of(hours)
	var h := hours - day * 24.0
	var w := rain_window(day)
	if w.z > 0.0 and h >= w.x and h < w.y:
		return _edge(h, w)
	var p := rain_window(day - 1)
	if p.z > 0.0 and p.y > 24.0 and h + 24.0 < p.y:
		return _edge(h + 24.0, p)
	return 0.0

static func _edge(h: float, w: Vector3) -> float:
	var ramp := minf(minf(h - w.x, w.y - h) / 0.5, 1.0)     # soft start / end over half an hour
	return w.z * clampf(ramp, 0.0, 1.0)

## Days until the next rain begins (0 = today still ahead or ongoing), or -1 if none within 40 days.
static func next_rain_in_days(hours: float) -> int:
	var day := day_of(hours)
	var h := hours - day * 24.0
	var w := rain_window(day)
	if w.z > 0.0 and h < w.y:
		return 0
	for i in range(1, 41):
		if rains_on(day + i):
			return i
	return -1

static func forecast_text(hours: float) -> String:
	if rain_at(hours) > 0.0:
		return "تمطر الآن"
	var n := next_rain_in_days(hours)
	if n < 0:
		return "جفاف طويل"
	if n == 0:
		var w := rain_window(day_of(hours))
		return "مطر اليوم قرب %02d:00" % int(w.x)
	if n == 1:
		return "مطر غدًا"
	return "مطر بعد %d أيام" % n

static func hud_text(hours: float) -> String:
	var day := day_of(hours)
	return "%s — اليوم %d | %s" % [season_name(day), posmod(day, DAYS_PER_SEASON * 4) + 1, forecast_text(hours)]
