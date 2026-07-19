extends Control

const EQUIPPED_ITEMS := [
	["res://ItemCore/Items/helmet_service.tres", GameEnums.EquipmentSlot.HEAD, 10.8],
	["res://ItemCore/Items/goggles.tres", GameEnums.EquipmentSlot.EYES, 8.1],
	["res://ItemCore/Items/mask_gas.tres", GameEnums.EquipmentSlot.FACE, 7.4],
	["res://ItemCore/Items/scarf_red.tres", GameEnums.EquipmentSlot.NECK, 11.0],
	["res://ItemCore/Items/shirt_thermo.tres", GameEnums.EquipmentSlot.INNER_TORSO, 9.5],
	["res://ItemCore/Items/armor_service.tres", GameEnums.EquipmentSlot.OUTER_TORSO, 5.2],
	["res://ItemCore/Items/webbing_service.tres", GameEnums.EquipmentSlot.VEST, 8.7],
	["res://ItemCore/Items/armour_arms.tres", GameEnums.EquipmentSlot.ARMS, 4.4],
	["res://ItemCore/Items/pants_service.tres", GameEnums.EquipmentSlot.LEGS, 6.8],
	["res://ItemCore/Items/boot_service.tres", GameEnums.EquipmentSlot.FEET, 10.0],
	["res://ItemCore/Items/service_rifle.tres", GameEnums.EquipmentSlot.HAND, 7.1],
	["res://ItemCore/Items/belt.tres", GameEnums.EquipmentSlot.BELT, 8.8],
	["res://ItemCore/Items/backpack_service.tres", GameEnums.EquipmentSlot.BACKPACK, 9.2],
]

@onready var inventory_ui: InventoryUI = %InventoryUI


func _ready() -> void:
	var equipment: Array[Dictionary] = []
	for entry: Array in EQUIPPED_ITEMS:
		var item := load(str(entry[0])) as ItemData
		if item == null:
			push_error("Paper-doll preview could not load %s." % entry[0])
			continue
		equipment.append(_descriptor(item, int(entry[1]), float(entry[2])))
	inventory_ui.open_inventory({
		"coords": Vector2i(4, -2),
		"current_capacity": 28,
		"maximum_capacity": 42,
		"capacity_breakdown": [
			{"name": "Service backpack", "capacity": 18},
			{"name": "Belt", "capacity": 4},
		],
		"equipment": equipment,
		"containers": [],
		"backpack": [],
		"ground": [],
		"limbs": [],
		"loadout_stats": {
			"weight": 24.6,
			"bulk": 8.2,
			"threat": 14.0,
			"insulation": 5.5,
			"protection_blunt": 8.5,
			"protection_sharp": 9.0,
			"protection_ballistic": 11.5,
			"kinetic_tier": "HEAVY",
		},
	}, "Authored equipment stage preview", true)


func _descriptor(item: ItemData, slot: int, condition: float) -> Dictionary:
	return {
		"instance_id": "%s_preview" % item.id,
		"item_id": item.id,
		"name": item.display_name,
		"description": item.lore_description,
		"item_type": item.item_type,
		"catalog_category": item.catalog_category,
		"item_grade": item.item_grade,
		"condition_enabled": true,
		"current_condition": condition,
		"condition_band": ItemConditionRules.condition_band(condition),
		"fault_chance": ItemConditionRules.fault_chance(condition),
		"is_jammed": false,
		"equipment_slot": slot,
		"preferred_equipment_slot": slot,
		"allowed_equipment_slots": [slot],
		"sprite_path": item.get_inventory_sprite_path(),
		"equipped_sprite_paths": item.get_equipped_sprite_paths(),
		"requires_two_hands": item.requires_two_hands,
		"weapon_type": item.weapon_type,
		"damage_type": item.damage_type,
		"flesh_damage": item.flesh_damage,
		"stance_damage": item.stance_damage,
		"armor_penetration": item.armor_penetration,
		"accuracy_rating": item.accuracy_rating,
		"effective_range": item.effective_range,
		"protection_blunt": item.protection_blunt,
		"protection_sharp": item.protection_sharp,
		"protection_ballistic": item.protection_ballistic,
		"bulk": item.bulk,
		"weight": item.weight,
		"capacity_bonus": item.capacity_bonus,
		"stack_count": item.stack_count,
		"stack_limit": item.get_stack_limit(),
		"can_equip": true,
	}

