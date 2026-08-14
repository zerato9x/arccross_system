extends Node
class_name CombatActionController

signal snapshot_changed(snapshot: Dictionary)
signal quote_changed(quote: CombatActionQuote)
signal action_committed(outcome: CombatActionOutcome)
signal action_denied(quote: CombatActionQuote)
signal presentation_requested(sequence: CombatPresentationSequence)
signal presentation_acknowledged(timeline_id: String)
signal presentation_barrier_changed(locked: bool)
signal gameplay_revision_changed(revision: int, reason: String)
signal ai_replan_requested(actor_id: String, reason: String)

const DEFAULT_CATALOG := preload("res://CombatCore/Tactical/default_combat_action_catalog.tres")
const _ActionLegality := preload("res://CombatCore/Tactical/CombatActionLegality.gd")
const _MovementResolver := preload("res://CombatCore/Tactical/CombatMovementResolver.gd")
const _InventoryResolver := preload("res://CombatCore/Tactical/CombatInventoryActionResolver.gd")
const _CombatActorState := preload("res://SystemCore/CombatActorState.gd")
const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")
const _CommunicationResolver := preload("res://SystemCore/CombatCommunicationResolver.gd")
const _NpcBehaviorState := preload("res://SystemCore/NpcBehaviorState.gd")
const _CombatRevisionAuthority := preload("res://CombatCore/Tactical/CombatRevisionAuthority.gd")
const _CombatRulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")
const _CombatActionQuoteService := preload("res://CombatCore/Tactical/CombatActionQuoteService.gd")

var catalog: CombatActionCatalog
var board: CombatBoard
var turn_manager: TacticalTurnManager
var resolution_engine: CombatResolutionEngine
var actors: Array[HumanoidCore] = []
var ground_items: Dictionary = {}
var _resolvers: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _busy := false
var _resolution_presentation_events: Array[Dictionary] = []
var _awaiting_timeline_id := ""
var _external_presentation_lock := false
var _action_legality := _ActionLegality.new()
var _movement_resolver := _MovementResolver.new()
var _inventory_resolver := _InventoryResolver.new()
var revision_authority = _CombatRevisionAuthority.new()

var combat_revision: int:
	get:
		return revision_authority.revision


func configure(
	combatants: Array[HumanoidCore],
	tactical_board: CombatBoard,
	turns: TacticalTurnManager,
	resolver: CombatResolutionEngine,
	action_catalog: CombatActionCatalog = null
) -> void:
	revision_authority.reset(0, "configure")
	if not revision_authority.revision_changed.is_connected(_on_revision_changed):
		revision_authority.revision_changed.connect(_on_revision_changed)
	actors = combatants.duplicate()
	board = tactical_board
	turn_manager = turns
	resolution_engine = resolver
	_external_presentation_lock = false
	_awaiting_timeline_id = ""
	if resolution_engine != null:
		if not resolution_engine.damage_resolved.is_connected(_on_damage_resolved):
			resolution_engine.damage_resolved.connect(_on_damage_resolved)
		if not resolution_engine.shot_resolved.is_connected(_on_shot_resolved):
			resolution_engine.shot_resolved.connect(_on_shot_resolved)
		if not resolution_engine.presentation_resolved.is_connected(_on_presentation_resolved):
			resolution_engine.presentation_resolved.connect(_on_presentation_resolved)
	catalog = action_catalog if action_catalog != null else DEFAULT_CATALOG.duplicate(true)
	_rng.seed = board.arena_state.baseline_seed if board != null and board.arena_state != null else 1
	if resolution_engine != null:
		resolution_engine.rng.seed = _rng.seed ^ 0x5EED5EED
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
		"engage": Callable(self, "_resolve_engage"),
		"take_cover": Callable(self, "_resolve_take_cover"),
		"escape": Callable(self, "_resolve_escape"),
		"end_turn": Callable(self, "_resolve_end_turn"),
		"leave_battle": Callable(self, "_resolve_leave_battle"),
		"weapon_attack": Callable(self, "_resolve_weapon_attack"),
		"shove": Callable(self, "_resolve_shove"),
		"incapacitate": Callable(self, "_resolve_incapacitate"),
		"execute": Callable(self, "_resolve_execute"),
		"communication": Callable(self, "_resolve_communication"),
		"offense": Callable(self, "_resolve_communication"),
		"defense": Callable(self, "_resolve_communication"),
		"support": Callable(self, "_resolve_communication"),
		"flee": Callable(self, "_resolve_communication"),
		"threaten": Callable(self, "_resolve_communication"),
		"ceasefire": Callable(self, "_resolve_communication"),
		"reload": Callable(self, "_resolve_reload"),
		"cycle": Callable(self, "_resolve_cycle"),
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
	if request == null:
		return CombatActionQuote.new().deny("missing_request", "No action request was supplied.")
	var normalized := _normalized_request(request)
	var projected: CombatRulesState = rules_state_snapshot()
	var result: CombatActionQuote = _CombatActionQuoteService.quote(normalized, projected)
	# Busy/presentation locks are live transaction barriers, not legality facts.
	if result.legal and (_busy or _external_presentation_lock):
		return result.deny("busy", "Another action is resolving.")
	return result


func preview(request: CombatActionRequest) -> CombatActionQuote:
	var result := quote(request)
	quote_changed.emit(result)
	return result


