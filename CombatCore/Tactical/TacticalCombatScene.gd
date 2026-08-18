extends Node2D
class_name TacticalCombatScene

const _NpcBehaviorState := preload("res://SystemCore/NpcBehaviorState.gd")
const _InteractionCoordinator := preload("res://CombatCore/Tactical/TacticalCombatInteractionCoordinator.gd")

signal combat_finished(result: CombatResultRecord)

@onready var board: CombatBoard = $CombatBoard
@onready var turn_manager: TacticalTurnManager = $TacticalTurnManager
@onready var resolution_engine: CombatResolutionEngine = $CombatResolutionEngine
@onready var encounter_builder: TacticalEncounterBuilder = $TacticalEncounterBuilder
@onready var action_controller: CombatActionController = $CombatActionController
@onready var presentation_player: TacticalPresentationPlayer = $TacticalPresentationPlayer
@onready var hud: TacticalCombatHUD = $HUDLayer/TacticalCombatHUD

var encounter_record: CombatEncounterRecord
var player_core: HumanoidCore
var enemy_core: HumanoidCore
var enemy_entity_id := ""
var actor_cores: Array[HumanoidCore] = []
var enemy_cores: Array[HumanoidCore] = []
var _resolving := false
var _interaction_coordinator := _InteractionCoordinator.new()
var _pending_terminal: Dictionary = {}
var _terminal_flush_scheduled := false
var _transfer_receipts: Array[Dictionary] = []
var _body_locations: Array[Dictionary] = []
## Full evaluator traces are retained only for Lab/debug inspection. The HUD
## consumes the coarse public intent projection from CombatActionController.
var _ai_decision_traces: Dictionary = {}
var _participant_contexts: Dictionary = {}


func _ready() -> void:
	hud.set_interaction_coordinator(_interaction_coordinator)
	hud.context_requested.connect(_on_context_requested)
	hud.action_selected.connect(_on_action_selected)
	hud.action_confirmed.connect(_on_action_confirmed)
	hud.selection_cancelled.connect(_on_selection_cancelled)
	hud.route_context_selected.connect(_on_route_context_selected)
	hud.item_selected.connect(_refresh_context_quotes.unbind(1))
	hud.wound_selected.connect(_refresh_context_quotes.unbind(1))
	action_controller.snapshot_changed.connect(hud.show_snapshot)
	action_controller.quote_changed.connect(hud.show_quote)
	action_controller.action_denied.connect(_on_action_denied)
	action_controller.action_committed.connect(hud.show_result_events)
	action_controller.action_committed.connect(_on_action_committed)
	action_controller.presentation_requested.connect(_on_presentation_requested)
	turn_manager.combat_bleed_tick.connect(_on_combat_bleed_tick)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.action_resolution_finished.connect(_on_action_resolution_finished)
	presentation_player.configure(hud.arena_view)
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		var encounter := _combat_lab_encounter()
		var player_definition := preload("res://BiologicalCore/player_def.tres")
		var enemy_definition := preload("res://BiologicalCore/scavenger_def.tres")
		encounter.actors = [
			{"actor_id": "player", "team_id": "player", "runtime_record": {"entity_id": "player", "definition": player_definition.to_state(), "runtime": {}}},
			{"actor_id": "combat_lab_enemy", "team_id": "enemy", "runtime_record": {"entity_id": "combat_lab_enemy", "definition": enemy_definition.to_state(), "runtime": {}}},
		]
		setup_encounter(encounter)


