extends Resource
class_name ItemData

@export_group("Identity")
@export var id: String = "unknown_item"
@export var display_name: String = "Generic Junk"
@export_multiline var lore_description: String = "Cryptic three-sentence lore goes here."
@export var item_type: GameEnums.ItemType = GameEnums.ItemType.JUNK

@export_group("Grid Math & Requirements")
@export var size_cost: int = 1
@export var capacity_bonus: int = 0 # THE FIX: Pockets are data-driven now
@export var target_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.BACKPACK
@export var requires_two_hands: bool = false 

@export_group("Presentation")
@export_file("*.png") var inventory_sprite_path: String = ""
@export_file("*.png") var unloaded_sprite_path: String = ""
@export_file("*.png") var equipped_sprite_path: String = ""

@export_group("Combat Variables")
@export var weapon_type: GameEnums.WeaponClass = GameEnums.WeaponClass.NONE
@export var damage_type: GameEnums.DamageType = GameEnums.DamageType.BLUNT
@export var flesh_damage: float = 0.0
@export var stance_damage: float = 0.0
@export_range(0.0, 12.0) var armor_penetration: float = 0.0
@export_range(0.0, 12.0) var accuracy_rating: float = 6.0
@export_range(0, 12) var effective_range: int = 1
@export_range(0, 12) var optimal_range: int = 1
@export_range(0.0, 1.0) var minimum_damage_multiplier: float = 1.0

@export_group("Gear Stats")
## Defensive values. Only relevant for ARMOR type items equipped on the paper doll.
@export var protection_blunt: float = 0.0
@export var protection_sharp: float = 0.0
@export var protection_ballistic: float = 0.0
## Sliding scale: negative = dodge/stealth bonus, positive = AP damage resistance bonus.
@export var bulk: float = 0.0
## AP tax applied to every action while this item is equipped.
@export var weight: float = 0.0
## Contributes to the entity's perceived power level. Drives AI fight-or-flight decisions.
@export var threat: float = 0.0
## Thermal insulation value for hypothermia resistance. Only inner/outer torso items.
@export_range(0.0, 12.0) var insulation: float = 0.0

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
## Firing leaves the action locked until CYCLE is used.
@export var requires_cycle_after_shot: bool = false
## When not cycling the action, CYCLE may hand-load one loose round.
@export var cycle_loads_one_round: bool = false

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

func is_ready_to_fire() -> bool:
	return is_ranged() and current_magazine > 0 and not needs_cycling

func damage_multiplier_at_distance(distance: int) -> float:
	if distance <= optimal_range or effective_range <= optimal_range:
		return 1.0
	var falloff_progress := clampf(
		float(distance - optimal_range)
			/ float(effective_range - optimal_range),
		0.0,
		1.0
	)
	return lerpf(1.0, minimum_damage_multiplier, falloff_progress)

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
	var instance := duplicate(true) as ItemData
	instance.instance_id = "item_" + str(ResourceUID.create_id())
	instance.template_path = template_path if not template_path.is_empty() else resource_path
	instance.current_magazine = max_magazine if starting_magazine < 0 else starting_magazine
	instance.needs_cycling = false
	return instance

func to_runtime_state() -> Dictionary:
	return {
		"instance_id": instance_id,
		"template_path": template_path if not template_path.is_empty() else resource_path,
		"current_magazine": current_magazine,
		"needs_cycling": needs_cycling,
		"definition": to_definition_state(),
	}

func to_definition_state() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"lore_description": lore_description,
		"item_type": item_type,
		"size_cost": size_cost,
		"capacity_bonus": capacity_bonus,
		"target_slot": target_slot,
		"requires_two_hands": requires_two_hands,
		"inventory_sprite_path": inventory_sprite_path,
		"unloaded_sprite_path": unloaded_sprite_path,
		"equipped_sprite_path": equipped_sprite_path,
		"weapon_type": weapon_type,
		"damage_type": damage_type,
		"flesh_damage": flesh_damage,
		"stance_damage": stance_damage,
		"armor_penetration": armor_penetration,
		"accuracy_rating": accuracy_rating,
		"effective_range": effective_range,
		"optimal_range": optimal_range,
		"minimum_damage_multiplier": minimum_damage_multiplier,
		"protection_blunt": protection_blunt,
		"protection_sharp": protection_sharp,
		"protection_ballistic": protection_ballistic,
		"bulk": bulk,
		"weight": weight,
		"threat": threat,
		"insulation": insulation,
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
		"requires_cycle_after_shot": requires_cycle_after_shot,
		"cycle_loads_one_round": cycle_loads_one_round,
		"compatible_weapon_ids": compatible_weapon_ids.duplicate(),
		"grants_snipe": grants_snipe,
		"macro_snipe_range": macro_snipe_range,
	}

static func from_runtime_state(state: Dictionary) -> ItemData:
	var item: ItemData
	var source_path: String = state.get("template_path", "")
	if not source_path.is_empty() and ResourceLoader.exists(source_path):
		item = load(source_path) as ItemData

	if item:
		item = item.create_runtime_instance()
	else:
		item = ItemData.new()
		item._apply_definition_state(state.get("definition", {}))
		item.instance_id = "item_" + str(ResourceUID.create_id())

	item.instance_id = state.get("instance_id", item.instance_id)
	item.template_path = source_path
	item.current_magazine = state.get("current_magazine", item.current_magazine)
	item.needs_cycling = state.get("needs_cycling", false)
	return item

func _apply_definition_state(state: Dictionary) -> void:
	for property_name in state.keys():
		set(property_name, state[property_name])
	armor_penetration = clampf(armor_penetration, 0.0, GameEnums.SCALE_MAX)
	accuracy_rating = clampf(accuracy_rating, 0.0, GameEnums.SCALE_MAX)
	effective_range = clampi(effective_range, 0, int(GameEnums.SCALE_MAX))
	optimal_range = clampi(optimal_range, 0, effective_range)
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
	consumable_potency = clampf(
		consumable_potency,
		0.0,
		GameEnums.SCALE_MAX
	)
