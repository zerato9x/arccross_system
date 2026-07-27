extends RefCounted
class_name CombatActionDenial

## Structured denial payload for turn-based action gating.
## Replaces print("DENIED: …") control flow so HUD / AI / tests can react.

const CODE_BUSY := "BUSY"
const CODE_REACTION_PENDING := "REACTION_PENDING"
const CODE_DEPRECATED := "DEPRECATED"
const CODE_FEATURE_LOCKED := "FEATURE_LOCKED"
const CODE_STANCE := "STANCE"
const CODE_NOT_YOUR_TURN := "NOT_YOUR_TURN"
const CODE_UNKNOWN_ACTION := "UNKNOWN_ACTION"
const CODE_REACTION_ONLY := "REACTION_ONLY"
const CODE_MELEE_LOCK := "MELEE_LOCK"
const CODE_INSUFFICIENT_AP := "INSUFFICIENT_AP"
const CODE_EMPTY_AP := "EMPTY_AP"

static func make(
	denial_code: String,
	denial_message: String,
	action_type: int = -1,
	actor_name: String = ""
) -> Dictionary:
	return {
		"code": denial_code,
		"message": denial_message,
		"action": action_type,
		"entity_name": actor_name,
	}
