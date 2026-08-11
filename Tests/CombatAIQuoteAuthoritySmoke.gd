extends SceneTree

const _RulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")
const _QuoteService := preload("res://CombatCore/Tactical/CombatActionQuoteService.gd")
const _PlanningProjection := preload("res://CombatCore/Tactical/CombatPlanningProjectionService.gd")
const _RevisionAuthority := preload("res://CombatCore/Tactical/CombatRevisionAuthority.gd")

var _board: CombatBoard
var _turns: TacticalTurnManager
var _engine: CombatResolutionEngine
var _controller: CombatActionController
var _alpha: HumanoidCore
var _bravo: HumanoidCore


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_board = CombatBoard.new()
	_turns = TacticalTurnManager.new()
	_engine = CombatResolutionEngine.new()
	_controller = CombatActionController.new()
	for node in [_board, _turns, _engine, _controller]:
		root.add_child(node)
	_alpha = _actor("alpha", GameEnums.Faction.ARCBORN_RESISTANCE)
	_bravo = _actor("bravo", GameEnums.Faction.CRAVEN_HIVE)
	await process_frame
	_board.configure_from_encounter(_encounter())
	_board.force_spawn_actor(_alpha, _board.arena_state.index_for(Vector2i(1, 2)), "player")
	_board.force_spawn_actor(_bravo, _board.arena_state.index_for(Vector2i(3, 2)), "enemy")
	_turns.initialize([_alpha, _bravo], _alpha)
	_turns.combatants = [_alpha, _bravo]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_engine.board = _board
	_engine.turn_manager = _turns
	_controller.configure([_alpha, _bravo], _board, _turns, _engine)

	var rules_state = _RulesState.from_board(_board, _turns, _controller.catalog, [_alpha, _bravo], 17)
	var request := _request("move")
	request.path = [Vector2i(1, 2), Vector2i(2, 2)]
	var before_request := request.to_dict()
	var before_rules := _rules_fingerprint(rules_state)
	var before_rng := _controller._rng.state
	var pure_quote: CombatActionQuote = _QuoteService.quote(request, rules_state)
	var pure_repeat: CombatActionQuote = _QuoteService.quote(request, rules_state)
	if not pure_quote.legal or not pure_repeat.legal:
		return _fail("Pure quote service rejected a legal clear move.")
	if pure_quote.to_dict() != pure_repeat.to_dict():
		return _fail("Repeated pure quotes were not deterministic.")
	if request.to_dict() != before_request:
		return _fail("Pure quote service mutated the request.")
	if _rules_fingerprint(rules_state) != before_rules:
		return _fail("Pure quote service mutated the projected rules state.")
	if _controller._rng.state != before_rng:
		return _fail("Pure quote service advanced live tactical RNG.")

	var live_request := _request("move")
	live_request.path = [Vector2i(1, 2), Vector2i(2, 2)]
	var live_quote := _controller.quote(live_request)
	if not live_quote.legal:
		return _fail("Live quote rejected the same clear move.")
	for key in ["legal", "action_id", "origin_sector", "projected_origin", "ap_cost", "movement_ap_cost", "action_ap_cost", "range_cells"]:
		if live_quote.to_dict().get(key) != pure_quote.to_dict().get(key):
			return _fail("Live and pure quote differ at %s." % key)

	var planning = _PlanningProjection.from_rules_state(rules_state, "alpha")
	var projected = _PlanningProjection.apply_quote(planning, request, pure_quote, rules_state)
	if projected.remaining_ap != planning.remaining_ap - pure_quote.ap_cost:
		return _fail("Projected preparation did not subtract quoted AP.")
	if projected.actor_sector != pure_quote.projected_origin:
		return _fail("Projected preparation lost the quoted destination.")
	if _board.position_of(_alpha) != _board.arena_state.index_for(Vector2i(1, 2)):
		return _fail("Planning projection mutated the live board.")

	var authority = _RevisionAuthority.new()
	var first := authority.bump("position")
	var second := authority.bump("ap")
	if first != 1 or second != 2 or not authority.is_current(2):
		return _fail("Combat revision authority was not monotonic.")
	print("COMBAT_AI_QUOTE_AUTHORITY_SMOKE: PASS")
	quit(0)


func _actor(actor_id: String, faction: int) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.faction = faction as GameEnums.Faction
	actor.definition = definition
	var body := HumanoidBody.new()
	body.name = "HumanoidBody"
	actor.add_child(body)
	var inventory := InventorySystem.new()
	inventory.name = "InventorySystem"
	actor.add_child(inventory)
	root.add_child(actor)
	return actor


func _encounter() -> CombatEncounterRecord:
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "combat_ai_quote_authority_smoke"
	encounter.world_seed = "COMBAT_AI_QUOTE_AUTHORITY_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _request(action_id: String) -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = "alpha"
	request.action_id = action_id
	return request


func _rules_fingerprint(rules_state) -> String:
	return JSON.stringify({
		"revision": rules_state.revision,
		"ap": rules_state.current_ap_pool,
		"actors": rules_state.actor_facts,
		"occupancy": rules_state.occupancy,
		"relationships": rules_state.relationships,
	})


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_QUOTE_AUTHORITY] " + message)
	quit(1)
	return false
