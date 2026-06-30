extends RefCounted
class_name EntityFactory

## Converts neutral entity records into runtime HumanoidCore nodes and back.
## Single fabrication path for macro, combat, and persistence boundaries.

static func record_to_humanoid_core(
	record: Dictionary,
	parent: Node,
	unit_name: String = "Humanoid",
	attach_ai: bool = false,
	lane_manager: CombatLaneManager = null,
	turn_manager: CombatTurnManager = null,
	resolution_engine: CombatResolutionEngine = null,
	items_spilled_callback: Callable = Callable()
) -> HumanoidCore:
	var definition_state: Dictionary = record.get("definition", {})
	var runtime_state: Dictionary = record.get("runtime", {})
	var definition := EntityDefinition.from_state(definition_state)

	var core := HumanoidCore.new()
	core.name = unit_name
	core.definition = definition

	var body := HumanoidBody.new()
	body.name = "HumanoidBody"
	core.add_child(body)
	core.body = body
	if definition:
		body.configure_structure(definition.fortitude)

	var inv := InventorySystem.new()
	inv.name = "InventorySystem"
	core.add_child(inv)
	core.inventory = inv

	if items_spilled_callback.is_valid():
		inv.items_spilled.connect(items_spilled_callback)

	if attach_ai and lane_manager and turn_manager and resolution_engine:
		var ai := CombatAIEvaluator.new()
		ai.name = "CombatAIEvaluator"
		ai.ai_core = core
		ai.lane_manager = lane_manager
		ai.turn_manager = turn_manager
		ai.resolution_engine = resolution_engine
		core.add_child(ai)

	if parent:
		parent.add_child(core)

	var has_humanoid_runtime := _has_humanoid_runtime(runtime_state)
	var inventory_runtime: Dictionary = runtime_state.get("inventory", {})
	var has_inventory_runtime := (
		has_humanoid_runtime
		and inventory_runtime is Dictionary
		and not inventory_runtime.is_empty()
	)
	if has_inventory_runtime:
		core.restore_runtime_state(runtime_state)
	elif definition.loadout:
		definition.loadout.apply_to(inv)
		if has_humanoid_runtime:
			core.restore_runtime_state(runtime_state)

	return core


static func humanoid_core_to_record(
	core: HumanoidCore,
	entity_id: String = "player",
	coords: Vector2i = Vector2i.ZERO
) -> Dictionary:
	if core == null:
		return {}
	return {
		"entity_id": entity_id,
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"life_state": (
			GameEnums.EntityLifeState.DEAD
			if core.is_dead
			else GameEnums.EntityLifeState.ALIVE
		),
		"coords": coords,
		"definition": core.definition.to_state() if core.definition else {},
		"runtime": core.capture_runtime_state().to_dict(),
	}


static func _has_humanoid_runtime(runtime_state: Dictionary) -> bool:
	for key in [
		"body",
		"inventory",
		"base_ap",
		"current_max_ap",
		"is_dead",
		"stance_points",
		"current_morale",
	]:
		if runtime_state.has(key):
			return true
	return false
