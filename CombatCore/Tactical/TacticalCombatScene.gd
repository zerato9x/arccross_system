extends Node2D
class_name TacticalCombatScene

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
var _resolving := false
var _transfer_receipts: Array[Dictionary] = []
var _body_locations: Array[Dictionary] = []


func _ready() -> void:
	hud.sector_selected.connect(_on_sector_selected)
	hud.action_selected.connect(_on_action_selected)
	hud.item_selected.connect(_refresh_context_quotes.unbind(1))
	hud.wound_selected.connect(_refresh_context_quotes.unbind(1))
	hud.reaction_selected.connect(_on_reaction_selected)
	action_controller.snapshot_changed.connect(hud.show_snapshot)
	action_controller.quote_changed.connect(hud.show_quote)
	action_controller.action_denied.connect(_on_action_denied)
	action_controller.presentation_requested.connect(presentation_player.play)
	turn_manager.reaction_window_opened.connect(_on_reaction_window_opened)
	turn_manager.turn_started.connect(_on_turn_started)
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
	encounter_record = encounter
	var player_actor := _find_team_actor(encounter.actors, "player")
	var enemy_actor := _find_team_actor(encounter.actors, "enemy")
	if player_actor.is_empty() or enemy_actor.is_empty():
		push_error("Tactical combat requires player and enemy teams.")
		return
	_clear_actors()
	player_core = _fabricate_actor(player_actor, "Player_Unit")
	enemy_core = _fabricate_actor(enemy_actor, "Enemy_Unit")
	player_core.set_meta("actor_id", str(player_actor.get("actor_id", "player")))
	enemy_core.set_meta("actor_id", str(enemy_actor.get("actor_id", "enemy")))
	enemy_entity_id = str(enemy_actor.get("actor_id", "enemy"))
	_wire_actor(player_core)
	_wire_actor(enemy_core)
	_resolving = false
	_transfer_receipts.clear()
	_body_locations.clear()
	turn_manager.halt_loop()
	encounter_builder.build(player_core, enemy_core, encounter)
	resolution_engine.board = board
	resolution_engine.turn_manager = turn_manager
	action_controller.configure([player_core, enemy_core], board, turn_manager, resolution_engine)
	var ai := TacticalCombatAI.new()
	ai.name = "TacticalCombatAI"
	add_child(ai)
	ai.configure(enemy_core, action_controller, board, turn_manager)
	_refresh_context_quotes()


func _fabricate_actor(actor_record: Dictionary, unit_name: String) -> HumanoidCore:
	var runtime_record: Dictionary = actor_record.get("runtime_record", {})
	return EntityFactory.record_to_humanoid_core(runtime_record, self, unit_name)


func _wire_actor(actor: HumanoidCore) -> void:
	actor.reset_combat_transients()
	actor.died.connect(_on_actor_died.bind(actor))
	actor.incapacitated.connect(_on_actor_incapacitated.bind(actor))
	if not actor.inventory.transfer_committed.is_connected(_on_transfer_committed):
		actor.inventory.transfer_committed.connect(_on_transfer_committed)
	if not actor.inventory.items_spilled.is_connected(_on_items_spilled.bind(actor)):
		actor.inventory.items_spilled.connect(_on_items_spilled.bind(actor))
	if actor == enemy_core and not actor.morale_broken.is_connected(_on_enemy_surrendered):
		actor.morale_broken.connect(_on_enemy_surrendered)


func _on_sector_selected(coords: Vector2i) -> void:
	var request := _build_request("move")
	var destination := CombatArenaState.index_for_coords(coords)
	var origin := board.position_of(player_core)
	var path := board.find_path(origin, destination, player_core)
	for index in path.slice(1):
		request.path.append(CombatArenaState.coords_for_index(int(index)))
	if path.size() >= 2:
		request.final_facing = board.facing_toward(int(path[-2]), int(path[-1]))
	hud.show_quote(action_controller.preview(request))
	_refresh_context_quotes()


func _on_action_selected(action_id: String) -> void:
	if _resolving:
		return
	var request := _build_request(action_id)
	var outcome := await action_controller.request_action(request)
	if not outcome.committed:
		hud.show_feedback(outcome.message)
	if action_id == "escape" and outcome.committed:
		_finish_combat(
			GameEnums.CombatOutcome.PLAYER_ESCAPED if request.actor_id == _actor_id(player_core) else GameEnums.CombatOutcome.ENEMY_ESCAPED,
			"escape"
		)
	_refresh_context_quotes()


