extends Node
class_name GameEnums

# ==========================================
# 1. BIOLOGY & ANATOMY (The Meat)
# ==========================================
# Core DNA. Cap at 12. Does NOT dictate raw combat numbers.
# Used for contextual actions, world interaction, and trauma resistance.
enum Stat { BRAWN, FINESSE, FORTITUDE, WILL }

# The expanded butcher shop. 
# Upper/Lower Torso will have separate logic for internal organ failure.
enum Limb { 
	HEAD, 
	UPPER_TORSO, 
	LOWER_TORSO, 
	LEFT_SHOULDER, 
	RIGHT_SHOULDER, 
	LEFT_ARM, 
	RIGHT_ARM, 
	LEFT_THIGH, 
	RIGHT_THIGH, 
	LEFT_LEG, 
	RIGHT_LEG 
}

# ==========================================
# 2. GEAR & INVENTORY (The Metal)
# ==========================================
# The layered clothing system.
enum EquipmentSlot { 
	NONE, 
	HEAD, 
	EYES, 
	FACE, 
	MOUTH, 
	INNER_TORSO, 
	OUTER_TORSO, 
	HANDS, 
	LEGS, 
	FEET, 
	BACKPACK 
}

# Weapon Classifications
enum WeaponClass { NONE, BLUNT, BLADE, PISTOL, RIFLE, ENERGY_RIFLE } # 6 type of weapons but 3 Sprites Silhoullete Style on both Macro and Duel scenes to minimize resources

# The specific types of trauma a weapon/hazard can inflict
enum DamageType { 
	BLUNT,        # Crushes bones, drains AP, cause by BLUNT and FIST.
	SHARP,        # Causes bleeding, shreds unarmored tissue, caused by BLADE, PISTOL and RIFLE.
	THERMAL,      # Burns, massive morale damage, caused by environment (WIP).
	ARC           # Metaphysical/Anomalous, caused by ENERGY_RIFLE
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

# ==========================================
# 4. COMBAT LOBBY & ACTIONS
# ==========================================
enum CombatAction {
	STRIKE,       
	SHOOT,        
	RELOAD,       
	REPOSITION,   # AP cost multiplied by gear WEIGHT
	THREATEN,     # Contextual action based on gear THREAT vs Enemy WILL
	USE_GEAR,     
	PUSH_FOLLOW,
	PUSH_STAY,
	PULL,
	FLEE          
}

enum CoverState { NONE, PARTIAL, FULL }

# ==========================================
# 5. MACRO WORLD & ENVIRONMENT
# ==========================================
enum GridBiome { PLAINS, FOREST, HILLS, MUD, SWAMP }

enum EncounterContext { 
	NEUTRAL_MEET,       
	PLAYER_AMBUSH,      
	ENEMY_AMBUSH,       
	DIALOGUE_BREAKDOWN  
}
