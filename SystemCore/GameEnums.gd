extends Node

# ==========================================
# 1. BIOLOGY & ANATOMY
# ==========================================
enum Genetics { BRAWN, FINESSE, FORTITUDE, WILL }

## Specific anatomical grouping targets required for the surgical trauma framework.
enum LimbRegion {
	HEAD,
	UPPER_TORSO, # Lungs, Heart, Ribcage
	LOWER_TORSO, # Stomach, Internal Organs
	LEFT_ARM,    # Shoulders down
	RIGHT_ARM,
	LEFT_LEG,    # Thighs down
	RIGHT_LEG
}

# The specific types of trauma a weapon/hazard can inflict
enum TraumaType { 
	NONE, 
	BLEEDING, 
	SHATTERED_LIMB, 
	ORGAN_FAILURE, 
	BURNT 
}

# ==========================================
# 2. ITEMS & INVENTORY
# ==========================================
enum EquipmentSlot { 
	NONE, 
	INNER_TORSO, 
	OUTER_TORSO, 
	HANDS, 
	LEGS, 
	FEET, 
	BACKPACK,
	SLING,     # For Rifles / Long Melee
	BELT,      # For Pistols / Short Melee
	VEST       # For Magazines / Armor Rigs
}

# Weapon Classifications
enum WeaponClass { NONE, BLUNT, BLADE, PISTOL, RIFLE }

enum GearStat { PROTECTION_BLUNT, PROTECTION_SHARP, PROTECTION_BALLISTIC, BULK, WEIGHT, THREAT }

## Functional classification of an item determining which systems interact with it.
enum ItemType {
	JUNK,        ## No mechanical function. Lore objects, trade barter, decoy weight.
	WEAPON,      ## Equips to HANDS. Has DamageType, flesh_damage, stance_damage.
	ARMOR,       ## Equips to torso/legs/feet. Provides PROTECTION and BULK.
	CONSUMABLE,  ## Single-use. Restores hunger, thirst, stops bleeding, fights fatigue.
	TOOL         ## Contextual world-interaction or campsite equipment.
}

## Specific metabolic or trauma effect a consumable item applies on use.
enum ConsumableEffect {
	RESTORE_HUNGER,
	RESTORE_THIRST,
	RESTORE_FATIGUE,
	STOP_BLEEDING,
	RESTORE_BLOOD
}

## Biological crisis conditions broadcast by the body when survival metrics hit critical.
enum MetabolicCondition {
	STARVING,
	DEHYDRATED,
	EXHAUSTED,
	HYPOTHERMIA
}

## The physical vector mechanics of a wound. Determines protective math and trauma.
enum DamageType {
	BLUNT,     ## Bypasses armor to destroy STANCE/equilibrium. Low flesh damage.
	SHARP,     ## Targets flesh directly. Inflicts severe bleeding and lacerations.
	BALLISTIC  ## Hyper-lethal projectiles. Bypasses standard defense outside of a Duel.
}

# ==========================================
# 3. IDENTITY, FACTION & METAPHYSICS
# ==========================================
enum Faction { UNALIGNED, SCAVENGER_CELL, ARCBORN_RESISTANCE, CRAVEN_HIVE }
enum ArcbornTier { NONE, TIER_1, TIER_2, TIER_3 }

## Neutral runtime identity used by world-state records.
enum RuntimeEntityKind { PLAYER, NPC }

## Persistent lifecycle state. Rendered nodes are only projections of this state.
enum EntityLifeState { ALIVE, DEAD }

## Macro-world disposition is separate from biological life state.
enum EntityWorldStatus { HOSTILE, CEASEFIRE, WITHDRAWN }

## Cross-system combat result. CombatCore emits this instead of exposing internals.
enum CombatOutcome {
	PLAYER_VICTORY,
	PLAYER_DEFEAT,
	PLAYER_ESCAPED,
	ENEMY_ESCAPED,
	DRAW
}

