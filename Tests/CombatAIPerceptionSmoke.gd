extends SceneTree

const _RulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")
const _PerceptionBuilder := preload("res://CombatCore/Tactical/CombatPerceptionBuilder.gd")

var _board: CombatBoard
var _turns: TacticalTurnManager
var _alpha: HumanoidCore
var _bravo: HumanoidCore
var _charlie: HumanoidCore


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_board = CombatBoard.new()
	_turns = TacticalTurnManager.new()
	root.add_child(_board)
	root.add_child(_turns)
	_alpha = _actor("alpha", GameEnums.Faction.ARCBORN_RESISTANCE)
	_bravo = _actor("bravo", GameEnums.Faction.CRAVEN_HIVE)
	_charlie = _actor("charlie", GameEnums.Faction.CRAVEN_HIVE)
	await process_frame
	_board.configure_from_encounter(_encounter())
	_board.force_spawn_actor(_alpha, _index(Vector2i(1, 2)), "player")
	_board.force_spawn_actor(_bravo, _index(Vector2i(3, 2)), "enemy")
	_board.force_spawn_actor(_charlie, _index(Vector2i(6, 2)), "enemy")
	var hidden_sector := _board.sectors[_index(Vector2i(4, 2))]
	hidden_sector.record.blocked = true
	hidden_sector.record.opaque = true
	hidden_sector.configure(hidden_sector.record)
	_turns.initialize([_alpha, _bravo, _charlie], _alpha)
	_turns.combatants = [_alpha, _bravo, _charlie]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	var rules_state = _RulesState.from_board(_board, _turns, null, [_alpha, _bravo, _charlie], 22)
	var snapshot = _PerceptionBuilder.build(rules_state, "alpha", {}, {}, "state_change")
	var fingerprint := JSON.stringify(snapshot.to_dict())
	var hidden = snapshot.known_actors.get("charlie")
	if hidden == null or hidden.knowledge_state == "visible":
		return _fail("Hidden actor remained visible through the perception boundary.")
	if not hidden.observable_weapon.is_empty():
		return _fail("Hidden actor leaked weapon details into perception.")
	if snapshot.actor.get("actor_id", "") != "alpha" or not snapshot.actor.has("blood"):
		return _fail("Self projection did not retain exact private facts.")
	if snapshot.hard_facts.get("dominant_tag", "").is_empty():
		return _fail("Hard-state input was not captured in the snapshot.")
	var repeated = _PerceptionBuilder.build(rules_state, "alpha", {}, {}, "state_change")
	if repeated.hard_facts != snapshot.hard_facts:
		return _fail("Identical perception inputs produced unstable hard facts.")
	rules_state.actor_facts["charlie"]["weapon"]["id"] = "mutated_after_snapshot"
	rules_state.actor_facts["alpha"]["private"]["blood"] = 0.0
	if JSON.stringify(snapshot.to_dict()) != fingerprint:
		return _fail("Snapshot changed after live projected facts were mutated.")
	print("COMBAT_AI_PERCEPTION_SMOKE: PASS")
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
	encounter.encounter_id = "combat_ai_perception_smoke"
	encounter.world_seed = "COMBAT_AI_PERCEPTION_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _index(coords: Vector2i) -> int:
	return _board.arena_state.index_for(coords)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_PERCEPTION] " + message)
	quit(1)
	return false
