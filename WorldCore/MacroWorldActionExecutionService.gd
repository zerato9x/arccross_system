extends RefCounted
class_name MacroWorldActionExecutionService

## Executes player-facing physical world actions against the shared kernel.
##
## The kernel owns the rules and MacroReceiptApplicationService owns receipt
## fan-out. This adapter owns the remaining application policy: target lookup,
## reservations, work progress, direct-action timing, and compatibility event
## text. UI and legacy manager callers still enter through the manager facade.

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var action_coordinator: MacroWorldActionCoordinator
var time_rules: MacroTimeRulesService
var actor_context_callback: Callable
var commit_receipt_callback: Callable
var consume_repair_material_callback: Callable
var set_event_callback: Callable


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	coordinator: MacroWorldActionCoordinator,
	time_service: MacroTimeRulesService,
	callbacks: Dictionary
) -> void:
	world_state = state
	world_generator = generator
	action_coordinator = coordinator
	time_rules = time_service
	actor_context_callback = _callback(callbacks, "actor_context")
	commit_receipt_callback = _callback(callbacks, "commit_receipt")
	consume_repair_material_callback = _callback(
		callbacks,
		"consume_repair_material"
	)
	set_event_callback = _callback(callbacks, "set_event")


func world_object_record_at(
	coords: Vector2i,
	preferred_id: String = ""
) -> WorldObjectRecord:
	if world_state == null:
		return null
	var hex := world_state.get_hex_record(coords)
	if hex == null:
		return null
	for object_value in hex.world_objects:
		if not object_value is Dictionary:
			continue
		var object := WorldObjectRecord.from_dict(object_value)
		if preferred_id.is_empty() or object.object_id == preferred_id:
			return object
	return null


func resolve_shared_work_action(
	coords: Vector2i,
	verb_id: String,
	preferred_target_id: String = "",
	method_id: String = "",
	noise_intensity: float = 0.0,
	elapsed_minutes: int = 15,
	hit_success_window: bool = true
) -> WorldActionReceipt:
	if (
		world_state == null
		or world_generator == null
		or action_coordinator == null
	):
		return null
	var target: WorldObjectRecord = null
	var affordance: WorldAffordance = null
	var hex := world_state.get_hex_record(coords)
	if hex == null:
		return null
	for object_value in hex.world_objects:
		if not object_value is Dictionary:
			continue
		var candidate := WorldObjectRecord.from_dict(object_value)
		if not preferred_target_id.is_empty() and candidate.object_id != preferred_target_id:
			continue
		for value in action_coordinator.query_affordances(_actor_context(), candidate):
			if value != null and value.verb_id == verb_id:
				target = candidate
				affordance = value
				break
		if affordance != null:
			break
	if affordance == null:
		return null

	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = target.object_id
	request.target_coords = coords
	request.verb_id = verb_id
	request.method_id = method_id
	request.expected_actor_revision = world_state.player_revision
	request.expected_target_revision = target.revision
	request.payload["expected_hex_revision"] = hex.revision
	var profile := action_coordinator.profile_for_id(affordance.task_profile_id)
	profile.base_noise = noise_intensity
	action_coordinator.apply_method_profile(profile, method_id)
	var saved_work: Dictionary = target.runtime.get("world_work", {})
	var action_id := str(saved_work.get("action_id", ""))
	if not action_id.is_empty():
		request.payload["action_id"] = action_id
	request.payload["node_id"] = world_state.active_node_id
	var reservation := (
		world_state.get_world_action_reservation(action_id)
		if not action_id.is_empty()
		else null
	)
	if reservation != null:
		if reservation.actor_id != request.actor_id:
			_set_event("Someone is already working on that object.")
			return null
	else:
		reservation = world_state.begin_world_action(request)
	if reservation == null:
		_set_event("Someone is already working on that object.")
		return null
	action_id = reservation.action_id
	request.payload["action_id"] = action_id

	var preview := action_coordinator.build_preview(
		request,
		affordance,
		_actor_context(),
		target.to_dict(),
		profile
	)
	if not preview.allowed:
		world_state.cancel_world_action(action_id)
		_set_event(str(preview.reason))
		return null
	var work_state: Dictionary = saved_work.duplicate(true)
	work_state["action_id"] = action_id
	work_state["receipt_id"] = reservation.next_receipt_id()
	work_state["attempt_index"] = reservation.attempt_index
	work_state["completed_units"] = int(work_state.get("completed_units", 0))
	work_state["elapsed_minutes"] = elapsed_minutes
	work_state["world_time_minutes"] = world_state.world_time_minutes
	work_state["emit_success_signal"] = noise_intensity > 0.0
	var next_miss_count := int(work_state.get("misses", 0)) + (
		0 if hit_success_window else 1
	)
	var severe_miss := not hit_success_window and next_miss_count >= profile.severe_miss_threshold
	var receipt := action_coordinator.resolve_work_attempt(
		request,
		profile,
		work_state,
		hit_success_window,
		severe_miss
	)
	if bool(preview.risk.get("trespass", false)):
		receipt.events.append({
			"type": "trespass",
			"owner_id": target.owner_id,
			"theft": bool(preview.risk.get("theft", false)),
		})
	if verb_id == WorldActionResolver.VERB_REPAIR:
		var material_item := _consume_repair_material()
		if material_item.is_empty():
			world_state.cancel_world_action(action_id)
			_set_event("Repair material was used before the work could commit.")
			return null
		receipt.mutations.append({
			"type": "consume_material",
			"instance_id": material_item.get("instance_id", ""),
			"item_id": material_item.get("item_id", ""),
		})
	if receipt.work_completed:
		target.runtime.erase("world_work")
	else:
		work_state["completed_units"] = int(
			receipt.work_progress * profile.normalized_units()
		)
		work_state["misses"] = next_miss_count
		work_state["last_receipt"] = receipt.to_dict()
		target.runtime["world_work"] = work_state
	action_coordinator.apply_work_consequences(target, verb_id, receipt)
	var application := _commit_receipt(receipt, coords, target)
	if application == null or not application.applied:
		_set_event(
			application.error if application != null else "World action did not commit."
		)
		return null
	return receipt


