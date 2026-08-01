extends Node
class_name CombatActionController

signal snapshot_changed(snapshot: Dictionary)
signal quote_changed(quote: CombatActionQuote)
signal action_committed(outcome: CombatActionOutcome)
signal action_denied(quote: CombatActionQuote)
signal presentation_requested(sequence: CombatPresentationSequence)

const DEFAULT_CATALOG := preload("res://CombatCore/Tactical/default_combat_action_catalog.tres")

var catalog: CombatActionCatalog
var board: CombatBoard
var turn_manager: TacticalTurnManager
var resolution_engine: CombatResolutionEngine
var actors: Array[HumanoidCore] = []
var ground_items: Dictionary = {}
var _resolvers: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _busy := false


func configure(
	combatants: Array[HumanoidCore],
	tactical_board: CombatBoard,
	turns: TacticalTurnManager,
	resolver: CombatResolutionEngine,
	action_catalog: CombatActionCatalog = null
) -> void:
	actors = combatants.duplicate()
	board = tactical_board
	turn_manager = turns
	resolution_engine = resolver
	catalog = action_catalog if action_catalog != null else DEFAULT_CATALOG.duplicate(true)
	_rng.seed = board.arena_state.baseline_seed if board != null and board.arena_state != null else 1
	_register_resolvers()
	if board != null and not board.board_changed.is_connected(_on_state_changed):
		board.board_changed.connect(_on_state_changed)
	if turn_manager != null:
		if not turn_manager.turn_started.is_connected(_on_turn_changed):
			turn_manager.turn_started.connect(_on_turn_changed)
		if not turn_manager.ap_spent.is_connected(_on_ap_spent):
			turn_manager.ap_spent.connect(_on_ap_spent)
	refresh_snapshot()


func _register_resolvers() -> void:
	_resolvers = {
		"move": Callable(self, "_resolve_move"),
		"change_posture": Callable(self, "_resolve_posture"),
		"disengage": Callable(self, "_resolve_disengage"),
		"brace": Callable(self, "_resolve_brace"),
		"take_cover": Callable(self, "_resolve_take_cover"),
		"escape": Callable(self, "_resolve_escape"),
		"end_turn": Callable(self, "_resolve_end_turn"),
		"strike": Callable(self, "_resolve_strike"),
		"power_strike": Callable(self, "_resolve_power_strike"),
		"aimed_strike": Callable(self, "_resolve_aimed_strike"),
		"shove": Callable(self, "_resolve_shove"),
		"fire": Callable(self, "_resolve_fire"),
		"aimed_fire": Callable(self, "_resolve_aimed_fire"),
		"reload": Callable(self, "_resolve_reload"),
		"cycle": Callable(self, "_resolve_cycle"),
		"clear_malfunction": Callable(self, "_resolve_clear_malfunction"),
		"use": Callable(self, "_resolve_use"),
		"treat": Callable(self, "_resolve_treat"),
		"pick_up": Callable(self, "_resolve_pick_up"),
		"drop": Callable(self, "_resolve_drop"),
		"strip": Callable(self, "_resolve_strip"),
		"ready": Callable(self, "_resolve_ready"),
		"rummage": Callable(self, "_resolve_rummage"),
		"interact": Callable(self, "_resolve_interact"),
	}


