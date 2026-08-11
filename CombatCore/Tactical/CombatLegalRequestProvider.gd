extends RefCounted
class_name CombatLegalRequestProvider

const _QuoteService := preload("res://CombatCore/Tactical/CombatActionQuoteService.gd")
const _Catalog := preload("res://CombatCore/Tactical/CombatActionCatalog.gd")

## Catalog-driven request expansion. Templates/problem tags choose candidate
## families; the quote service remains the only legality authority.


static func generate(snapshot, motive_candidate, problem, rules_state, plan_metadata: Dictionary = {}) -> Dictionary:
	var result := {"requests": [], "quotes": [], "denials": []}
	if snapshot == null or rules_state == null or motive_candidate == null or problem == null:
		return result
	var target_id := str(motive_candidate.subject_id) if motive_candidate.subject_type == "actor" else ""
	var definitions: Array = rules_state.action_definitions.values()
	definitions.sort_custom(func(left, right): return left.action_id < right.action_id)
	for definition in definitions:
		if definition == null or not _is_ai_eligible(definition):
			continue
		if bool(snapshot.actor.get("mindless", false)) and "communication" in definition.ai_tags:
			continue
		if not _matches_problem(definition, problem.problem_id, motive_candidate.motive):
			continue
		for request in _expand_definition(definition, snapshot, motive_candidate, problem, rules_state, target_id, plan_metadata):
			var quote = _QuoteService.quote(request, rules_state)
			if quote.legal:
				result.requests.append(request)
				result.quotes.append(quote)
			else:
				result.denials.append({
					"request": request.to_dict(),
					"denial_code": quote.denial_code,
					"denial_message": quote.denial_message,
				})
	if result.requests.is_empty():
		var end_turn := CombatActionRequest.new()
		end_turn.actor_id = str(snapshot.actor.get("actor_id", ""))
		end_turn.action_id = "end_turn"
		var end_quote = _QuoteService.quote(end_turn, rules_state)
		if end_quote.legal:
			result.requests.append(end_turn)
			result.quotes.append(end_quote)
	return result


static func _is_ai_eligible(definition: CombatActionDefinition) -> bool:
	return (
		definition != null
		and definition.visibility_tier != "compatibility"
		and not _Catalog.RETIRED_PLAYER_ACTIONS.has(definition.action_id)
	)


static func _matches_problem(definition: CombatActionDefinition, problem_id: String, motive: String) -> bool:
	var tags: Array = definition.ai_tags
	match problem_id:
		"NEED_ENGAGE":
			return "engagement" in tags
		"NEED_RELOAD":
			return "reload" in tags
		"NEED_UNJAM":
			return "unjam" in tags
		"NEED_READY":
			return "ready" in tags
		"NEED_LINE_OF_FIRE", "NEED_RANGE", "NEED_POSITION":
			return "movement" in tags or "position" in tags or "cover" in tags
		"NEED_COVER":
			return "cover" in tags
		"NEED_BREAK_ENGAGEMENT":
			return "break_engagement" in tags
		"NEED_RETREAT":
			return "retreat" in tags or "survival" in tags
		"READY":
			if motive in ["ATTACK", "PRESSURE", "PURSUE"]:
				return "damage" in tags or "attack" in tags
			if motive in ["PROTECT", "SUPPORT"]:
				return "support" in tags or "cover" in tags or "movement" in tags or "position" in tags
			if motive in ["SUBMIT", "DEESCALATE"]:
				return "communication" in tags or "terminal" in tags
			return true
		"NO_LEGAL_ACTION", "SUBJECT_INVALID":
			return "terminal" in tags
	return false


static func _expand_definition(
	definition: CombatActionDefinition,
	snapshot,
	motive_candidate,
	problem,
	rules_state,
	target_id: String,
	plan_metadata: Dictionary
) -> Array:
	var requests: Array = []
	var request := CombatActionRequest.new()
	request.actor_id = str(snapshot.actor.get("actor_id", ""))
	request.action_id = definition.action_id
	request.target_actor_id = target_id
	if definition.target_mode == CombatActionDefinition.TARGET_ACTOR and not target_id.is_empty():
		request.target_sector = _target_sector(snapshot, target_id)
	var action_tags: Array = definition.ai_tags
	if definition.target_mode == CombatActionDefinition.TARGET_ACTOR and target_id.is_empty():
		return requests
	if "engagement" in action_tags:
		request.approach_path = _path_to_target_sector(rules_state, request.actor_id, target_id, true)
		request.path = request.approach_path.duplicate()
	elif definition.target_mode == CombatActionDefinition.TARGET_PATH:
		request.path = (
			_position_path(rules_state, request.actor_id, target_id)
			if not target_id.is_empty()
			else _retreat_path(rules_state, request.actor_id)
		)
		if request.path.is_empty():
			return requests
	elif definition.target_mode == CombatActionDefinition.TARGET_ITEM:
		var weapon: Dictionary = snapshot.actor.get("weapon", {})
		request.target_item_instance_id = str(weapon.get("instance_id", ""))
	if "collision" in action_tags:
		request.shove_direction = str(plan_metadata.get("shove_direction", "east"))
	if definition.resolver_id == "communication":
		request.communication_intent = definition.action_id
	request.metadata["ai_tags"] = definition.ai_tags.duplicate()
	request.metadata["planning_uncertain"] = definition.planning_outcome == "uncertain"
	var weapon: Dictionary = snapshot.actor.get("weapon", {})
	if not weapon.is_empty():
		# Request metadata is an immutable receipt for the controller/UI; the
		# provider does not use legacy cycling flags to decide legality.
		request.metadata["weapon_id"] = str(weapon.get("id", ""))
		request.metadata["weapon_instance_id"] = str(weapon.get("instance_id", ""))
		request.metadata["weapon_ready"] = not bool(weapon.get("jammed", false))
		request.metadata["magazine"] = int(weapon.get("current_magazine", 0))
		request.metadata["jammed"] = bool(weapon.get("jammed", false))
		request.metadata["behavior_profile_id"] = str(plan_metadata.get("profile_id", ""))
	requests.append(request)
	return requests


