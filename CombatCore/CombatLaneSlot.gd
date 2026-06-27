extends Resource
class_name CombatLaneSlot

const PLAINS_GROUND_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/bg_plains.png"
const DIRT_ROAD_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Dirt road 1 StraightA.png"
const MUD_SURFACE_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Earth Patch - Rough - Brown - 2x2.png"
const CRATE_OBJECT_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Homestead Crates Size1.png"
const BARRICADE_OBJECT_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/Structures/barricade 2A.png"
const ROCK_OBJECT_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz1 A.png"
const RUBBLE_OBJECT_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 A.png"

# Using our Lexicon from earlier
@export var background: CombatRules.TileBackground = CombatRules.TileBackground.NONE
@export var current_cover: CombatRules.TileObject = CombatRules.TileObject.NONE

var lane_index: int = -1
var object_durability: float = 100.0
var object_name: String = "None"
var surface_name: String = ""
var surface_asset_path: String = ""
var surface_note: String = ""
var is_spawnable: bool = true # Grids 5 and 6 will turn this off

# The claustrophobic box
var occupants: Array[HumanoidCore] = []
var is_melee_locked: bool = false
var grapple_stance_scale: int = 12 # 12 = Dominant, 6 = Slipping, 0 = Prone

func _init(index: int) -> void:
	lane_index = index

func configure_surface(
	display_name: String,
	asset_path: String = "",
	note: String = ""
) -> void:
	surface_name = display_name
	surface_asset_path = asset_path
	surface_note = note

func get_presentation_descriptor() -> Dictionary:
	return {
		"background_label": get_background_label(),
		"ground_asset": PLAINS_GROUND_ASSET,
		"surface_label": get_surface_label(),
		"surface_asset": get_surface_asset_path(),
		"terrain_modifiers": get_terrain_modifiers(),
		"object_name": get_object_display_name(),
		"object_asset": get_object_asset_path(),
		"object_interactions": get_object_interactions(),
	}

func get_background_label() -> String:
	match background:
		CombatRules.TileBackground.MUD:
			return "MUD"
		CombatRules.TileBackground.TREES:
			return "TREE LINE"
	return "PLAINS"

func get_surface_label() -> String:
	if background == CombatRules.TileBackground.MUD:
		return "EARTH PATCH"
	if not surface_name.strip_edges().is_empty():
		return surface_name
	return "GRASS"

func get_surface_asset_path() -> String:
	if background == CombatRules.TileBackground.MUD:
		return MUD_SURFACE_ASSET
	return surface_asset_path

func get_terrain_modifiers() -> Array[String]:
	var modifiers: Array[String] = []
	match background:
		CombatRules.TileBackground.MUD:
			modifiers.append(
				"MUD: %d%% walk trip, %d%% charge trip, %d%% dodge trip"
				% [
					roundi(CombatRules.MUD_MOVE_TRIP_CHANCE * 100.0),
					roundi(CombatRules.MUD_CHARGE_TRIP_CHANCE * 100.0),
					roundi(CombatRules.MUD_DODGE_TRIP_CHANCE * 100.0),
				]
			)
		CombatRules.TileBackground.TREES:
			modifiers.append("TREE LINE: 25% visibility penalty")
		_:
			modifiers.append("PLAINS GRASS: 0 movement, aim, and trip modifiers")
	if not surface_note.strip_edges().is_empty():
		modifiers.append(surface_note)
	return modifiers

func get_object_display_name() -> String:
	if object_name == "Escape Zone" or object_name == "Shattered debris":
		return object_name
	if current_cover == CombatRules.TileObject.NONE:
		return "NONE"
	if not object_name.strip_edges().is_empty() and object_name != "None":
		return object_name
	return CombatRules.TileObject.keys()[current_cover].capitalize()

func get_object_asset_path() -> String:
	var display_name := get_object_display_name().to_lower()
	if display_name.contains("crate"):
		return CRATE_OBJECT_ASSET
	if display_name.contains("barricade"):
		return BARRICADE_OBJECT_ASSET
	if display_name.contains("rock"):
		return ROCK_OBJECT_ASSET
	if display_name.contains("shattered") or display_name.contains("debris"):
		return RUBBLE_OBJECT_ASSET
	return ""

func get_object_interactions() -> Array[String]:
	var interactions: Array[String] = []
	if object_name == "Escape Zone":
		interactions.append("RETREAT: begin the escape countdown")
	match current_cover:
		CombatRules.TileObject.COVER:
			interactions.append("TAKE COVER: brace behind " + get_object_display_name())
		CombatRules.TileObject.OBSTACLE:
			interactions.append("OBJ INTERACT: vault, bash, or circle the obstacle")
		CombatRules.TileObject.TRAP:
			interactions.append("OBJ INTERACT: inspect or disarm the trap")
	if get_object_display_name().to_lower().contains("crate"):
		interactions.append("SEARCH: loot hook for the object resolver")
	return interactions

# --- PHYSICAL OCCUPANCY ---

func enter_slot(entity: HumanoidCore) -> bool:
	if occupants.has(entity):
		return true
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
	if current_cover == CombatRules.TileObject.NONE:
		return
	
	object_durability = max(0.0, object_durability - amount)
	if object_durability <= 0.0:
		current_cover = CombatRules.TileObject.NONE
		object_name = "Shattered debris"
		

# How much does the background biome ruin your aim? (Percentage penalty)
const VISIBILITY_PENALTIES = {
	CombatRules.TileBackground.NONE: 0.0,
	CombatRules.TileBackground.TREES: 0.25,
	CombatRules.TileBackground.MUD: 0.0,
}

# How likely is the object to physically intercept the bullet?
const COVER_INTERCEPTION_CHANCE = {
	CombatRules.TileObject.NONE: 0.0,
	CombatRules.TileObject.COVER: 0.60,
	CombatRules.TileObject.OBSTACLE: 0.20,
	CombatRules.TileObject.TRAP: 0.0,
}

func get_visibility_penalty() -> float:
	return VISIBILITY_PENALTIES[background]

func get_cover_interception() -> float:
	# If the cover is destroyed, it intercepts nothing.
	if current_cover == CombatRules.TileObject.NONE:
		return 0.0
	return COVER_INTERCEPTION_CHANCE[current_cover]
