extends Node
## Ads abstraction (autoload "Ads"). Game logic only talks to this interface.
## Debug builds: clearly-labelled SIMULATION (not a real ad). Release builds: real
## ads only if an Android plugin singleton "StartioAds" is present (see docs/ADS.md).
signal reward_granted(placement: String)

const PLUGIN := "StartioAds"

func is_simulated() -> bool:
	return OS.has_feature("debug") and not Engine.has_singleton(PLUGIN)

func is_available() -> bool:
	return Engine.has_singleton(PLUGIN) or OS.has_feature("debug")

func show_rewarded(placement: String) -> void:
	if Engine.has_singleton(PLUGIN):
		# The plugin must call back Ads.on_reward(placement). Keys live in plugin config, never in git.
		Engine.get_singleton(PLUGIN).call("showRewarded", placement)
	elif OS.has_feature("debug"):
		await get_tree().create_timer(1.5).timeout
		reward_granted.emit(placement)

func on_reward(placement: String) -> void:
	reward_granted.emit(placement)
