extends RefCounted
class_name TurnBasedCombatBalance

## Turn-based owns cadence and presentation timing. ItemData remains canonical;
## realtime combat may tune the same weapon through its own balance layer.
const DEFAULT_PROFILE := {
	"duration": 0.62,
	"cue_fraction": 0.72,
	"recovery": 0.10,
}

const _ACTION_PROFILES := {
	GameEnums.ActionType.SHOOT: {
		"duration": 0.72,
		"cue_fraction": 0.42,
		"recovery": 0.16,
	},
	GameEnums.ActionType.AIMED_SHOT: {
		"duration": 1.05,
		"cue_fraction": 0.62,
		"recovery": 0.20,
	},
	GameEnums.ActionType.RELOAD: {
		"duration": 1.15,
		"cue_fraction": 0.96,
		"recovery": 0.12,
	},
	GameEnums.ActionType.CYCLE: {
		"duration": 0.58,
		"cue_fraction": 0.88,
		"recovery": 0.08,
	},
	GameEnums.ActionType.CLEAR_MALFUNCTION: {
		"duration": 0.92,
		"cue_fraction": 0.92,
		"recovery": 0.12,
	},
	GameEnums.ActionType.STRIKE: {
		"duration": 0.78,
		"cue_fraction": 0.56,
		"recovery": 0.16,
	},
	GameEnums.ActionType.GRAPPLE: {
		"duration": 0.90,
		"cue_fraction": 0.58,
		"recovery": 0.18,
	},
	GameEnums.ActionType.BREAK: {
		"duration": 0.82,
		"cue_fraction": 0.56,
		"recovery": 0.16,
	},
	GameEnums.ActionType.PUSH_STAY: {
		"duration": 0.82,
		"cue_fraction": 0.60,
		"recovery": 0.16,
	},
	GameEnums.ActionType.PULL_FOLLOW: {
		"duration": 0.86,
		"cue_fraction": 0.62,
		"recovery": 0.16,
	},
	GameEnums.ActionType.TAKE_COVER: {
		"duration": 0.68,
		"cue_fraction": 0.92,
		"recovery": 0.10,
	},
	GameEnums.ActionType.GET_UP: {
		"duration": 0.88,
		"cue_fraction": 0.94,
		"recovery": 0.10,
	},
	GameEnums.ActionType.USE_ITEM: {
		"duration": 0.76,
		"cue_fraction": 0.92,
		"recovery": 0.10,
	},
}


static func presentation_profile(action: int) -> Dictionary:
	return (
		_ACTION_PROFILES.get(action, DEFAULT_PROFILE) as Dictionary
	).duplicate(true)


static func duration(action: int) -> float:
	return float(presentation_profile(action).duration)


static func cue_fraction(action: int) -> float:
	return float(presentation_profile(action).cue_fraction)


static func recovery(action: int) -> float:
	return float(presentation_profile(action).recovery)
