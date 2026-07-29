extends RefCounted
class_name TurnBasedCombatBalance

## Turn-based owns cadence and presentation timing. ItemData remains canonical;
## realtime combat may tune the same weapon through its own balance layer.
##
## Durations are authored near each action's humanoid clip length so
## HumanoidTokenView timed stretch stays inside ~0.75x–1.25x of nominal FPS.
const DEFAULT_PROFILE := {
	"duration": 1.05,
	"cue_fraction": 0.72,
	"recovery": 0.12,
}

const _ACTION_PROFILES := {
	GameEnums.ActionType.SHOOT: {
		"duration": 0.55,
		"cue_fraction": 0.45,
		"recovery": 0.14,
	},
	GameEnums.ActionType.AIMED_SHOT: {
		"duration": 0.90,
		"cue_fraction": 0.50,
		"recovery": 0.18,
	},
	GameEnums.ActionType.RELOAD: {
		"duration": 1.15,
		"cue_fraction": 0.92,
		"recovery": 0.14,
	},
	GameEnums.ActionType.CYCLE: {
		"duration": 0.90,
		"cue_fraction": 0.88,
		"recovery": 0.12,
	},
	GameEnums.ActionType.CLEAR_MALFUNCTION: {
		"duration": 1.10,
		"cue_fraction": 0.92,
		"recovery": 0.14,
	},
	GameEnums.ActionType.STRIKE: {
		"duration": 1.10,
		"cue_fraction": 0.52,
		"recovery": 0.16,
	},
	GameEnums.ActionType.GRAPPLE: {
		"duration": 1.10,
		"cue_fraction": 0.55,
		"recovery": 0.18,
	},
	GameEnums.ActionType.BREAK: {
		"duration": 1.05,
		"cue_fraction": 0.54,
		"recovery": 0.16,
	},
	GameEnums.ActionType.PUSH_STAY: {
		"duration": 1.05,
		"cue_fraction": 0.58,
		"recovery": 0.16,
	},
	GameEnums.ActionType.PULL_FOLLOW: {
		"duration": 1.10,
		"cue_fraction": 0.58,
		"recovery": 0.16,
	},
	GameEnums.ActionType.TAKE_COVER: {
		"duration": 0.95,
		"cue_fraction": 0.90,
		"recovery": 0.12,
	},
	GameEnums.ActionType.GET_UP: {
		"duration": 1.10,
		"cue_fraction": 0.92,
		"recovery": 0.12,
	},
	GameEnums.ActionType.USE_ITEM: {
		"duration": 1.05,
		"cue_fraction": 0.90,
		"recovery": 0.12,
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
