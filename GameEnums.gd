extends Node

# --- BIOLOGY & ANATOMY ---
enum Limb { HEAD, TORSO, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }

enum Faction { UNALIGNED, SCAVENGER_CELL, ARCBORN_RESISTANCE, CRAVEN_HIVE }
enum ArcbornTier { NONE, TIER_1, TIER_2, TIER_3 }

# --- ITEMS & INVENTORY ---
enum EquipmentSlot { NONE, BACKPACK, INNER_TORSO, OUTER_TORSO, HANDS }
enum WeaponClass { NONE, BLUNT, BLADE, FIREARM }

# --- GRID & ENVIRONMENT ---
enum CoverState { NONE, PARTIAL, FULL }
enum GridBiome { PLAINS, FOREST, HILLS, MUD, SWAMP }

# --- STATUS CONDITIONS ---
enum TraumaType { NONE, BLEEDING, SHATTERED, BURNT }

# --- ENCOUNTER TYPES ---
enum EncounterContext { 
	NEUTRAL_MEET,       # Both stumbled into each other. Default spawns. Initiative rolled.
	PLAYER_AMBUSH,      # Player stalked them. Player spawns close, Enemy trapped. Player goes first.
	ENEMY_AMBUSH,       # Player stepped on a twig. Enemy spawns close. Enemy goes first.
	DIALOGUE_BREAKDOWN  # A Threaten/Demand went wrong. Both start very close. 
}
# --- AI PERSONALITY & MORALE ---
enum Agenda { 
	SURVIVALIST,   # Flee early. Values their life over everything.
	BELLIGERENT,   # Aggressive. Flee only when severely outmatched or crippled.
	ZEALOT,        # Flee never. Fights to the absolute bitter end.
	MINDLESS       # Cravens. Literally lacks the cognitive ability to run away.
}
