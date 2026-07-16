extends RefCounted
class_name GameTimeRules

## Physical time remains in minutes. These are orchestration rules, not enums.
## Radius-12 axial zone: 469 cells at ~0.69 km² per hex.
const HEX_AREA_KM2: float = 0.69
const ZONE_AREA_KM2: float = HEX_AREA_KM2 * GameEnums.MACRO_ZONE_CELL_COUNT
const HEX_CENTER_DISTANCE_KM: float = 0.9

const STARTING_WORLD_MINUTES: int = 8 * 60
## Plains baseline: one hex step is a real trek (~45 minutes).
const MOVE_MINUTES: int = 45
const SEARCH_MINUTES: int = 60
const CAMP_MINUTES: int = 8 * 60
const COMBAT_MINUTES: int = 15

static func move_minutes_for_hex(hex_data: MacroHexData) -> int:
	if hex_data == null:
		return MOVE_MINUTES
	return maxi(1, int(round(float(MOVE_MINUTES) * hex_data.travel_time_multiplier())))


static func travel_distance_km(hex_steps: int = 1) -> float:
	return HEX_CENTER_DISTANCE_KM * float(maxi(0, hex_steps))


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
