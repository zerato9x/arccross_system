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

@export_group("Combat Variables")
@export var weapon_type: GameEnums.WeaponClass = GameEnums.WeaponClass.NONE
@export var damage_type: GameEnums.DamageType = GameEnums.DamageType.BLUNT
@export var flesh_damage: float = 0.0
@export var stance_damage: float = 0.0
@export var armor_penetration: float = 0.0

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
@export var insulation: float = 0.0

@export_group("Consumable")
@export var consumable_effect: GameEnums.ConsumableEffect = GameEnums.ConsumableEffect.RESTORE_HUNGER
@export var consumable_potency: float = 0.0 # How much it restores (0.0 to 1.0 scale)

@export_group("Firearm Mechanics")
## Pistols: Maximum rounds the internal magazine can hold. 0 = no internal magazine (Rifle).
@export var max_magazine: int = 0
## Pistols: Current rounds remaining in the internal magazine.
var current_magazine: int = 0
## Rifles: Whether the bolt needs cycling before the next shot.
var needs_cycling: bool = false

## Helper: Is this item a ranged weapon?
func is_ranged() -> bool:
	return weapon_type == GameEnums.WeaponClass.PISTOL or weapon_type == GameEnums.WeaponClass.RIFLE

## Helper: Is this item a melee weapon?
func is_melee() -> bool:
	return weapon_type == GameEnums.WeaponClass.BLUNT or weapon_type == GameEnums.WeaponClass.BLADE