func setup_encounter(encounter: CombatEncounterRecord) -> void:
	if encounter == null or encounter.actors.size() < 2:
		push_error("Tactical combat requires at least two actor records.")
		return
	if encounter.actors.size() > 6:
		push_error("Tactical combat supports at most six active actors.")
		return
	if encounter.late_reinforcements_enabled:
		push_warning("Late combat reinforcements are not supported; freezing the assembled roster.")
		encounter.late_reinforcements_enabled = false
	encounter_record = encounter
	resolution_engine.encounter_id = encounter.encounter_id
	_participant_contexts.clear()
	for actor_record in encounter.actors:
		_participant_contexts[str(actor_record.get("actor_id", ""))] = actor_record.get("participant_context", {}).duplicate(true)
	var dialogue_seed := str(encounter.combat_seed) if encounter.combat_seed != 0 else encounter.encounter_id
	presentation_player.configure_dialogue_seed(dialogue_seed)
	var player_record: Dictionary = _find_direct_player_record(encounter)
	var autonomous_records := _find_autonomous_actors(encounter.actors, player_record)
	if player_record.is_empty() or autonomous_records.is_empty():
		push_error("Tactical combat requires a player and at least one autonomous actor.")
		return
	_clear_actors()
	player_core = _fabricate_actor(player_record, "Player_Unit")
	player_core.set_meta("actor_id", str(player_record.get("actor_id", "player")))
	player_core.set_meta("direct_player", true)
	player_core.set_meta("combat_side", "player")
	player_core.set_meta("combat_team_id", str(player_record.get("team_id", "player")))
	player_core.set_meta("participant_context", player_record.get("participant_context", {}).duplicate(true))
	player_core.set_meta("dialogue_id", str(player_record.get("dialogue_id", "")))
	player_core.set_meta("role_id", str(player_record.get("role_id", "")))
	player_core.set_meta("faction_id", str(player_record.get("faction_id", "")))
	actor_cores.append(player_core)
	# Production encounters may contain up to five autonomous NPCs. The actor
	# registry is authoritative; never silently discard an authored participant.
	for index in range(autonomous_records.size()):
		var enemy_record: Dictionary = autonomous_records[index]
		var enemy := _fabricate_actor(enemy_record, "Enemy_Unit_%02d" % (index + 1))
		enemy.set_meta("actor_id", str(enemy_record.get("actor_id", "enemy_%02d" % index)))
		enemy.set_meta("combat_side", _combat_side_for_record(enemy_record, player_record))
		enemy.set_meta("combat_team_id", str(enemy_record.get("team_id", "enemy")))
		enemy.set_meta("participant_context", enemy_record.get("participant_context", {}).duplicate(true))
		enemy.set_meta("dialogue_id", str(enemy_record.get("dialogue_id", "")))
		enemy.set_meta("role_id", str(enemy_record.get("role_id", "")))
		enemy.set_meta("faction_id", str(enemy_record.get("faction_id", "")))
		enemy_cores.append(enemy)
		actor_cores.append(enemy)
	enemy_core = enemy_cores[0]
	enemy_entity_id = _actor_id(enemy_core)
	for actor in actor_cores:
		_wire_actor(actor)
	_resolving = false
	_pending_terminal.clear()
	_terminal_flush_scheduled = false
	_transfer_receipts.clear()
	_body_locations.clear()
	_ai_decision_traces.clear()
	turn_manager.halt_loop()
	encounter_builder.build(actor_cores, encounter)
	resolution_engine.board = board
	resolution_engine.turn_manager = turn_manager
	action_controller.configure(actor_cores, board, turn_manager, resolution_engine)
	_load_encounter_ground_items(encounter)
	action_controller.refresh_snapshot()
	hud.configure_action_catalog(action_controller.catalog)
	for index in range(enemy_cores.size()):
		var ai := TacticalCombatAI.new()
		ai.name = "TacticalCombatAI_%02d" % (index + 1)
		add_child(ai)
		ai.decision_trace_updated.connect(_on_ai_decision_trace_updated)
		ai.configure(enemy_cores[index], action_controller, board, turn_manager)
	_refresh_context_quotes()
	# Hydrated zero-blood/zero-consciousness records must resolve through the
	# same terminal path as live wounds; otherwise an old save can leave an
	# immortal target or a battle that never reaches its terminal state.
	call_deferred("_reevaluate_terminal_state")


func _fabricate_actor(actor_record: Dictionary, unit_name: String) -> HumanoidCore:
	var runtime_record: Dictionary = actor_record.get("runtime_record", {})
	return EntityFactory.record_to_humanoid_core(runtime_record, self, unit_name)


func _load_encounter_ground_items(encounter: CombatEncounterRecord) -> void:
	action_controller.ground_items.clear()
	if encounter == null:
		return
	var player_index := board.position_of(player_core)
	var fallback_coords := board.arena_state.coords_for(player_index) if player_index >= 0 else Vector2i.ZERO
	for raw_state in encounter.ground_items:
		if not raw_state is Dictionary:
			continue
		var item := ItemData.from_runtime_state(raw_state)
		if item == null or item.instance_id.is_empty():
			continue
		action_controller.ground_items[item.instance_id] = item
		var coords := _ground_item_sector(raw_state, fallback_coords)
		if not board.arena_state.contains(coords):
			coords = fallback_coords
		var sector := board.arena_state.sector_at(coords)
		if sector != null and item.instance_id not in sector.ground_item_instance_ids:
			sector.ground_item_instance_ids.append(item.instance_id)


