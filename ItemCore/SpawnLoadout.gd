extends Resource
class_name SpawnLoadout

## Defines the starting equipment and backpack contents for an entity at spawn time.
## Drag ItemData .tres files into these slots in the Inspector.

@export_group("Paper Doll (Equipped)")
@export var weapon: ItemData         ## HAND slot
@export var offhand: ItemData        ## OFFHAND slot
@export var inner_torso: ItemData    ## INNER_TORSO slot
@export var outer_torso: ItemData    ## OUTER_TORSO slot
@export var legs: ItemData           ## LEGS slot
@export var feet: ItemData           ## FEET slot
@export var vest: ItemData           ## VEST slot / combat-accessible rig
@export var backpack_gear: ItemData  ## BACKPACK slot (the bag itself, not contents)
@export var head: ItemData           ## HEAD slot
@export var eyes: ItemData           ## EYES slot
@export var face: ItemData           ## FACE slot
@export var neck: ItemData           ## NECK slot
@export var arms: ItemData           ## ARMS slot
@export var belt: ItemData           ## BELT slot / worn storage
@export var sling: ItemData          ## SLING slot / worn storage

@export_group("Backpack Contents (Loose Items)")
@export var starting_items: Array[ItemData] = []

## Equips all items from this loadout onto the given inventory system.
## Call this AFTER the InventorySystem has initialized its paper_doll.
func apply_to(inventory: InventorySystem) -> void:
	# 1. Equip storage-bearing paper doll slots first so loose items have a legal
	# destination when the loadout is materialized.
	if backpack_gear:
		inventory.equip_item(backpack_gear, GameEnums.EquipmentSlot.BACKPACK)
	if sling:
		inventory.equip_item(sling, GameEnums.EquipmentSlot.SLING)
	if belt:
		inventory.equip_item(belt, GameEnums.EquipmentSlot.BELT)
	if vest:
		inventory.equip_item(vest, GameEnums.EquipmentSlot.VEST)
	if outer_torso:
		inventory.equip_item(outer_torso, GameEnums.EquipmentSlot.OUTER_TORSO)
	if legs:
		inventory.equip_item(legs, GameEnums.EquipmentSlot.LEGS)

	# 2. Equip the remaining authored slots supported by InventorySystem.
	if inner_torso:
		inventory.equip_item(inner_torso, GameEnums.EquipmentSlot.INNER_TORSO)
	if feet:
		inventory.equip_item(feet, GameEnums.EquipmentSlot.FEET)
	if head:
		inventory.equip_item(head, GameEnums.EquipmentSlot.HEAD)
	if eyes:
		inventory.equip_item(eyes, GameEnums.EquipmentSlot.EYES)
	if face:
		inventory.equip_item(face, GameEnums.EquipmentSlot.FACE)
	if neck:
		inventory.equip_item(neck, GameEnums.EquipmentSlot.NECK)
	if arms:
		inventory.equip_item(arms, GameEnums.EquipmentSlot.ARMS)
	if weapon:
		inventory.equip_item(weapon, GameEnums.EquipmentSlot.HAND)
	if offhand:
		inventory.equip_item(offhand, GameEnums.EquipmentSlot.OFFHAND)

	# 3. Materialize authored quantities as explicit stack instances. This is
	# creation-time authoring, not an implicit pickup/transfer merge: every
	# created stack receives one stable instance identity.
	for item in _materialize_starting_items():
		if not inventory.add_to_backpack(item):
			print("[LOADOUT] WARNING: Worn storage full. Could not fit: ", item.display_name)

	# Authored loadouts begin field-ready. Replacement magazines found later
	# must be fitted through the inventory action.
	for carried_item in inventory.backpack_array.duplicate():
		if carried_item.is_magazine() and carried_item.loaded_rounds == 0:
			inventory.load_magazine(carried_item)


func _materialize_starting_items() -> Array[ItemData]:
	var counts_by_path: Dictionary = {}
	var definitions_by_path: Dictionary = {}
	for definition in starting_items:
		if definition == null:
			continue
		var key := definition.resource_path
		if key.is_empty():
			key = "embedded:%s" % definition.id
		counts_by_path[key] = int(counts_by_path.get(key, 0)) + 1
		definitions_by_path[key] = definition
	var instances: Array[ItemData] = []
	for key in counts_by_path:
		var definition: ItemData = definitions_by_path[key]
		var remaining := int(counts_by_path[key])
		while remaining > 0:
			var instance := definition.create_runtime_instance()
			instance.stack_count = mini(remaining, definition.get_stack_limit())
			remaining -= instance.stack_count
			instances.append(instance)
	return instances

func to_state() -> Dictionary:
	return {
		"weapon": _item_definition_path(weapon),
		"offhand": _item_definition_path(offhand),
		"inner_torso": _item_definition_path(inner_torso),
		"outer_torso": _item_definition_path(outer_torso),
		"legs": _item_definition_path(legs),
		"feet": _item_definition_path(feet),
		"vest": _item_definition_path(vest),
		"backpack_gear": _item_definition_path(backpack_gear),
		"head": _item_definition_path(head),
		"eyes": _item_definition_path(eyes),
		"face": _item_definition_path(face),
		"neck": _item_definition_path(neck),
		"arms": _item_definition_path(arms),
		"belt": _item_definition_path(belt),
		"sling": _item_definition_path(sling),
		"starting_items": starting_items.map(
			func(item: ItemData) -> String: return _item_definition_path(item)
		),
	}

static func from_state(state: Dictionary) -> SpawnLoadout:
	var loadout := SpawnLoadout.new()
	loadout.weapon = _load_item_definition(state.get("weapon", ""))
	loadout.offhand = _load_item_definition(state.get("offhand", ""))
	loadout.inner_torso = _load_item_definition(state.get("inner_torso", ""))
	loadout.outer_torso = _load_item_definition(state.get("outer_torso", ""))
	loadout.legs = _load_item_definition(state.get("legs", ""))
	loadout.feet = _load_item_definition(state.get("feet", ""))
	loadout.vest = _load_item_definition(state.get("vest", ""))
	loadout.backpack_gear = _load_item_definition(state.get("backpack_gear", ""))
	loadout.head = _load_item_definition(state.get("head", ""))
	loadout.eyes = _load_item_definition(state.get("eyes", ""))
	loadout.face = _load_item_definition(state.get("face", ""))
	loadout.neck = _load_item_definition(state.get("neck", ""))
	loadout.arms = _load_item_definition(state.get("arms", ""))
	loadout.belt = _load_item_definition(state.get("belt", ""))
	loadout.sling = _load_item_definition(state.get("sling", ""))

	for item_path in state.get("starting_items", []):
		var item := _load_item_definition(item_path)
		if item:
			loadout.starting_items.append(item)

	return loadout

func _item_definition_path(item: ItemData) -> String:
	return item.resource_path if item else ""

static func _load_item_definition(path: String) -> ItemData:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as ItemData
