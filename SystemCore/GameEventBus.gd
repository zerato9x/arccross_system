extends Node

## ---------------------------------------------------------
## GAME EVENT BUS (SystemCore Autoload)
## ---------------------------------------------------------
## A central hub for cross-core transient events like SFX, VFX,
## or UI notifications. Persistent state remains in WorldState,
## but ephemeral events pass through here to decouple domains.
## ---------------------------------------------------------

signal combat_action_executed(entity: Node, action: GameEnums.ActionType, weapon_class: GameEnums.WeaponClass, weapon_id: String)
signal humanoid_injured(entity: Node, trauma: GameEnums.TraumaType)
signal humanoid_exhausted(entity: Node)
signal item_used(entity: Node, category: GameEnums.ItemCategory)
signal humanoid_footstep_taken(entity: Node, background: String)

# ---------------------------------------------------------
# EMITTERS
# ---------------------------------------------------------

func emit_combat_action(
	entity: Node,
	action: GameEnums.ActionType,
	weapon_class: GameEnums.WeaponClass = GameEnums.WeaponClass.NONE,
	weapon_id: String = ""
) -> void:
	combat_action_executed.emit(entity, action, weapon_class, weapon_id)

func emit_humanoid_injured(entity: Node, trauma: GameEnums.TraumaType) -> void:
	humanoid_injured.emit(entity, trauma)

func emit_humanoid_exhausted(entity: Node) -> void:
	humanoid_exhausted.emit(entity)

func emit_item_used(entity: Node, category: GameEnums.ItemCategory) -> void:
	item_used.emit(entity, category)

func emit_humanoid_footstep(entity: Node, background: String) -> void:
	humanoid_footstep_taken.emit(entity, background)
