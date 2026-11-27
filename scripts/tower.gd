extends Node
## Lookout tower beside the lake (boards T_1..T_8 on the build board). Near the half-built tower a hint offers a reward ad
## that finishes the current stage at once. Once finished it warns about predators that come close.
signal message(text: String)
const BD := preload("res://scripts/building_data.gd")
const L := preload("res://scripts/hunt_logic.gd")
const NEAR := 11.0
const HINT_FROM := 3                 # the ad offer appears after stage 3 (the frame) is finished
const WARN_R := 42.0
var builder
var player
var hunt
var _confirm_until := 0.0
var _warn_t := 0.0
var _announced := ""

func _ready() -> void:
	Ads.reward_granted.connect(_on_reward)

## Index of the tower board being built (-1 when none is available or the tower is complete).
func current() -> int:
	for i in 8:
		var bi: int = builder.index_of("T_%d" % (i + 1))
		if bi >= 0 and builder.available(bi) and builder.remaining(bi) > 0:
			return bi
	return -1

func stage() -> int:                   # number of finished stages
	var n := 0
	for i in 8:
		if builder.board_done("T_%d" % (i + 1)):
			n += 1
	return n

func done() -> bool:
	return builder != null and builder.board_done("T_8")

func near(pos: Vector3) -> bool:
	return Vector2(pos.x - BD.TOWER_C.x, pos.z - BD.TOWER_C.z).length() < NEAR

func _ad_stage(pos: Vector3) -> bool:
	return builder != null and near(pos) and stage() >= HINT_FROM and current() >= 0

func hint(pos: Vector3) -> String:
	if not _ad_stage(pos):
		return ""
	return "تفاعل: شاهد إعلانًا لإنهاء «%s» فورًا" % str(builder.boards[current()].name)

func interact(pos: Vector3) -> bool:
	if not _ad_stage(pos):
		return false
	var now := Time.get_ticks_msec() * 0.001
	if now < _confirm_until:
		_confirm_until = 0.0
		if Ads.is_available():
			message.emit("جارٍ تحميل إعلان المكافأة%s" % (" (محاكاة تطوير)" if Ads.is_simulated() else ""))
			Ads.show_rewarded("tower_boost")
		else:
			message.emit("لا يتوفر إعلان الآن — أكمل البناء بنفسك")
	else:
		_confirm_until = now + 6.0
		message.emit("اضغط «تفاعل» مرة أخرى خلال 6 ثوانٍ لمشاهدة إعلان وإنهاء المرحلة الحالية فورًا")
	return true

func _on_reward(placement: String) -> void:
	if placement != "tower_boost" or builder == null:
		return
	var bi := current()
	if bi < 0:
		return
	var nm := str(builder.boards[bi].name)
	builder.complete_board(bi)
	message.emit("شاهدتَ الإعلان: اكتملت «%s» ✓" % nm)

## Called a few times a second: once the tower stands it spots predators that approach the player.
func watch(dt: float, pos: Vector3) -> void:
	_warn_t = maxf(0.0, _warn_t - dt)
	if not done() or _warn_t > 0.0 or hunt == null:
		return
	for a in hunt.animals:
		if not is_instance_valid(a) or a.dead or not a.predator:
			continue
		var d := Vector2(a.global_position.x - pos.x, a.global_position.z - pos.z).length()
		if d < WARN_R and Vector2(pos.x, pos.z).length() >= L.SAFE_R:
			_warn_t = 30.0
			message.emit("برج المراقبة: %s يقترب منك (%d م)!" % [("دب" if a.kind == "bear" else ("ذئب" if a.kind == "wolf" else "ثعلب")), int(d)])
			return
