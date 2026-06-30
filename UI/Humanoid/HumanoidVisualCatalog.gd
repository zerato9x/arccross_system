extends RefCounted
class_name HumanoidVisualCatalog

const ROOT_DIR := "res://Asset/humanoid_spritesheets"
const BASE_LAYER_DIR := ROOT_DIR + "/Humanoid/nake_64"
const FRAME_COLUMNS := 15
const DIRECTION_ROWS := 8
const FRAME_SIZE := Vector2i(128, 128)
const DIRECTION_RIGHT := 0
const DIRECTION_DOWN_RIGHT := 1
const DIRECTION_DOWN := 2
const DIRECTION_DOWN_LEFT := 3
const DIRECTION_LEFT := 4
const DIRECTION_UP_LEFT := 5
const DIRECTION_UP := 6
const DIRECTION_UP_RIGHT := 7

const ANIMATION_FPS := {
	"Idle": 5.0,
	"Idle2": 5.0,
	"Idle3": 5.0,
	"Walk": 10.0,
	"Run": 12.0,
	"RunBackwards": 12.0,
	"CrouchIdle": 5.0,
	"CrouchRun": 10.0,
	"Attack1": 12.0,
	"Attack2": 12.0,
	"Attack3": 12.0,
	"Attack4": 12.0,
	"StrafeLeft": 12.0,
	"StrafeRight": 12.0,
	"TakeDamage": 10.0,
	"Taunt": 12.0,
	"Die": 10.0,
}

const NON_LOOPING_ANIMATIONS := [
	"Attack1",
	"Attack2",
	"Attack3",
	"Attack4",
	"StrafeLeft",
	"StrafeRight",
	"TakeDamage",
	"Taunt",
	"Die",
]

const ANIMATION_FRAMES := {
	"Attack1": 5,
}


# Item IDs are presentation aliases, not unique looks. Multiple definitions
# intentionally resolve to the same directory when their Innawoods art matches.
const ITEM_VISUAL_DIRECTORIES := {
	"armor_arcborn": "items/armor/arcbornarmor",
	"armor_makeshift": "items/armor/makeshiftarmor_red",
	"armor_metal": "items/armor/metalarmor_grey",
	"armor_service": "items/armor/servicearmor_tan",
	"backpack_service": "items/backpack/bag_small_service",
	"backpack_service_big": "items/backpack/bag_big_service",
	"backpack_survivalist": "items/backpack/bag_small_survivalist",
	"tornister": "items/backpack/bag_small_tornister",
	"boot_black": "items/foot/boots_black",
	"boot_brown": "items/foot/boots_brown",
	"boot_service": "items/foot/boots_grey",
	"bandana": "items/head/head_bandana_green",
	"boonie": "items/head/head_boonie_green",
	"cap": "items/head/head_cap_grey",
	"cap2": "items/head/head_cap_grey",
	"cap3": "items/head/head_cap_grey",
	"hat_winter": "items/head/head_winter_brown",
	"helmet": "items/head/helmet_green",
	"helmet_2": "items/head/helmet_grey",
	"helmet_3": "items/head/helmet_tan",
	"helmet_service": "items/head/helmet_green",
	"shirt_service": "items/innertorso/serviceshirt_green",
	"shirt_thermo": "items/innertorso/thermoshirt_grey",
	"tanktop": "items/innertorso/tanktop_white",
	"tshirt_black": "items/innertorso/tshirt_black",
	"tshirt_white": "items/innertorso/tshirt_white",
	"pants_carbon": "items/leg/combatpants_carbon",
	"jeans_1": "items/leg/jeans",
	"jeans_2": "items/leg/jeans",
	"pants_black": "items/leg/pants_black",
	"pants_cargo": "items/leg/pants_brown",
	"pants_cargo_camo": "items/leg/pants_camo",
	"pants_khaki": "items/leg/pants_khaki",
	"pants_service": "items/leg/servicepants_olive",
	"shorts_khaki": "items/leg/shorts_khaki",
	"shorts_khaki_2": "items/leg/shorts_khaki",
	"coat": "items/outertorso/jacket_brown",
	"coat_black": "items/outertorso/jacket_black",
	"coat_leather": "items/outertorso/jacket_leather",
	"makeshift_shield": "items/shield",
	"shield_ballistic": "items/shield",
	"ak47": "weapons/guns/ak47",
	"carbon_rifle": "weapons/guns/assaultrifle",
	"service_rifle": "weapons/guns/servicerilfe",
	"shotgun": "weapons/guns/shotgun",
	"carbon_pistol": "weapons/guns/pistol",
	"service_pistol": "weapons/guns/pistol",
	"unique_theoperator": "weapons/guns/pistol",
	"revolver": "weapons/guns/revolver",
	"axe": "weapons/melee/axe",
	"axe_arctic": "weapons/melee/axe",
	"axe_makeshift": "weapons/melee/axe",
	"bat_1": "weapons/melee/bat",
	"bat_2": "weapons/melee/bat",
	"bat_spiked": "weapons/melee/bat",
	"crowbar": "weapons/melee/crowbar",
	"hammer": "weapons/melee/hammer",
	"knife_carbon": "weapons/melee/knife",
	"knife_makeshift": "weapons/melee/knife",
	"knife_service": "weapons/melee/knife",
	"sledgehammer": "weapons/melee/sledgehammer",
	"sword_carbon": "weapons/melee/sword",
}

