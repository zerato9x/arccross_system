extends Resource
class_name ItemData

@export_group("Identity")
@export var id: String = "unknown_item"
@export var display_name: String = "Generic Junk"
@export_multiline var lore_description: String = "Cryptic three-sentence lore goes here."
@export var item_type: GameEnums.ItemType = GameEnums.ItemType.JUNK
@export var catalog_category: GameEnums.ItemCategory = GameEnums.ItemCategory.MISC
@export var item_grade: GameEnums.ItemGrade = GameEnums.ItemGrade.CIVILIAN
@export var tags: Array[String] = []
## Explicit extensible roles for mods and catalog validation. Legacy resources
## receive deterministic roles from their authored mechanics when this is empty.
@export var functional_roles: PackedStringArray = []
## Optional stable ID resolved through the knowledge catalog on inspection.
@export var knowledge_entry_id: String = ""

@export_group("Condition & Repair")
@export var condition_enabled: bool = true
@export var repair_domain: GameEnums.RepairDomain = GameEnums.RepairDomain.NONE
@export var maintenance_constraint: String = ""

@export_group("Grid Math & Requirements")
@export var size_cost: int = 1
@export var item_size: GameEnums.ItemSize = GameEnums.ItemSize.SMALL
@export var capacity_bonus: int = 0
@export var target_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.BACKPACK
@export var requires_two_hands: bool = false 
@export var max_stack_size: int = 1

@export_group("Presentation")
@export_file("*.png") var inventory_sprite_path: String = ""
@export_file("*.png") var unloaded_sprite_path: String = ""
@export_file("*.png") var equipped_sprite_path: String = ""
@export_file("*.png") var equipped_sprite_paths: Array[String] = []

@export_group("Combat Variables")
@export var weapon_type: GameEnums.WeaponClass = GameEnums.WeaponClass.NONE
## Optional weapon-authored combat verbs beyond the class-derived default.
## CombatActionCatalog owns their behavior and rejects unknown IDs.
@export var specialized_action_ids: PackedStringArray = []
@export var damage_type: GameEnums.DamageType = GameEnums.DamageType.BLUNT
@export var flesh_damage: float = 0.0
@export var balance_impact: float = 0.0
@export_range(0.0, 12.0) var armor_penetration: float = 0.0
@export_range(0.0, 12.0) var accuracy_rating: float = 6.0
## Tactical-sector range contract. Vector2i stores inclusive min/max optimal
## distance; maximum_range_cells is the hard limit.
@export var optimal_range_cells: Vector2i = Vector2i(1, 1)
@export_range(0, 10) var maximum_range_cells: int = 1
@export_range(0.0, 1.0) var range_falloff: float = 0.12
@export_range(1, 2) var weapon_reach_cells: int = 1
## Firearm behaviour while the owner shares a sector with a hostile actor.
## Kept on the item definition so compact sidearms and long guns do not need
## controller special cases.
@export_enum("allowed", "prohibited", "penalized") var engaged_fire_policy: String = "allowed"
@export_range(0.0, 1.0) var engaged_fire_accuracy_penalty: float = 0.0
@export_range(0.0, 1.0) var minimum_damage_multiplier: float = 1.0

@export_group("Gear Stats")
## Defensive values. Only relevant for ARMOR type items equipped on the paper doll.
@export var protection_blunt: float = 0.0
@export var protection_sharp: float = 0.0
@export var protection_ballistic: float = 0.0
@export var armor_coverage: Array[int] = []
@export_range(0, 3) var armor_layer: int = 0
## Sliding scale: negative = dodge/stealth bonus, positive = AP damage resistance bonus.
@export var bulk: float = 0.0
## AP tax applied to every action while this item is equipped.
@export var weight: float = 0.0
## Contributes to the entity's perceived power level. Drives AI fight-or-flight decisions.
@export var threat: float = 0.0
## Encounter Stance modifier authored by worn equipment. Combat derives the
## actor's starting Stance from physical capability plus this value; it is not
## a hidden controller bonus.
@export_range(-6.0, 6.0) var stance_modifier: float = 0.0
## Thermal insulation value for hypothermia resistance. Only inner/outer torso items.
@export_range(0.0, 12.0) var insulation: float = 0.0

