extends Node

## Canonical maximum for authored gameplay meters shared across domain boundaries.
## Ratios may use 0.0-1.0 inside local calculations, but stored meter values use 0-12.
const SCALE_MAX: float = 12.0
const SCALE_MIDPOINT: float = 6.0

# ==========================================
# 1. BIOLOGY & ANATOMY
# ==========================================
## The four immutable genetic pillars used by character generation.
enum Pillar { BRAWN, FINESSE, FORTITUDE, WILL }

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
	NONE = 0,
	INNER_TORSO = 1,
	OUTER_TORSO = 2,
	HAND = 3,
	LEGS = 4,
	FEET = 5,
	BACKPACK = 6,
	SLING = 7,
	BELT = 8,
	VEST = 9,
	HEAD = 10,
	EYES = 11,
	FACE = 12,
	NECK = 13,
	ARMS = 14,
	OFFHAND = 15,
	# Runtime saves and older tests used value 3 under this name.
	HANDS = 3,
}

enum ItemSize { SMALL, AVERAGE, BIG }

# Weapon Classifications
enum WeaponClass { NONE, BLUNT, BLADE, PISTOL, RIFLE, SHOTGUN }

## Functional classification of an item determining which systems interact with it.
enum ItemType {
	JUNK,        ## No mechanical function. Lore objects, trade barter, decoy weight.
	WEAPON,      ## Equips to HANDS. Has DamageType, flesh_damage, stance_damage.
	ARMOR,       ## Equips to torso/legs/feet. Provides PROTECTION and BULK.
	CONSUMABLE,  ## Single-use. Restores hunger, thirst, stops bleeding, fights fatigue.
	TOOL,        ## Contextual world-interaction or campsite equipment.
	AMMUNITION,  ## Loose rounds, magazines, clips, speedloaders, and shells.
	MATERIAL,
	ATTACHMENT
}

## Presentation and content-authoring category. Gameplay behavior remains
## governed by ItemType and the item's authored fields.
enum ItemCategory {
	MISC,
	CAMPING,
	ELECTRONICS,
	MATERIALS,
	MEDICINE,
	NUTRITION,
	TOOLS,
	TRAPS,
	AMMUNITION,
	MELEE_WEAPON,
	FIREARM,
	ARMOR,
	BACKPACK,
	CHEST_RIG,
	EYEWEAR,
	FACEWEAR,
	FOOTWEAR,
	HEADWEAR,
	INNER_TORSO,
	LEGWEAR,
	NECKWEAR,
	OUTER_TORSO,
	ATTACHMENT
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

# ==========================================
# 4. COMBAT LOBBY & ACTIONS
# ==========================================
## Kinetic Burden Tier, measuring how physically restricted an entity is.
enum KineticTier {
	FLUID,     ## Tier 1 (Burden 0-3) - Base costs (1, 2, 3, 4)
	LABORED,   ## Tier 2 (Burden 4-8) - Middle costs (2, 3, 4, 6)
	AGONIZING  ## Tier 3 (Burden 9+) - Severe costs (3, 4, 6, 12)
}

## Physiological equilibrium brackets based on the mandatory Base-12 threshold.
enum StanceState {
	PLANTED,   ## 7 to 12 Points: Full balance. Standard operations.
	STUMBLING, ## 1 to 6 Points: Unbalanced but receives a normal active turn. Threat = 0.
	FELLED     ## 0 Points: Prone/Collapsed. Spends the next turn recovering.
}

## Strict command mapping database for combat resolution parsing.
enum ActionType {
	# --- Non-Duel Actions ---
	MOVE_FORWARD,   # 2 AP: Standard traversal through the 12-lane matrix
	MOVE_BACKWARD,  # 2 AP: Standard traversal backward
	CHARGE,         # 4 AP: Sprints 2 cells forward. Grapple Intercept risk at distance 1.
	SHOOT,          # 4 AP: Fire a ranged weapon at a random body part
	AIMED_SHOT,     # 6 AP: Fire a ranged weapon at a specific target limb
	CYCLE,          # 1 AP: Cycle an action or hand-load one round where supported
	RELOAD,         # 2 AP: Reload through a compatible magazine, clip, or speedloader
	OBJ_INTERACT,   # 4 AP: Interact with the object at any tile
	USE_ITEM,       # 2 AP: Use a consumable from the backpack
	TAKE_COVER,     # 4 AP: Brace behind cover and recover a small amount of Stance.
	