func _ground_item_sector(raw_state: Dictionary, fallback_coords: Vector2i) -> Vector2i:
	var raw_coords: Variant = raw_state.get("sector", raw_state.get("target_sector", fallback_coords))
	if raw_coords is Vector2i:
		return raw_coords
	if raw_coords is Vector2:
		return Vector2i(roundi(raw_coords.x), roundi(raw_coords.y))
	if raw_coords is Dictionary:
		return Vector2i(int(raw_coords.get("x", fallback_coords.x)), int(raw_coords.get("y", fallback_coords.y)))
	return fallback_coords


func _wire_actor(actor: HumanoidCore) -> void:
	actor.reconcile_terminal_state()
	actor.reset_combat_transients()
	actor.died.connect(_on_actor_died.bind(actor))
	actor.incapacitated.connect(_on_actor_incapacitated.bind(actor))
	if not actor.inventory.transfer_committed.is_connected(_on_transfer_committed):
		actor.inventory.transfer_committed.connect(_on_transfer_committed)
	if not actor.inventory.items_spilled.is_connected(_on_items_spilled.bind(actor)):
		actor.inventory.items_spilled.connect(_on_items_spilled.bind(actor))
	if actor in enemy_cores and not actor.morale_broken.is_connected(_on_enemy_surrendered.bind(actor)):
		actor.morale_broken.connect(_on_enemy_surrendered.bind(actor))


func _on_context_requested(coords: Vector2i) -> void:
	if _resolving:
		return
	var sector := board.arena_state.sector_at(coords)
	if sector == null:
		return
	_refresh_context_quotes()


func _on_route_context_selected(coords: Vector2i, approach_path: Array[Vector2i]) -> void:
	if _resolving:
		return
	var route := approach_path.duplicate()
	var context_quotes: Array[CombatActionQuote] = []
	for definition in action_controller.catalog.all():
		var request := _build_request(definition.action_id, route)
		context_quotes.append(action_controller.quote(request))
	hud.show_quotes(context_quotes)
	var destination_index := board.arena_state.index_for(coords) if board.arena_state.contains(coords) else -1
	if destination_index >= 0 and board.actor_at(destination_index) == null and route.size() > 1:
		var move_request := _build_request("move", route)
		var move_quote := action_controller.preview(move_request)
		hud.show_route_quote(move_quote)
		_interaction_coordinator.stage_request(move_request, move_quote)
	else:
		_interaction_coordinator.clear_request()


func _on_action_selected(action_id: String) -> void:
	if _resolving:
		return
	var request := _build_request(action_id)
	var action_quote := action_controller.preview(request)
	hud.show_quote(action_quote)
	if not action_quote.legal:
		_interaction_coordinator.clear_request()
		return
	_interaction_coordinator.stage_request(request, action_quote)
	var definition := action_controller.catalog.definition(action_id)
	if definition != null and not definition.requires_confirmation:
		await _execute_pending_action()


func _on_action_confirmed() -> void:
	if not _resolving:
		await _execute_pending_action()


func _execute_pending_action() -> void:
	if not _interaction_coordinator.has_pending_request():
		hud.show_feedback("Select and preview a legal action first.")
		return
	var request := _interaction_coordinator.take_request()
	var outcome := await action_controller.request_action(request)
	if not outcome.committed:
		hud.show_feedback(outcome.message)
	if request.action_id == "escape" and outcome.committed:
		_finish_combat(
			GameEnums.CombatOutcome.PLAYER_ESCAPED if request.actor_id == _actor_id(player_core) else GameEnums.CombatOutcome.ENEMY_ESCAPED,
			"escape"
		)
	elif request.action_id == "leave_battle" and outcome.committed and request.actor_id == _actor_id(player_core):
		_finish_combat(GameEnums.CombatOutcome.PLAYER_ESCAPED, "leave_battle")
	hud.clear_staged_action()
	_flush_pending_terminal()
	_refresh_context_quotes()