@export_group("Shield BLOCK Mechanics")
## Damage types this item can intercept when it is readied in either hand.
@export var block_damage_types: Array[int] = []
## Limb Regions protected by the raised shield. Empty means no shield coverage.
@export var block_coverage: Array[int] = []
## Fraction of the intercepted attack that bleeds through the shield.
@export_range(0.0, 1.0) var block_flesh_multiplier: float = 1.0
@export_range(0.0, 1.0) var block_balance_multiplier: float = 1.0

@export_group("Consumable")
@export var consumable_effect: GameEnums.ConsumableEffect = GameEnums.ConsumableEffect.RESTORE_HUNGER
@export_range(0.0, 12.0) var consumable_potency: float = 0.0

@export_group("Macro Interaction")
@export var interaction_roles: Array[int] = []
@export_range(-12.0, 12.0) var search_loot_bonus: float = 0.0
@export_range(-12.0, 12.0) var search_safety_bonus: float = 0.0
@export_range(-12.0, 12.0) var search_sneak_bonus: float = 0.0
@export_range(-12.0, 12.0) var camp_sleep_bonus: float = 0.0
@export_range(-12.0, 12.0) var camp_shelter_bonus: float = 0.0
@export_range(-12.0, 12.0) var camp_healing_bonus: float = 0.0
@export_range(-12.0, 12.0) var camp_concealment_bonus: float = 0.0
@export_range(-12.0, 12.0) var camp_alertness_bonus: float = 0.0

@export_group("Firearm Mechanics")
## Total ready capacity, including any chambered round represented by the weapon.
@export var max_magazine: int = 0
## Initial rounds assigned when a runtime item instance is created.
@export var starting_magazine: int = -1
## Exact loose ammunition item ID accepted by this weapon.
@export var ammunition_id: String = ""
## Detachable magazine required by RELOAD. Empty means no detachable magazine.
@export var magazine_id: String = ""
## Optional clip or speedloader required for the fast RELOAD action.
@export var reload_aid_id: String = ""
## Magazine/clip metadata. Loose rounds leave these at their defaults.
@export var accepted_ammunition_id: String = ""
@export var magazine_capacity: int = 0
@export var starting_loaded_rounds: int = 0
## Compatibility authoring hint. Mechanical post-shot cycling is automatic.
@export var requires_cycle_after_shot: bool = false
## Compatibility hint consumed by Reload feeding policy, never as a verb.
@export var cycle_loads_one_round: bool = false
## Some authored firearms begin unready and require an explicit READY action.
@export var requires_ready_action: bool = false

@export_group("Attachment Mechanics")
@export var compatible_weapon_ids: Array[String] = []
@export var grants_snipe: bool = false
@export_range(0, 12) var macro_snipe_range: int = 0

## Runtime identity. Static .tres definitions leave this empty.
var instance_id: String = ""
var template_path: String = ""
## Pistols: Current rounds remaining in the internal magazine.
var current_magazine: int = 0
## Rifles: Whether the bolt needs cycling before the next shot.
var needs_cycling: bool = false
var is_readied: bool = true
## Loose items stack in one inventory footprint.
var stack_count: int = 1
## Runtime rounds currently fitted into a magazine, clip, or speedloader.
var loaded_rounds: int = 0
## Persistent cross-mode state. Condition is a Base-12 meter; firearms may jam.
var current_condition: float = GameEnums.SCALE_MAX
var is_jammed: bool = false
## Stable physical placement and fitted-item identity.
var owner_id: String = ""
var physical_location: String = "unassigned"
var equipped_slot: int = GameEnums.EquipmentSlot.NONE
var container_instance_id: String = ""
var fitted_magazine_instance_id: String = ""
var fitted_magazine_state: Dictionary = {}
var fitted_attachment_instance_ids: Array[String] = []
var fitted_attachment_states: Array[Dictionary] = []

## Helper: Is this item a ranged weapon?
func is_ranged() -> bool:
	return (
		weapon_type == GameEnums.WeaponClass.PISTOL
		or weapon_type == GameEnums.WeaponClass.RIFLE
		or weapon_type == GameEnums.WeaponClass.SHOTGUN
	)

## Helper: Is this item a melee weapon?
func is_melee() -> bool:
	return weapon_type == GameEnums.WeaponClass.BLUNT or weapon_type == GameEnums.WeaponClass.BLADE


func default_combat_action_id() -> String:
	if is_melee():
		return "strike"
	if is_ranged():
		return "fire"
	return ""


