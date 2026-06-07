extends Resource
class_name CombatLaneSlot

# Using our Lexicon from earlier
@export var background: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
@export var current_cover: GameEnums.CoverState = GameEnums.CoverState.NONE

var lane_index: int = -1
var object_durability: float = 100.0
var object_name: String = "None"
var is_spawnable: bool = true # Grids 5 and 6 will turn this off

# The claustrophobic box
var occupants: Array[HumanoidCore] = []
var is_melee_locked: bool = false
var grapple_stance_scale: int = 12 # 12 = Dominant, 6 = Slipping, 0 = Prone

func _init(index: int) -> void:
	lane_index = index

# --- PHYSICAL OCCUPANCY ---

func enter_slot(entity: HumanoidCore) -> bool:
	if not is_spawnable:
		print("Cannot enter No Man's Void.")
		return false
		
	if occupants.size() >= 2:
		print("Slot ", lane_index, " is at capacity. Access denied.")
		return false
		
	occupants.append(entity)
	_evaluate_lock_state()
	return true

func exit_slot(entity: HumanoidCore) -> void:
	if occupants.has(entity):
		occupants.erase(entity)
		_evaluate_lock_state()

func _evaluate_lock_state() -> void:
	if occupants.size() == 2:
		is_melee_locked = true
		grapple_stance_scale = 12 # Start the struggle at a neutral balance
	else:
		is_melee_locked = false
		grapple_stance_scale = 12

# --- COVER PHYSICS ---

func damage_cover(amount: float) -> void:
	if current_cover == GameEnums.CoverState.NONE: 
		return
	
	object_durability = max(0.0, object_durability - amount)
	if object_durability <= 0.0:
		current_cover = GameEnums.CoverState.NONE
		object_name = "Shattered debris"
		

# How much does the background biome ruin your aim? (Percentage penalty)
const VISIBILITY_PENALTIES = {
	GameEnums.GridBiome.PLAINS: 0.0,
	GameEnums.GridBiome.HILLS: 0.10,
	GameEnums.GridBiome.FOREST: 0.25, # 25% miss chance
	GameEnums.GridBiome.MUD: 0.0,
	GameEnums.GridBiome.SWAMP: 0.15 
}

# How likely is the object to physically intercept the bullet?
const COVER_INTERCEPTION_CHANCE = {
	GameEnums.CoverState.NONE: 0.0,
	GameEnums.CoverState.PARTIAL: 0.40, # 40% chance the bullet hits the object
	GameEnums.CoverState.FULL: 0.75      # 75% chance the bullet hits the object
}

func get_visibility_penalty() -> float:
	return VISIBILITY_PENALTIES[background]

func get_cover_interception() -> float:
	# If the cover is destroyed, it intercepts nothing.
	if current_cover == GameEnums.CoverState.NONE:
		return 0.0
	return COVER_INTERCEPTION_CHANCE[current_cover]
