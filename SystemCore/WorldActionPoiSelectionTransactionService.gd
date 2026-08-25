extends RefCounted
class_name WorldActionPoiSelectionTransactionService

## Canonical POI gear deployment. Selection commands are replayed against a
## detached player and a detached hex so inventory, deployed gear, traps, and
## overflow ground items cross the world-action boundary as one transaction.

const MUTATION_TYPE := "poi_selection_application"
const MODE_CAMP_SETUP := "camp_setup"
const MODE_SLEEP_SETUP := "sleep_setup"
const MODE_TRAP_INSTALL := "trap_install"
const MAX_CAMP_ITEMS := 3
const MAX_TRAPS := 2

var store: RuntimeStateStore


func configure(state: RuntimeStateStore) -> void:
	store = state


func has_action(receipt: WorldActionReceipt) -> bool:
	if receipt == null:
		return false
	for mutation in receipt.mutations:
		if mutation is Dictionary and str(mutation.get("type", "")) == MUTATION_TYPE:
			return true
	return false


func validation_error(receipt: WorldActionReceipt) -> String:
	if not has_action(receipt):
		return ""
	var actions: Array[Dictionary] = []
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		var mutation_type := str(mutation.get("type", ""))
		if mutation_type == MUTATION_TYPE:
			actions.append(mutation)
		elif mutation_type != "elapsed_time":
			return "World-action POI selection contains conflicting mutations."
	if actions.size() != 1:
		return "World-action receipt contains duplicate POI selections."
	if receipt.actor_id != "player":
		return "World-action POI selection only supports the player actor."
	var mutation := actions[0]
	var mode := str(mutation.get("mode", ""))
	var selected_value: Variant = mutation.get("selected_instance_ids", [])
	if mode not in [MODE_CAMP_SETUP, MODE_SLEEP_SETUP, MODE_TRAP_INSTALL]:
		return "World-action POI selection has an unsupported mode."
	if not selected_value is Array:
		return "World-action POI selection has malformed item identities."
	var selected: Array = selected_value
	var unique: Dictionary = {}
	for instance_value in selected:
		var instance_id := str(instance_value)
		if instance_id.is_empty() or unique.has(instance_id):
			return "World-action POI selection has duplicate or empty item identities."
		unique[instance_id] = true
	if selected.size() > MAX_CAMP_ITEMS + MAX_TRAPS:
		return "World-action POI selection exceeds the available deployment slots."
	var expected_identity := _target_id(mode, receipt.target_coords)
	if receipt.target_id != expected_identity:
		return "World-action POI selection targets the wrong location identity."
	if mode == MODE_TRAP_INSTALL:
		if receipt.verb_id != "trap" or receipt.method_id != "trap_gear":
			return "World-action trap installation has the wrong verb or method."
	elif receipt.verb_id != "configure_camp" or receipt.method_id != "poi_selection":
		return "World-action camp selection has the wrong verb or method."
	return ""


func preview(
	coords: Vector2i,
	selected_instance_ids: Array,
	mode: String,
	actor_name: String = "PoiSelectionValidationActor"
) -> Dictionary:
	if store == null or store.player_record == null:
		return _failure("Canonical player state is unavailable.")
	var hex := store.get_hex_record(coords)
	if hex == null:
		return _failure("Canonical POI state is unavailable.")
	var core := EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(), null, actor_name
	)
	if core == null:
		return _failure("Could not reconstruct canonical player state.")
	var result := _apply_selection(
		core,
		HexRecord.from_dict(hex.to_dict()),
		selected_instance_ids,
		mode
	)
	core.free()
	return result


