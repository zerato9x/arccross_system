extends SceneTree

const _PerceptionBuilder := preload("res://CombatCore/Tactical/CombatPerceptionBuilder.gd")

var _board: CombatBoard
var _turns: TacticalTurnManager
var _controller: CombatActionController
var _ai: TacticalCombatAI
var _enemy: HumanoidCore
var _player: HumanoidCore


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_board = CombatBoard.new()
	_turns = TacticalTurnManager.new()
	_controller = CombatActionController.new()
	_ai = TacticalCombatAI.new()
	for node in [_board, _turns, _controller, _ai]:
		root.add_child(node)
	_enemy = _actor("enemy", GameEnums.Faction.CRAVEN_HIVE)
	_player = _actor("player", GameEnums.Faction.ARCBORN_RESISTANCE)
	await process_frame
	_board.configure_from_encounter(_encounter())
	_board.force_spawn_actor(_enemy, _board.arena_state.index_for(Vector2i(1, 2)), "enemy")
	_board.force_spawn_actor(_player, _board.arena_state.index_for(Vector2i(3, 2)), "player")
	_turns.initialize([_player, _enemy], _player)
	_turns.combatants = [_player, _enemy]
	_turns.active_actor_index = _turns.combatants.find(_player)
	_turns.current_ap_pool = 12
	_controller.configure([_enemy, _player], _board, _turns, null)
	_ai.configure(_enemy, _controller, _board, _turns)
	# Configure while the player is active so the deferred production turn does
	# not race this evaluator-boundary smoke.
	_turns.active_actor_index = _turns.combatants.find(_enemy)
	_turns.current_ap_pool = 12

	var evaluation := _ai.evaluate_decision("intent_smoke")
	var intent = evaluation.get("intent")
	var trace = evaluation.get("trace")
	if intent == null or trace == null:
		return _fail("AI did not produce an intent and decision trace.")
	if intent.current_request == null:
		return _fail("Intent did not carry exactly one current request.")
	if intent.snapshot_revision != _controller.combat_revision:
		return _fail("Intent did not bind to the monotonic controller revision.")
	var repeat_evaluation := _ai.evaluate_decision("intent_smoke")
	var repeat_intent = repeat_evaluation.get("intent")
	var repeat_trace = repeat_evaluation.get("trace")
	if repeat_intent == null or repeat_trace == null:
		return _fail("Repeated deterministic evaluation did not produce a decision.")
	if repeat_intent.current_request.to_dict() != intent.current_request.to_dict() or repeat_trace.tie_break_key != trace.tie_break_key:
		return _fail("Repeated evaluation changed the request or deterministic tie-break.")
	_ai._publish_intent(intent)
	var actor_state := _board.combat_state(_enemy)
	if actor_state.public_intent.is_empty() or int(actor_state.public_intent.get("intent_revision", 0)) != intent.intent_revision:
		return _fail("Coarse intent view was not published to encounter state.")
	var rules_state = _controller.rules_state_snapshot()
	var observer_snapshot = _PerceptionBuilder.build(rules_state, "player")
	var observed = observer_snapshot.known_actors.get("enemy")
	if observed == null or observed.public_intent.is_empty():
		return _fail("Public intent was not visible through the observer perception projection.")
	var old_revision := int(intent.snapshot_revision)
	_controller.revision_authority.bump("intent_smoke_mutation")
	if _controller.is_revision_current(old_revision):
		return _fail("Stale intent revision was accepted after authoritative mutation.")
	var source := FileAccess.get_file_as_string("res://CombatCore/Tactical/TacticalCombatAI.gd")
	if source.find("var target:") >= 0 or source.find("var target =") >= 0:
		return _fail("AI still exposes a mutable global target field.")
	if trace.first_request.is_empty() or trace.intent.is_empty() or trace.deterministic_seed.is_empty():
		return _fail("Decision trace omitted request, intent, or deterministic seed evidence.")
	print("COMBAT_AI_INTENT_SMOKE: PASS")
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
	encounter.encounter_id = "combat_ai_intent_smoke"
	encounter.world_seed = "COMBAT_AI_INTENT_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_INTENT] " + message)
	quit(1)
	return false