func _on_presentation_requested(sequence: CombatPresentationSequence) -> void:
	_resolving = true
	hud.show_presentation_action(sequence)
	await presentation_player.play(sequence)
	hud.finish_presentation()
	action_controller.acknowledge_presentation(sequence.timeline_id)
	_resolving = false
	_flush_pending_terminal()
	_refresh_context_quotes()


func _on_action_resolution_finished(_actor: HumanoidCore) -> void:
	# The controller clears its busy flag immediately after this signal. Defer
	# the flush one frame so terminal outcomes are not rejected by that final
	# transaction barrier.
	if not _terminal_flush_scheduled:
		_terminal_flush_scheduled = true
		call_deferred("_flush_pending_terminal")


func _on_selection_cancelled() -> void:
	_interaction_coordinator.clear_request()


func _build_request(action_id: String, route_override: Array[Vector2i] = []) -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = _actor_id(player_core)
	request.action_id = action_id
	var context := hud.selected_context()
	request.target_actor_id = str(context.target_actor_id)
	request.target_sector = context.target_sector
	request.target_item_instance_id = str(context.item_instance_id)
	request.target_wound_id = str(context.wound_id)
	request.target_body_region = int(context.body_region)
	request.shove_direction = str(context.get("shove_direction", ""))
	request.declared_neutral_attack_confirmation = bool(context.get("declared_neutral_attack_confirmation", false))
	if action_id in ["offense", "defense", "support", "flee", "threaten", "ceasefire"]:
		request.communication_intent = action_id
	var selected_sector := board.arena_state.sector_at(request.target_sector) if board.arena_state.contains(request.target_sector) else null
	if action_id == "interact" and selected_sector != null:
		request.metadata["interaction_id"] = str(selected_sector.object_state.get("id", "inspect"))
	var actor_snapshot: Dictionary = {}
	for actor in hud.snapshot.get("actors", []):
		if str(actor.get("actor_id", "")) == request.actor_id:
			actor_snapshot = actor
			break
	var definition := action_controller.catalog.definition(action_id)
	var uses_ranged_weapon := (
		(definition != null and definition.is_ranged_weapon_action())
		or action_id in ["reload", "cycle", "ready"]
	)
	var weapon: Dictionary = actor_snapshot.get("ranged_weapon", {}) if uses_ranged_weapon else actor_snapshot.get("melee_weapon", {})
	if not weapon.is_empty():
		if action_id in ["reload", "cycle", "ready"]:
			request.target_item_instance_id = str(weapon.get("instance_id", ""))
		request.metadata["weapon_class"] = int(weapon.get("weapon_type", GameEnums.WeaponClass.NONE))
		request.metadata["weapon_id"] = str(weapon.get("definition_id", ""))
	var staged_route: Array[Vector2i] = route_override if not route_override.is_empty() else hud.staged_route()
	if definition != null and definition.target_mode == CombatActionDefinition.TARGET_PATH:
		if staged_route.size() > 1:
			request.approach_path = staged_route.duplicate()
			for coords in staged_route.slice(1):
				request.path.append(coords)
		else:
			var origin := board.position_of(player_core)
			var path: Array[int] = []
			var destination := board.arena_state.index_for(request.target_sector) if board.arena_state.contains(request.target_sector) else -1
			path = board.find_path(origin, destination, player_core)
			for index in path.slice(1):
				request.path.append(board.arena_state.coords_for(int(index)))
	elif not staged_route.is_empty() and action_id != "move":
		request.approach_path = staged_route.duplicate()
		request.path = staged_route.duplicate()
	return request


func _refresh_context_quotes() -> void:
	if player_core == null or action_controller.catalog == null:
		return
	var quotes: Array[CombatActionQuote] = []
	for definition in action_controller.catalog.all():
		var request := _build_request(definition.action_id)
		quotes.append(action_controller.quote(request))
	hud.show_quotes(quotes)


func _on_turn_started(actor: HumanoidCore) -> void:
	board.set_condition(actor, "off_balance", false)
	if actor == player_core and not _resolving:
		_refresh_context_quotes()