const LOADOUT_SLOT_KEYS := {
	"backpack_gear": GameEnums.EquipmentSlot.BACKPACK,
	"inner_torso": GameEnums.EquipmentSlot.INNER_TORSO,
	"outer_torso": GameEnums.EquipmentSlot.OUTER_TORSO,
	"legs": GameEnums.EquipmentSlot.LEGS,
	"feet": GameEnums.EquipmentSlot.FEET,
	"vest": GameEnums.EquipmentSlot.VEST,
	"weapon": GameEnums.EquipmentSlot.HAND,
	"offhand": GameEnums.EquipmentSlot.OFFHAND,
}

static var _path_exists_cache: Dictionary = {}

static func appearance_from_equipment_snapshot(equipment: Array) -> Dictionary:
	var slot_item_ids: Dictionary = {}
	for raw_entry in equipment:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var item_id := str(entry.get("id", ""))
		if item_id.is_empty():
			continue
		slot_item_ids[int(entry.get("equipment_slot", 0))] = item_id
	return appearance_from_slot_item_ids(slot_item_ids)


static func appearance_from_record(record: Dictionary) -> Dictionary:
	var slot_item_ids: Dictionary = {}
	var runtime: Dictionary = record.get("runtime", {})
	var inventory_state: Dictionary = runtime.get("inventory", {})
	var equipment_state: Dictionary = inventory_state.get("equipment", {})

	if not equipment_state.is_empty():
		for raw_slot_key in equipment_state.keys():
			var item_state: Dictionary = equipment_state[raw_slot_key]
			var item_id := _item_id_from_runtime_state(item_state)
			if not item_id.is_empty():
				slot_item_ids[int(raw_slot_key)] = item_id
	else:
		var definition_state: Dictionary = record.get("definition", {})
		var loadout_state: Dictionary = definition_state.get("loadout", {})
		for loadout_key in LOADOUT_SLOT_KEYS.keys():
			var item_id := _item_id_from_resource_path(
				str(loadout_state.get(loadout_key, ""))
			)
			if not item_id.is_empty():
				slot_item_ids[LOADOUT_SLOT_KEYS[loadout_key]] = item_id

	return appearance_from_slot_item_ids(slot_item_ids)

static func appearance_from_slot_item_ids(slot_item_ids: Dictionary) -> Dictionary:
	var layers: Array[Dictionary] = []
	var seen_directories: Dictionary = {}
	var unmapped_item_ids: Array[String] = []

	for raw_slot in slot_item_ids.keys():
		var item_id := str(slot_item_ids[raw_slot])
		var relative_directory := str(ITEM_VISUAL_DIRECTORIES.get(item_id, ""))
		if relative_directory.is_empty():
			unmapped_item_ids.append(item_id)
			continue

		var directory := ROOT_DIR + "/" + relative_directory
		if seen_directories.has(directory):
			continue
		seen_directories[directory] = true
		layers.append({
			"directory": directory,
			"order": _layer_order(directory),
		})

	layers.sort_custom(_sort_layers)
	var signature_parts: Array[String] = [BASE_LAYER_DIR]
	for layer in layers:
		signature_parts.append(str(layer.get("directory", "")))

	return {
		"base_directory": BASE_LAYER_DIR,
		"layers": layers,
		"signature": "|".join(signature_parts),
		"unmapped_item_ids": unmapped_item_ids,
	}