func _build_request(action_id: String) -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = _actor_id(player_core)
	request.action_id = action_id
	var context := hud.selected_context()
	request.target_actor_id = str(context.target_actor_id)
	request.target_sector = context.target_sector
	request.target_item_instance_id = str(context.item_instance_id)
	request.target_wound_id = str(context.wound_id)
	request.final_facing = str(context.facing)
	var definition := action_controller.catalog.definition(action_id)
	if definition != null and definition.target_mode == CombatActionDefinition.TARGET_PATH:
		var origin := board.position_of(player_core)
		var path: Array[int] = []
		if action_id == "drag" and board.grapple_target(player_core) != null:
			path = [origin, board.position_of(board.grapple_target(player_core))]
		else:
			var destination := CombatArenaState.index_for_coords(request.target_sector) if CombatArenaState.contains_coords(request.target_sector) else -1
			path = board.find_path(origin, destination, player_core)
		for index in path.slice(1):
			request.path.append(CombatArenaState.coords_for_index(int(index)))
		if action_id == "drag" and path.size() == 2:
			request.path.push_front(CombatArenaState.coords_for_index(origin))
		if request.final_facing.is_empty() and path.size() >= 2:
			request.final_facing = board.facing_toward(int(path[-2]), int(path[-1]))
	if action_id == "turn" and request.final_facing.is_empty() and CombatArenaState.contains_coords(request.target_sector):
		request.final_facing = board.facing_toward(board.position_of(player_core), CombatArenaState.index_for_coords(request.target_sector))
	if action_id == "aimed_fire":
		var wound := _find_wound(enemy_core, request.target_wound_id)
		request.metadata["body_region"] = wound.body_region if wound != null else GameEnums.LimbRegion.UPPER_TORSO
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
	board.set_condition(actor, "braced", false)
	board.set_condition(actor, "off_balance", false)
	board._tactics(actor)["momentum"] = 0
	board.break_invalid_grapples()
	if actor == player_core:
		_refresh_context_quotes()


func _on_reaction_window_opened(
	defender: HumanoidCore,
	_attacker: HumanoidCore,
	_trigger_action,
	available: Array
) -> void:
	if defender == player_core:
		var ids: Array[String] = []
		for action in available:
			ids.append(str(action))
		hud.show_reaction({"actions": ids})
	else:
		var choice = available[0] if not available.is_empty() else -1
		if choice == -1:
			turn_manager.decline_reaction(defender)
		else:
			turn_manager.resolve_reaction(defender, choice)


func _on_reaction_selected(action_id: String) -> void:
	if not turn_manager.resolve_reaction(player_core, action_id):
		turn_manager.decline_reaction(player_core)


func _on_action_denied(action_quote: CombatActionQuote) -> void:
	hud.show_feedback(action_quote.denial_message)


func _on_actor_died(cause: String, actor: HumanoidCore) -> void:
	if _resolving:
		return
	_record_body(actor)
	var outcome := GameEnums.CombatOutcome.PLAYER_DEFEAT if actor == player_core else GameEnums.CombatOutcome.PLAYER_VICTORY
	_finish_combat(outcome, "death", cause)


func _on_actor_incapacitated(reason: String, actor: HumanoidCore) -> void:
	if _resolving:
		return
	var outcome := GameEnums.CombatOutcome.DRAW
	if player_core.is_comatose and enemy_core.is_comatose:
		outcome = GameEnums.CombatOutcome.DRAW
	elif actor == player_core:
		outcome = GameEnums.CombatOutcome.PLAYER_DEFEAT
	else:
		outcome = GameEnums.CombatOutcome.PLAYER_VICTORY
	_finish_combat(outcome, "mutual_incapacity" if outcome == GameEnums.CombatOutcome.DRAW else "incapacity", reason)


func _on_enemy_surrendered() -> void:
	if not _resolving and enemy_core != null and not enemy_core.is_dead and not enemy_core.is_mindless_hive_thrall:
		_finish_combat(GameEnums.CombatOutcome.ENEMY_SURRENDERED, "surrender")


func _finish_combat(outcome: int, reason: String, detail: String = "") -> void:
	if _resolving:
		return
	_resolving = true
	turn_manager.halt_loop()
	board.break_grapple(player_core)
	board.break_grapple(enemy_core)
	player_core.reset_combat_transients()
	enemy_core.reset_combat_transients()
	var result := CombatResultRecord.new()
	result.encounter_id = encounter_record.encounter_id if encounter_record != null else ""
	result.source_coords = encounter_record.source_coords if encounter_record != null else Vector2i.ZERO
	result.outcome = outcome
	result.reason = reason
	result.actor_runtime_updates = [
		{"actor_id": "player", "runtime": player_core.capture_runtime_state().to_dict()},
		{"actor_id": enemy_entity_id, "runtime": enemy_core.capture_runtime_state().to_dict()},
	]
	result.item_transfer_receipts = _transfer_receipts.duplicate(true)
	result.body_locations = _body_locations.duplicate(true)
	result.ground_items = _ground_item_states()
	result.environment_patch = board.capture_environment_patch()
	result.trap_outcomes = board.trap_outcomes.duplicate(true)
	result.elapsed_minutes = GameTimeRules.COMBAT_MINUTES
	if reason == "escape":
		var escaping := player_core if outcome == GameEnums.CombatOutcome.PLAYER_ESCAPED else enemy_core
		var sector_index := board.position_of(escaping)
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


func _ground_item_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in action_controller.ground_items.values():
		if item is ItemData:
			result.append(item.to_runtime_state())
	return result


func _find_team_actor(records: Array[Dictionary], team_id: String) -> Dictionary:
	for record in records:
		if str(record.get("team_id", "")) == team_id:
			return record
	return {}


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
	if is_instance_valid(board):
		board.clear_actors()


func _combat_lab_encounter() -> CombatEncounterRecord:
	return (load("res://CombatCore/Tactical/combat_lab_encounter.tres") as CombatEncounterRecord).duplicate(true)