func combat_action_ids() -> PackedStringArray:
	var result: PackedStringArray = []
	var default_id := default_combat_action_id()
	if not default_id.is_empty():
		result.append(default_id)
	for raw_action_id in specialized_action_ids:
		var action_id := str(raw_action_id).strip_edges()
		if not action_id.is_empty() and action_id not in result:
			result.append(action_id)
	return result

func is_blocking_shield() -> bool:
	return not block_damage_types.is_empty() and not block_coverage.is_empty()

func can_block_damage(damage_type: GameEnums.DamageType, limb_region: int = -1) -> bool:
	return (
		is_blocking_shield()
		and block_damage_types.has(int(damage_type))
		and (limb_region < 0 or block_coverage.has(limb_region))
	)

func is_ready_to_fire() -> bool:
	return (
		is_ranged()
		and current_condition > 0.0
		and not is_jammed
		and current_magazine > 0
		and (not requires_ready_action or is_readied)
	)

func has_active_function() -> bool:
	return not condition_enabled or current_condition > 0.0


func get_functional_roles() -> PackedStringArray:
	if not functional_roles.is_empty():
		return functional_roles.duplicate()
	var roles: PackedStringArray = []
	match item_type:
		GameEnums.ItemType.WEAPON: roles.append("weapon")
		GameEnums.ItemType.ARMOR: roles.append("equipment")
		GameEnums.ItemType.CONSUMABLE: roles.append("consumable")
		GameEnums.ItemType.TOOL: roles.append("tool")
		GameEnums.ItemType.AMMUNITION: roles.append("ammunition")
		GameEnums.ItemType.MATERIAL: roles.append("repair_material")
		GameEnums.ItemType.ATTACHMENT: roles.append("attachment")
		_: roles.append("barter")
	if capacity_bonus > 0 and not roles.has("container"):
		roles.append("container")
	if insulation > 0.0 and not roles.has("insulation"):
		roles.append("insulation")
	if not interaction_roles.is_empty() and not roles.has("world_interaction"):
		roles.append("world_interaction")
	if not knowledge_entry_id.is_empty() and not roles.has("knowledge"):
		roles.append("knowledge")
	return roles


func can_inspect_knowledge() -> bool:
	return not knowledge_entry_id.is_empty()


## Rough relative worth for macro barter. Prefer explicit threat / damage / protection
## signals over a separate economy table until a full value catalog exists.
func get_barter_value() -> float:
	var value := 1.0
	value += maxf(0.0, threat) * 1.5
	value += maxf(0.0, flesh_damage) * 0.75
	value += maxf(0.0, balance_impact) * 0.5
	value += maxf(0.0, protection_blunt + protection_sharp + protection_ballistic) * 0.6
	value += maxf(0.0, consumable_potency) * 0.4
	value += maxf(0.0, float(max_magazine)) * 0.15
	match item_type:
		GameEnums.ItemType.WEAPON:
			value += 4.0
		GameEnums.ItemType.ARMOR:
			value += 3.0
		GameEnums.ItemType.CONSUMABLE:
			value += 1.5
		GameEnums.ItemType.AMMUNITION:
			value += 1.0 + float(maxi(1, stack_count)) * 0.1
		_:
			value += 0.5
	return value * maxf(0.25, float(maxi(1, stack_count)))


func get_inventory_sprite_path() -> String:
	if current_magazine == 0 and not unloaded_sprite_path.is_empty():
		return unloaded_sprite_path
	return inventory_sprite_path

func get_effective_item_size() -> GameEnums.ItemSize:
	if item_size == GameEnums.ItemSize.BIG:
		return GameEnums.ItemSize.BIG
	if item_size == GameEnums.ItemSize.AVERAGE or size_cost >= 3:
		return GameEnums.ItemSize.AVERAGE
	return GameEnums.ItemSize.SMALL

func get_inventory_cost() -> int:
	return maxi(1, size_cost)

func get_stack_limit() -> int:
	if max_stack_size > 1:
		return max_stack_size
	if item_type != GameEnums.ItemType.AMMUNITION:
		return 1
	if id == "pistol_round":
		return 24
	if id in ["rifle_round", "carbon_rifle_round", "shotgun_shell"]:
		return 12
	return 1

func is_magazine() -> bool:
	return magazine_capacity > 0 and not accepted_ammunition_id.is_empty()