func _on_combat_bleed_tick(actor: HumanoidCore, _event: Dictionary) -> void:
	if actor == null:
		return
	_resolving = true
	action_controller.set_presentation_lock(true)
	var sequence := CombatPresentationSequence.new()
	sequence.action_id = "bleeding_tick"
	sequence.timeline_id = "bleeding_%s_%s" % [_actor_id(actor), str(Time.get_ticks_usec())]
	sequence.total_duration_seconds = 0.72
	sequence.impact_marker_seconds = 0.22
	var cue := CombatPresentationCue.new()
	cue.phase_id = "impact"
	cue.action_id = "bleeding_tick"
	cue.actor_id = _actor_id(actor)
	cue.target_actor_id = _actor_id(actor)
	var sector_index := board.position_of(actor)
	var coords := board.arena_state.coords_for(sector_index) if sector_index >= 0 else Vector2i(-1, -1)
	cue.start_sector = coords
	cue.end_sector = coords
	cue.duration_seconds = 0.72
	cue.animation_id = "TakeDamage"
	cue.actor_animation_id = "TakeDamage"
	cue.outcome_tag = "bleeding"
	cue.vfx_id = "melee_contact"
	sequence.cues.append(cue)
	hud.show_presentation_action(sequence)
	hud.push_consequence("BLEEDING: %s" % _actor_display_name(actor))
	await presentation_player.play(sequence)
	hud.finish_presentation()
	action_controller.set_presentation_lock(false)
	_resolving = false
	_flush_pending_terminal()
	action_controller.refresh_snapshot()
	_refresh_context_quotes()


func _actor_display_name(actor: HumanoidCore) -> String:
	if actor == null:
		return "HOSTILE"
	return str(actor.name)


func _on_action_denied(action_quote: CombatActionQuote) -> void:
	hud.show_feedback(action_quote.denial_message)


func _on_ai_decision_trace_updated(actor_id: String, trace: Array) -> void:
	_ai_decision_traces[actor_id] = trace.duplicate(true)
	set_meta("combat_lab_decision_traces", _ai_decision_traces.duplicate(true))


func get_combat_lab_decision_traces() -> Dictionary:
	return _ai_decision_traces.duplicate(true)


func _on_action_committed(outcome: CombatActionOutcome) -> void:
	# AI and player requests both pass through CombatActionController.  Terminal
	# state changes therefore need one scene-level reevaluation hook rather than
	# relying on the player HUD callback (which AI never uses).
	if outcome == null:
		return
	var terminal_recheck := false
	for event in outcome.result_events:
		if not event is Dictionary:
			continue
		var event_type := str(event.get("type", ""))
		if event_type == "executed":
			_record_handoff_body(event)
		if event_type in ["incapacitated", "surrendered", "leave_battle"]:
			terminal_recheck = true
	if terminal_recheck:
		call_deferred("_reevaluate_terminal_state")


func _on_actor_died(cause: String, actor: HumanoidCore) -> void:
	_record_body(actor)
	turn_manager.remove_combatant(actor)
	board.remove_actor(actor)
	if actor == player_core:
		_queue_terminal(GameEnums.CombatOutcome.PLAYER_DEFEAT, "death", cause)
	elif not _has_active_enemies() and not _has_hostile_npc_conflict():
		_queue_terminal(GameEnums.CombatOutcome.PLAYER_VICTORY, "death", cause)


func _on_actor_incapacitated(reason: String, actor: HumanoidCore) -> void:
	if actor == null:
		return
	if board.position_of(actor) >= 0:
		board.mark_incapacitated(actor, reason)
	turn_manager.remove_combatant(actor)
	var outcome := GameEnums.CombatOutcome.DRAW
	if player_core.is_comatose and not _has_active_enemies():
		outcome = GameEnums.CombatOutcome.DRAW
	elif actor == player_core:
		outcome = GameEnums.CombatOutcome.PLAYER_DEFEAT
	elif not _has_active_enemies() and not _has_hostile_npc_conflict():
		outcome = GameEnums.CombatOutcome.PLAYER_VICTORY
	else:
		return
	_queue_terminal(outcome, "mutual_incapacity" if outcome == GameEnums.CombatOutcome.DRAW else "incapacity", reason)


func _reevaluate_terminal_state() -> void:
	if _resolving or player_core == null:
		return
	for actor in actor_cores:
		if actor == null:
			continue
		actor.reconcile_terminal_state()
		if actor.is_dead and board.position_of(actor) >= 0:
			_record_body(actor)
			turn_manager.remove_combatant(actor)
			board.remove_actor(actor)
	if player_core.is_dead:
		_queue_terminal(GameEnums.CombatOutcome.PLAYER_DEFEAT, "death", "hydrated_zero_blood")
	elif not _has_active_enemies() and not _has_hostile_npc_conflict():
		_queue_terminal(
			GameEnums.CombatOutcome.ENEMY_SURRENDERED if _has_surrendered_enemy() else GameEnums.CombatOutcome.PLAYER_VICTORY,
			"surrender" if _has_surrendered_enemy() else "terminal_state",
			"no_player_hostile_actors"
		)


