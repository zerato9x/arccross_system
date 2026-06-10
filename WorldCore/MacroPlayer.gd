extends Node2D
class_name MacroPlayer

@export var definition: EntityDefinition

@onready var humanoid_core: HumanoidCore = $HumanoidCore

var current_hex_coords: Vector2i = Vector2i(0, 0)

func _ready() -> void:
	if not humanoid_core:
		push_error("MacroPlayer requires a HumanoidCore child.")
		return

	definition = humanoid_core.definition
	if not definition:
		push_error("MacroPlayer's HumanoidCore requires an EntityDefinition.")
		return

	if definition.loadout and _inventory_is_empty():
		definition.loadout.apply_to(humanoid_core.inventory)
		print("[PLAYER] Persistent runtime state initialized with starting loadout.")

func get_humanoid_core() -> HumanoidCore:
	return humanoid_core

func capture_runtime_record() -> Dictionary:
	return {
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"life_state": (
			GameEnums.EntityLifeState.DEAD
			if humanoid_core.is_dead
			else GameEnums.EntityLifeState.ALIVE
		),
		"coords": current_hex_coords,
		"definition": humanoid_core.definition.to_state(),
		"runtime": humanoid_core.capture_runtime_state(),
	}

func restore_runtime_record(record: Dictionary) -> void:
	if record.is_empty():
		return

	var definition_state: Dictionary = record.get("definition", {})
	if not definition_state.is_empty():
		definition = EntityDefinition.from_state(definition_state)
		humanoid_core.definition = definition
		humanoid_core.body.configure_structure(definition.fortitude)
		humanoid_core.inventory.base_max_capacity = definition.brawn
		humanoid_core.inventory._recalculate_bounds()

	humanoid_core.restore_runtime_state(record.get("runtime", {}))
	current_hex_coords = record.get("coords", current_hex_coords)

func snap_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	position = pixel_position

func walk_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	# A smooth, 0.2-second hop to the next tile
	var tween = create_tween()
	tween.tween_property(self, "position", pixel_position, 0.2).set_trans(Tween.TRANS_SINE)

func _inventory_is_empty() -> bool:
	if humanoid_core.inventory.backpack_array.size() > 0:
		return false

	for item in humanoid_core.inventory.paper_doll.values():
		if item != null:
			return false

	return true