func can_stack_with(other: ItemData) -> bool:
	return (
		other != null
		and id == other.id
		and get_stack_limit() > 1
		and current_magazine == other.current_magazine
		and loaded_rounds == other.loaded_rounds
	)

func get_equipped_sprite_paths() -> Array[String]:
	if not equipped_sprite_paths.is_empty():
		return equipped_sprite_paths.duplicate()
	if not equipped_sprite_path.is_empty():
		return [equipped_sprite_path]
	return []

func damage_multiplier_at_distance(distance: int) -> float:
	var optimal_max := optimal_range_cells.y
	if distance >= optimal_range_cells.x and distance <= optimal_max:
		return 1.0
	var cells_outside := (
		optimal_range_cells.x - distance
		if distance < optimal_range_cells.x
		else distance - optimal_max
	)
	return maxf(
		minimum_damage_multiplier,
		1.0 - range_falloff * float(cells_outside)
	)

func is_runtime_instance() -> bool:
	return not instance_id.is_empty()

func has_interaction_role(role: GameEnums.InteractionItemRole) -> bool:
	return interaction_roles.has(role)

func to_interaction_descriptor() -> Dictionary:
	return {
		"instance_id": instance_id,
		"name": display_name,
		"roles": interaction_roles.duplicate(),
		"search": {
			"loot": search_loot_bonus,
			"safety": search_safety_bonus,
			"sneak": search_sneak_bonus,
		},
		"camp": {
			"sleep": camp_sleep_bonus,
			"shelter": camp_shelter_bonus,
			"healing": camp_healing_bonus,
			"concealment": camp_concealment_bonus,
			"alertness": camp_alertness_bonus,
		},
	}

func create_runtime_instance() -> ItemData:
	# Rebuild through the typed definition contract instead of relying on
	# Resource.duplicate() to preserve an in-memory script instance. Godot can
	# return a base Resource for unsaved runtime definitions in headless mode.
	var instance := ItemData.new()
	instance._apply_definition_state(to_definition_state())
	instance.instance_id = "item_" + str(ResourceUID.create_id())
	instance.template_path = template_path if not template_path.is_empty() else resource_path
	instance.current_magazine = max_magazine if starting_magazine < 0 else starting_magazine
	instance.needs_cycling = false
	instance.is_readied = not instance.requires_ready_action
	instance.stack_count = 1
	instance.loaded_rounds = clampi(
		starting_loaded_rounds,
		0,
		magazine_capacity
	)
	instance.current_condition = GameEnums.SCALE_MAX
	instance.is_jammed = false
	instance.owner_id = ""
	instance.physical_location = "unassigned"
	instance.equipped_slot = GameEnums.EquipmentSlot.NONE
	instance.container_instance_id = ""
	instance.fitted_magazine_instance_id = ""
	instance.fitted_magazine_state = {}
	instance.fitted_attachment_instance_ids = []
	instance.fitted_attachment_states = []
	return instance

func to_runtime_state() -> Dictionary:
	return {
		"instance_id": instance_id,
		"template_path": template_path if not template_path.is_empty() else resource_path,
		"current_magazine": current_magazine,
		"needs_cycling": needs_cycling,
		"is_readied": is_readied,
		"stack_count": stack_count,
		"loaded_rounds": loaded_rounds,
		"current_condition": current_condition,
		"is_jammed": is_jammed,
		"owner_id": owner_id,
		"physical_location": physical_location,
		"equipped_slot": equipped_slot,
		"container_instance_id": container_instance_id,
		"fitted_magazine_instance_id": fitted_magazine_instance_id,
		"fitted_magazine_state": fitted_magazine_state.duplicate(true),
		"fitted_attachment_instance_ids": fitted_attachment_instance_ids.duplicate(),
		"fitted_attachment_states": fitted_attachment_states.duplicate(true),
		"definition": to_definition_state(),
	}