func stage(core: HumanoidCore, receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {
			"handled": false,
			"success": true,
			"changed": false,
			"hex_state": {},
			"ground_additions": [],
		}
	if core == null or store == null:
		return _failure("POI selection transaction services are unavailable.")
	var current_hex := store.get_hex_record(receipt.target_coords)
	if current_hex == null:
		return _failure("Canonical POI state is unavailable.")
	var mutation := _mutation(receipt)
	var result := _apply_selection(
		core,
		HexRecord.from_dict(current_hex.to_dict()),
		mutation.get("selected_instance_ids", []),
		str(mutation.get("mode", ""))
	)
	result["handled"] = true
	if bool(result.get("success", false)) and not bool(result.get("changed", false)):
		return _failure("POI gear selection is no longer valid.")
	return result


func _apply_selection(
	core: HumanoidCore,
	hex: HexRecord,
	selected_instance_ids: Array,
	mode: String
) -> Dictionary:
	if core == null or hex == null:
		return _failure("POI selection staging is unavailable.")
	var selected: Array[String] = []
	var unique: Dictionary = {}
	for instance_value in selected_instance_ids:
		var instance_id := str(instance_value)
		if instance_id.is_empty() or unique.has(instance_id):
			return _failure("Selected POI gear has invalid item identities.")
		unique[instance_id] = true
		selected.append(instance_id)
	if selected.size() > MAX_CAMP_ITEMS + MAX_TRAPS:
		return _failure("Too much gear was selected for this location.")

	var camp_by_id := _states_by_id(hex.camp_item_states)
	var trap_by_id := _states_by_id(hex.camp_traps)
	var selection_error := _selection_error(
		core, selected, mode, camp_by_id, trap_by_id
	)
	if not selection_error.is_empty():
		return _failure(selection_error)

	var before_runtime := core.capture_runtime_state().to_dict()
	var before_hex := hex.to_dict()
	var ground_additions: Array = []
	match mode:
		MODE_CAMP_SETUP:
			_apply_full_camp_selection(
				core, hex, selected, camp_by_id, trap_by_id, ground_additions
			)
		MODE_SLEEP_SETUP:
			_apply_sleep_selection(core, hex, selected)
		MODE_TRAP_INSTALL:
			_apply_trap_additions(core, hex, selected)
		_:
			return _failure("POI selection mode is unsupported.")
	var runtime := core.capture_runtime_state().to_dict()
	var hex_state := hex.to_dict()
	return {
		"handled": true,
		"success": true,
		"changed": runtime != before_runtime or hex_state != before_hex,
		"message": "POI gear selection staged.",
		"hex_state": hex_state,
		"ground_additions": ground_additions,
	}


func _selection_error(
	core: HumanoidCore,
	selected: Array[String],
	mode: String,
	camp_by_id: Dictionary,
	trap_by_id: Dictionary
) -> String:
	if mode not in [MODE_CAMP_SETUP, MODE_SLEEP_SETUP, MODE_TRAP_INSTALL]:
		return "POI selection mode is unsupported."
	if mode == MODE_TRAP_INSTALL and selected.is_empty():
		return "Choose an eligible trap from the gear tray."
	for instance_id in selected:
		if mode == MODE_CAMP_SETUP and (
			camp_by_id.has(instance_id) or trap_by_id.has(instance_id)
		):
			continue
		if mode == MODE_SLEEP_SETUP and camp_by_id.has(instance_id):
			continue
		if mode == MODE_TRAP_INSTALL and trap_by_id.has(instance_id):
			continue
		var item := core.inventory.find_item_by_instance_id(instance_id)
		if item == null:
			return "Selected POI gear is no longer carried or deployed."
		if mode == MODE_TRAP_INSTALL:
			if not item.has_interaction_role(GameEnums.InteractionItemRole.TRAP_GEAR):
				return "Selected gear cannot be installed as a trap."
		elif (
			not item.has_interaction_role(GameEnums.InteractionItemRole.CAMP_GEAR)
			or item.has_interaction_role(GameEnums.InteractionItemRole.TRAP_GEAR)
		):
			return "Selected gear cannot be deployed as camp gear."
	return ""


func _apply_full_camp_selection(
	core: HumanoidCore,
	hex: HexRecord,
	selected: Array[String],
	camp_by_id: Dictionary,
	trap_by_id: Dictionary,
	ground_additions: Array
) -> void:
	var desired_camp: Array[String] = []
	var desired_traps: Array[String] = []
	for instance_id in selected:
		if camp_by_id.has(instance_id):
			if desired_camp.size() < MAX_CAMP_ITEMS:
				desired_camp.append(instance_id)
			continue
		if trap_by_id.has(instance_id):
			if desired_traps.size() < MAX_TRAPS:
				desired_traps.append(instance_id)
			continue
		var item := core.inventory.find_item_by_instance_id(instance_id)
		if item != null and item.has_interaction_role(
			GameEnums.InteractionItemRole.TRAP_GEAR
		):
			if desired_traps.size() < MAX_TRAPS:
				desired_traps.append(instance_id)
		elif desired_camp.size() < MAX_CAMP_ITEMS:
			desired_camp.append(instance_id)

	var next_camp: Array = []
	for instance_id in desired_camp:
		if camp_by_id.has(instance_id):
			next_camp.append(camp_by_id[instance_id].duplicate(true))
		else:
			var removed := core.inventory.remove_item_by_instance_id(instance_id)
			if removed != null:
				next_camp.append(_deployed_state(removed, "camp"))
	for instance_id in camp_by_id.keys():
		if not desired_camp.has(str(instance_id)):
			_return_deployed_item(
				core, camp_by_id[instance_id], ground_additions
			)
	hex.camp_item_states = next_camp

	var next_traps: Array = []
	for instance_id in desired_traps:
		if trap_by_id.has(instance_id):
			next_traps.append(trap_by_id[instance_id].duplicate(true))
		else:
			var removed := core.inventory.remove_item_by_instance_id(instance_id)
			if removed != null:
				next_traps.append(_trap_state(removed, next_traps.size()))
	for instance_id in trap_by_id.keys():
		if not desired_traps.has(str(instance_id)):
			_return_deployed_item(
				core, trap_by_id[instance_id], ground_additions
			)
	hex.camp_traps = next_traps
	hex.sleep_gear_instance_id = _sleep_gear_id(next_camp)


func _apply_sleep_selection(
	core: HumanoidCore,
	hex: HexRecord,
	selected: Array[String]
) -> void:
	var camp_by_id := _states_by_id(hex.camp_item_states)
	for instance_id in selected:
		if camp_by_id.has(instance_id):
			continue
		if hex.camp_item_states.size() >= MAX_CAMP_ITEMS:
			break
		var removed := core.inventory.remove_item_by_instance_id(instance_id)
		if removed == null:
			continue
		var state := _deployed_state(removed, "camp")
		hex.camp_item_states.append(state)
		camp_by_id[instance_id] = state
	for instance_id in selected:
		var state: Dictionary = camp_by_id.get(instance_id, {})
		var item := ItemData.from_runtime_state(state) if not state.is_empty() else null
		if item != null and item.camp_sleep_bonus > 0.0:
			hex.sleep_gear_instance_id = instance_id
			return
	if not hex.sleep_gear_instance_id.is_empty() and not camp_by_id.has(
		hex.sleep_gear_instance_id
	):
		hex.sleep_gear_instance_id = ""


func _apply_trap_additions(
	core: HumanoidCore,
	hex: HexRecord,
	selected: Array[String]
) -> void:
	var existing := _states_by_id(hex.camp_traps)
	for instance_id in selected:
		if existing.has(instance_id):
			continue
		if hex.camp_traps.size() >= MAX_TRAPS:
			break
		var removed := core.inventory.remove_item_by_instance_id(instance_id)
		if removed == null:
			continue
		var state := _trap_state(removed, hex.camp_traps.size())
		hex.camp_traps.append(state)
		existing[instance_id] = state


func _return_deployed_item(
	core: HumanoidCore,
	state: Dictionary,
	ground_additions: Array
) -> void:
	var item := ItemData.from_runtime_state(state)
	if item == null:
		return
	item.owner_id = "player"
	item.physical_location = "inventory"
	item.container_instance_id = ""
	item.equipped_slot = GameEnums.EquipmentSlot.NONE
	if not core.inventory.add_to_backpack(item):
		ground_additions.append(item.to_runtime_state())


func _deployed_state(item: ItemData, location: String) -> Dictionary:
	var state := item.to_runtime_state()
	state["owner_id"] = ""
	state["physical_location"] = location
	state["container_instance_id"] = ""
	state["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	return state


func _trap_state(item: ItemData, trap_index: int) -> Dictionary:
	var state := _deployed_state(item, "trap")
	state["item_id"] = item.id
	state["anchor_id"] = "door_frame" if trap_index == 0 else "brush_line"
	state["sector_x"] = 1
	state["sector_y"] = 2 if trap_index == 0 else 3
	state["trap_damage"] = maxf(item.flesh_damage, 2.5)
	return state


func _sleep_gear_id(camp_states: Array) -> String:
	for state_value in camp_states:
		if not state_value is Dictionary:
			continue
		var item := ItemData.from_runtime_state(state_value)
		if item != null and item.camp_sleep_bonus > 0.0:
			return item.instance_id
	return ""


func _states_by_id(states: Array) -> Dictionary:
	var result: Dictionary = {}
	for state_value in states:
		if not state_value is Dictionary:
			continue
		var instance_id := str(state_value.get("instance_id", ""))
		if not instance_id.is_empty():
			result[instance_id] = state_value.duplicate(true)
	return result


func _mutation(receipt: WorldActionReceipt) -> Dictionary:
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == MUTATION_TYPE:
			return mutation
	return {}


func _target_id(mode: String, coords: Vector2i) -> String:
	return ("trap:" if mode == MODE_TRAP_INSTALL else "poi:") + str(coords)


func _failure(message: String) -> Dictionary:
	return {
		"handled": true,
		"success": false,
		"changed": false,
		"message": message,
		"error": message,
		"hex_state": {},
		"ground_additions": [],
	}
