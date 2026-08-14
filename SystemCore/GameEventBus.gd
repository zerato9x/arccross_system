extends Node

## ---------------------------------------------------------
## GAME EVENT BUS (SystemCore Autoload)
## ---------------------------------------------------------
## A central hub for cross-core transient events like SFX, VFX,
## or UI notifications. Persistent state remains in WorldState,
## but ephemeral events pass through here to decouple domains.
## ---------------------------------------------------------

signal combat_action_executed(entity: Node, action_id: String, weapon_class: GameEnums.WeaponClass, weapon_id: String)
signal humanoid_injured(entity: Node, wound_type: int, context: Dictionary)
signal humanoid_exhausted(entity: Node)
signal item_used(entity: Node, category: GameEnums.ItemCategory)
signal humanoid_footstep_taken(entity: Node, background: String)
signal scene_audio_requested(scene_id: String, context: Dictionary)
signal player_vitals_changed(context: Dictionary)
signal world_action_presentation(receipt: Dictionary)

# ---------------------------------------------------------
# EMITTERS
# ---------------------------------------------------------

func emit_combat_action(
	entity: Node,
	action_id: String,
	weapon_class: GameEnums.WeaponClass = GameEnums.WeaponClass.NONE,
	weapon_id: String = ""
) -> void:
	combat_action_executed.emit(entity, action_id, weapon_class, weapon_id)

func emit_humanoid_injured(entity: Node, wound_type: int, context: Dictionary = {}) -> void:
	humanoid_injured.emit(entity, wound_type, context.duplicate(true))

func emit_humanoid_exhausted(entity: Node) -> void:
	humanoid_exhausted.emit(entity)

func emit_item_used(entity: Node, category: GameEnums.ItemCategory) -> void:
	item_used.emit(entity, category)

func emit_humanoid_footstep(entity: Node, background: String) -> void:
	humanoid_footstep_taken.emit(entity, background)


func emit_scene_audio(scene_id: String, context: Dictionary = {}) -> void:
	scene_audio_requested.emit(scene_id, context)


func emit_world_action_presentation(receipt: Dictionary) -> void:
	world_action_presentation.emit(receipt.duplicate(true))


func emit_player_vitals(context: Dictionary) -> void:
	player_vitals_changed.emit(context)
