extends RefCounted
class_name GameTimeRules

## Physical time remains in minutes. These are orchestration rules, not enums.
const STARTING_WORLD_MINUTES: int = 8 * 60
const MOVE_MINUTES: int = 15
const SEARCH_MINUTES: int = 60
const CAMP_MINUTES: int = 8 * 60
const COMBAT_MINUTES: int = 15

static func clock_snapshot(total_minutes: int) -> Dictionary:
	var safe_minutes := maxi(0, total_minutes)
	var minute_of_day := safe_minutes % (24 * 60)
	return {
		"total_minutes": safe_minutes,
		"day": floori(float(safe_minutes) / float(24 * 60)) + 1,
		"hour": floori(float(minute_of_day) / 60.0),
		"minute": minute_of_day % 60,
	}


static func calendar_snapshot(total_minutes: int) -> Dictionary:
	var clock: Dictionary = clock_snapshot(total_minutes)
	var day_index := int(clock.get("day", 1)) - 1
	var year := floori(float(day_index) / 360.0) + 1
	var day_of_year := day_index % 360
	var month := floori(float(day_of_year) / 30.0) + 1
	var day_of_month := (day_of_year % 30) + 1
	return {
		"total_minutes": clock.get("total_minutes", 0),
		"day": clock.get("day", 1),
		"hour": clock.get("hour", 0),
		"minute": clock.get("minute", 0),
		"month": month,
		"year": year,
		"day_of_month": day_of_month,
	}