func _queue_terminal(outcome: int, reason: String, detail: String = "") -> void:
	# Terminal state is authoritative even while an action/presentation is busy.
	# Keep the first conclusion, except a player defeat always outranks a later
	# stale victory candidate.
	if _pending_terminal.is_empty() or outcome == GameEnums.CombatOutcome.PLAYER_DEFEAT:
		_pending_terminal = {"outcome": outcome, "reason": reason, "detail": detail}
	if not _terminal_flush_scheduled:
		_terminal_flush_scheduled = true
		call_deferred("_flush_pending_terminal")


func _flush_pending_terminal() -> void:
	_terminal_flush_scheduled = false
	if _pending_terminal.is_empty() or _resolving or action_controller.is_presentation_locked():
		return
	var terminal := _pending_terminal.duplicate(true)
	_pending_terminal.clear()
	_finish_combat(int(terminal.outcome), str(terminal.reason), str(terminal.detail))


func _on_enemy_surrendered(enemy: HumanoidCore) -> void:
	if enemy == null or enemy.is_dead or enemy.is_mindless_hive_thrall:
		return
	var existing_state := board.combat_state(enemy)
	if existing_state != null and existing_state.surrendered:
		return
	board.mark_surrendered(enemy, "morale")
	turn_manager.remove_combatant(enemy)
	if not _resolving and not _has_active_enemies() and not _has_hostile_npc_conflict():
		_finish_combat(GameEnums.CombatOutcome.ENEMY_SURRENDERED, "surrender")
	elif not _has_active_enemies() and not _has_hostile_npc_conflict():
		_queue_terminal(GameEnums.CombatOutcome.ENEMY_SURRENDERED, "surrender")


