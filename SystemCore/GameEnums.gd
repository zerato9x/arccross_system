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
	BACKPACK 
}

# Weapon Classifications
enum WeaponClass { NONE, BLUNT, BLADE, PISTOL, RIFLE }

enum GearStat { PROTECTION_BLUNT, PROTECTION_SHARP, PROTECTION_BALLISTIC, BULK, WEIGHT, THREAT }

## Functional classification of an item determining which systems interact with it.
enum ItemType {
	JUNK,        ## No mechanical function. Lore objects, trade barter, decoy weight.
	WEAPON,      ## Equips to HANDS. Has DamageType, flesh_damage, stance_damage.
	ARMOR,       ## Equips to torso/legs/feet. Provides PROTECTION and BULK.
	CONSUMABLE   ## Single-use. Restores hunger, thirst, stops bleeding, fights fatigue.
}

## Specific metabolic or trauma effect a consumable item applies on use.
enum ConsumableEffect {
	RESTORE_HUNGER,
	RESTORE_THIRST,
	RESTORE_FATIGUE,
	STOP_BLEEDING,
	RESTORE_BLOOD
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
	NON_DUEL,    ## Approach phase maneuvers.
	DUEL_LOCKED, ## Melee lock engagements.
	PRONE_WINDOW ## Options explicitly tied to down-state exploitation or recovery.
}

## Strict command mapping database for combat resolution parsing.
enum ActionType {
	# --- Non-Duel Actions ---
	MOVE_FORWARD,   # Standard traversal through the 12-lane matrix
	MOVE_BACKWARD,
	CHARGE,         # High-AP advance to slam into an enemy and force a Duel Lock
	SHOOT,          # Shoot a player, the player can choose which limb in the LimbRegion section
	CYCLE,          # Cycle your gun, because in this game, every ranged weapon need to cycle between shot, allows the enemy to push effectively, avoiding turtling.
	OBJ_INTERACT,   # Interact with the object at any tile, either [Create Obstacle] or [Set Trap], etc...
	USE_ITEM,       # Use a consumable from the backpack
	
	# --- Duel-Locked Actions ---
	STRIKE,         # Core weapon action aiming for flesh/limb damage
	GRAPPLE,        # High-AP move to force the enemy and yourself in FELLED state, enabling EXCUTE command
	PUSH_STAY,      # Displace enemy Right (Away) and break lock; Player remains
	PUSH_FOLLOW,    # Displace enemy Right and advance lane; Player maintains lock
	PULL_FOLLOW,    # Drag enemy Left (Closer); Player steps back to maintain lock boundaries
	DISENGAGE,      # Desperate attempt to tear away from a melee lock
	
	# --- Prone Window Actions ---
	TRIP,           # Actively yank a stumbling opponent down to the ground
	GET_UP,         # High-AP emergency tax to clear the FELLED state
	EXECUTE         # Auto-critical decapitation strike against FELLED targets
}

# ==========================================
# 5. MACRO WORLD & ENVIRONMENT
# ==========================================
enum GridBiome { PLAINS, FOREST, HILLS, MUD, SWAMP }

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
