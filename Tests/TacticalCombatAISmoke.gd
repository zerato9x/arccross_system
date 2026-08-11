extends SceneTree

var board: CombatBoard
var turns: TacticalTurnManager
var engine: CombatResolutionEngine
var controller: CombatActionController
var enemy: HumanoidCore
var near_hostile: HumanoidCore
var far_hostile: HumanoidCore
var ai: TacticalCombatAI
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_behavior_migration()
	board = CombatBoard.new()
	turns = TacticalTurnManager.new()
	engine = CombatResolutionEngine.new()
	controller = CombatActionController.new()
	ai = TacticalCombatAI.new()
	for node in [board, turns, engine, controller, ai]:
		root.add_child(node)
	enemy = _actor("enemy", GameEnums.Faction.CRAVEN_HIVE, "enemy")
	near_hostile = _actor("near", GameEnums.Faction.ARCBORN_RESISTANCE, "player")
	far_hostile = _actor("far", GameEnums.Faction.ARCBORN_RESISTANCE, "player")
	await process_frame
	board.configure_from_encounter(_encounter())
	_deploy(enemy, Vector2i(1, 2), "enemy")
	_deploy(near_hostile, Vector2i(3, 2), "player")
	_deploy(far_hostile, Vector2i(6, 2), "player")
	turns.initialize([near_hostile, enemy, far_hostile], near_hostile)
	turns.combatants = [near_hostile, enemy, far_hostile]
	turns.active_actor_index = 0
	turns.current_ap_pool = 12
	engine.board = board
	engine.turn_manager = turns
	controller.configure([enemy, near_hostile, far_hostile], board, turns, engine)
	_equip_firearm(enemy)
	var mindless_requests := ai.enumerate_requests()
	for request in mindless_requests:
		if request.action_id in ["offense", "defense", "support", "flee", "threaten", "ceasefire"]:
			_fail("Mindless AI enumerated a communication action and could spend Communication Points.")
			break

	for profile_id in ["marksman", "brute", "opportunist", "defender"]:
		turns.active_actor_index = 0
		enemy.set_meta("npc_behavior_state", {
			"schema_version": 1,
			"profile_id": profile_id,
			"survival_pressure": 0.0,
			"decision_memory": {},
		})
		ai.configure(enemy, controller, board, turns)
		turns.active_actor_index = 1
		turns.current_ap_pool = 12
		if ai.behavior_profile == null or ai.behavior_profile.profile_id != profile_id:
			_fail("Behavior profile %s was not resolved through the neutral catalog." % profile_id)
		var requests := ai.enumerate_requests()
		if requests.is_empty() or not requests.any(func(request: CombatActionRequest) -> bool: return request.action_id == "end_turn"):
			_fail("%s did not enumerate a deterministic decision set with an explicit end." % profile_id)
		if not requests.any(func(request: CombatActionRequest) -> bool: return controller.quote(request).legal and request.action_id != "end_turn"):
			_fail("%s found no meaningful legal action through the player legality quotes." % profile_id)
		for request in requests:
			if request.action_id in ["fire", "reload", "cycle"]:
				if str(request.metadata.get("weapon_id", "")) != "ai_service_pistol":
					_fail("%s firearm request lost its equipped weapon metadata." % profile_id)

	# Subject selection is tested under an authored pressure profile so the
	# motive evaluator cannot choose a defensive self-subject merely because the
	# previous profile happened to prefer HOLD.
	enemy.set_meta("npc_behavior_state", {"schema_version": 2, "profile_id": "brute", "survival_pressure": 0.0})
	turns.active_actor_index = 0
	ai.configure(enemy, controller, board, turns)
	turns.active_actor_index = 1
	turns.current_ap_pool = 12
	var first_evaluation := ai.evaluate_decision("subject_selection")
	var first_intent = first_evaluation.get("intent")
	if first_intent == null or first_intent.target_actor_id != "near":
		_fail("AI did not select the nearest observed hostile through its intent subject.")
	near_hostile.is_dead = true
	var second_evaluation := ai.evaluate_decision("subject_invalidated")
	var second_intent = second_evaluation.get("intent")
	if second_intent == null or second_intent.target_actor_id != "far":
		_fail("AI did not select a new observed hostile after the previous subject became nonviable.")
	near_hostile.is_dead = false

	var weapon: ItemData = enemy.inventory.get_active_weapon(false)
	weapon.current_magazine = 0
	weapon.is_jammed = false
	var empty_requests := ai.enumerate_requests()
	if not empty_requests.any(func(request: CombatActionRequest) -> bool:
		return request.action_id == "reload" and str(request.metadata.get("weapon_id", "")) == weapon.id
	):
		_fail("Empty firearm state was not carried into the reload decision.")
	weapon.current_magazine = 4
	weapon.is_jammed = true
	var jammed_requests := ai.enumerate_requests()
	if not jammed_requests.any(func(request: CombatActionRequest) -> bool:
		return request.action_id == "cycle" and bool(request.metadata.get("jammed", false))
	):
		_fail("Malfunctioning firearm state was not carried into the service decision.")
	weapon.is_jammed = false

	# The selected subject and plan are now traceable without exposing a mutable
	# global target or an AI-owned score function.
	var trace = ai.evaluate_decision("trace_contract").get("trace")
	if trace == null or trace.first_request.is_empty() or trace.intent.is_empty():
		_fail("AI did not publish a detailed decision trace with its first request and intent.")

	# Finally execute an actual unarmed turn. It must spend AP making progress or
	# pass explicitly; the loop may not remain the active actor at positive AP.
	enemy.inventory.unequip_item(GameEnums.EquipmentSlot.HAND)
	enemy.definition.agenda = GameEnums.Agenda.BELLIGERENT
	enemy.set_meta("npc_behavior_state", {"schema_version": 1, "profile_id": "brute", "survival_pressure": 0.0})
	turns.active_actor_index = 1
	turns.current_ap_pool = 4
	ai.configure(enemy, controller, board, turns)
	await ai._take_turn()
	if turns.get_active_entity() == enemy and turns.current_ap_pool > 0:
		_fail("Unarmed AI turn stalled without committing or explicitly ending.")

	if failures.is_empty():
		print("TACTICAL_COMBAT_AI_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _verify_behavior_migration() -> void:
	var legacy_runtime := {
		"npc_role_id": "sentry",
		"biology": {"hunger": 3.0, "thirst": 8.0, "fatigue": 2.0},
		"wounds": [{"wound_id": "canonical_wound"}],
		"inventory": [{"instance_id": "canonical_item"}],
		"morale": 5.0,
	}
	var migrated := NpcBehaviorState.ensure_runtime(legacy_runtime, {})
	var payload: Dictionary = migrated.get(NpcBehaviorState.RUNTIME_KEY, {})
	if payload.get("profile_id", "") != "defender" or not is_equal_approx(float(payload.get("survival_pressure", -1.0)), 9.0):
		_fail("Legacy role and biology did not migrate deterministically into neutral behavior state.")
	for canonical_key in ["wounds", "inventory", "morale", "biology"]:
		if migrated.get(canonical_key) != legacy_runtime.get(canonical_key):
			_fail("Behavior migration mutated canonical %s data." % canonical_key)
	var defaulted: Resource = NpcBehaviorState.from_runtime({}, {"combat_tactic": GameEnums.CombatTactic.MARKSMAN})
	if defaulted.profile_id != "marksman" or not is_zero_approx(defaulted.survival_pressure):
		_fail("Missing behavior state did not receive deterministic tactic and zero-pressure defaults.")
	var catalog := NpcBehaviorProfileCatalog.load_default()
	if catalog == null or catalog.profile_for_id("opportunist").exploration_projection().is_empty() or catalog.profile_for_id("opportunist").combat_projection().is_empty():
		_fail("Neutral behavior catalog did not expose independent exploration and combat projections.")


func _actor(actor_id: String, faction: int, side: String) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	actor.set_meta("combat_side", side)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.faction = faction as GameEnums.Faction
	definition.agenda = GameEnums.Agenda.BELLIGERENT
	actor.definition = definition
	var body := HumanoidBody.new()
	body.name = "HumanoidBody"
	actor.add_child(body)
	var inventory := InventorySystem.new()
	inventory.name = "InventorySystem"
	actor.add_child(inventory)
	root.add_child(actor)
	return actor


func _equip_firearm(actor: HumanoidCore) -> void:
	var definition := ItemData.new()
	definition.id = "ai_service_pistol"
	definition.display_name = "AI Service Pistol"
	definition.item_type = GameEnums.ItemType.WEAPON
	definition.weapon_type = GameEnums.WeaponClass.PISTOL
	definition.max_magazine = 6
	definition.optimal_range_cells = Vector2i(2, 5)
	definition.maximum_range_cells = 8
	var weapon := definition.create_runtime_instance()
	actor.inventory.equip_item(weapon, GameEnums.EquipmentSlot.HAND)


func _encounter() -> CombatEncounterRecord:
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "tactical_ai_smoke"
	encounter.world_seed = "TACTICAL_AI_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _deploy(actor: HumanoidCore, coords: Vector2i, side: String) -> void:
	if not board.force_spawn_actor(actor, board.arena_state.index_for(coords), side):
		_fail("Could not deploy %s at %s." % [actor.name, coords])


func _fail(message: String) -> void:
	failures.append("[TACTICAL_COMBAT_AI] " + message)