func to_definition_state() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"lore_description": lore_description,
		"item_type": item_type,
		"catalog_category": catalog_category,
		"item_grade": item_grade,
		"tags": tags.duplicate(),
		"functional_roles": Array(get_functional_roles()),
		"knowledge_entry_id": knowledge_entry_id,
		"condition_enabled": condition_enabled,
		"repair_domain": repair_domain,
		"maintenance_constraint": maintenance_constraint,
		"size_cost": size_cost,
		"item_size": item_size,
		"capacity_bonus": capacity_bonus,
		"target_slot": target_slot,
		"requires_two_hands": requires_two_hands,
		"max_stack_size": max_stack_size,
		"inventory_sprite_path": inventory_sprite_path,
		"unloaded_sprite_path": unloaded_sprite_path,
		"equipped_sprite_path": equipped_sprite_path,
		"equipped_sprite_paths": equipped_sprite_paths.duplicate(),
		"weapon_type": weapon_type,
		"specialized_action_ids": Array(specialized_action_ids),
		"damage_type": damage_type,
		"flesh_damage": flesh_damage,
		"balance_impact": balance_impact,
		"armor_penetration": armor_penetration,
		"accuracy_rating": accuracy_rating,
		"optimal_range_cells": optimal_range_cells,
		"maximum_range_cells": maximum_range_cells,
		"range_falloff": range_falloff,
		"weapon_reach_cells": weapon_reach_cells,
		"engaged_fire_policy": engaged_fire_policy,
		"engaged_fire_accuracy_penalty": engaged_fire_accuracy_penalty,
		"minimum_damage_multiplier": minimum_damage_multiplier,
		"protection_blunt": protection_blunt,
		"protection_sharp": protection_sharp,
		"protection_ballistic": protection_ballistic,
		"armor_coverage": armor_coverage.duplicate(),
		"armor_layer": armor_layer,
		"bulk": bulk,
		"weight": weight,
		"threat": threat,
		"stance_modifier": stance_modifier,
		"insulation": insulation,
		"block_damage_types": block_damage_types.duplicate(),
		"block_coverage": block_coverage.duplicate(),
		"block_flesh_multiplier": block_flesh_multiplier,
		"block_balance_multiplier": block_balance_multiplier,
		"consumable_effect": consumable_effect,
		"consumable_potency": consumable_potency,
		"interaction_roles": interaction_roles.duplicate(),
		"search_loot_bonus": search_loot_bonus,
		"search_safety_bonus": search_safety_bonus,
		"search_sneak_bonus": search_sneak_bonus,
		"camp_sleep_bonus": camp_sleep_bonus,
		"camp_shelter_bonus": camp_shelter_bonus,
		"camp_healing_bonus": camp_healing_bonus,
		"camp_concealment_bonus": camp_concealment_bonus,
		"camp_alertness_bonus": camp_alertness_bonus,
		"max_magazine": max_magazine,
		"starting_magazine": starting_magazine,
		"ammunition_id": ammunition_id,
		"magazine_id": magazine_id,
		"reload_aid_id": reload_aid_id,
		"accepted_ammunition_id": accepted_ammunition_id,
		"magazine_capacity": magazine_capacity,
		"starting_loaded_rounds": starting_loaded_rounds,
		"requires_cycle_after_shot": requires_cycle_after_shot,
		"cycle_loads_one_round": cycle_loads_one_round,
		"requires_ready_action": requires_ready_action,
		"compatible_weapon_ids": compatible_weapon_ids.duplicate(),
		"grants_snipe": grants_snipe,
		"macro_snipe_range": macro_snipe_range,
	}

