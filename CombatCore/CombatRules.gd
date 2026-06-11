extends RefCounted
class_name CombatRules

## Temporary feature gate. EXECUTE remains a shared command ID so a future
## trait can unlock it without changing the cross-system contract.
const EXECUTE_ENABLED: bool = false

## Stance recovery tuning. GET_UP consumes the active turn and restores a
## Felled combatant to Stumbling with temporary knockdown protection.
const FELLED_RECOVERY_POINTS: int = 6
const STUMBLING_TURN_RECOVERY: int = 2
const TAKE_COVER_STANCE_RECOVERY: int = 2

## Mathematical categorization of action costs. Scales through KineticTier.
enum ActionCategory {
	QUICK,
	MINOR,
	MAJOR,
	HEAVY,
	FREE,
	ALL_AP,
}

## Combat-local contexts used to gate action eligibility.
enum ActionGroup {
	NON_DUEL,
	DUEL_LOCKED,
	PRONE_WINDOW,
	REACTION,
}

## Passive lane surface properties evaluated inside CombatCore.
enum TileBackground {
	NONE,
	TREES,
	MUD,
}

## Destructible or interactive objects occupying combat lanes.
enum TileObject {
	NONE,
	COVER,
	OBSTACLE,
	TRAP,
}

const ACTION_GROUPS := {
	GameEnums.ActionType.MOVE_FORWARD: ActionGroup.NON_DUEL,
	GameEnums.ActionType.MOVE_BACKWARD: ActionGroup.NON_DUEL,
	GameEnums.ActionType.CHARGE: ActionGroup.NON_DUEL,
	GameEnums.ActionType.SHOOT: ActionGroup.NON_DUEL,
	GameEnums.ActionType.AIMED_SHOT: ActionGroup.NON_DUEL,
	GameEnums.ActionType.CYCLE: ActionGroup.NON_DUEL,
	GameEnums.ActionType.RELOAD: ActionGroup.NON_DUEL,
	GameEnums.ActionType.OBJ_INTERACT: ActionGroup.NON_DUEL,
	GameEnums.ActionType.USE_ITEM: ActionGroup.NON_DUEL,
	GameEnums.ActionType.TAKE_COVER: ActionGroup.NON_DUEL,
	GameEnums.ActionType.STRIKE: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.GRAPPLE: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.PUSH_STAY: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.PUSH_FOLLOW: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.PULL_FOLLOW: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.PULL_STAY: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.BREAK: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.DISENGAGE: ActionGroup.DUEL_LOCKED,
	GameEnums.ActionType.TRIP: ActionGroup.PRONE_WINDOW,
	GameEnums.ActionType.GET_UP: ActionGroup.PRONE_WINDOW,
	GameEnums.ActionType.EXECUTE: ActionGroup.PRONE_WINDOW,
	GameEnums.ActionType.BLOCK: ActionGroup.REACTION,
	GameEnums.ActionType.DODGE: ActionGroup.REACTION,
	GameEnums.ActionType.STAY: ActionGroup.REACTION,
	GameEnums.ActionType.FOLLOW: ActionGroup.REACTION,
}

const TACTIC_MULTIPLIERS := {
	GameEnums.CombatTactic.MARKSMAN: {
		GameEnums.ActionType.SHOOT: 2.0,
		GameEnums.ActionType.AIMED_SHOT: 2.5,
		GameEnums.ActionType.RELOAD: 2.0,
		GameEnums.ActionType.CYCLE: 2.0,
		GameEnums.ActionType.TAKE_COVER: 1.5,
		GameEnums.ActionType.DISENGAGE: 2.0,
		GameEnums.ActionType.MOVE_BACKWARD: 1.5,
		GameEnums.ActionType.CHARGE: 0.1,
		GameEnums.ActionType.GRAPPLE: 0.0,
		GameEnums.ActionType.STRIKE: 0.5,
	},
	GameEnums.CombatTactic.BRUTE: {
		GameEnums.ActionType.CHARGE: 2.5,
		GameEnums.ActionType.GRAPPLE: 2.5,
		GameEnums.ActionType.STRIKE: 1.5,
		GameEnums.ActionType.PUSH_FOLLOW: 2.0,
		GameEnums.ActionType.MOVE_FORWARD: 2.0,
		GameEnums.ActionType.SHOOT: 0.5,
		GameEnums.ActionType.TAKE_COVER: 0.0,
		GameEnums.ActionType.MOVE_BACKWARD: 0.1,
	},
	GameEnums.CombatTactic.OPPORTUNIST: {
		GameEnums.ActionType.TRIP: 3.0,
		GameEnums.ActionType.TAKE_COVER: 1.5,
		GameEnums.ActionType.CHARGE: 0.5,
		GameEnums.ActionType.STRIKE: 0.8,
	},
	GameEnums.CombatTactic.DEFENDER: {
		GameEnums.ActionType.MOVE_BACKWARD: 2.0,
		GameEnums.ActionType.TAKE_COVER: 2.0,
		GameEnums.ActionType.BREAK: 2.0,
		GameEnums.ActionType.BLOCK: 2.0,
		GameEnums.ActionType.CHARGE: 0.2,
		GameEnums.ActionType.GRAPPLE: 0.5,
	},
}

const SURVIVAL_MULTIPLIERS := {
	GameEnums.ActionType.USE_ITEM: 3.0,
	GameEnums.ActionType.DISENGAGE: 3.0,
	GameEnums.ActionType.MOVE_BACKWARD: 2.5,
	GameEnums.ActionType.TAKE_COVER: 2.5,
	GameEnums.ActionType.GET_UP: 3.0,
	GameEnums.ActionType.DODGE: 2.0,
	GameEnums.ActionType.BLOCK: 2.0,
	GameEnums.ActionType.CHARGE: 0.0,
	GameEnums.ActionType.GRAPPLE: 0.0,
}