	# --- Duel-Locked Actions ---
	STRIKE,         # Core melee attack. Resolution randomly selects a non-Head Limb Region.
	GRAPPLE,        # Opposed takedown check. Success fells the defender.
	PUSH_STAY,      # 4 AP: Leverage check → displace enemy 1 cell away, initiator stays. Lock breaks.
	PUSH_FOLLOW,    # 4 AP: Leverage check → displace enemy 1 cell away, initiator follows. Lock holds.
	PULL_FOLLOW,    # Leverage check: drag both combatants 1 cell toward the initiator's rear.
	PULL_STAY,      # 4 AP: Leverage check → drag enemy 1 cell closer, initiator stays. Lock breaks.
	BREAK,          # 2 AP: Braced stance attack. Erodes stance points only, no flesh damage.
	DISENGAGE,      # 6 AP: Desperate attempt to tear away from a melee lock
	
	# --- Prone Window Actions ---
	TRIP,           # ALL AP: Ground sweep. Dexterity check to pull standing opponent into FELLED.
	GET_UP,         # 4 AP: Rise from FELLED into STUMBLING with recovery protection.
	EXECUTE,        # Trait-gated finishing action. Disabled until trait ownership exists.
	
	# --- Reaction Strikes (Off-Turn) ---
	BLOCK,          # 3 AP: Absorb a STRIKE. Requires shield or functional arm.
	DODGE,          # 3 AP: Evade ranged or melee attacks. Uses Finesse. Disabled if legs destroyed.
	STAY,           # 0 AP: After successful PUSH — initiator holds position, lock breaks.
	FOLLOW          # 0 AP: After successful PUSH — initiator follows into vacated slot, lock holds.
}

## Specific tactical profiles defining how an entity behaves once inside the combat lane.
enum CombatTactic {
	MARKSMAN,     # Heavily weights SHOOT, DISENGAGE, and TAKE_COVER. Wants to maintain distance.
	BRUTE,        # Heavily weights CHARGE, GRAPPLE, and PUSH_FOLLOW. Wants to force Melee Locks.
	OPPORTUNIST,  # Avoids direct strikes unless opponent is STUMBLING/FELLED. Uses TRIP often.
	DEFENDER      # Heavily weights MOVE_BACKWARD to become a BRACED support. Uses BLOCK often.
}

# ==========================================
# 5. MACRO WORLD & ENVIRONMENT
# ==========================================
enum GridBiome { PLAINS, FOREST, HILLS, MOUNTAIN, MUD, SWAMP }

## Phase 1 uses PLAINS as the only biome. These layers describe what is
## painted and placed on top of that biome without lying to gameplay code.
enum MacroTerrainTile {
	PLAINS_GRASS,
	FOREST_SPARSE,
	MUD_YELLOW,
	SNOW_TRANSITION,
}

enum MacroFloraLayer {
	NONE,
	SHRUBS,
	TREES,
}

enum MacroRockLayer {
	NONE,
	HILLS,
	ROCKS,
}

enum MacroStructureLayer {
	NONE,
	STRUCTURES,
	REMNANTS,
}

enum MacroInteractionType { NONE, POI, ENTITY_COLLISION }
enum PoiAction { SEARCH, CAMP }
enum InteractionItemRole { NONE, SEARCH_TOOL, CAMP_GEAR }
enum TalkAction { THREAT, ROB, CEASEFIRE }
enum NegotiationOutcome { INTIMIDATED, ROB_SUCCESS, CEASEFIRE, COMBAT }
enum AmbushPosition { FAR, STANDARD, CLOSE }

enum EncounterContext { 
	NEUTRAL_MEET,       
	PLAYER_AMBUSH,      
	ENEMY_AMBUSH,       
	DIALOGUE_BREAKDOWN  
}
