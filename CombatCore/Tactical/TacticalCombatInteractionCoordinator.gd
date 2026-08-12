extends RefCounted
class_name TacticalCombatInteractionCoordinator

var state := CombatInteractionState.new()


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
	state.pending_request = request if action_quote != null and action_quote.legal else null
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


func take_request() -> CombatActionRequest:
	var request := state.pending_request
	state.pending_request = null
	state.phase = CombatInteractionState.Phase.PRESENTING
	return request
