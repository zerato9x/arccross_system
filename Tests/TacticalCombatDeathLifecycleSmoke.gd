extends SceneTree

const SCENE := preload("res://CombatCore/Tactical/TacticalCombatScene.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := SCENE.instantiate() as TacticalCombatScene
	root.add_child(scene)
	await process_frame
	var encounter := CombatEncounterRecord.new()
	encounter.encounter_id = "death_lifecycle_smoke"
	encounter.topology_id = "duel_12x1"
	encounter.initiator_id = "player"
	encounter.center_hex = HexRecord.new()
	encounter.world_seed = "DEATH_LIFECYCLE_SMOKE"
	var player_definition := preload("res://BiologicalCore/player_def.tres")
	var enemy_definition := preload("res://BiologicalCore/scavenger_def.tres")
	encounter.actors = [
		{
			"actor_id": "player",
			"team_id": "player",
			"runtime_record": {"entity_id": "player", "definition": player_definition.to_state(), "runtime": {}},
		},
		{
			"actor_id": "enemy",
			"team_id": "enemy",
			"runtime_record": {"entity_id": "enemy", "definition": enemy_definition.to_state(), "runtime": {}},
		},
	]
	scene.setup_encounter(encounter)
	await process_frame
	if scene.enemy_core == null or scene.player_core == null:
		_failures.append("Death smoke encounter did not deploy both actors.")
	else:
		var finished := {"value": false}
		scene.combat_finished.connect(func(_result: CombatResultRecord) -> void: finished.value = true)
		# Reproduce the original race: the biological signal arrives while the
		# action/presentation lock is still held. It must be queued, not dropped.
		scene.enemy_core.is_dead = true
		scene._resolving = true
		scene._on_actor_died("Exsanguination", scene.enemy_core)
		if scene._pending_terminal.is_empty():
			_failures.append("Terminal enemy death was lost while resolving an action.")
		scene._resolving = false
		scene._flush_pending_terminal()
		await process_frame
		if not bool(finished.value):
			_failures.append("Queued terminal death did not finish the combat encounter.")

		# Older persisted records may contain zero blood without is_dead. The
		# handoff reconciliation must make that actor terminal before deployment.
		var restored := HumanoidCore.new()
		var restored_definition := EntityDefinition.new()
		restored_definition.archetype_name = "restored"
		restored.definition = restored_definition
		var restored_body := HumanoidBody.new()
		restored_body.name = "HumanoidBody"
		restored.add_child(restored_body)
		var restored_inventory := InventorySystem.new()
		restored_inventory.name = "InventorySystem"
		restored.add_child(restored_inventory)
		root.add_child(restored)
		await process_frame
		restored_body.blood_level = 0.0
		restored.reconcile_terminal_state()
		if not restored.is_dead or restored.current_max_ap != 0:
			_failures.append("Zero-blood runtime state was not reconciled to death.")
	if _failures.is_empty():
		print("TACTICAL_COMBAT_DEATH_LIFECYCLE_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