func resolve_direct_action(
	coords: Vector2i,
	target_id: String,
	verb_id: String
) -> WorldActionReceipt:
	if action_coordinator == null or world_state == null:
		return null
	var target := world_object_record_at(coords, target_id)
	if target == null:
		_set_event("That physical object is no longer here.")
		return null
	var affordance: WorldAffordance = null
	for candidate in action_coordinator.query_affordances(_actor_context(), target):
		if candidate != null and candidate.verb_id == verb_id:
			affordance = candidate
			break
	if affordance == null:
		_set_event("That object no longer supports this action.")
		return null

	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = target.object_id
	request.target_coords = coords
	request.verb_id = verb_id
	request.expected_actor_revision = world_state.player_revision
	request.expected_target_revision = target.revision
	request.payload["world_time_minutes"] = world_state.world_time_minutes
	request.payload["action_id"] = "direct:%s:%s:%s:%d:%d" % [
		request.actor_id,
		verb_id,
		target.object_id,
		world_state.player_revision,
		target.revision,
	]
	var source_hex := world_state.get_hex_record(coords)
	request.payload["expected_hex_revision"] = source_hex.revision if source_hex != null else -1
	request.payload["node_id"] = world_state.active_node_id
	var direct_preview := action_coordinator.build_preview(
		request,
		affordance,
		_actor_context(),
		target.to_dict()
	)
	if not direct_preview.allowed:
		_set_event(direct_preview.reason)
		return null

	var elapsed_minutes := 0
	var exertion := 0.0
	var noise_intensity := 0.0
	var message := "The object is physically present and unchanged."
	if verb_id == WorldActionResolver.VERB_OPEN:
		elapsed_minutes = time_rules.action_minutes("action")
		exertion = 0.1
		noise_intensity = 0.2
		message = "The door opens."
	elif verb_id == WorldActionResolver.VERB_SLEEP:
		elapsed_minutes = time_rules.camp_minutes()
		exertion = 0.2
		message = "You settle into the physical shelter and rest."
	var receipt := action_coordinator.resolve_direct_action(
		request,
		elapsed_minutes,
		exertion,
		noise_intensity,
		message
	)
	if verb_id == WorldActionResolver.VERB_OPEN:
		var door := target.component("door")
		if bool(door.get("locked", false)):
			_set_event("The lock holds. Force it or find a key.")
			return null
		door["open"] = true
		door["state"] = "open"
		target.components["door"] = door
		receipt.mutations.append({"type": "door_open", "target_id": target.object_id})
	if bool(direct_preview.risk.get("trespass", false)):
		receipt.events.append({
			"type": "trespass",
			"owner_id": target.owner_id,
			"theft": verb_id in [WorldActionResolver.VERB_SEARCH, WorldActionResolver.VERB_PICK_UP],
		})
	var application := _commit_receipt(receipt, coords, target)
	if application == null or not application.applied:
		_set_event(
			application.error if application != null else "World action did not commit."
		)
		return null
	return receipt


func _actor_context() -> Dictionary:
	if not actor_context_callback.is_valid():
		return {}
	var value: Variant = actor_context_callback.call()
	return value if value is Dictionary else {}


func _consume_repair_material() -> Dictionary:
	if not consume_repair_material_callback.is_valid():
		return {}
	var value: Variant = consume_repair_material_callback.call()
	return value if value is Dictionary else {}


func _commit_receipt(
	receipt: WorldActionReceipt,
	coords: Vector2i,
	target: WorldObjectRecord
) -> WorldActionApplicationReceipt:
	if commit_receipt_callback.is_valid():
		var value: Variant = commit_receipt_callback.call(receipt, coords, target)
		return value as WorldActionApplicationReceipt
	return null


func _set_event(message: String) -> void:
	if set_event_callback.is_valid():
		set_event_callback.call(message)


func _callback(callbacks: Dictionary, key: String) -> Callable:
	var value: Variant = callbacks.get(key, Callable())
	if value is Callable:
		return value
	return Callable()
