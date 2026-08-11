extends RefCounted
class_name EntityFactory

const _NpcBehaviorState := preload("res://SystemCore/NpcBehaviorState.gd")
const _CombatActorState := preload("res://SystemCore/CombatActorState.gd")

## Converts neutral entity records into runtime HumanoidCore nodes and back.
## Single fabrication path for macro, combat, and persistence boundaries.

static func record_to_humanoid_core(
	record: Dictionary,
	parent: Node,
	unit_name: String = "Humanoid",
	items_spilled_callback: Callable = Callable()
) -> HumanoidCore:
	var definition_state: Dictionary = record.get("definition", {})
	var runtime_state: Dictionary = record.get("runtime", {})
	var definition := EntityDefinition.from_state(definition_state)

	var core := HumanoidCore.new()
	core.name = unit_name
	core.definition = definition
	var behavior_state: Resource = _NpcBehaviorState.from_runtime(runtime_state, definition_state)
	core.set_meta("npc_behavior_state", behavior_state.to_dict())

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
	if runtime_state.get("combat_actor_state", {}) is Dictionary:
		core.set_meta(
			"combat_actor_state",
			_CombatActorState.from_runtime(runtime_state.get("combat_actor_state", {}))
		)
	# Macro NPCs can acquire ordinary items before a tactical encounter without
	# fabricating a fake private salvage store. Merge those neutral carried
	# instances into the same InventorySystem after the authored loadout.
	for item_state in runtime_state.get("inventory_items", []):
		if not item_state is Dictionary:
			continue
		# Macro NPCs materialize authored loadout items as neutral planning
		# states. The tactical factory already applies the same authored loadout;
		# skip only those tagged copies while preserving acquired/traded items.
		if bool(item_state.get("_authored_loadout", false)):
			continue
		var item := ItemData.from_runtime_state(item_state)
		if item != null:
			inv.add_to_backpack(item)

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
		"runtime": _runtime_with_combat_state(core),
	}


static func _runtime_with_combat_state(core: HumanoidCore) -> Dictionary:
	var runtime := core.capture_runtime_state().to_dict()
	if core.has_meta("combat_actor_state") and core.get_meta("combat_actor_state") is _CombatActorState:
		runtime["combat_actor_state"] = (core.get_meta("combat_actor_state") as _CombatActorState).to_dict()
	# Behaviour is an encounter/world contract, not part of HumanoidState (the
	# biological snapshot deliberately remains domain-neutral).  Carry the
	# authored profile, pressure meter, and decision memory across every factory
	# boundary so a combat handoff cannot silently reset an NPC to its role
	# default.  Old records are normalised by NpcBehaviorState.from_runtime().
	var behavior_payload: Dictionary = {}
	if core.has_meta("npc_behavior_state") and core.get_meta("npc_behavior_state") is Dictionary:
		behavior_payload = core.get_meta("npc_behavior_state").duplicate(true)
	else:
		var definition_state := core.definition.to_state() if core.definition != null else {}
		behavior_payload = _NpcBehaviorState.from_runtime({}, definition_state).to_dict()
	runtime[_NpcBehaviorState.RUNTIME_KEY] = behavior_payload
	return runtime


static func _has_humanoid_runtime(runtime_state: Dictionary) -> bool:
	for key in [
		"body",
		"inventory",
		"base_ap",
		"current_max_ap",
		"is_dead",
		"current_morale",
	]:
		if runtime_state.has(key):
			return true
	return false
