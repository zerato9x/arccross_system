extends RefCounted
class_name MacroTimeRulesService

## Macro application adapter for authored time values. GameTimeRules still owns
## stable algorithms such as day/night bands; this service owns the tunable
## action durations consumed by the macro shell.

const DEFAULT_ACTION_MINUTES := 15
const DEFAULT_SEARCH_MINUTES := 30
const DEFAULT_CAMP_MINUTES := 480

var profile: TimeRulesProfile


func configure(value: TimeRulesProfile = null) -> void:
	profile = value if value != null else load(
		"res://SystemCore/default_time_rules.tres"
	) as TimeRulesProfile


func action_minutes(action_id: String, fallback: int = DEFAULT_ACTION_MINUTES) -> int:
	return profile.minutes_for(action_id, fallback) if profile != null else fallback


func search_minutes() -> int:
	return action_minutes("search", DEFAULT_SEARCH_MINUTES)


func camp_minutes() -> int:
	return maxi(
		1,
		profile.camp_minutes if profile != null else DEFAULT_CAMP_MINUTES
	)


func move_minutes_for_hex(hex_data: MacroHexData) -> int:
	if hex_data == null:
		return action_minutes("travel", DEFAULT_ACTION_MINUTES)
	var base := action_minutes(
		"travel",
		profile.travel_minutes_per_step if profile != null else DEFAULT_ACTION_MINUTES
	)
	return maxi(1, int(round(float(base) * hex_data.travel_time_multiplier())))


func exertion_for_hex(hex_data: MacroHexData) -> float:
	if hex_data == null:
		return 1.0
	return hex_data.travel_exertion()