func _finish_combat(outcome: int, reason: String, detail: String = "") -> void:
	if _resolving:
		return
	_resolving = true
	turn_manager.halt_loop()
	var escaping_ids: Array[String] = []
	for actor in actor_cores:
		if actor != null and actor.is_escaping:
			escaping_ids.append(_actor_id(actor))
	if outcome == GameEnums.CombatOutcome.PLAYER_ESCAPED and player_core != null and _actor_id(player_core) not in escaping_ids:
		escaping_ids.append(_actor_id(player_core))
	if outcome == GameEnums.CombatOutcome.ENEMY_ESCAPED and enemy_core != null and _actor_id(enemy_core) not in escaping_ids:
		escaping_ids.append(_actor_id(enemy_core))
	for actor in actor_cores:
		actor.reset_combat_transients()
	var result := CombatResultRecord.new()
	result.encounter_id = encounter_record.encounter_id if encounter_record != null else ""
	result.source_coords = encounter_record.source_coords if encounter_record != null else Vector2i.ZERO
	result.outcome = outcome
	result.reason = reason
	result.actor_runtime_updates.clear()
	result.participant_contexts = _participant_contexts.duplicate(true)
	for actor in actor_cores:
		var actor_id := _actor_id(actor)
		var runtime_update := actor.capture_runtime_state().to_dict()
		var combat_state := board.combat_state(actor)
		if combat_state != null:
			runtime_update["combat_actor_state"] = combat_state.to_dict()
		var escaped := actor_id in escaping_ids
		if escaped:
			# reset_combat_transients() deliberately clears encounter-only flags;
			# retain the terminal escape as a result fact for macro persistence.
			runtime_update["is_escaping"] = true
		if actor in enemy_cores:
			var behavior_payload: Dictionary = actor.get_meta("npc_behavior_state", {})
			var behavior_state: Resource = _NpcBehaviorState.from_runtime(
				{_NpcBehaviorState.RUNTIME_KEY: behavior_payload},
				actor.definition.to_state() if actor.definition != null else {}
			)
			behavior_state.decision_memory["last_combat_outcome"] = outcome
			behavior_state.decision_memory["last_combat_reason"] = reason
			behavior_state.decision_memory["last_combat_round"] = turn_manager.current_round
			runtime_update[_NpcBehaviorState.RUNTIME_KEY] = behavior_state.to_dict()
		var sector_index := board.position_of(actor)
		var sector_coords := _sector_coords_for_actor(actor_id, sector_index)
		var status := "active"
		if actor.is_dead or bool(runtime_update.get("is_dead", false)):
			status = "dead"
		elif escaped:
			status = "escaped"
		elif combat_state != null and combat_state.surrendered:
			status = "surrendered"
		elif actor.is_comatose or (combat_state != null and combat_state.incapacitated):
			status = "incapacitated"
		if actor in enemy_cores and status in ["escaped", "surrendered", "incapacitated"]:
			if actor_id not in result.withdrawn_actor_ids:
				result.withdrawn_actor_ids.append(actor_id)
		if status == "escaped" and actor_id not in result.escaped_actor_ids:
			result.escaped_actor_ids.append(actor_id)
		var participant_context: Dictionary = _participant_contexts.get(actor_id, {}).duplicate(true)
		result.participant_results.append({
			"actor_id": actor_id,
			"status": status,
			"sector_index": sector_index,
			"sector_coords": sector_coords,
			"origin_coords": participant_context.get("origin_coords", Vector2i(-1, -1)),
			"macro_origin_coords": participant_context.get("macro_origin_coords", Vector2i(-1, -1)),
			"return_policy": participant_context.get("return_policy", "origin"),
			"escape_direction": participant_context.get("escape_direction", GameEnums.MacroTravelDirection.NONE),
		})
		result.actor_runtime_updates.append({
			"actor_id": actor_id,
			"runtime": runtime_update,
			"participant_context": participant_context,
		})
	result.item_transfer_receipts = _transfer_receipts.duplicate(true)
	result.body_locations = _body_locations.duplicate(true)
	result.incapacitated_locations = _incapacitated_locations()
	result.surrendered_actor_ids = _surrendered_actor_ids()
	result.surrendered_locations = _surrendered_locations()
	result.ground_items = _ground_item_states()
	result.environment_patch = board.capture_environment_patch()
	result.trap_outcomes = board.trap_outcomes.duplicate(true)
	result.relationship_state = board.relationship_ledger.to_dict() if board.relationship_ledger != null else {}
	result.communication_points_spent = board.communication_points_spent
	result.communication_points_remaining = board.communication_points
	result.elapsed_minutes = GameTimeRules.COMBAT_MINUTES
	if reason == "escape":
		var escaping: HumanoidCore = null
		for actor in actor_cores:
			if _actor_id(actor) in result.escaped_actor_ids:
				escaping = actor
				break
		var sector_index := board.position_of(escaping) if escaping != null else -1
		if sector_index >= 0:
			result.escape_edge = board.sectors[sector_index].record.escape_side
	if not detail.is_empty():
		print("[TACTICAL COMBAT] %s" % detail)
	combat_finished.emit(result)


func _on_items_spilled(spilled: Array[ItemData], actor: HumanoidCore) -> void:
	var index := board.position_of(actor)
	if index < 0:
		return
	for item in spilled:
		action_controller.ground_items[item.instance_id] = item
		if item.instance_id not in board.sectors[index].record.ground_item_instance_ids:
			board.sectors[index].record.ground_item_instance_ids.append(item.instance_id)
	action_controller.refresh_snapshot()


func _on_transfer_committed(receipt: Dictionary) -> void:
	_transfer_receipts.append(receipt.duplicate(true))


func _record_body(actor: HumanoidCore) -> void:
	var index := board.position_of(actor)
	if index < 0:
		return
	var actor_id := _actor_id(actor)
	if actor_id not in board.sectors[index].record.body_entity_ids:
		board.sectors[index].record.body_entity_ids.append(actor_id)
	_body_locations.append({"actor_id": actor_id, "sector_index": index})


func _record_handoff_body(event: Dictionary) -> void:
	var actor_id := str(event.get("actor_id", ""))
	var handoff: Dictionary = event.get("handoff", {})
	var index := int(handoff.get("sector_index", -1))
	if actor_id.is_empty() or index < 0:
		return
	for existing in _body_locations:
		if str(existing.get("actor_id", "")) == actor_id:
			return
	_body_locations.append({"actor_id": actor_id, "sector_index": index})


