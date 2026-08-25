extends RefCounted
class_name WorldActionActorStagingService

## Detached actor/runtime staging for world-action receipts. The returned
## dictionary is a proposed state only; WorldActionApplicationService remains
## the sole owner of canonical commits, rollback, time, signals, and receipts.

var store: RuntimeStateStore
var _inventory_transaction: WorldActionInventoryTransactionService
var _poi_selection_transaction: WorldActionPoiSelectionTransactionService
var _camp_transaction: WorldActionCampTransactionService
var _movement_transaction: WorldActionMovementTransactionService
var _search_transaction: WorldActionSearchTransactionService
var _npc_work_transaction: WorldActionNpcWorkTransactionService


func configure(
	state: RuntimeStateStore,
	inventory_transaction: WorldActionInventoryTransactionService,
	poi_selection_transaction: WorldActionPoiSelectionTransactionService,
	camp_transaction: WorldActionCampTransactionService,
	movement_transaction: WorldActionMovementTransactionService,
	search_transaction: WorldActionSearchTransactionService,
	npc_work_transaction: WorldActionNpcWorkTransactionService
) -> void:
	store = state
	_inventory_transaction = inventory_transaction
	_poi_selection_transaction = poi_selection_transaction
	_camp_transaction = camp_transaction
	_movement_transaction = movement_transaction
	_search_transaction = search_transaction
	_npc_work_transaction = npc_work_transaction


func stage(receipt: WorldActionReceipt, elapsed_minutes: int) -> Dictionary:
	var actor_data: Dictionary = (
		store.player_record.to_dict()
		if receipt.actor_id == "player" and store.player_record != null
		else store.get_entity_snapshot(receipt.actor_id)
	)
	if actor_data.is_empty():
		return {"runtime": {}, "error": "World-action actor is unavailable."}
	var movement_error := _movement_transaction.staging_error(receipt)
	if not movement_error.is_empty():
		return {"runtime": {}, "error": movement_error}
	if receipt.actor_id == "player":
		return _stage_player(actor_data, receipt, elapsed_minutes)
	return _stage_neutral_actor(actor_data, receipt)


func _stage_player(
	actor_data: Dictionary,
	receipt: WorldActionReceipt,
	elapsed_minutes: int
) -> Dictionary:
	var core := EntityFactory.record_to_humanoid_core(
		actor_data, null, "WorldActionApplicationActor"
	)
	if core == null:
		return {"runtime": {}, "error": "Could not construct the world-action actor."}
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == "biological_hit":
			core.body.apply_targeted_hit(
				int(mutation.get("limb_region", GameEnums.LimbRegion.LEFT_ARM)),
				float(mutation.get("damage", 0.0)),
				float(mutation.get("armor", 0.0))
			)
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) != "medical_application":
			continue
		var item := core.inventory.find_item_by_instance_id(
			str(mutation.get("instance_id", ""))
		)
		if (
			item == null
			or not core.apply_consumable_to_limb(
				item,
				int(mutation.get("limb_region", -1))
			)
		):
			core.free()
			return {"runtime": {}, "error": "Medical treatment is no longer valid."}
	var inventory_result := _inventory_transaction.stage(core, receipt)
	if not bool(inventory_result.get("success", false)):
		core.free()
		return _failure(inventory_result, "Inventory action is no longer valid.")
	var poi_selection_result := _poi_selection_transaction.stage(core, receipt)
	if not bool(poi_selection_result.get("success", false)):
		core.free()
		return _failure(poi_selection_result, "POI gear selection is no longer valid.")
	var camp_result := _camp_transaction.stage(core, receipt)
	if not bool(camp_result.get("success", false)):
		core.free()
		return _failure(camp_result, "Camp recovery is no longer valid.")
	var search_result := _search_transaction.stage(receipt)
	if not bool(search_result.get("success", false)):
		core.free()
		return _failure(search_result, "Search outcome is no longer valid.")
	var staged_hex_state: Dictionary = {}
	for semantic_result in [poi_selection_result, camp_result, search_result]:
		var candidate: Dictionary = semantic_result.get("hex_state", {}).duplicate(true)
		if candidate.is_empty():
			continue
		if not staged_hex_state.is_empty():
			core.free()
			return {
				"runtime": {},
				"error": "World action staged conflicting semantic hex mutations.",
			}
		staged_hex_state = candidate
	core.process_survival_time(
		elapsed_minutes,
		15.0,
		maxf(0.1, receipt.exertion),
		float(receipt.presentation.get("insulation_bonus", 0.0))
	)
	core.reconcile_terminal_state()
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) != "consume_material":
			continue
		var item := core.inventory.find_item_by_instance_id(
			str(mutation.get("instance_id", ""))
		)
		if item == null or not core.inventory.consume_item_units(item):
			core.free()
			return {
				"runtime": {},
				"error": "World-action material is no longer available.",
			}
	if receipt.tool_wear > 0.0 and not receipt.method_id.is_empty():
		core.inventory.condition_service.apply_tool_wear(
			core.inventory,
			receipt.method_id,
			receipt.tool_wear
		)
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	return {
		"runtime": runtime,
		"knowledge": actor_data.get("knowledge", {}).duplicate(true),
		"error": "",
		"ground_remove_ids": inventory_result.get("ground_remove_ids", []).duplicate(true),
		"ground_additions": inventory_result.get("ground_additions", []).duplicate(true) + poi_selection_result.get("ground_additions", []).duplicate(true),
		"hex_state": staged_hex_state,
		"created_items": [],
		"target_state_handled": false,
	}