# AI Agendas heavily rely on the new THREAT stat from player gear
enum Agenda { 
	SURVIVALIST,   # Flees immediately if Player THREAT > Enemy WILL
	BELLIGERENT,   # Fights until severely crippled or out-Threatened
	ZEALOT,        # Ignores THREAT. Fights to the bitter end.
	MINDLESS       # No self-preservation. Ignores THREAT completely.
}

## Behavioral templates dictating friendly-fire thresholds and brace logic parameters.
enum FactionAITemperament {
	AGGRESSIVE_SCAVENGER, # Desperate. Willing to take high-risk friendly-fire volleys.
	COORDINATED_ELITE     # Strategic. Routinely steps into BRACED lines to protect frontlines.
}

# ==========================================
# 4. COMBAT LOBBY & ACTIONS
# ==========================================
## Kinetic Burden Tier, measuring how physically restricted an entity is.
enum KineticTier {
	FLUID,     ## Tier 1 (Burden 0-3) - Base costs (1, 2, 3, 4)
	LABORED,   ## Tier 2 (Burden 4-8) - Middle costs (2, 3, 4, 6)
	AGONIZING  ## Tier 3 (Burden 9+) - Severe costs (3, 4, 6, 12)
}

## Mathematical categorization of action costs. Scales via KineticTier.
enum ActionCategory {
	QUICK,     ## 1 / 2 / 3 AP
	MINOR,     ## 2 / 3 / 4 AP
	MAJOR,     ## 3 / 4 / 6 AP
	HEAVY,     ## 4 / 6 / 12 AP
	FREE,      ## 0 AP
	ALL_AP     ## Consumes all remaining AP
}

## Physiological equilibrium brackets based on the mandatory Base-12 threshold.
enum StanceState {
	PLANTED,   ## 7 to 12 Points: Full balance. Standard operations.
	STUMBLING, ## 1 to 6 Points: Unbalanced. Restricted abilities, flee disabled, Threat = 0.
	FELLED     ## 0 Points: Prone/Collapsed. Loss of turn, open to execution.
}

## Engagement status of an entity relative to its current spatial context.
enum DuelState {
	NONE,   ## Skirmish mode. Out of melee locks; fully exposed to ballistic mapping.
	LOCKED, ## 1v1 Melee Locked state. Left-Right spatial rules and Stance mapping apply.
	BRACED  ## Rear-occupant support status. Auto-anchors allies and focuses on stance breaking.
}

## Contextual category boundaries to segregate action eligibility.
enum ActionGroup {
	NON_DUEL,     ## Approach phase maneuvers.
	DUEL_LOCKED,  ## Melee lock engagements.
	PRONE_WINDOW, ## Options explicitly tied to down-state exploitation or recovery.
	REACTION      ## Defensive abilities triggered during the opponent's active turn.
}

## Strict command mapping database for combat resolution parsing.
enum ActionType {
	# --- Non-Duel Actions ---
	MOVE_FORWARD,   # 2 AP: Standard traversal through the 12-lane matrix
	MOVE_BACKWARD,  # 2 AP: Standard traversal backward
	CHARGE,         # 4 AP: Sprints 2 cells forward. Grapple Intercept risk at distance 1.
	SHOOT,          # 4 AP: Fire a ranged weapon at a random body part
	AIMED_SHOT,     # 6 AP: Fire a ranged weapon at a specific target limb
	CYCLE,          # 1 AP: Manually cycle a rifle bolt between shots
	RELOAD,         # 2 AP: Refill a pistol's internal magazine from backpack ammo
	OBJ_INTERACT,   # 4 AP: Interact with the object at any tile
	USE_ITEM,       # 2 AP: Use a consumable from the backpack
	TAKE_COVER,     # 4 AP: Drop profile. Sets stance to 1 (STUMBLING floor). Evasion bonus.
	
