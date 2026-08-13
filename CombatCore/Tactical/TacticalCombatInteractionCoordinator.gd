extends RefCounted
class_name TacticalCombatInteractionCoordinator

var state := CombatInteractionState.new()


func state_snapshot() -> Dictionary:
	return state.to_dict()


func set_phase(value: CombatInteractionState.Phase) -> void:
	state.phase = value


func set_controlled_actor_id(actor_id: String) -> void:
	state.controlled_actor_id = actor_id


func set_selected_actor_id(actor_id: String) -> void:
	state.selected_actor_id = actor_id


func set_selected_sector(coords: Vector2i) -> void:
	state.selected_sector = coords
	state.projected_origin = coords


func set_selected_item_id(instance_id: String) -> void:
	state.selected_item_id = instance_id


func set_selected_wound_id(wound_id: String) -> void:
	state.selected_wound_id = wound_id


func set_selected_body_region(region: int) -> void:
	state.selected_body_region = region


func set_shove_direction(direction: String) -> void:
	state.selected_shove_direction = direction


func set_neutral_attack_confirmation(value: bool) -> void:
	state.declared_neutral_attack_confirmation = value


func set_highlighted_action(index: int) -> void:
	state.highlighted_action_index = maxi(0, index)


func set_route_path(path: Array[Vector2i]) -> void:
	state.route_path = path.duplicate()
	state.projected_origin = state.route_path.back() if not state.route_path.is_empty() else state.selected_sector


func set_projected_origin(coords: Vector2i) -> void:
	state.projected_origin = coords


func set_bumped_actor_id(actor_id: String) -> void:
	state.bumped_actor_id = actor_id


func set_current_quote(value: CombatActionQuote) -> void:
	state.current_quote = value


func reset_staged_action(clear_route: bool = false) -> void:
	state.current_quote = null
	state.pending_request = null
	state.staged_action_id = ""
	state.selected_body_region = -1
	state.bumped_actor_id = ""
	if clear_route:
		state.route_path.clear()
	state.projected_origin = state.selected_sector
	if state.phase != CombatInteractionState.Phase.PRESENTING:
		state.phase = CombatInteractionState.Phase.INSPECTING


func select(kind: String, data: Dictionary) -> void:
	state.select(kind, data)


func open_root_menu() -> void:
	state.open_root_menu()


func open_action_menu() -> void:
	state.open_actions()


func open_communication_menu() -> void:
	state.open_communication()


func begin_route() -> void:
	state.phase = CombatInteractionState.Phase.ROUTE_PREVIEW
	state.staged_action_id = "move"


func stage_quote(action_id: String, legal: bool) -> void:
	state.stage(action_id, legal)


func begin_presentation() -> void:
	state.begin_presentation()


func finish_presentation() -> void:
	state.finish_presentation()


func cancel_one_step() -> void:
	state.cancel_one_step()


func clear_selection() -> void:
	state.clear()


func stage_request(request: CombatActionRequest, action_quote: CombatActionQuote) -> void:
	state.current_quote = action_quote
	state.pending_request = request.duplicate(true) if request != null and action_quote != null and action_quote.legal else null
	state.staged_action_id = request.action_id if request != null else ""
	if request == null:
		state.phase = CombatInteractionState.Phase.IDLE
	elif request.action_id == "move":
		state.phase = CombatInteractionState.Phase.ROUTE_PREVIEW
	elif request.action_id in ["offense", "defense", "support", "flee", "threaten", "ceasefire"]:
		state.phase = CombatInteractionState.Phase.COMMUNICATION_MENU
	else:
		state.phase = CombatInteractionState.Phase.CONFIRMATION if action_quote != null and action_quote.legal else CombatInteractionState.Phase.ACTION_PREVIEW


func clear_request() -> void:
	state.pending_request = null
	state.current_quote = null
	state.staged_action_id = ""


func has_pending_request() -> bool:
	return state.pending_request != null


func take_request() -> CombatActionRequest:
	var request := state.pending_request
	state.pending_request = null
	state.phase = CombatInteractionState.Phase.PRESENTING
	return request
