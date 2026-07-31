extends Node
class_name TacticalCombatAI

const MAX_ACTIONS_PER_TURN := 6

var actor: HumanoidCore
var controller: CombatActionController
var board: CombatBoard
var turn_manager: TacticalTurnManager
var target: HumanoidCore
var _rng := RandomNumberGenerator.new()
var _running := false


func configure(
	ai_actor: HumanoidCore,
	action_controller: CombatActionController,
	tactical_board: CombatBoard,
	turns: TacticalTurnManager
) -> void:
	actor = ai_actor
	controller = action_controller
	board = tactical_board
	turn_manager = turns
	_rng.seed = (board.arena_state.baseline_seed if board.arena_state != null else 1) ^ _actor_id(actor).hash()
	if not turn_manager.turn_started.is_connected(_on_turn_started):
		turn_manager.turn_started.connect(_on_turn_started)
	if turn_manager.get_active_entity() == actor:
		call_deferred("_take_turn")


func _on_turn_started(active: HumanoidCore) -> void:
	if active != actor or _running:
		return
	call_deferred("_take_turn")


func _take_turn() -> void:
	if _running:
		return
	_running = true
	target = _first_hostile()
	var actions_taken := 0
	while (
		actions_taken < MAX_ACTIONS_PER_TURN
		and turn_manager.get_active_entity() == actor
		and turn_manager.current_ap_pool > 0
		and not actor.is_dead
		and not actor.is_comatose
	):
		var candidates := enumerate_requests()
		var best_request: CombatActionRequest
		var best_score := -INF
		for request in candidates:
			var action_quote := controller.quote(request)
			if not action_quote.legal:
				continue
			var score := _score(request, action_quote) + _rng.randf_range(0.0, 0.0001)
			if score > best_score:
				best_score = score
				best_request = request
		if best_request == null or best_request.action_id == "end_turn":
			turn_manager.pass_turn(actor)
			break
		var before := turn_manager.current_ap_pool
		var outcome := await controller.request_action(best_request)
		actions_taken += 1
		if not outcome.committed or turn_manager.current_ap_pool >= before:
			turn_manager.pass_turn(actor)
			break
	_running = false


func enumerate_requests() -> Array[CombatActionRequest]:
	var requests: Array[CombatActionRequest] = []
	if actor == null or target == null:
		return requests
	var actor_id := _actor_id(actor)
	var target_id := _actor_id(target)
	for action_id in ["strike", "power_strike", "aimed_strike", "shove", "fire", "aimed_fire", "take_cover"]:
		var request := CombatActionRequest.new()
		request.actor_id = actor_id
		request.action_id = action_id
		request.target_actor_id = target_id
		if action_id in ["aimed_strike", "aimed_fire"]:
			request.target_body_region = _preferred_target_region()
		requests.append(request)
	for action_id in ["brace", "crouch", "stand", "reload", "cycle", "clear_malfunction", "escape", "end_turn"]:
		var request := CombatActionRequest.new()
		request.actor_id = actor_id
		request.action_id = action_id
		requests.append(request)
	var reachable := board.reachable_sectors(actor, controller.movement_step_base(actor), turn_manager.current_ap_pool)
	var origin := board.position_of(actor)
	for destination in reachable:
		if int(destination) == origin:
			continue
		var path := board.find_path(origin, int(destination), actor)
		if path.size() < 2:
			continue
		for action_id in ["move", "disengage"]:
			var request := CombatActionRequest.new()
			request.actor_id = actor_id
			request.action_id = action_id
			request.final_facing = board.facing_toward(int(path[-2]), int(path[-1]))
			for index in path.slice(1):
				request.path.append(CombatArenaState.coords_for_index(int(index)))
			requests.append(request)
	return requests


func _score(request: CombatActionRequest, action_quote: CombatActionQuote) -> float:
	var definition := controller.catalog.definition(request.action_id)
	var score := -float(action_quote.ap_cost) * 0.04
	var tags := definition.ai_tags
	var target_index := board.position_of(target)
	var destination := (
		CombatArenaState.index_for_coords(action_quote.target_sector)
		if CombatArenaState.contains_coords(action_quote.target_sector)
		else board.position_of(actor)
	)
	var distance := board.grid_distance(destination, target_index)
	if "damage" in tags:
		score += 4.0 + action_quote.forecast.hit_probability * 3.0 if action_quote.forecast != null else 5.0
	if "control" in tags:
		score += 2.4
	if "hazard" in tags and not action_quote.collision_preview.get("hazard", {}).is_empty():
		score += 4.0
	if "collision" in tags and str(action_quote.collision_preview.get("type", "")) != "clear":
		score += 2.5
	if "cover" in tags:
		score += board.cover_against(destination, target_index) * 3.0
	if "flank" in tags and destination >= 0:
		var incoming := board.facing_toward(target_index, destination)
		if incoming != board.get_facing(target):
			score += 1.5
	if "melee" in tags:
		score += maxf(0.0, 3.0 - distance)
	if "ranged" in tags:
		var weapon := actor.inventory.get_active_weapon(false)
		if weapon != null:
			var optimal := weapon.optimal_range_cells
			if distance >= optimal.x and distance <= optimal.y:
				score += 2.0
	if "position" in tags:
		score += maxf(0.0, 3.0 - float(distance))
	if "survival" in tags:
		var crisis := actor.body.blood_level < GameEnums.SCALE_MIDPOINT or actor.body.consciousness < GameEnums.SCALE_MIDPOINT
		score += 6.0 if crisis else -1.0
	if not action_quote.reaction_threat_ids.is_empty():
		score -= float(action_quote.reaction_threat_ids.size()) * 2.0
	if request.action_id == "end_turn":
		score = 0.2
	return score


func _preferred_target_region() -> int:
	if target == null:
		return GameEnums.LimbRegion.UPPER_TORSO
	var head_function := target.body.get_limb_function(GameEnums.LimbRegion.HEAD)
	var torso_function := target.body.get_limb_function(GameEnums.LimbRegion.UPPER_TORSO)
	return GameEnums.LimbRegion.HEAD if head_function < torso_function - 2.0 else GameEnums.LimbRegion.UPPER_TORSO


func _first_hostile() -> HumanoidCore:
	for candidate in controller.actors:
		if candidate != actor and candidate.definition.faction != actor.definition.faction and not candidate.is_dead:
			return candidate
	return null


func _actor_id(value: HumanoidCore) -> String:
	return "" if value == null else str(value.get_meta("actor_id", value.name))