	# --- Duel-Locked Actions ---
	STRIKE,         # 4 AP: Core weapon action aiming for flesh/limb damage (no Head targeting)
	GRAPPLE,        # 6 AP: Force both entities into FELLED. Opens 2 AP EXECUTE reaction window.
	PUSH_STAY,      # 4 AP: Leverage check → displace enemy 1 cell away, initiator stays. Lock breaks.
	PUSH_FOLLOW,    # 4 AP: Leverage check → displace enemy 1 cell away, initiator follows. Lock holds.
	PULL_FOLLOW,    # 4 AP: Leverage check → drag enemy 1 cell closer, initiator steps back. Lock holds.
	PULL_STAY,      # 4 AP: Leverage check → drag enemy 1 cell closer, initiator stays. Lock breaks.
	BREAK,          # 4 AP: Braced stance attack. Erodes stance points only, no flesh damage.
	DISENGAGE,      # 6 AP: Desperate attempt to tear away from a melee lock
	
	# --- Prone Window Actions ---
	TRIP,           # ALL AP: Ground sweep. Dexterity check to pull standing opponent into FELLED.
	GET_UP,         # ALL AP: Emergency tax. Clears FELLED, restores stance to 12.
	EXECUTE,        # 2 AP: Instant kill on a FELLED opponent in the same grid slot.
	
	# --- Reaction Strikes (Off-Turn) ---
	BLOCK,          # 3 AP: Absorb a STRIKE. Requires shield or functional arm.
	DODGE,          # 3 AP: Evade ranged or melee attacks. Uses Finesse. Disabled if legs destroyed.
	STAY,           # 0 AP: After successful PUSH — initiator holds position, lock breaks.
	FOLLOW          # 0 AP: After successful PUSH — initiator follows into vacated slot, lock holds.
}

## Maps each ActionType to its required context group for gatekeeper validation.
const ACTION_GROUPS = {
	# --- Non-Duel ---
	ActionType.MOVE_FORWARD: ActionGroup.NON_DUEL,
	ActionType.MOVE_BACKWARD: ActionGroup.NON_DUEL,
	ActionType.CHARGE: ActionGroup.NON_DUEL,
	ActionType.SHOOT: ActionGroup.NON_DUEL,
	ActionType.AIMED_SHOT: ActionGroup.NON_DUEL,
	ActionType.CYCLE: ActionGroup.NON_DUEL,
	ActionType.RELOAD: ActionGroup.NON_DUEL,
	ActionType.OBJ_INTERACT: ActionGroup.NON_DUEL,
	ActionType.USE_ITEM: ActionGroup.NON_DUEL,
	ActionType.TAKE_COVER: ActionGroup.NON_DUEL,
	# --- Duel-Locked ---
	ActionType.STRIKE: ActionGroup.DUEL_LOCKED,
	ActionType.GRAPPLE: ActionGroup.DUEL_LOCKED,
	ActionType.PUSH_STAY: ActionGroup.DUEL_LOCKED,
	ActionType.PUSH_FOLLOW: ActionGroup.DUEL_LOCKED,
	ActionType.PULL_FOLLOW: ActionGroup.DUEL_LOCKED,
	ActionType.PULL_STAY: ActionGroup.DUEL_LOCKED,
	ActionType.BREAK: ActionGroup.DUEL_LOCKED,
	ActionType.DISENGAGE: ActionGroup.DUEL_LOCKED,
	# --- Prone Window ---
	ActionType.TRIP: ActionGroup.PRONE_WINDOW,
	ActionType.GET_UP: ActionGroup.PRONE_WINDOW,
	ActionType.EXECUTE: ActionGroup.PRONE_WINDOW,
	# --- Reactions (off-turn, consume leftover AP) ---
	ActionType.BLOCK: ActionGroup.REACTION,
	ActionType.DODGE: ActionGroup.REACTION,
	ActionType.STAY: ActionGroup.REACTION,
	ActionType.FOLLOW: ActionGroup.REACTION,
}

## Specific tactical profiles defining how an entity behaves once inside the combat lane.
enum CombatTactic {
	MARKSMAN,     # Heavily weights SHOOT, DISENGAGE, and TAKE_COVER. Wants to maintain distance.
	BRUTE,        # Heavily weights CHARGE, GRAPPLE, and PUSH_FOLLOW. Wants to force Melee Locks.
	OPPORTUNIST,  # Avoids direct strikes unless opponent is STUMBLING/FELLED. Uses TRIP often.
	DEFENDER      # Heavily weights MOVE_BACKWARD to become a BRACED support. Uses BLOCK often.
}