static func _target_sector(snapshot, target_id: String) -> Vector2i:
	var observed = snapshot.known_actors.get(target_id)
	return observed.sector if observed != null else Vector2i(-1, -1)


static func _path_to_target_sector(rules_state, actor_id: String, target_id: String, allow_final_engagement: bool) -> Array[Vector2i]:
	var target: Dictionary = rules_state.actor(target_id)
	var target_index := int(target.get("sector_index", -1))
	var origin: Dictionary = rules_state.actor(actor_id)
	var origin_index := int(origin.get("sector_index", -1))
	if target_index < 0 or origin_index < 0:
		return []
	var frontier: Array[int] = [origin_index]
	var came_from: Dictionary = {origin_index: -1}
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		if current == target_index:
			break
		for neighbor in rules_state.neighboring_indices(current):
			var index := int(neighbor)
			if came_from.has(index):
				continue
			var occupants: Array = rules_state.occupants_at(index)
			var is_final := index == target_index
			if is_final and allow_final_engagement:
				if occupants.size() != 1 or str(occupants[0]) != target_id:
					continue
			elif not occupants.is_empty():
				continue
			if bool(rules_state.sector(index).get("blocked", false)):
				continue
			came_from[index] = current
			frontier.append(index)
	if not came_from.has(target_index):
		return []
	return _indices_to_coords(rules_state, _reconstruct(came_from, origin_index, target_index))


static func _position_path(rules_state, actor_id: String, target_id: String) -> Array[Vector2i]:
	var target: Dictionary = rules_state.actor(target_id)
	var target_index := int(target.get("sector_index", -1))
	if target_index < 0:
		return []
	for neighbor in rules_state.neighboring_indices(target_index):
		var index := int(neighbor)
		if rules_state.occupants_at(index).is_empty() and not bool(rules_state.sector(index).get("blocked", false)):
			var path := _path_to_empty(rules_state, actor_id, index)
			if not path.is_empty():
				return path
	return []


static func _retreat_path(rules_state, actor_id: String) -> Array[Vector2i]:
	var actor: Dictionary = rules_state.actor(actor_id)
	var origin_index := int(actor.get("sector_index", -1))
	if origin_index < 0:
		return []
	var candidates: Array[int] = []
	for neighbor in rules_state.neighboring_indices(origin_index):
		candidates.append(int(neighbor))
	candidates.sort()
	for index in candidates:
		if rules_state.occupants_at(index).is_empty() and not bool(rules_state.sector(index).get("blocked", false)):
			return _indices_to_coords(rules_state, [origin_index, index])
	return []


static func _path_to_empty(rules_state, actor_id: String, target_index: int) -> Array[Vector2i]:
	var origin: Dictionary = rules_state.actor(actor_id)
	var origin_index := int(origin.get("sector_index", -1))
	var frontier: Array[int] = [origin_index]
	var came_from: Dictionary = {origin_index: -1}
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		if current == target_index:
			return _indices_to_coords(rules_state, _reconstruct(came_from, origin_index, target_index))
		for neighbor in rules_state.neighboring_indices(current):
			var index := int(neighbor)
			if came_from.has(index) or not rules_state.occupants_at(index).is_empty() or bool(rules_state.sector(index).get("blocked", false)):
				continue
			came_from[index] = current
			frontier.append(index)
	return []


static func _reconstruct(came_from: Dictionary, origin: int, destination: int) -> Array[int]:
	var path: Array[int] = [destination]
	var cursor := destination
	while cursor != origin:
		cursor = int(came_from[cursor])
		path.push_front(cursor)
	return path


static func _indices_to_coords(rules_state, indices: Array[int]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in indices:
		result.append(rules_state.coordinate_for(index))
	return result