func request_action(request: CombatActionRequest) -> CombatActionOutcome:
	request = _normalized_request(request)
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
	if not turn_manager.begin_action_resolution(actor, action_quote.ap_cost):
		action_quote.deny("transaction_busy", "The action transaction could not be reserved.")
		action_denied.emit(action_quote)
		return _failed_outcome(request, action_quote.denial_message)
	_busy = true
	_resolution_presentation_events.clear()
	if resolution_engine != null:
		resolution_engine.begin_random_trace()
		request.metadata["action_event_id"] = "%s:%d:%s" % [request.actor_id, combat_revision + 1, request.action_id]
		request.metadata["encounter_id"] = resolution_engine.encounter_id
		resolution_engine.begin_action_context({
			"action_id": request.action_id,
			"action_event_id": request.metadata["action_event_id"],
			"attacker_id": request.actor_id,
			"victim_id": request.target_actor_id,
			"source_item_instance_id": str(request.metadata.get("weapon_instance_id", "")),
		})
	var stance_before := _stance_snapshot()
	var positions_before := _position_snapshot()
	var relations_before := _relation_snapshot()
	var outcome: CombatActionOutcome
	if not request.approach_path.is_empty() and not _movement_resolver.is_movement_action(request.action_id):
		outcome = await _resolve_composite(request, action_quote, resolver)
	else:
		outcome = await resolver.call(request, action_quote)
	var random_draws: Array[Dictionary] = resolution_engine.consume_random_trace() if resolution_engine != null else []
	if resolution_engine != null:
		resolution_engine.end_action_context()
	if outcome != null:
		outcome.random_draws.append_array(random_draws)
		# Capture the post-resolution diff once at the semantic action boundary.
		# Composite child resolvers run inside this same transaction and therefore
		# must not publish a second, cue-level receipt.
		outcome.stance_events.append_array(_stance_events_since(stance_before))
		outcome.occupancy_transitions.append_array(_occupancy_transitions_since(positions_before))
		if outcome.relation_events.is_empty():
			outcome.relation_events.append_array(_relation_events_since(relations_before))
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
	if not _movement_resolver.is_movement_action(request.action_id):
		outcome.action_executed = outcome.action_executed or not outcome.interrupted
	var cost_to_commit := action_quote.ap_cost
	if not action_quote.path.is_empty() and _movement_resolver.is_movement_action(request.action_id):
		cost_to_commit = _movement_cost_for_steps(action_quote, outcome.movement_steps_completed)
	elif not request.approach_path.is_empty() and not _movement_resolver.is_movement_action(request.action_id):
		cost_to_commit = _movement_cost_for_steps(action_quote, outcome.movement_steps_completed)
		if outcome.action_executed:
			cost_to_commit += action_quote.action_ap_cost
	if not turn_manager.commit_action_cost(actor, request.action_id, cost_to_commit):
		push_error("Validated tactical action lost its AP reservation before commit.")
		turn_manager.end_action_resolution(actor)
		_busy = false
		return _failed_outcome(request, "AP reservation was lost.")
	outcome.ap_spent = cost_to_commit
	outcome.presentation_events.append_array(_resolution_presentation_events.duplicate(true))
	_enrich_presentation_metadata(request, actor, outcome)
	if definition.presentation_profile != null:
		outcome.presentation_sequence = definition.presentation_profile.build_sequence(request, action_quote, outcome)
	if outcome.presentation_sequence != null:
		outcome.timeline_id = outcome.presentation_sequence.timeline_id
	revision_authority.bump("action:%s" % request.action_id)
	action_committed.emit(outcome)
	if outcome.presentation_sequence != null and not DisplayServer.get_name().contains("headless"):
		_awaiting_timeline_id = outcome.presentation_sequence.timeline_id
		presentation_requested.emit(outcome.presentation_sequence)
		await presentation_acknowledged
		_awaiting_timeline_id = ""
	turn_manager.end_action_resolution(actor)
	_busy = false
	refresh_snapshot()
	var queued_replans: Dictionary = {}
	for request_payload in outcome.ai_replan_requests:
		var replan_actor_id := str(request_payload.get("actor_id", ""))
		if replan_actor_id.is_empty() or queued_replans.has(replan_actor_id):
			continue
		queued_replans[replan_actor_id] = true
		ai_replan_requested.emit(replan_actor_id, str(request_payload.get("reason", "state_changed")))
	return outcome


func acknowledge_presentation(timeline_id: String = "") -> void:
	if not _busy or _awaiting_timeline_id.is_empty():
		return
	if timeline_id.is_empty() or timeline_id == _awaiting_timeline_id:
		presentation_acknowledged.emit(_awaiting_timeline_id)


func set_presentation_lock(locked: bool) -> void:
	if _external_presentation_lock == locked:
		return
	_external_presentation_lock = locked
	presentation_barrier_changed.emit(locked)


func is_presentation_locked() -> bool:
	return _busy or _external_presentation_lock


func _on_damage_resolved(event: Dictionary) -> void:
	if _busy:
		_resolution_presentation_events.append(event.duplicate(true))


func _on_shot_resolved(event: Dictionary) -> void:
	if _busy:
		_resolution_presentation_events.append(event.duplicate(true))


func _on_presentation_resolved(event: Dictionary) -> void:
	if _busy:
		_resolution_presentation_events.append(event.duplicate(true))


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
		for coords in context.get("approach_path", context.get("path", [])):
			request.path.append(coords)
		request.approach_path = request.path.duplicate()
		results.append(quote(request))
	return results


func _apply_authoritative_weapon_metadata(request: CombatActionRequest, actor: HumanoidCore) -> void:
	if request == null or actor == null or actor.inventory == null:
		return
	var definition := catalog.definition(request.action_id) if catalog != null else null
	var is_melee := definition != null and definition.is_melee_weapon_action()
	var weapon := actor.inventory.get_active_weapon(is_melee)
	if weapon == null:
		request.metadata.erase("weapon_id")
		request.metadata["weapon_class"] = GameEnums.WeaponClass.NONE
		return
	request.metadata["weapon_id"] = weapon.id
	request.metadata["weapon_instance_id"] = weapon.instance_id
	request.metadata["weapon_class"] = int(weapon.weapon_type)
	request.metadata["weapon_action_id"] = request.action_id


func _normalized_request(request: CombatActionRequest) -> CombatActionRequest:
	var normalized := request.duplicate(true) as CombatActionRequest
	var actor := actor_by_id(normalized.actor_id)
	_apply_authoritative_weapon_metadata(normalized, actor)
	return normalized


