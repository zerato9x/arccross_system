extends SceneTree

const DUEL_SCENE := preload("res://CombatCore/MainDuelScene.tscn")
const PLAYER_DEFINITION := preload("res://BiologicalCore/player_def.tres")
const ENEMY_DEFINITION := preload("res://BiologicalCore/scavenger_def.tres")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena := DUEL_SCENE.instantiate()
	root.add_child(arena)
	await process_frame

	var player: HumanoidCore = arena._fabricate_humanoid(
		"Fumble_Player",
		PLAYER_DEFINITION,
		false
	)
	arena.setup_duel(player, {
		"entity_id": "fumble_enemy",
		"definition": ENEMY_DEFINITION.to_state(),
		"runtime": {},
	})
	arena.turn_manager.halt_loop()

	var lanes: CombatLaneManager = arena.lane_manager
	var enemy: HumanoidCore = arena.enemy_core
	lanes.remove_entity(player)
	lanes.remove_entity(enemy)
	lanes.force_spawn_entity(player, 6)
	lanes.force_spawn_entity(enemy, 6)

	var punishment_hits := 0
	arena.resolution_engine.damage_applied.connect(
		func(victim: HumanoidCore) -> void:
			if victim == player:
				punishment_hits += 1
	)

	# Escape roll is capped at 1 while the healthy opponent's grip is 5.
	player.current_max_ap = 1
	if lanes.attempt_disengage(player, 6, 5):
		_fail("Forced failed disengage unexpectedly succeeded.")
		return
	if punishment_hits != 1:
		_fail("Failed disengage did not trigger exactly one Fumble Strike.")
		return

	arena.queue_free()
	await process_frame
	print("[TEST PASS] Failed disengage triggers one Fumble Strike.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
