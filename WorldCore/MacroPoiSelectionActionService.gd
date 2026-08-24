extends RefCounted
class_name MacroPoiSelectionActionService

## Macro orchestration for canonical camp gear and trap deployment. The manager
## submits intent; SystemCore reconstructs and stages the real actor and hex.

const MODE_CAMP_SETUP := WorldActionPoiSelectionTransactionService.MODE_CAMP_SETUP
const MODE_SLEEP_SETUP := WorldActionPoiSelectionTransactionService.MODE_SLEEP_SETUP
const MODE_TRAP_INSTALL := WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL

var world_state: RuntimeStateStore
var action_coordinator: MacroWorldActionCoordinator
var commit_receipt: Callable
var _transaction := WorldActionPoiSelectionTransactionService.new()


func configure(
	state: RuntimeStateStore,
	coordinator: MacroWorldActionCoordinator,
	commit_callback: Callable
) -> void:
	world_state = state
	action_coordinator = coordinator
	commit_receipt = commit_callback
	_transaction.configure(state)


func resolve(
	coords: Vector2i,
	selected_instance_ids: Array,
	mode: String,
	elapsed_minutes: int = 0,
	exertion: float = 0.0,
	noise: float = 0.0
) -> Dictionary:
	if world_state == null or world_state.player_record == null:
		return _failure("Canonical player state is unavailable.")
	if action_coordinator == null or not commit_receipt.is_valid():
		return _failure("POI selection transaction services are unavailable.")
	var validation := _transaction.preview(
		coords,
		selected_instance_ids,
		mode
	)
	if not bool(validation.get("success", false)):
		return validation
	if not bool(validation.get("changed", false)):
		validation["committed"] = true
		validation["application"] = null
		return validation

	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = _target_id(mode, coords)
	request.target_coords = coords
	request.verb_id = "trap" if mode == MODE_TRAP_INSTALL else "configure_camp"
	request.method_id = "trap_gear" if mode == MODE_TRAP_INSTALL else "poi_selection"
	request.expected_actor_revision = world_state.player_record.revision
	request.payload = {
		"world_time_minutes": world_state.world_time_minutes,
		"action_id": "poi-selection:%s:%s:%d:%d" % [
			mode,
			str(coords),
			world_state.player_record.revision,
			world_state.get_hex_record(coords).revision,
		],
	}
	var receipt := action_coordinator.resolve_direct_action(
		request,
		maxi(0, elapsed_minutes),
		maxf(0.0, exertion),
		maxf(0.0, noise),
		"POI gear selection committed."
	)
	receipt.mutations.append({
		"type": WorldActionPoiSelectionTransactionService.MUTATION_TYPE,
		"mode": mode,
		"selected_instance_ids": selected_instance_ids.duplicate(),
	})
	var application: WorldActionApplicationReceipt = commit_receipt.call(receipt, coords)
	validation["action_receipt"] = receipt.to_dict()
	validation["application"] = application
	if application == null or not application.applied:
		world_state.cancel_world_action(receipt.action_id)
		return _failure(
			application.error
			if application != null and not application.error.is_empty()
			else "The POI gear transaction was rejected without changing world state."
		)
	validation["committed"] = true
	validation["message"] = "POI gear selection committed."
	return validation


func _target_id(mode: String, coords: Vector2i) -> String:
	return ("trap:" if mode == MODE_TRAP_INSTALL else "poi:") + str(coords)


func _failure(message: String) -> Dictionary:
	return {
		"success": false,
		"committed": false,
		"changed": false,
		"message": message,
		"error": message,
	}