func _stage_neutral_actor(
	actor_data: Dictionary,
	receipt: WorldActionReceipt
) -> Dictionary:
	var runtime: Dictionary = actor_data.get("runtime", {}).duplicate(true)
	var npc_work_result := _npc_work_transaction.stage(
		runtime,
		actor_data.get("knowledge", {}),
		receipt
	)
	if not bool(npc_work_result.get("success", false)):
		return _failure(npc_work_result, "NPC work progress is no longer valid.")
	runtime = npc_work_result.get("runtime", {}).duplicate(true)
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == "consume_material":
			if not _consume_neutral_item(runtime, str(mutation.get("instance_id", ""))):
				return {
					"runtime": {},
					"error": "World-action material is no longer available.",
				}
	_apply_neutral_tool_wear(runtime, receipt.method_id, receipt.tool_wear)
	return {
		"runtime": runtime,
		"knowledge": npc_work_result.get("knowledge", {}).duplicate(true),
		"hex_state": npc_work_result.get("hex_state", {}).duplicate(true),
		"created_items": npc_work_result.get("created_items", []).duplicate(true),
		"target_state_handled": bool(npc_work_result.get("target_state_handled", false)),
		"error": "",
	}


func _failure(result: Dictionary, fallback: String) -> Dictionary:
	return {"runtime": {}, "error": str(result.get("error", fallback))}


func _consume_neutral_item(runtime: Dictionary, instance_id: String) -> bool:
	for list_path in ["inventory_items", "backpack"]:
		var items: Array = (
			runtime.get(list_path, []).duplicate(true)
			if list_path == "inventory_items"
			else runtime.get("inventory", {}).get("backpack", []).duplicate(true)
		)
		for index in range(items.size()):
			var state: Variant = items[index]
			if not state is Dictionary or str(state.get("instance_id", "")) != instance_id:
				continue
			var count := int(state.get("stack_count", 1))
			if count > 1:
				state = state.duplicate(true)
				state["stack_count"] = count - 1
				items[index] = state
			else:
				items.remove_at(index)
			if list_path == "inventory_items":
				runtime["inventory_items"] = items
			else:
				var inventory: Dictionary = runtime.get("inventory", {}).duplicate(true)
				inventory["backpack"] = items
				runtime["inventory"] = inventory
			return true
	var inventory: Dictionary = runtime.get("inventory", {}).duplicate(true)
	var equipment: Dictionary = inventory.get("equipment", {}).duplicate(true)
	for slot in equipment.keys():
		var state: Variant = equipment[slot]
		if state is Dictionary and str(state.get("instance_id", "")) == instance_id:
			equipment.erase(slot)
			inventory["equipment"] = equipment
			runtime["inventory"] = inventory
			return true
	return false


func _apply_neutral_tool_wear(runtime: Dictionary, method_id: String, wear: float) -> void:
	if wear <= 0.0 or method_id.is_empty():
		return
	var items: Array = runtime.get("inventory_items", []).duplicate(true)
	for index in range(items.size()):
		var state: Variant = items[index]
		if not state is Dictionary:
			continue
		var definition: Dictionary = state.get("definition", {})
		var item_id := str(definition.get("id", state.get("item_id", "")))
		if (
			(method_id == "crowbar" and item_id not in ["crowbar", "bent_pry_bar"])
			or (method_id == "multitool" and item_id not in ["multitool", "lockpick"])
		):
			continue
		state = state.duplicate(true)
		state["current_condition"] = maxf(
			0.0,
			float(state.get("current_condition", GameEnums.SCALE_MAX)) - wear
		)
		items[index] = state
		runtime["inventory_items"] = items
		return
