extends Resource
class_name ItemData

@export_group("Identity")
@export var id: String = "unknown_item"
@export var display_name: String = "Generic Junk"
@export_multiline var lore_description: String = "Cryptic three-sentence lore goes here."

@export_group("Grid Math & Requirements")
@export var size_cost: int = 1
@export var target_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.BACKPACK
# The "Black Knight" fix: Does this require two hands to hold?
@export var requires_two_hands: bool = false 

@export_group("Combat Variables")
@export var weapon_type: GameEnums.WeaponClass = GameEnums.WeaponClass.NONE
@export var flesh_damage: float = 0.0
@export var stance_damage: float = 0.0
@export var armor_penetration: float = 0.0
