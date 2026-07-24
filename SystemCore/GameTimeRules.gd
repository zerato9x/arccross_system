extends RefCounted
class_name GameTimeRules

## Physical time remains in minutes. These are orchestration rules, not enums.
## Radius-12 axial zone: 469 cells. Hex pitch ~0.45 km → ~0.175 km² each,
## zone ~82 km² (district-scale travel board).
## One plains step = 15 minutes (four action atoms per hour).
const HEX_CENTER_DISTANCE_KM: float = 0.45
## Area of a regular hex with center-to-center pitch d: (√3/2) * d²
const HEX_AREA_KM2: float = 0.175
const ZONE_AREA_KM2: float = HEX_AREA_KM2 * GameEnums.MACRO_ZONE_CELL_COUNT

## Shared action atom — biology intervals and world verbs align here.
const ACTION_MINUTES: int = 15

const STARTING_WORLD_MINUTES: int = 8 * 60
## Plains baseline: one hex step is one action atom.
const MOVE_MINUTES: int = ACTION_MINUTES
## Careful scavenge at a fixture = two atoms.
const SEARCH_MINUTES: int = ACTION_MINUTES * 2
const CAMP_MINUTES: int = 8 * 60
const COMBAT_MINUTES: int = ACTION_MINUTES

static func move_minutes_for_hex(hex_data: MacroHexData) -> int:
	if hex_data == null:
		return MOVE_MINUTES
	return maxi(1, int(round(float(MOVE_MINUTES) * hex_data.travel_time_multiplier())))


static func travel_distance_km(hex_steps: int = 1) -> float:
	return HEX_CENTER_DISTANCE_KM * float(maxi(0, hex_steps))


static func action_atoms(minutes: int) -> int:
	return maxi(1, int(ceil(float(maxi(0, minutes)) / float(ACTION_MINUTES))))


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


## Shared day/night bands for HUD labels, vignette lighting, and audio.
static func phase_for_hour(hour: int) -> String:
	var safe_hour := clampi(hour, 0, 23)
	if safe_hour < 5:
		return "night"
	if safe_hour < 7:
		return "dawn"
	if safe_hour < 11:
		return "morning"
	if safe_hour < 14:
		return "midday"
	if safe_hour < 17:
		return "afternoon"
	if safe_hour < 20:
		return "dusk"
	return "night"


static func is_night_phase(phase: String) -> bool:
	return phase == "night"


static func is_night_hour(hour: int) -> bool:
	return is_night_phase(phase_for_hour(hour))


## Screen-space lighting presets for VisionVignetteOverlay.
## Keys: vignette_color, strength, vision_strength, breathe_scale, accent_color
static func lighting_for_phase(phase: String) -> Dictionary:
	match phase:
		"night":
			return {
				"vignette_color": Color(0.02, 0.04, 0.09, 1.0),
				"strength": 0.58,
				"vision_strength": 0.86,
				"breathe_scale": 1.35,
				"accent_color": Color(0.48, 0.56, 0.66, 1.0),
			}
		"dawn":
			return {
				"vignette_color": Color(0.08, 0.04, 0.02, 1.0),
				"strength": 0.48,
				"vision_strength": 0.76,
				"breathe_scale": 1.15,
				"accent_color": Color(0.88, 0.70, 0.29, 1.0),
			}
		"dusk":
			return {
				"vignette_color": Color(0.09, 0.035, 0.025, 1.0),
				"strength": 0.50,
				"vision_strength": 0.78,
				"breathe_scale": 1.2,
				"accent_color": Color(0.88, 0.70, 0.29, 1.0),
			}
		"midday":
			return {
				"vignette_color": Color(0.03, 0.035, 0.03, 1.0),
				"strength": 0.22,
				"vision_strength": 0.48,
				"breathe_scale": 0.7,
				"accent_color": Color(0.84, 0.60, 0.26, 1.0),
			}
		"morning", "afternoon":
			return {
				"vignette_color": Color(0.015, 0.02, 0.015, 1.0),
				"strength": 0.38,
				"vision_strength": 0.72,
				"breathe_scale": 1.0,
				"accent_color": Color(0.84, 0.60, 0.26, 1.0),
			}
		_:
			return lighting_for_phase("morning")


static func lighting_for_hour(hour: int) -> Dictionary:
	return lighting_for_phase(phase_for_hour(hour))