func quote(request: CombatActionRequest) -> CombatActionQuote:
	var result := CombatActionQuote.new()
	if request == null:
		return result.deny("missing_request", "No action request was supplied.")
	result.actor_id = request.actor_id
	result.action_id = request.action_id
	result.target_sector = request.target_sector
	result.final_facing = request.final_facing
	var definition := catalog.definition(request.action_id) if catalog != null else null
	if definition == null:
		return result.deny("unknown_action", "Unknown action ID: %s" % request.action_id)
	result.presentation_profile_id = definition.presentation_profile.profile_id if definition.presentation_profile != null else "neutral"
	var actor := actor_by_id(request.actor_id)
	if actor == null:
		return result.deny("unknown_actor", "The acting entity is not present.")
	var origin_index := board.position_of(actor)
	result.origin_sector = board.arena_state.coords_for(origin_index) if origin_index >= 0 else Vector2i(-1, -1)
	if _busy:
		return result.deny("busy", "Another action is resolving.")
	if turn_manager == null or turn_manager.get_active_entity() != actor:
		return result.deny("not_active_actor", "It is not this actor's turn.")
	if actor.is_dead or actor.is_comatose:
		return result.deny("actor_incapacitated", "The actor cannot take actions.")
	if origin_index < 0:
		return result.deny("actor_not_on_board", "The actor has no tactical sector.")
	if board.posture(actor) not in definition.required_postures and not definition.required_postures.is_empty():
		return result.deny("posture_required", "This action is unavailable while %s." % board.posture(actor))
	var requirement_denial := _validate_requirements(actor, definition)
	if not requirement_denial.is_empty():
		return result.deny(str(requirement_denial.code), str(requirement_denial.message))
	var target := actor_by_id(request.target_actor_id)
	if definition.target_mode == CombatActionDefinition.TARGET_ACTOR:
		if target == null or target == actor:
			return result.deny("invalid_target_actor", "Select another actor.")
		result.target_sector = board.arena_state.coords_for(board.position_of(target))
	if definition.target_mode == CombatActionDefinition.TARGET_SECTOR and not board.arena_state.contains(request.target_sector):
		return result.deny("invalid_target_sector", "Select a sector inside the arena.")

	if definition.target_mode == CombatActionDefinition.TARGET_PATH:
		var path_check := board.validate_path(actor, request.path)
		if not bool(path_check.valid):
			return result.deny(str(path_check.code), _path_denial(str(path_check.code)))
		var indices: Array = path_check.path
		for index in indices:
			result.path.append(board.arena_state.coords_for(int(index)))
		result.target_sector = result.path.back()
		result.movement_cost = board.path_cost(indices, movement_step_base(actor))
		if request.action_id != "disengage":
			result.reaction_threat_ids = board.reaction_threats(actor, indices)

	var target_index := board.position_of(target) if target != null else (
		board.arena_state.index_for(result.target_sector)
		if board.arena_state.contains(result.target_sector)
		else origin_index
	)
	result.range_cells = board.grid_distance(origin_index, target_index)
	if definition.minimum_range_cells > 0 and result.range_cells < definition.minimum_range_cells:
		return result.deny("target_too_close", "The target is inside the action's minimum range.")
	var maximum_range := definition.maximum_range_cells
	if request.action_id in ["strike", "power_strike", "aimed_strike", "opportunity_strike"]:
		maximum_range = board.weapon_reach(actor)
	if maximum_range > 0 and result.range_cells > maximum_range:
		return result.deny("target_out_of_range", "The target is outside the action's range.")
	if request.action_id in ["strike", "power_strike", "aimed_strike", "opportunity_strike"] and target != null:
		if not board.can_melee_reach(actor, target_index):
			return result.deny("cardinal_reach_required", "Melee reach travels only along a clear cardinal line.")
	result.has_line_of_sight = board.has_line_of_sight(origin_index, target_index)
	if definition.requires_line_of_sight and not result.has_line_of_sight:
		return result.deny("line_of_sight_blocked", "No clear line of sight reaches the target.")
	result.cover_strength = board.cover_against(target_index, origin_index) if target != null else 0.0

	var specific_denial := _validate_specific(request, actor, target, definition, result)
	if not specific_denial.is_empty():
		return result.deny(str(specific_denial.code), str(specific_denial.message))

	result.ap_cost = definition.base_ap_cost(actor.kinetic_tier, turn_manager.current_ap_pool)
	if definition.movement_cost_policy in ["path", "path_plus_action"]:
		result.ap_cost += result.movement_cost
	if not turn_manager.can_commit_action_cost(actor, result.ap_cost):
		return result.deny("insufficient_ap", "Needs %d AP; %d remains." % [result.ap_cost, turn_manager.current_ap_pool])
	if request.action_id == "shove" and target != null:
		result.collision_preview = board.preview_shove(actor, target)
		if str(result.collision_preview.get("type", "")) == "clear":
			result.predicted_displacement.append({"actor_id": request.target_actor_id, "to": result.collision_preview.destination})
	result.forecast = resolution_engine.build_forecast(request, definition, actor, target, result)
	return result.allow()


func preview(request: CombatActionRequest) -> CombatActionQuote:
	var result := quote(request)
	quote_changed.emit(result)
	return result