func _incapacitated_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sector in board.sectors:
		if sector == null or sector.record == null:
			continue
		for actor_id in sector.record.incapacitated_entity_ids:
			result.append({"actor_id": str(actor_id), "sector_index": sector.index})
	return result


func _surrendered_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for sector in board.sectors:
		if sector == null or sector.record == null:
			continue
		for actor_id in sector.record.surrendered_entity_ids:
			if str(actor_id) not in result:
				result.append(str(actor_id))
	return result


func _surrendered_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sector in board.sectors:
		if sector == null or sector.record == null:
			continue
		for actor_id in sector.record.surrendered_entity_ids:
			result.append({"actor_id": str(actor_id), "sector_index": sector.index})
	return result


func _sector_coords_for_actor(actor_id: String, sector_index: int) -> Vector2i:
	if sector_index >= 0 and sector_index < board.sectors.size():
		return board.sectors[sector_index].coords
	for sector in board.sectors:
		if sector == null or sector.record == null:
			continue
		if actor_id in sector.record.incapacitated_entity_ids or actor_id in sector.record.surrendered_entity_ids or actor_id in sector.record.body_entity_ids:
			return sector.coords
	return Vector2i(-1, -1)


func _ground_item_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in action_controller.ground_items.values():
		if item is ItemData:
			var state: Dictionary = item.to_runtime_state()
			var coords := _ground_item_coords(item.instance_id)
			if coords != Vector2i(-1, -1):
				state["sector"] = coords
			result.append(state)
	return result


func _ground_item_coords(instance_id: String) -> Vector2i:
	if board == null:
		return Vector2i(-1, -1)
	for sector in board.sectors:
		if sector != null and sector.record != null and instance_id in sector.record.ground_item_instance_ids:
			return sector.coords
	return Vector2i(-1, -1)


func _find_team_actors(records: Array[Dictionary], team_id: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for record in records:
		if str(record.get("team_id", "")) == team_id:
			matches.append(record)
	return matches


func _find_direct_player_record(encounter: CombatEncounterRecord) -> Dictionary:
	if encounter == null:
		return {}
	for record in encounter.actors:
		if bool(record.get("direct_player", false)) or str(record.get("actor_id", "")) == "player":
			return record
	for record in encounter.actors:
		if str(record.get("team_id", "")) == "player":
			return record
	return {}


func _find_autonomous_actors(records: Array[Dictionary], player_record: Dictionary = {}) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var player_id := str(player_record.get("actor_id", ""))
	for record in records:
		if str(record.get("actor_id", "")) != player_id:
			matches.append(record)
	return matches


func _combat_side_for_record(record: Dictionary, player_record: Dictionary) -> String:
	var explicit := str(record.get("combat_side", ""))
	if not explicit.is_empty():
		return explicit
	var player_team := str(player_record.get("team_id", "player"))
	return "player" if str(record.get("team_id", "")) == player_team else "enemy"


func _has_active_enemies() -> bool:
	for enemy in enemy_cores:
		if enemy != null and not enemy.is_dead and not enemy.is_comatose and not bool(enemy.get_meta("combat_surrendered", false)) and board.is_hostile(player_core, enemy):
			return true
	return false


func _has_surrendered_enemy() -> bool:
	for enemy in enemy_cores:
		if enemy == null or enemy.is_dead:
			continue
		var state := board.combat_state(enemy)
		if state != null and state.surrendered:
			return true
	return false


func _has_hostile_npc_conflict() -> bool:
	return board != null and board.has_active_hostile_conflict(player_core)


func _find_wound(actor: HumanoidCore, wound_id: String) -> Wound:
	if actor == null or wound_id.is_empty():
		return null
	for wounds in actor.body.wounds_by_limb.values():
		for wound in wounds:
			if wound is Wound and wound.wound_id == wound_id:
				return wound
	return null


func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))


func _clear_actors() -> void:
	if is_instance_valid(turn_manager):
		turn_manager.halt_loop()
	for child in get_children():
		if child is HumanoidCore or child is TacticalCombatAI:
			child.queue_free()
	player_core = null
	enemy_core = null
	actor_cores.clear()
	enemy_cores.clear()
	if is_instance_valid(board):
		board.clear_actors()


func _combat_lab_encounter() -> CombatEncounterRecord:
	return (load("res://CombatCore/Tactical/combat_lab_encounter.tres") as CombatEncounterRecord).duplicate(true)