static func layer_directories(appearance: Dictionary) -> Array[String]:
	var directories: Array[String] = []
	var base_directory := str(
		appearance.get("base_directory", BASE_LAYER_DIR)
	)
	if not base_directory.is_empty():
		directories.append(base_directory)
	for raw_layer in appearance.get("layers", []):
		var layer: Dictionary = raw_layer
		var directory := str(layer.get("directory", ""))
		if not directory.is_empty():
			directories.append(directory)
	return directories

static func texture_path(directory: String, animation: String) -> String:
	var requested_animation := (
		animation if supports_animation(animation) else "Idle"
	)
	var requested_path := "%s/%s.png" % [directory, requested_animation]
	if _resource_exists(requested_path):
		return requested_path

	var idle_path := "%s/Idle.png" % directory
	return idle_path if _resource_exists(idle_path) else ""

static func supports_animation(animation: String) -> bool:
	return ANIMATION_FPS.has(animation)

static func animation_frames(animation: String) -> int:
	return int(ANIMATION_FRAMES.get(animation, FRAME_COLUMNS))

static func animation_fps(animation: String) -> float:
	return float(ANIMATION_FPS.get(animation, ANIMATION_FPS["Idle"]))

static func animation_loops(animation: String) -> bool:
	return animation not in NON_LOOPING_ANIMATIONS

static func direction_row_for_vector(direction: Vector2) -> int:
	if direction.length_squared() <= 0.001:
		return DIRECTION_DOWN
	var angle := atan2(direction.y, direction.x)
	return posmod(
		int(round(angle / (PI / 4.0))),
		DIRECTION_ROWS
	)

static func layer_depth(directory: String, direction_row: int) -> int:
	if directory == BASE_LAYER_DIR:
		return 10
	if "/items/backpack/" in directory:
		return (
			48
			if direction_row in [
				DIRECTION_UP_LEFT,
				DIRECTION_UP,
				DIRECTION_UP_RIGHT,
			]
			else 15
		)
	return _layer_order(directory)

static func visual_directory_for_item_id(item_id: String) -> String:
	var relative_directory := str(ITEM_VISUAL_DIRECTORIES.get(item_id, ""))
	return (
		ROOT_DIR + "/" + relative_directory
		if not relative_directory.is_empty()
		else ""
	)

static func _item_id_from_runtime_state(item_state: Dictionary) -> String:
	var definition_state: Dictionary = item_state.get("definition", {})
	var item_id := str(definition_state.get("id", ""))
	if not item_id.is_empty():
		return item_id
	return _item_id_from_resource_path(
		str(item_state.get("template_path", ""))
	)

static func _item_id_from_resource_path(path: String) -> String:
	if path.is_empty():
		return ""
	return path.get_file().get_basename()

static func _layer_order(directory: String) -> int:
	if "/items/backpack/" in directory:
		return 0
	if "/items/leg/" in directory:
		return 20
	if "/items/foot/" in directory:
		return 25
	if "/items/innertorso/" in directory:
		return 30
	if "/items/outertorso/" in directory:
		return 40
	if "/items/armor/" in directory:
		return 45
	if "/items/head/" in directory:
		return 50
	if directory.ends_with("/items/shield"):
		return 65
	if "/weapons/" in directory:
		return 70
	return 60

static func _sort_layers(left: Dictionary, right: Dictionary) -> bool:
	var left_order := int(left.get("order", 0))
	var right_order := int(right.get("order", 0))
	if left_order == right_order:
		return str(left.get("directory", "")) < str(
			right.get("directory", "")
		)
	return left_order < right_order

static func _resource_exists(path: String) -> bool:
	if not _path_exists_cache.has(path):
		_path_exists_cache[path] = ResourceLoader.exists(path)
	return bool(_path_exists_cache[path])