func request_action(request: CombatActionRequest) -> CombatActionOutcome:
	var action_quote := quote(request)
	if not action_quote.legal:
		action_denied.emit(action_quote)
		return _failed_outcome(request, action_quote.denial_message)
	var actor := actor_by_id(request.actor_id)
	var definition := catalog.definition(request.action_id)
	var resolver: Callable = _resolvers.get(definition.resolver_id, Callable())
	if not resolver.is_valid():
		action_quote.deny("resolver_missing", "No typed resolver is registered for %s." % definition.resolver_id)
		action_denied.emit(action_quote)
		return _failed_outcome(request, action_quote.denial_message)
	if not turn_manager.begin_action_resolution(actor):
		action_quote.deny("transaction_busy", "The action transaction could not be reserved.")
		action_denied.emit(action_quote)
		return _failed_outcome(request, action_quote.denial_message)
	_busy = true
	var outcome: CombatActionOutcome = await resolver.call(request, action_quote)
	if outcome == null or not outcome.committed:
		turn_manager.end_action_resolution(actor)
		_busy = false
		var message := "Resolution failed without committing state."
		if outcome != null and not outcome.message.is_empty():
			message = outcome.message
		action_quote.deny("resolution_failed", message)
		action_denied.emit(action_quote)
		refresh_snapshot()
		return outcome if outcome != null else _failed_outcome(request, message)
	if not turn_manager.commit_action_cost(actor, request.action_id, action_quote.ap_cost):
		push_error("Validated tactical action lost its AP reservation before commit.")
		turn_manager.end_action_resolution(actor)
		_busy = false
		return _failed_outcome(request, "AP reservation was lost.")
	outcome.ap_spent = action_quote.ap_cost
	turn_manager.end_action_resolution(actor)
	_busy = false
	if definition.presentation_profile != null:
		outcome.presentation_sequence = definition.presentation_profile.build_sequence(
			request.action_id,
			request.actor_id,
			request.target_actor_id,
			action_quote.origin_sector,
			action_quote.target_sector,
			action_quote.final_facing,
			action_quote.path
		)
	action_committed.emit(outcome)
	if outcome.presentation_sequence != null and not DisplayServer.get_name().contains("headless"):
		presentation_requested.emit(outcome.presentation_sequence)
	else:
		refresh_snapshot()
	return outcome


func quotes_for_actor(actor: HumanoidCore, context: Dictionary = {}) -> Array[CombatActionQuote]:
	var results: Array[CombatActionQuote] = []
	if actor == null or catalog == null:
		return results
	for definition in catalog.all():
		var request := CombatActionRequest.new()
		request.actor_id = _actor_id(actor)
		request.action_id = definition.action_id
		request.target_actor_id = str(context.get("target_actor_id", ""))
		request.target_sector = context.get("target_sector", Vector2i(-1, -1))
		request.target_item_instance_id = str(context.get("item_instance_id", ""))
		request.target_wound_id = str(context.get("wound_id", ""))
		request.final_facing = str(context.get("facing", ""))
		for coords in context.get("path", []):
			request.path.append(coords)
		results.append(quote(request))
	return results


func refresh_snapshot() -> void:
	if board == null or turn_manager == null:
		return
	var actor_data: Array[Dictionary] = []
	for actor in actors:
		if actor == null:
			continue
		actor_data.append(_actor_snapshot(actor))
	snapshot_changed.emit({
		"round": turn_manager.current_round,
		"ap": turn_manager.current_ap_pool,
		"reserved_ap": _reserved_snapshot(),
		"active_actor_id": _actor_id(turn_manager.get_active_entity()),
		"busy": _busy,
		"actors": actor_data,
		"arena": board.snapshot(),
	})


func movement_step_base(actor: HumanoidCore) -> int:
	var posture_cost := 1 if board != null and board.posture(actor) == "crouched" else 0
	match actor.kinetic_tier:
		GameEnums.KineticTier.LABORED:
			return 3 + posture_cost
		GameEnums.KineticTier.AGONIZING:
			return 4 + posture_cost
	return 2 + posture_cost


func _validate_requirements(actor: HumanoidCore, definition: CombatActionDefinition) -> Dictionary:
	for tag in definition.required_limb_tags:
		if tag == "one_arm" and not actor.body.has_functional_arms():
			return {"code": "functional_arm_required", "message": "A functional arm is required."}
		if tag == "two_arms" and _functional_arm_count(actor) < 2:
			return {"code": "two_arms_required", "message": "Two functional arms are required."}
		if tag == "legs" and actor.body.are_both_legs_disabled():
			return {"code": "functional_leg_required", "message": "A functional leg is required."}
	for tag in definition.required_equipment_tags:
		if tag == "ranged_weapon" and actor.inventory.get_active_weapon(false) == null:
			return {"code": "ranged_weapon_required", "message": "Ready a functional ranged weapon."}
	return {}