func refresh_snapshot() -> void:
	if board == null or turn_manager == null:
		return
	var actor_data: Array[Dictionary] = []
	for actor in actors:
		if actor == null:
			continue
		actor_data.append(_actor_snapshot(actor))
	var arena_snapshot := board.snapshot()
	for sector in arena_snapshot.get("sectors", []):
		if not sector is Dictionary:
			continue
		var visible_ground_items: Array[Dictionary] = []
		for instance_id in sector.get("ground_item_instance_ids", []):
			var item := ground_items.get(str(instance_id)) as ItemData
			if item != null:
				visible_ground_items.append(_item_snapshot(item, "ground"))
		sector["ground_items"] = visible_ground_items
	var initiative_order: Array[String] = []
	for actor in turn_manager.combatants:
		if actor != null:
			initiative_order.append(_actor_id(actor))
	var active_actor := turn_manager.get_active_entity()
	snapshot_changed.emit({
		"revision": combat_revision,
		"round": turn_manager.current_round,
		"ap": turn_manager.current_ap_pool,
		"max_ap": active_actor.current_max_ap if active_actor != null else 0,
		"active_actor_id": _actor_id(active_actor),
		"initiative_order": initiative_order,
		"busy": _busy,
		"actors": actor_data,
		"arena": arena_snapshot,
	})


func rules_state_snapshot():
	return _CombatRulesState.from_board(board, turn_manager, catalog, actors, combat_revision, ground_items)


func projected_quote(request: CombatActionRequest, rules_state = null) -> CombatActionQuote:
	var projected = rules_state if rules_state != null else rules_state_snapshot()
	if request == null:
		return CombatActionQuote.new().deny("missing_request", "No action request was supplied.")
	var normalized := _normalized_request(request)
	return _CombatActionQuoteService.quote(normalized, projected)


func is_revision_current(candidate_revision: int) -> bool:
	return revision_authority.is_current(candidate_revision)


func publish_intent_view(actor_id: String, view: Dictionary) -> void:
	var subject := actor_by_id(actor_id)
	if subject == null:
		return
	var public_view := view.duplicate(true)
	subject.set_meta("combat_intent_view", public_view)
	var state := board.combat_state(subject) if board != null else null
	if state != null:
		state.public_intent = public_view.duplicate(true)
		state.intent_revision = int(public_view.get("intent_revision", state.intent_revision))
	# This is a presentation/projection update, not a gameplay revision. Passive
	# redraws must not invalidate an already quoted action.
	refresh_snapshot()


func movement_step_base(actor: HumanoidCore) -> int:
	return _movement_resolver.movement_step_base(actor, board)