static func from_runtime_state(state: Dictionary) -> ItemData:
	# Hydrate through the current typed ItemData contract instead of assigning
	# runtime fields onto a loaded Resource instance.  Older authored resources
	# can still deserialize as a base Resource in headless/editor caches, which
	# makes newly-added runtime fields (attachments, fitted magazines) vanish or
	# abort the whole inventory restore.  The saved definition is authoritative;
	# the template is only a fallback for older records that predate it.
	var source_path: String = str(state.get("template_path", ""))
	var definition_state: Dictionary = state.get("definition", {}).duplicate(true)
	if definition_state.is_empty() and not source_path.is_empty() and ResourceLoader.exists(source_path):
		var template := load(source_path) as ItemData
		if template != null:
			definition_state = template.to_definition_state()
	var definition_item := ItemData.new()
	if not definition_state.is_empty():
		definition_item._apply_definition_state(definition_state)
	definition_item.template_path = source_path
	var item := definition_item.create_runtime_instance()
	if item == null:
		item = ItemData.new()
		item.instance_id = "item_" + str(ResourceUID.create_id())

	item.instance_id = state.get("instance_id", item.instance_id)
	item.template_path = source_path
	item.current_magazine = state.get("current_magazine", item.current_magazine)
	item.needs_cycling = state.get("needs_cycling", false)
	item.is_readied = bool(state.get("is_readied", not item.requires_ready_action))
	item.stack_count = maxi(1, int(state.get("stack_count", 1)))
	item.loaded_rounds = clampi(
		int(state.get("loaded_rounds", item.loaded_rounds)),
		0,
		item.magazine_capacity
	)
	# Missing keys are older saves: migrate them to pristine, functional gear.
	item.current_condition = clampf(
		float(state.get("current_condition", GameEnums.SCALE_MAX)),
		0.0,
		GameEnums.SCALE_MAX
	)
	item.is_jammed = bool(state.get("is_jammed", false))
	# Legacy saves may contain a post-shot lock. CYCLE is now jam clearing only;
	# healthy firearms always hydrate ready for ordinary action selection.
	item.needs_cycling = false
	item.owner_id = str(state.get("owner_id", ""))
	item.physical_location = str(state.get("physical_location", "unassigned"))
	item.equipped_slot = int(state.get("equipped_slot", GameEnums.EquipmentSlot.NONE))
	item.container_instance_id = str(state.get("container_instance_id", ""))
	item.fitted_magazine_instance_id = str(state.get("fitted_magazine_instance_id", ""))
	item.fitted_magazine_state = state.get("fitted_magazine_state", {}).duplicate(true)
	for attachment_id in state.get("fitted_attachment_instance_ids", []):
		item.fitted_attachment_instance_ids.append(str(attachment_id))
	# JSON/save hydration returns an untyped Array.  The runtime contract is
	# deliberately typed, so rebuild it entry-by-entry instead of assigning the
	# raw Array and tripping Godot's typed-property guard on older saves.
	var attachment_states: Array[Dictionary] = []
	for attachment_state in state.get("fitted_attachment_states", []):
		if attachment_state is Dictionary:
			attachment_states.append(attachment_state.duplicate(true))
	item.fitted_attachment_states = attachment_states
	return item

func _apply_definition_state(state: Dictionary) -> void:
	for property_name in state.keys():
		var value = state[property_name]
		if property_name in [
			"tags",
			"equipped_sprite_paths",
			"compatible_weapon_ids",
		]:
			var strings: Array[String] = []
			for entry in value:
				strings.append(str(entry))
			set(property_name, strings)
		elif property_name in ["functional_roles", "specialized_action_ids"]:
			var functional_strings: PackedStringArray = []
			for entry in value:
				functional_strings.append(str(entry))
			set(property_name, functional_strings)
		elif property_name in [
			"interaction_roles",
			"block_damage_types",
			"block_coverage",
			"armor_coverage",
		]:
			var roles: Array[int] = []
			for entry in value:
				roles.append(int(entry))
			set(property_name, roles)
		else:
			set(property_name, value)
	armor_penetration = clampf(armor_penetration, 0.0, GameEnums.SCALE_MAX)
	accuracy_rating = clampf(accuracy_rating, 0.0, GameEnums.SCALE_MAX)
	maximum_range_cells = clampi(maximum_range_cells, 0, 10)
	optimal_range_cells.x = clampi(optimal_range_cells.x, 0, maximum_range_cells)
	optimal_range_cells.y = clampi(
		optimal_range_cells.y,
		optimal_range_cells.x,
		maximum_range_cells
	)
	weapon_reach_cells = clampi(weapon_reach_cells, 1, 2)
	if engaged_fire_policy not in ["allowed", "prohibited", "penalized"]:
		engaged_fire_policy = "allowed"
	engaged_fire_accuracy_penalty = clampf(engaged_fire_accuracy_penalty, 0.0, 1.0)
	range_falloff = clampf(range_falloff, 0.0, 1.0)
	minimum_damage_multiplier = clampf(
		minimum_damage_multiplier,
		0.0,
		1.0
	)
	macro_snipe_range = clampi(
		macro_snipe_range,
		0,
		int(GameEnums.SCALE_MAX)
	)
	insulation = clampf(insulation, 0.0, GameEnums.SCALE_MAX)
	block_flesh_multiplier = clampf(block_flesh_multiplier, 0.0, 1.0)
	block_balance_multiplier = clampf(block_balance_multiplier, 0.0, 1.0)
	consumable_potency = clampf(
		consumable_potency,
		0.0,
		GameEnums.SCALE_MAX
	)