func _validate_specific(
	request: CombatActionRequest,
	actor: HumanoidCore,
	target: HumanoidCore,
	_definition: CombatActionDefinition,
	result: CombatActionQuote
) -> Dictionary:
	if request.action_id in ["aimed_strike", "aimed_fire"]:
		if request.target_body_region < 0 or request.target_body_region >= GameEnums.LimbRegion.keys().size():
			return {"code": "body_region_required", "message": "Select a body region on the target."}
	match request.action_id:
		"block", "dodge", "opportunity_strike":
			return {"code": "reaction_only", "message": "This action is only available from a reaction prompt."}
		"stand":
			if board.posture(actor) == "standing":
				return {"code": "posture_unchanged", "message": "The actor is already standing."}
			if actor.body.are_both_legs_disabled():
				return {"code": "functional_leg_required", "message": "Standing requires a functional leg."}
		"crouch":
			if board.posture(actor) != "standing":
				return {"code": "standing_required", "message": "Crouching begins from standing."}
		"move", "disengage":
			if request.final_facing.is_empty():
				result.final_facing = board.facing_toward(board.position_of(actor), board.arena_state.index_for(result.target_sector))
		"shove":
			if target == null or board.grid_distance(board.position_of(actor), board.position_of(target)) != 1:
				return {"code": "cardinal_adjacency_required", "message": "This action requires cardinal adjacency."}
		"fire", "aimed_fire":
			var weapon := actor.inventory.get_active_weapon(false)
			if weapon == null or not weapon.is_ready_to_fire():
				return {"code": "weapon_not_ready", "message": "The ranged weapon is empty, damaged, jammed, or needs cycling."}
			if result.range_cells > weapon.maximum_range_cells:
				return {"code": "weapon_range", "message": "The weapon cannot reach that sector."}
		"reload":
			var weapon := actor.inventory.get_active_weapon(false)
			if weapon == null or weapon.current_magazine >= weapon.max_magazine:
				return {"code": "reload_not_needed", "message": "The weapon cannot accept a reload."}
			if not _has_reload_source(actor, weapon):
				return {"code": "ammunition_unavailable", "message": "No compatible accessible ammunition is available."}
		"cycle":
			var weapon := actor.inventory.get_active_weapon(false)
			if weapon == null or (not weapon.needs_cycling and not weapon.cycle_loads_one_round):
				return {"code": "cycle_not_needed", "message": "The weapon does not need cycling."}
		"clear_malfunction":
			var weapon := actor.inventory.get_active_weapon(false)
			if weapon == null or not weapon.is_jammed:
				return {"code": "no_malfunction", "message": "The weapon is not malfunctioning."}
		"use", "drop", "ready", "rummage":
			var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
			if item == null:
				return {"code": "item_not_owned", "message": "Select an owned item instance."}
			if request.action_id == "use" and not actor.inventory.is_combat_accessible(item):
				return {"code": "item_not_accessible", "message": "Rummage or ready the item first."}
		"treat":
			var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
			var wound := _find_wound(actor, request.target_wound_id)
			if item == null or wound == null:
				return {"code": "treatment_target_invalid", "message": "Select a compatible item and a specific wound."}
			if not actor.inventory.is_combat_accessible(item):
				return {"code": "item_not_accessible", "message": "The treatment item is not accessible."}
			if item.consumable_effect != GameEnums.ConsumableEffect.STOP_BLEEDING or wound.active_bleeding_rate() <= 0.0:
				return {"code": "treatment_incompatible", "message": "That item cannot stabilize the selected wound."}
		"pick_up":
			if not ground_items.has(request.target_item_instance_id):
				return {"code": "ground_item_missing", "message": "The selected ground item is no longer present."}
			var sector := board.arena_state.sector_at(request.target_sector)
			if sector == null or request.target_item_instance_id not in sector.ground_item_instance_ids:
				return {"code": "ground_item_sector", "message": "The item is not in the selected sector."}
			var target_index := board.arena_state.index_for(request.target_sector)
			if board.grid_distance(board.position_of(actor), target_index) > 1:
				return {"code": "adjacency_required", "message": "Ground items require path-valid adjacency."}
		"strip":
			if target == null or (not target.is_dead and not target.is_comatose):
				return {"code": "body_not_incapacitated", "message": "Only dead or incapacitated actors can be stripped."}
			if board.grid_distance(board.position_of(actor), board.position_of(target)) > 1:
				return {"code": "adjacency_required", "message": "Stripping a body requires adjacency."}
			if target.inventory.find_item_by_instance_id(request.target_item_instance_id) == null:
				return {"code": "target_item_missing", "message": "Select an item carried by the target."}
		"take_cover":
			if target == null or board.cover_against(board.position_of(actor), board.position_of(target)) <= 0.0:
				return {"code": "cover_edge_missing", "message": "No cover edge protects against that actor."}
		"escape":
			var sector := board.sectors[board.position_of(actor)].record
			if sector.escape_side != str(actor.get_meta("combat_side", "")):
				return {"code": "escape_edge_required", "message": "Reach an eligible escape sector first."}
	return {}