func _resolve_move(request: CombatActionRequest, action_quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var indices := _quote_path_indices(action_quote)
	for offset in range(1, indices.size()):
		var from_index := board.position_of(actor)
		var to_index := int(indices[offset])
		if from_index < 0 or from_index != int(indices[offset - 1]):
			break
		var step_policy := CombatBoard.ENTRY_HOSTILE_ENGAGEMENT if request.action_id == "engage" and offset == indices.size() - 1 else CombatBoard.ENTRY_ORDINARY
		var step_changes := board.commit_path(actor, [from_index, to_index], step_policy, actor_by_id(request.target_actor_id))
		if step_changes.is_empty():
			break
		outcome.actor_changes.append_array(step_changes)
		outcome.movement_steps_completed += 1
		# Movement is an ordinary committed action unless the destination itself
		# is illegal.
		if actor.is_dead or actor.is_comatose:
			outcome.interrupted = true
			break
	if outcome.actor_changes.is_empty():
		outcome.message = "The selected path could not be committed."
		return outcome
	outcome.committed = true
	return outcome


func _resolve_composite(
	request: CombatActionRequest,
	action_quote: CombatActionQuote,
	resolver: Callable
) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var indices := _quote_path_indices(action_quote)
	var arrived := indices.size() <= 1
	for offset in range(1, indices.size()):
		var from_index := board.position_of(actor)
		var to_index := int(indices[offset])
		if from_index < 0 or from_index != int(indices[offset - 1]):
			break
		var step_policy := CombatBoard.ENTRY_HOSTILE_ENGAGEMENT if request.action_id == "engage" and offset == indices.size() - 1 else CombatBoard.ENTRY_ORDINARY
		var step_changes := board.commit_path(
			actor,
			[from_index, to_index],
			step_policy,
			actor_by_id(request.target_actor_id)
		)
		if step_changes.is_empty():
			break
		outcome.actor_changes.append_array(step_changes)
		outcome.movement_steps_completed += 1
		# Composite approaches use the same quote and one transaction across all
		# movement steps.
		if actor.is_dead or actor.is_comatose:
			outcome.interrupted = true
			break
		arrived = offset == indices.size() - 1
	if not arrived or actor.is_dead or actor.is_comatose:
		outcome.interrupted = true
		outcome.committed = not outcome.actor_changes.is_empty()
		outcome.result_events.append({
			"type": "composite_interrupted",
			"actor_id": request.actor_id,
			"action_id": request.action_id,
			"movement_steps_completed": outcome.movement_steps_completed,
			"action_cancelled": true,
		})
		outcome.message = "Movement was interrupted; the selected action was cancelled."
		return outcome
	var action_outcome: CombatActionOutcome = await resolver.call(request, action_quote)
	if action_outcome == null or not action_outcome.committed:
		outcome.interrupted = true
		outcome.committed = not outcome.actor_changes.is_empty()
		outcome.message = "The actor arrived, but the selected action could not resolve."
		return outcome
	outcome.action_executed = true
	outcome.committed = true
	outcome.actor_changes.append_array(action_outcome.actor_changes)
	outcome.sector_changes.append_array(action_outcome.sector_changes)
	outcome.rolls.append_array(action_outcome.rolls)
	outcome.wound_events.append_array(action_outcome.wound_events)
	outcome.item_receipts.append_array(action_outcome.item_receipts)
	outcome.ai_replan_requests.append_array(action_outcome.ai_replan_requests)
	outcome.terrain_mutations.append_array(action_outcome.terrain_mutations)
	outcome.result_events.append_array(action_outcome.result_events)
	outcome.communication_receipts.append_array(action_outcome.communication_receipts)
	outcome.relation_events.append_array(action_outcome.relation_events)
	outcome.occupancy_transitions.append_array(action_outcome.occupancy_transitions)
	outcome.message = action_outcome.message
	return outcome


func _resolve_engage(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	if actor == null or target == null or board.position_of(actor) != board.position_of(target):
		outcome.message = "Engage resolved without reaching the target sector."
		return outcome
	var relation_event := _establish_hostility_if_neutral(actor, target)
	if not relation_event.is_empty():
		outcome.relation_events.append(relation_event)
	outcome.actor_changes.append({
		"actor_id": request.actor_id,
		"engaged_target_id": request.target_actor_id,
		"sector": board.arena_state.coords_for(board.position_of(actor)),
	})
	outcome.committed = true
	return outcome


func _resolve_take_cover(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	if actor == null or target == null or target.is_dead or target.is_comatose:
		outcome.message = "Take Cover requires an active threat actor."
		return outcome
	var actor_index := board.position_of(actor)
	var target_index := board.position_of(target)
	if actor_index < 0 or target_index < 0 or board.cover_against(actor_index, target_index) <= 0.0:
		outcome.message = "No cover edge protects against that actor."
		return outcome
	outcome.committed = board.take_cover(actor, board.position_of(target))
	if outcome.committed:
		outcome.actor_changes.append({"actor_id": request.actor_id, "cover_edge": board.actor_cover_edges.get(request.actor_id, "")})
	return outcome


func _resolve_escape(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	if actor == null:
		outcome.message = "The actor cannot escape without a tactical sector."
		return outcome
	var actor_index := board.position_of(actor)
	var side := str(actor.get_meta("combat_side", actor.get_meta("combat_team_id", "")))
	if actor_index < 0 or actor_index >= board.sectors.size() or side.is_empty() or board.sectors[actor_index].record.escape_side != side:
		outcome.message = "Reach an eligible escape sector first."
		return outcome
	actor.is_escaping = true
	outcome.actor_changes.append({"actor_id": request.actor_id, "escaping": true})
	outcome.committed = true
	return outcome


func _resolve_end_turn(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	turn_manager.pass_turn(actor_by_id(request.actor_id))
	outcome.committed = true
	return outcome


func _resolve_leave_battle(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	if actor == null or board.has_active_player_hostile(actor):
		outcome.message = "The player still has an active hostile actor in the encounter."
		return outcome
	actor.is_escaping = true
	outcome.actor_changes.append({"actor_id": request.actor_id, "leaving_battle": true})
	outcome.result_events.append({"type": "leave_battle", "actor_id": request.actor_id})
	outcome.committed = true
	return outcome


func _resolve_weapon_attack(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	var relation_event := _establish_hostility_if_neutral(actor, target)
	if not relation_event.is_empty():
		outcome.relation_events.append(relation_event)
	var definition := catalog.definition(request.action_id)
	var resolved := false
	if definition.is_melee_weapon_action():
		resolved = await resolution_engine.execute_melee_strike(actor, target, -1, definition.effect_profile, definition.targeting_profile, request.action_id)
	elif definition.is_ranged_weapon_action():
		resolved = await resolution_engine.execute_ranged_strike(
			actor,
			board.position_of(target),
			definition.effect_profile,
			definition.targeting_profile,
			target,
			request.action_id
		)
	outcome.committed = resolved
	if not resolved:
		outcome.message = "The weapon action failed its final legality or readiness check."
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
	var collision_damage := clampf(
		board.balance_profile.shove_stance_damage * 0.5 + margin * board.balance_profile.collision_wound_per_margin,
		board.balance_profile.collision_wound_min,
		board.balance_profile.collision_wound_max
	)
	var collision := board.commit_shove(actor, target, margin, collision_damage, request.shove_direction)
	outcome.actor_changes.append({"actor_id": request.target_actor_id, "shove": collision})
	if str(collision.get("type", "")) == "object_collision":
		target.body.apply_targeted_hit(
			GameEnums.LimbRegion.UPPER_TORSO,
			collision_damage,
			0.0,
			GameEnums.DamageType.BLUNT,
			resolution_engine.injury_context(GameEnums.LimbRegion.UPPER_TORSO) if resolution_engine != null else {}
		)
		outcome.wound_events.append({"actor_id": request.target_actor_id, "region": GameEnums.LimbRegion.UPPER_TORSO, "damage": collision_damage, "source": "collision"})
	if str(collision.get("type", "")) == "actor_collision":
		# Actor-to-actor collisions are deliberately Stance-only.  The board has
		# already applied the authored collision Stance loss to both occupants;
		# do not smuggle a wound into the shove path through a generic impact.
		outcome.result_events.append({
			"type": "stance_collision",
			"target_id": request.target_actor_id,
			"other_actor_id": str(collision.get("other_actor_id", "")),
			"stance_damage": board.balance_profile.collision_stance_damage,
		})
	if collision.has("terrain_mutation") and not collision.terrain_mutation.is_empty():
		outcome.terrain_mutations.append(collision.terrain_mutation)
	if str(collision.get("type", "")) == "clear" and not bool(target.get_meta("direct_player", false)):
		outcome.ai_replan_requests.append({
			"actor_id": request.target_actor_id,
			"reason": "shoved_out_of_engagement",
		})
	outcome.committed = true
	return outcome


func _projected_occupancy_for_shove(preview: Dictionary, target: HumanoidCore) -> String:
	var kind := str(preview.get("type", ""))
	if kind in ["boundary", "forced_exit", "object_collision", "full", "invalid"]:
		return "unchanged"
	if kind == "actor_collision":
		var other := board.actor_by_id(str(preview.get("other_actor_id", "")))
		return "engaged" if other != null and board.is_hostile(target, other) else "crowded"
	if kind == "clear":
		var destination_coords: Vector2i = preview.get("destination", Vector2i(-1, -1))
		if not board.arena_state.contains(destination_coords):
			return "forced_exit"
		var destination := board.actors_at(board.arena_state.index_for(destination_coords))
		if destination.is_empty():
			return "single"
		var other: HumanoidCore = destination[0]
		return "engaged" if board.is_hostile(target, other) else "crowded"
	return "unknown"


func _resolve_incapacitate(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	if actor == null or target == null or target.is_dead or target.is_comatose or not board.is_hostile(actor, target):
		return outcome
	var state := board.combat_state(target)
	if target == null or state == null or not state.broken:
		return outcome
	var handoff := board.mark_incapacitated(target, "combat_incapacitate")
	turn_manager.remove_combatant(target)
	outcome.result_events.append({
		"type": "incapacitated",
		"actor_id": request.target_actor_id,
		"reason": "combat_incapacitate",
		"handoff": handoff,
	})
	outcome.committed = true
	return outcome


func _resolve_execute(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	if actor == null or target == null or target.is_dead or target.is_comatose or not board.is_hostile(actor, target):
		return outcome
	var state := board.combat_state(target)
	if target == null or state == null or (not state.broken and not state.incapacitated) or target.is_dead:
		return outcome
	var died := target.apply_combat_lethal_wound("Execution")
	state.broken = false
	state.incapacitated = false
	state.surrendered = false
	target.set_meta("combat_actor_state", state)
	outcome.result_events.append({
		"type": "executed",
		"actor_id": request.target_actor_id,
		"lethal": died,
	})
	outcome.committed = died
	if not died:
		outcome.message = "The biological system rejected the terminal wound."
	return outcome


func _resolve_communication(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	if actor == null or target == null or not board.spend_communication_point():
		return outcome
	var relation := board.relation_between(actor, target)
	var receipt := _CommunicationResolver.evaluate(
		request.communication_intent if not request.communication_intent.is_empty() else request.action_id,
		_communication_projection(actor),
		_communication_projection(target),
		relation,
		{"relative_force": _communication_relative_force(actor, target)},
		board.communication_profile
	)
	receipt["communication_point_spent"] = true
	# Preserve the old receipt key for macro/runtime readers that have not yet
	# migrated their display vocabulary.
	receipt["squad_point_spent"] = true
	outcome.communication_receipts.append(receipt)
	outcome.result_events.append({"type": "communication", "receipt": receipt.duplicate(true)})
	if bool(receipt.get("accepted", false)):
		var intent := str(receipt.get("intent", request.action_id))
		var target_state := board.combat_state(target)
		if intent == "ceasefire":
			board.set_relation(actor, target, _RelationshipLedger.Relation.FRIENDLY)
			outcome.relation_events.append({
				"left_id": request.actor_id,
				"right_id": request.target_actor_id,
				"relation": "friendly",
				"reason": "ceasefire_accepted",
			})
		elif intent == "threaten":
			if target_state != null and target_state.broken and float(receipt.get("score", 0.0)) >= float(receipt.get("threshold", 0.0)) + 2.0:
				var handoff := board.mark_surrendered(target, "threaten")
				turn_manager.remove_combatant(target)
				outcome.result_events.append({"type": "surrendered", "actor_id": request.target_actor_id, "reason": "threaten", "handoff": handoff})
			else:
				_set_communication_order(target, "flee")
		else:
			_set_communication_order(target, intent)
		outcome.actor_changes.append({"actor_id": request.target_actor_id, "communication_order": intent})
	outcome.committed = true
	return outcome


func _set_communication_order(target: HumanoidCore, order_id: String) -> void:
	if target == null:
		return
	var state := board.combat_state(target)
	if state != null:
		state.communication_order = order_id
	if board.relationship_ledger != null:
		board.relationship_ledger.set_order(_actor_id(target), order_id)
	var behavior_payload: Dictionary = target.get_meta("npc_behavior_state", {})
	var behavior: Resource = _NpcBehaviorState.from_runtime(
		{_NpcBehaviorState.RUNTIME_KEY: behavior_payload},
		target.definition.to_state() if target.definition != null else {}
	)
	behavior.combat_instruction = order_id
	target.set_meta("npc_behavior_state", behavior.to_dict())
	if order_id == "flee":
		target.is_fleeing = true


func _establish_hostility_if_neutral(actor: HumanoidCore, target: HumanoidCore) -> Dictionary:
	if actor == null or target == null or board.relation_between(actor, target) != _RelationshipLedger.Relation.NEUTRAL:
		return {}
	board.set_relation(actor, target, _RelationshipLedger.Relation.HOSTILE)
	return {
		"left_id": _actor_id(actor),
		"right_id": _actor_id(target),
		"relation": "hostile",
		"reason": "declared_neutral_attack",
	}


func _communication_projection(actor: HumanoidCore) -> Dictionary:
	if actor == null:
		return {}
	var behavior_payload: Dictionary = actor.get_meta("npc_behavior_state", {})
	var definition_state := actor.definition.to_state() if actor.definition != null else {}
	var behavior: Resource = _NpcBehaviorState.from_runtime(
		{_NpcBehaviorState.RUNTIME_KEY: behavior_payload}, definition_state
	)
	var agenda_id := int(actor.definition.agenda) if actor.definition != null else GameEnums.Agenda.SURVIVALIST
	var agenda: String = str(GameEnums.Agenda.keys()[clampi(agenda_id, 0, GameEnums.Agenda.keys().size() - 1)]).to_lower()
	var stance_state := board.combat_state(actor)
	return {
		"actor_id": _actor_id(actor),
		"morale": actor.current_morale,
		"pain": actor.body.get_total_pain(),
		"shock": actor.body.shock,
		"stance": stance_state.stance if stance_state != null else 12.0,
		"max_stance": stance_state.max_stance if stance_state != null else 12.0,
		"broken": stance_state.broken if stance_state != null else false,
		"survival_pressure": behavior.survival_pressure if behavior != null else 0.0,
		"agenda": agenda,
		"mindless": actor.is_mindless_hive_thrall or agenda == "mindless",
	}


func _communication_relative_force(initiator: HumanoidCore, target: HumanoidCore) -> float:
	var initiator_force := 0.0
	var target_force := 0.0
	for candidate in actors:
		if candidate == null or candidate.is_dead or candidate.is_comatose:
			continue
		if candidate == initiator or board.relation_between(initiator, candidate) == _RelationshipLedger.Relation.FRIENDLY:
			initiator_force += 1.0
		if candidate == target or board.relation_between(target, candidate) == _RelationshipLedger.Relation.FRIENDLY:
			target_force += 1.0
	return initiator_force - target_force


func _resolve_reload(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	outcome.committed = resolution_engine.execute_reload(actor_by_id(request.actor_id))
	return outcome


func _resolve_cycle(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	outcome.committed = resolution_engine.execute_cycle(actor_by_id(request.actor_id))
	return outcome


func _resolve_use(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	if actor == null or actor.inventory == null:
		return outcome
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	if item == null or item.item_type != GameEnums.ItemType.CONSUMABLE or item.stack_count <= 0 or not actor.inventory.is_combat_accessible(item):
		return outcome
	outcome.committed = actor.use_consumable_item(item, true)
	if outcome.committed:
		outcome.item_receipts.append({"type": "use", "instance_id": request.target_item_instance_id})
	return outcome


func _resolve_treat(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	if actor == null or actor.inventory == null or actor.body == null:
		return outcome
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	var wound := _wound_by_id(actor, request.target_wound_id)
	if (
		item == null
		or wound == null
		or item.item_type != GameEnums.ItemType.CONSUMABLE
		or item.stack_count <= 0
		or not actor.inventory.is_combat_accessible(item)
		or item.consumable_effect != GameEnums.ConsumableEffect.STOP_BLEEDING
		or wound.active_bleeding_rate() <= 0.0
	):
		return outcome
	if actor.body.treat_wound(request.target_wound_id, "bandage", item.consumable_potency):
		outcome.committed = actor.inventory.consume_item_units(item)
	if outcome.committed:
		outcome.item_receipts.append({"type": "treat", "instance_id": request.target_item_instance_id, "wound_id": request.target_wound_id})
	return outcome


func _resolve_drop(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	if actor == null or actor.inventory == null:
		return outcome
	var actor_index := board.position_of(actor)
	if actor_index < 0 or actor_index >= board.sectors.size():
		return outcome
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
	if actor == null or actor.inventory == null:
		return outcome
	var item := ground_items.get(request.target_item_instance_id) as ItemData
	var target_index := board.arena_state.index_for(request.target_sector)
	var actor_index := board.position_of(actor)
	var sector := board.arena_state.sector_at(request.target_sector)
	if (
		item == null
		or sector == null
		or actor_index < 0
		or target_index < 0
		or request.target_item_instance_id not in sector.ground_item_instance_ids
		or board.grid_distance(actor_index, target_index) > 1
	):
		return outcome
	if not actor.inventory.add_to_backpack(item):
		return outcome
	ground_items.erase(request.target_item_instance_id)
	sector.ground_item_instance_ids.erase(request.target_item_instance_id)
	outcome.item_receipts.append({"type": "pick_up", "instance_id": item.instance_id, "sector": request.target_sector})
	outcome.committed = true
	return outcome


func _resolve_strip(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target := actor_by_id(request.target_actor_id)
	if actor == null or target == null or actor.inventory == null or target.inventory == null:
		return outcome
	var target_state := board.combat_state(target)
	if not target.is_dead and not target.is_comatose and (target_state == null or not target_state.incapacitated):
		return outcome
	var actor_index := board.position_of(actor)
	var target_index := board.position_of(target)
	if actor_index < 0 or target_index < 0 or board.grid_distance(actor_index, target_index) > 1:
		return outcome
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
	if actor == null or actor.inventory == null:
		return outcome
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	if item == null:
		return outcome
	if item != null and item.is_ranged() and item.requires_ready_action and not item.is_readied:
		item.is_readied = true
		outcome.item_receipts.append({"type": "ready", "instance_id": item.instance_id, "weapon_ready": true})
		outcome.committed = true
		return outcome
	var slot := actor.inventory.get_preferred_equipment_slot(item)
	outcome.committed = actor.inventory.equip_item(item, slot)
	if outcome.committed:
		outcome.item_receipts.append({"type": "ready", "instance_id": item.instance_id, "slot": slot})
	return outcome


func _resolve_rummage(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	if actor == null or actor.inventory == null:
		return outcome
	var item := actor.inventory.find_item_by_instance_id(request.target_item_instance_id)
	if item == null:
		return outcome
	var quick_slot := GameEnums.EquipmentSlot.BELT
	outcome.committed = actor.inventory.move_to_container(item, quick_slot)
	if outcome.committed:
		outcome.item_receipts.append({"type": "rummage", "instance_id": item.instance_id, "container_slot": quick_slot})
	return outcome


func _resolve_interact(request: CombatActionRequest, _quote: CombatActionQuote) -> CombatActionOutcome:
	var outcome := _outcome(request)
	var actor := actor_by_id(request.actor_id)
	var target_index := board.arena_state.index_for(request.target_sector)
	var actor_index := board.position_of(actor) if actor != null else -1
	var definition := catalog.definition(request.action_id)
	var sector := board.arena_state.sector_at(request.target_sector)
	if (
		actor == null
		or target_index < 0
		or actor_index < 0
		or definition == null
		or sector == null
		or sector.object_state.is_empty()
		or (definition.maximum_range_cells > 0 and board.grid_distance(actor_index, target_index) > definition.maximum_range_cells)
	):
		return outcome
	outcome.sector_changes.append({"sector": request.target_sector, "interaction": str(request.metadata.get("interaction_id", "inspect")), "object_id": str(sector.object_state.get("id", ""))})
	outcome.committed = true
	return outcome


func _opposed_control_roll(initiator: HumanoidCore, defender: HumanoidCore, initiator_bonus: float) -> Dictionary:
	var attack_roll := resolution_engine.draw_int(1, 12, "shove_attack") if resolution_engine != null else _rng.randi_range(1, 12)
	var defense_roll := resolution_engine.draw_int(1, 12, "shove_defense") if resolution_engine != null else _rng.randi_range(1, 12)
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
	var balance := -2.0 if board.has_condition(actor, "off_balance") else 0.0
	var grip := 0.0
	var sector_index := board.position_of(actor)
	if sector_index >= 0:
		grip = -float(board.sectors[sector_index].hazard_state.get("grip_penalty", 0.0))
	return float(actor.definition.brawn) + arms + balance + grip - float(actor.total_burden) * 0.25


func _functional_arm_count(actor: HumanoidCore) -> int:
	return _action_legality.functional_arm_count(actor)


func _wound_by_id(actor: HumanoidCore, wound_id: String) -> Wound:
	if actor == null or actor.body == null or wound_id.is_empty():
		return null
	for wounds in actor.body.wounds_by_limb.values():
		for wound in wounds:
			if wound is Wound and wound.wound_id == wound_id:
				return wound
	return null


func _actor_snapshot(actor: HumanoidCore) -> Dictionary:
	actor.reconcile_terminal_state()
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
	var combat_state := board.combat_state(actor) if board != null else null
	var behavior_payload: Dictionary = actor.get_meta("npc_behavior_state", {})
	var behavior: Resource = _NpcBehaviorState.from_runtime(
		{_NpcBehaviorState.RUNTIME_KEY: behavior_payload},
		actor.definition.to_state() if actor.definition != null else {}
	)
	var agenda_id := int(actor.definition.agenda) if actor.definition != null else GameEnums.Agenda.SURVIVALIST
	var agenda: String = str(GameEnums.Agenda.keys()[clampi(agenda_id, 0, GameEnums.Agenda.keys().size() - 1)]).to_lower()
	var definition_state: Dictionary = actor.definition.to_state() if actor.definition != null else {}
	return {
		"actor_id": _actor_id(actor),
		"name": actor.name,
		"team_id": str(actor.get_meta("combat_team_id", actor.get_meta("combat_side", ""))),
		"sector": board.arena_state.coords_for(board.position_of(actor)) if board.position_of(actor) >= 0 else Vector2i(-1, -1),
		"conditions": board._tactics(actor).duplicate(true),
		"blood": actor.body.blood_level,
		"pain": actor.body.get_total_pain(),
		"shock": actor.body.shock,
		"consciousness": actor.body.consciousness,
		"region_function": _region_function(actor),
		"limbs": _limb_descriptors(actor),
		"wounds": wounds,
		"items": items,
		"equipment": _equipment_snapshot(actor),
		"ranged_weapon": _item_snapshot(ranged_weapon, "equipped") if ranged_weapon != null else {},
		"melee_weapon": _item_snapshot(melee_weapon, "equipped") if melee_weapon != null else {},
		"dead": actor.is_dead,
		"incapacitated": actor.is_comatose,
		"stance": combat_state.stance if combat_state != null else 0.0,
		"max_stance": combat_state.max_stance if combat_state != null else 0.0,
		"max_ap": actor.current_max_ap,
		"burden": actor.total_burden,
		"burden_tier": _kinetic_tier_label(actor.kinetic_tier),
		"broken": combat_state.broken if combat_state != null else false,
		"surrendered": combat_state.surrendered if combat_state != null else bool(actor.get_meta("combat_surrendered", false)),
		"agenda": agenda,
		"combat_tactic": int(actor.definition.combat_tactic) if actor.definition != null else GameEnums.CombatTactic.BRUTE,
		"survival_pressure": behavior.survival_pressure if behavior != null else 0.0,
		"behavior_profile_id": behavior.profile_id if behavior != null else "",
		"communication_order": combat_state.communication_order if combat_state != null else "",
		"public_intent": (
			combat_state.public_intent.duplicate(true)
			if combat_state != null and not combat_state.public_intent.is_empty()
			else actor.get_meta("combat_intent_view", {}).duplicate(true)
		),
		"intent_revision": combat_state.intent_revision if combat_state != null else 0,
		"mindless": actor.is_mindless_hive_thrall or agenda == "mindless",
		"direct_player": bool(actor.get_meta("direct_player", false)),
		"dialogue_id": str(definition_state.get("dialogue_id", actor.get_meta("dialogue_id", ""))),
		"role_id": str(definition_state.get("npc_role_id", actor.get_meta("role_id", ""))),
		"faction_id": str(definition_state.get("faction", actor.get_meta("faction_id", ""))),
	}


func _enrich_presentation_metadata(request: CombatActionRequest, actor: HumanoidCore, outcome: CombatActionOutcome) -> void:
	if request == null or actor == null or outcome == null:
		return
	var event := ""
	var priority := 0
	if request.action_id in ["escape", "leave_battle"]:
		event = "escape"
		priority = 2
	elif request.action_id in ["communication", "offense", "defense", "support", "flee", "threaten", "ceasefire"]:
		event = "accepted_order" if outcome.committed else "refused_order"
		priority = 2
	elif not outcome.relation_events.is_empty():
		event = "first_contact"
		priority = 1
	elif not outcome.wound_events.is_empty():
		event = "major_wound"
		priority = 0
	if event.is_empty():
		return
	var actor_snapshot := _actor_snapshot(actor)
	request.metadata["dialogue_event"] = event
	request.metadata["dialogue_id"] = str(actor_snapshot.get("dialogue_id", ""))
	request.metadata["dialogue_priority"] = priority


func _item_snapshot(item: ItemData, access: String) -> Dictionary:
	if item == null:
		return {}
	var readiness_reason := "ready"
	if item.is_ranged():
		if item.current_condition <= 0.0:
			readiness_reason = "broken"
		elif item.is_jammed:
			readiness_reason = "jammed"
		elif item.requires_ready_action and not item.is_readied:
			readiness_reason = "unready"
		elif item.current_magazine <= 0:
			readiness_reason = "empty"
	return {
		"instance_id": item.instance_id,
		"definition_id": item.id,
		"id": item.id,
		"name": item.display_name,
		"display_name": item.display_name,
		"access": access,
		"access_tier": access,
		"location": item.physical_location,
		"equipped_slot": item.equipped_slot,
		"equipment_slot": item.equipped_slot,
		"item_type": item.item_type,
		"catalog_category": item.catalog_category,
		"consumable_effect": item.consumable_effect,
		"consumable_potency": item.consumable_potency,
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
		"equipped_sprite_path": item.equipped_sprite_path,
		"equipped_sprite_paths": item.get_equipped_sprite_paths(),
		"sprite_path": item.equipped_sprite_path if not item.equipped_sprite_path.is_empty() else item.inventory_sprite_path,
		"presentation": {
			"icon_path": item.inventory_sprite_path,
			"sprite_path": item.equipped_sprite_path if not item.equipped_sprite_path.is_empty() else item.inventory_sprite_path,
			"label": item.display_name,
			"slot": item.equipped_slot,
		},
		"readiness": {"reason": readiness_reason},
		"needs_cycling": item.needs_cycling,
		"requires_cycle_after_shot": item.requires_cycle_after_shot,
		"cycle_loads_one_round": item.cycle_loads_one_round,
		"requires_ready_action": item.requires_ready_action,
		"is_readied": item.is_readied,
		"is_jammed": item.is_jammed,
		"combat_action_ids": Array(item.combat_action_ids()),
	}


func _region_function(actor: HumanoidCore) -> Dictionary:
	var result: Dictionary = {}
	for region in GameEnums.LimbRegion.values():
		result[GameEnums.LimbRegion.keys()[region].to_lower()] = actor.body.get_limb_function(region)
	return result


func _limb_descriptors(actor: HumanoidCore) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if actor == null or actor.body == null:
		return result
	for region_value in GameEnums.LimbRegion.values():
		var region := int(region_value)
		var wounds_for_region: Array[Dictionary] = []
		for wound in actor.body.get_wounds_for_limb(region):
			if wound is Wound:
				wounds_for_region.append(wound.to_dict())
		var maximum := actor.body.get_limb_max(region)
		var current := actor.body.get_limb_function(region)
		var bleeding := actor.body.get_limb_bleeding_rate(region)
		var trauma_value := int(actor.body.limb_trauma.get(region, GameEnums.TraumaType.NONE))
		var damage_type := int(actor.body.limb_damage_types.get(region, -1))
		result.append({
			"region": region,
			"region_id": str(GameEnums.LimbRegion.keys()[region]).to_lower(),
			"label": str(GameEnums.LimbRegion.keys()[region]).replace("_", " ").capitalize(),
			"current": current,
			"maximum": maximum,
			"function": current,
			"bleeding_rate": bleeding,
			"trauma": str(GameEnums.TraumaType.keys()[clampi(trauma_value, 0, GameEnums.TraumaType.keys().size() - 1)]),
			"damage_type": damage_type,
			"wounds": wounds_for_region,
		})
	return result


func _equipment_snapshot(actor: HumanoidCore) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if actor == null or actor.inventory == null:
		return result
	var seen_instance_ids: Dictionary = {}
	var slots: Array = actor.inventory.paper_doll.keys()
	slots.sort()
	for raw_slot in slots:
		var slot := int(raw_slot)
		var item: ItemData = actor.inventory.paper_doll.get(slot)
		if item == null or seen_instance_ids.has(item.instance_id):
			continue
		seen_instance_ids[item.instance_id] = true
		var descriptor := _item_snapshot(item, actor.inventory.get_access_tier(item))
		descriptor["equipment_slot"] = slot
		descriptor["equipped_slot"] = slot
		result.append(descriptor)
	return result


func _kinetic_tier_label(tier: int) -> String:
	var names := GameEnums.KineticTier.keys()
	return str(names[clampi(tier, 0, names.size() - 1)]).to_lower()


func _quote_path_indices(action_quote: CombatActionQuote) -> Array:
	return _movement_resolver.quote_path_indices(action_quote, board)


func _movement_cost_for_steps(action_quote: CombatActionQuote, completed_steps: int) -> int:
	return _movement_resolver.movement_cost_for_steps(action_quote, completed_steps)


func actor_by_id(actor_id: String) -> HumanoidCore:
	for actor in actors:
		if actor != null and _actor_id(actor) == actor_id:
			return actor
	return null


func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))


func _stance_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for actor in actors:
		if actor == null:
			continue
		var state := board.combat_state(actor)
		if state != null:
			result[_actor_id(actor)] = {
				"stance": state.stance,
				"max_stance": state.max_stance,
				"broken": state.broken,
				"incapacitated": state.incapacitated,
				"surrendered": state.surrendered,
			}
	return result


func _stance_events_since(before: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var after := _stance_snapshot()
	for actor_id in after.keys():
		var previous: Dictionary = before.get(actor_id, {})
		var current: Dictionary = after[actor_id]
		if previous.is_empty() or not is_equal_approx(float(previous.get("stance", 0.0)), float(current.get("stance", 0.0))) or previous.get("broken", false) != current.get("broken", false):
			events.append({
				"actor_id": str(actor_id),
				"before": previous.duplicate(true),
				"after": current.duplicate(true),
			})
	return events


func _position_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for actor in actors:
		if actor != null:
			result[_actor_id(actor)] = board.position_of(actor)
	return result


func _occupancy_transitions_since(before: Dictionary) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	var after := _position_snapshot()
	for actor_id in after.keys():
		var previous := int(before.get(actor_id, -1))
		var current := int(after[actor_id])
		if previous != current:
			transitions.append({"actor_id": str(actor_id), "from_index": previous, "to_index": current})
	return transitions


func _relation_snapshot() -> Dictionary:
	return board.relationship_ledger.relation_by_pair.duplicate(true) if board != null and board.relationship_ledger != null else {}


func _relation_events_since(before: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var after := _relation_snapshot()
	for key in after.keys():
		if int(before.get(key, -1)) != int(after[key]):
			events.append({"pair": str(key), "before": int(before.get(key, -1)), "after": int(after[key])})
	return events


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
	return _action_legality.path_denial(code)


func _on_state_changed() -> void:
	revision_authority.bump("board_changed")
	refresh_snapshot()


func _on_turn_changed(_actor: HumanoidCore) -> void:
	revision_authority.bump("turn")
	refresh_snapshot()


func _on_ap_spent(_actor: HumanoidCore, _remaining: int) -> void:
	revision_authority.bump("ap")
	refresh_snapshot()


func _on_revision_changed(revision: int, reason: String) -> void:
	gameplay_revision_changed.emit(revision, reason)