## Base scoring multipliers for each tactic when healthy.
const TACTIC_MULTIPLIERS = {
	CombatTactic.MARKSMAN: {
		ActionType.SHOOT: 2.0, ActionType.AIMED_SHOT: 2.5, ActionType.RELOAD: 2.0, ActionType.CYCLE: 2.0,
		ActionType.TAKE_COVER: 1.5, ActionType.DISENGAGE: 2.0, ActionType.MOVE_BACKWARD: 1.5,
		ActionType.CHARGE: 0.1, ActionType.GRAPPLE: 0.0, ActionType.STRIKE: 0.5
	},
	CombatTactic.BRUTE: {
		ActionType.CHARGE: 2.5, ActionType.GRAPPLE: 2.5, ActionType.STRIKE: 1.5,
		ActionType.PUSH_FOLLOW: 2.0, ActionType.MOVE_FORWARD: 2.0,
		ActionType.SHOOT: 0.5, ActionType.TAKE_COVER: 0.0, ActionType.MOVE_BACKWARD: 0.1
	},
	CombatTactic.OPPORTUNIST: {
		ActionType.TRIP: 3.0, ActionType.EXECUTE: 2.5, ActionType.TAKE_COVER: 1.5,
		ActionType.CHARGE: 0.5, ActionType.STRIKE: 0.8
	},
	CombatTactic.DEFENDER: {
		ActionType.MOVE_BACKWARD: 2.0, ActionType.TAKE_COVER: 2.0, ActionType.BREAK: 2.0,
		ActionType.BLOCK: 2.0, ActionType.CHARGE: 0.2, ActionType.GRAPPLE: 0.5
	}
}

## Override multipliers when an entity is injured, bleeding, or severely unbalanced.
## Survival bias overrides their standard training to prioritize staying alive.
const SURVIVAL_MULTIPLIERS = {
	ActionType.USE_ITEM: 3.0,        # Desperate to heal
	ActionType.DISENGAGE: 3.0,       # Desperate to escape Melee Locks
	ActionType.MOVE_BACKWARD: 2.5,   # Fleeing backward
	ActionType.TAKE_COVER: 2.5,      # Trying not to get shot
	ActionType.GET_UP: 3.0,          # Desperate to not get executed
	ActionType.DODGE: 2.0,
	ActionType.BLOCK: 2.0,
	ActionType.CHARGE: 0.0,          # Won't charge if bleeding out
	ActionType.GRAPPLE: 0.0          # Won't grapple if heavily injured
}

# ==========================================
# 5. MACRO WORLD & ENVIRONMENT
# ==========================================
enum GridBiome { PLAINS, FOREST, HILLS, MUD, SWAMP }

enum MacroInteractionType { NONE, POI, ENTITY_COLLISION }
enum PoiAction { SEARCH, CAMP }
enum InteractionItemRole { NONE, SEARCH_TOOL, CAMP_GEAR }
enum TalkAction { THREAT, ROB, CEASEFIRE }
enum NegotiationOutcome { INTIMIDATED, ROB_SUCCESS, CEASEFIRE, COMBAT }
enum AmbushPosition { FAR, STANDARD, CLOSE }

## Passive floor attributes continuously evaluated by the CombatLaneManager.
enum TileBackground {
	NONE,      # Neutral lane structural surface
	TREES,     # Increase dodge change from ranged attack
	MUD,       # Increase AP spend to move
}

## Destructible environmental objects placed into grid cells to disrupt lane lines.
enum TileObject {
	NONE,
	COVER,     # Provides ballistic hit-chance mitigation arrays until crushed
	OBSTACLE,  # Physically present debris requiring AP to move
	TRAP       # Rigged macro-world asset slated to explode upon target interaction
}

enum EncounterContext { 
	NEUTRAL_MEET,       
	PLAYER_AMBUSH,      
	ENEMY_AMBUSH,       
	DIALOGUE_BREAKDOWN  
}