func _resolve_move(request: CombatActionRequest, action_quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var indices := _quote_path_indices(action_quote)
	outcome.actor_changes = board.commit_path(actor, indices)
	if outcome.actor_changes.is_empty():
		outcome.message = "The selected path could not be committed."
		return outcome
	if not request.final_facing.is_empty():
		board.set_facing(actor, request.final_facing)
	await _resolve_opportunities(actor, action_quote, outcome)
	outcome.committed = true
	return outcome


func _resolve_posture(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var next_posture := {
		"stand": "standing",
		"crouch": "crouched",
	}.get(request.action_id, "standing") as String
	outcome.committed = board.set_posture(actor, next_posture)
	if outcome.committed:
		outcome.actor_changes.append({"actor_id": request.actor_id, "posture": next_posture})
	return outcome


func _resolve_disengage(request: CombatActionRequest, action_quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	outcome.actor_changes = board.commit_path(actor, _quote_path_indices(action_quote), true)
	if not request.final_facing.is_empty():
		board.set_facing(actor, request.final_facing)
	outcome.committed = not outcome.actor_changes.is_empty()
	return outcome


func _resolve_brace(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	board.set_condition(actor, "braced", true)
	board.set_condition(actor, "off_balance", false)
	outcome.actor_changes.append({"actor_id": request.actor_id, "braced": true, "off_balance": false})
	outcome.committed = true
	return outcome


func _resolve_take_cover(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	outcome.committed = board.take_cover(actor, board.position_of(target))
	outcome.actor_changes.append({"actor_id": request.actor_id, "cover_edge": board.actor_cover_edges.get(request.actor_id, "")})
	return outcome


func _resolve_escape(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	actor.is_escaping = true
	outcome.actor_changes.append({"actor_id": request.actor_id, "escaping": true})
	outcome.committed = true
	return outcome


func _resolve_end_turn(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	turn_manager.pass_turn(actor_by_id(request.actor_id))
	outcome.committed = true
	return outcome


func _resolve_strike(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	board.set_facing(actor, board.facing_toward(board.position_of(actor), board.position_of(target)))
	var definition := catalog.definition(request.action_id)
	await resolution_engine.execute_melee_strike(actor, target, -1, definition.effect_profile, definition.targeting_profile, request.action_id)
	outcome.committed = true
	return outcome


func _resolve_power_strike(request: CombatActionRequest, action_quote: CombatActionQuote) -> CombatActionOutcome:
	return await _resolve_strike(request, action_quote)


func _resolve_aimed_strike(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	var definition := catalog.definition(request.action_id)
	board.set_facing(actor, board.facing_toward(board.position_of(actor), board.position_of(target)))
	await resolution_engine.execute_melee_strike(
		actor,
		target,
		request.target_body_region,
		definition.effect_profile,
		definition.targeting_profile,
		request.action_id
	)
	outcome.committed = true
	return outcome


func _resolve_shove(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	var opposed := _opposed_control_roll(actor, target, 0.0)
	outcome.rolls.append(opposed)
	var margin := float(opposed.margin)
	if margin <= 0.0:
		if margin <= -4.0:
			board.set_condition(actor, "off_balance", true)
			outcome.actor_changes.append({"actor_id": request.actor_id, "off_balance": true})
		outcome.message = "The shove failed."
		outcome.committed = true
		return outcome
	var collision_damage := clampf(1.0 + margin * 0.35, 1.0, 5.0)
	var collision := board.commit_shove(actor, target, margin, collision_damage)
	outcome.actor_changes.append({"actor_id": request.target_actor_id, "shove": collision})
	if str(collision.get("type", "")) in ["object_collision", "actor_collision", "boundary"]:
		target.body.apply_targeted_hit(GameEnums.LimbRegion.UPPER_TORSO, collision_damage, 0.0, GameEnums.DamageType.BLUNT)
		outcome.wound_events.append({"actor_id": request.target_actor_id, "region": GameEnums.LimbRegion.UPPER_TORSO, "damage": collision_damage, "source": "collision"})
	if collision.has("terrain_mutation") and not collision.terrain_mutation.is_empty():
		outcome.terrain_mutations.append(collision.terrain_mutation)
	outcome.committed = true
	return outcome


func _resolve_fire(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	var definition := catalog.definition(request.action_id)
	board.set_facing(actor, board.facing_toward(board.position_of(actor), board.position_of(target)))
	await resolution_engine.execute_ranged_strike(
		actor,
		board.position_of(target),
		definition.effect_profile,
		definition.targeting_profile
	)
	outcome.committed = true
	return outcome


func _resolve_aimed_fire(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	var definition := catalog.definition(request.action_id)
	board.set_facing(actor, board.facing_toward(board.position_of(actor), board.position_of(target)))
	await resolution_engine.execute_aimed_shot(
		actor,
		board.position_of(target),
		request.target_body_region,
		definition.effect_profile,
		definition.targeting_profile
	)
	outcome.committed = true
	return outcome


func _resolve_reload(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	outcome.committed = resolution_engine.execute_reload(actor_by_id(request.actor_id))
	return outcome


func _resolve_cycle(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	outcome.committed = resolution_engine.execute_cycle(actor_by_id(request.actor_id))
	return outcome


func _resolve_clear_malfunction(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	outcome.committed = resolution_engine.execute_clear_malfunction(actor_by_id(request.actor_id))
	return outcome


func _resolve_use(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	outcome.committed = actor.use_consumable_item(item, true)
	if outcome.committed:
		outcome.item_receipts.append({"type": "use", "instance_id": request.target_item_instance_id})
	return outcome


func _resolve_treat(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	if actor.body.treat_wound(request.target_wound_id, "bandage", item.consumable_potency):
		outcome.committed = actor.inventory.consume_item_units(item)
	if outcome.committed:
		outcome.item_receipts.append({"type": "treat", "instance_id": request.target_item_instance_id, "wound_id": request.target_wound_id})
	return outcome


func _resolve_drop(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var item := actor.inventory.remove_item_by_instance_id(request.target_item_instance_id)
	if item == null:
		return outcome
	var sector := board.sectors[board.position_of(actor)].record
	ground_items[item.instance_id] = item
	sector.ground_item_instance_ids.append(item.instance_id)
	outcome.item_receipts.append({"type": "drop", "instance_id": item.instance_id, "sector": sector.coords})
	outcome.committed = true
	return outcome


func _resolve_pick_up(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var item := ground_items.get(request.target_item_instance_id) as ItemData
	if item == null or not actor.inventory.add_to_backpack(item):
		return outcome
	ground_items.erase(item.instance_id)
	var sector := board.arena_state.sector_at(request.target_sector)
	sector.ground_item_instance_ids.erase(item.instance_id)
	outcome.item_receipts.append({"type": "pick_up", "instance_id": item.instance_id, "sector": request.target_sector})
	outcome.committed = true
	return outcome


func _resolve_strip(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	var item := target.inventory.remove_item_by_instance_id(request.target_item_instance_id)
	if item == null:
		return outcome
	if not actor.inventory.add_to_backpack(item):
		target.inventory.add_to_backpack(item)
		outcome.message = "No physical storage can accept that item."
		return outcome
	outcome.item_receipts.append({
		"type": "strip",
		"instance_id": item.instance_id,
		"from_actor_id": request.target_actor_id,
		"to_actor_id": request.actor_id,
	})
	outcome.committed = true
	return outcome


func _resolve_ready(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	var slot := actor.inventory.get_preferred_equipment_slot(item)
	outcome.committed = actor.inventory.equip_item(item, slot)
	if outcome.committed:
		outcome.item_receipts.append({"type": "ready", "instance_id": item.instance_id, "slot": slot})
	return outcome


func _resolve_rummage(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	var quick_slot := GameEnums.EquipmentSlot.BELT
	outcome.committed = actor.inventory.move_to_container(item, quick_slot)
	if outcome.committed:
		outcome.item_receipts.append({"type": "rummage", "instance_id": item.instance_id, "container_slot": quick_slot})
	return outcome


func _resolve_interact(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var sector := board.arena_state.sector_at(request.target_sector)
	if sector == null or sector.object_state.is_empty():
		return outcome
	outcome.sector_changes.append({"sector": request.target_sector, "interaction": str(request.metadata.get("interaction_id", "inspect")), "object_id": str(sector.object_state.get("id", ""))})
	outcome.committed = true
	return outcome


func _resolve_opportunities(actor: HumanoidCore, action_quote: CombatActionQuote, outcome: CombatActionOutcome) -> void:
	for threat_id in action_quote.reaction_threat_ids:
		var threat := actor_by_id(threat_id)
		if threat == null or threat.is_dead:
			continue
		var available := int(turn_manager.reserved_ap.get(threat, 0))
		var cost := catalog.definition("opportunity_strike").base_ap_cost(threat.kinetic_tier, available)
		if available < cost or board.grid_distance(board.position_of(threat), board.position_of(actor)) > board.weapon_reach(threat):
			continue
		turn_manager.reserved_ap[threat] = available - cost
		await resolution_engine.execute_melee_strike(threat, actor)
		outcome.reactions.append({"actor_id": threat_id, "action_id": "opportunity_strike", "ap_spent": cost})


func _opposed_control_roll(initiator: HumanoidCore, defender: HumanoidCore, initiator_bonus: float) -> Dictionary:
	var attack_roll := _rng.randi_range(1, 12)
	var defense_roll := _rng.randi_range(1, 12)
	var attack_score := float(attack_roll) + _control_score(initiator) + initiator_bonus
	var defense_score := float(defense_roll) + _control_score(defender)
	return {
		"kind": "opposed_control",
		"attack_roll": attack_roll,
		"defense_roll": defense_roll,
		"attack_score": attack_score,
		"defense_score": defense_score,
		"margin": attack_score - defense_score,
	}


func _control_score(actor: HumanoidCore) -> float:
	if actor == null:
		return -12.0
	var arms := (
		actor.body.get_limb_function(GameEnums.LimbRegion.LEFT_ARM)
		+ actor.body.get_limb_function(GameEnums.LimbRegion.RIGHT_ARM)
	) / GameEnums.SCALE_MAX
	var posture_modifier: float = float({"standing": 2.0, "crouched": 1.0}.get(board.posture(actor), 0.0))
	var brace := 2.0 if board.has_condition(actor, "braced") else 0.0
	var balance := -2.0 if board.has_condition(actor, "off_balance") else 0.0
	var grip := 0.0
	var sector_index := board.position_of(actor)
	if sector_index >= 0:
		grip = -float(board.sectors[sector_index].hazard_state.get("grip_penalty", 0.0))
	return float(actor.definition.brawn) + arms + posture_modifier + brace + balance + grip - float(actor.total_burden) * 0.25


func _has_reload_source(actor: HumanoidCore, weapon: ItemData) -> bool:
	if not weapon.magazine_id.is_empty():
		return actor.inventory.find_filled_magazine(weapon.magazine_id) != null
	if not weapon.reload_aid_id.is_empty():
		return actor.inventory.find_filled_magazine(weapon.reload_aid_id) != null
	if weapon.cycle_loads_one_round:
		return false
	return actor.inventory.has_combat_item(weapon.ammunition_id)


func _functional_arm_count(actor: HumanoidCore) -> int:
	var count := 0
	for region in [GameEnums.LimbRegion.LEFT_ARM, GameEnums.LimbRegion.RIGHT_ARM]:
		if actor.body.get_limb_function(region) > 0.0:
			count += 1
	return count


func _find_wound(actor: HumanoidCore, wound_id: String) -> Wound:
	if actor == null or wound_id.is_empty():
		return null
	for wounds in actor.body.wounds_by_limb.values():
		for wound in wounds:
			if wound is Wound and wound.wound_id == wound_id:
				return wound
	return null


func _actor_snapshot(actor: HumanoidCore) -> Dictionary:
	var wounds: Array[Dictionary] = []
	for region in actor.body.wounds_by_limb:
		for wound in actor.body.wounds_by_limb[region]:
			if wound is Wound:
				wounds.append(wound.to_dict())
	var items: Array[Dictionary] = []
	for item in actor.inventory.get_all_items():
		items.append(_item_snapshot(item, actor.inventory.get_access_tier(item)))
	var ranged_weapon := actor.inventory.get_active_weapon(false)
	var melee_weapon := actor.inventory.get_active_weapon(true)
	return {
		"actor_id": _actor_id(actor),
		"name": actor.name,
		"team_id": str(actor.get_meta("combat_side", "")),
		"sector": board.arena_state.coords_for(board.position_of(actor)) if board.position_of(actor) >= 0 else Vector2i(-1, -1),
		"facing": board.get_facing(actor),
		"posture": board.posture(actor),
		"conditions": board._tactics(actor).duplicate(true),
		"blood": actor.body.blood_level,
		"pain": actor.body.get_total_pain(),
		"shock": actor.body.shock,
		"consciousness": actor.body.consciousness,
		"region_function": _region_function(actor),
		"wounds": wounds,
		"items": items,
		"ranged_weapon": _item_snapshot(ranged_weapon, "equipped") if ranged_weapon != null else {},
		"melee_weapon": _item_snapshot(melee_weapon, "equipped") if melee_weapon != null else {},
		"dead": actor.is_dead,
		"incapacitated": actor.is_comatose,
	}


func _item_snapshot(item: ItemData, access: String) -> Dictionary:
	if item == null:
		return {}
	var readiness_reason := "ready"
	if item.is_ranged():
		if item.current_condition <= 0.0:
			readiness_reason = "broken"
		elif item.is_jammed:
			readiness_reason = "jammed"
		elif item.needs_cycling:
			readiness_reason = "cycle"
		elif item.current_magazine <= 0:
			readiness_reason = "empty"
	return {
		"instance_id": item.instance_id,
		"definition_id": item.id,
		"id": item.id,
		"name": item.display_name,
		"display_name": item.display_name,
		"access": access,
		"location": item.physical_location,
		"equipped_slot": item.equipped_slot,
		"condition": item.current_condition,
		"current_condition": item.current_condition,
		"quantity": item.stack_count,
		"item_grade": item.item_grade,
		"weapon_type": item.weapon_type,
		"current_magazine": item.current_magazine,
		"max_magazine": item.max_magazine,
		"optimal_range_cells": item.optimal_range_cells,
		"maximum_range_cells": item.maximum_range_cells,
		"inventory_sprite_path": item.inventory_sprite_path,
		"sprite_path": item.equipped_sprite_path if not item.equipped_sprite_path.is_empty() else item.inventory_sprite_path,
		"readiness": {"reason": readiness_reason},
	}


func _region_function(actor: HumanoidCore) -> Dictionary:
	var result: Dictionary = {}
	for region in GameEnums.LimbRegion.values():
		result[GameEnums.LimbRegion.keys()[region].to_lower()] = actor.body.get_limb_function(region)
	return result


func _reserved_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for actor in turn_manager.reserved_ap:
		result[_actor_id(actor)] = int(turn_manager.reserved_ap[actor])
	return result


func _quote_path_indices(action_quote: CombatActionQuote) -> Array:
	var indices: Array = []
	for coords in action_quote.path:
		indices.append(board.arena_state.index_for(coords))
	return indices


func actor_by_id(actor_id: String) -> HumanoidCore:
	for actor in actors:
		if actor != null and _actor_id(actor) == actor_id:
			return actor
	return null


func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))


func _outcome(request: CombatActionRequest) -> CombatActionOutcome:
	var outcome := CombatActionOutcome.new()
	outcome.actor_id = request.actor_id
	outcome.action_id = request.action_id
	return outcome


func _failed_outcome(request: CombatActionRequest, message: String) -> CombatActionOutcome:
	var outcome := CombatActionOutcome.new()
	outcome.actor_id = request.actor_id if request != null else ""
	outcome.action_id = request.action_id if request != null else ""
	outcome.message = message
	return outcome


func _path_denial(code: String) -> String:
	return {
		"actor_not_on_board": "The actor is not on the board.",
		"path_out_of_bounds": "The path leaves the arena.",
		"path_not_orthogonal": "Movement paths must use orthogonal steps.",
		"path_blocked": "An obstacle or actor blocks the path.",
		"empty_path": "Select at least one destination sector.",
	}.get(code, "The selected path is invalid.")


func _on_state_changed() -> void:
	refresh_snapshot()


func _on_turn_changed(_actor: HumanoidCore) -> void:
	refresh_snapshot()


func _on_ap_spent(_actor: HumanoidCore, _remaining: int) -> void:
	refresh_snapshot()
