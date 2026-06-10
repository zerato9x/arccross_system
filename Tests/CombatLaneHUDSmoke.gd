extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var holder := Node.new()
	root.add_child(holder)

	var duel_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	if not duel_scene:
		_fail("Could not load the combat scene.")
		return
	var arena = duel_scene.instantiate()
	holder.add_child(arena)
	await process_frame

	if arena.get_node_or_null("DebugUI") != null:
		_fail("The retired combat DebugUI still exists.")
		return

	var player_definition := load(
		"res://BiologicalCore/player_def.tres"
	) as EntityDefinition
	var enemy_definition := load(
		"res://BiologicalCore/scavenger_def.tres"
	) as EntityDefinition
	var player: HumanoidCore = arena._fabricate_humanoid(
		"HUD_Player",
		player_definition,
		false
	)
	arena.setup_duel(
		player,
		{
			"entity_id": "hud_smoke_enemy",
			"definition": enemy_definition.to_state(),
			"runtime": {},
		}
	)
	await process_frame

	var snapshot: Dictionary = arena.command_adapter.get_snapshot()
	var lane_slots: Array = snapshot.get("lane_slots", [])
	if lane_slots.size() != 12:
		_fail("Combat snapshot did not expose exactly twelve lane slots.")
		return
	if not _slot_has_side(lane_slots[2], "player"):
		_fail("Neutral deployment did not project the player in slot 2.")
		return
	if not _slot_has_side(lane_slots[9], "enemy"):
		_fail("Neutral deployment did not project the enemy in slot 9.")
		return

	var hud_snapshot: Dictionary = arena.lane_hud.get_snapshot()
	if hud_snapshot.get("lane_slots", []).size() != 12:
		_fail("CombatLaneHUD did not receive the twelve-slot snapshot.")
		return
	if arena.lane_hud.is_showing_melee_lock():
		_fail("The lane HUD entered lock mode before combatants shared a slot.")
		return

	var enemy_lane: int = arena.lane_manager._find_entity_lane(arena.enemy_core)
	arena.lane_manager.remove_entity(player)
	arena.lane_manager.force_spawn_entity(player, enemy_lane)
	await process_frame

	if not arena.lane_hud.is_showing_melee_lock():
		_fail("The lane HUD did not switch to the melee-lock overlay.")
		return
	var lock_snapshot: Dictionary = arena.lane_hud.get_snapshot()
	var lock_slot: Dictionary = lock_snapshot.get("lane_slots", [])[enemy_lane]
	if (
		not lock_slot.get("is_melee_locked", false)
		or lock_slot.get("occupants", []).size() != 2
	):
		_fail("The melee-lock projection did not preserve shared occupancy.")
		return

	arena.turn_manager.halt_loop()
	holder.queue_free()
	await process_frame
	print(
		"[TEST PASS] Combat HUD projects twelve slots and switches to "
		+ "melee-lock presentation without owning lane state."
	)
	quit(0)

func _slot_has_side(slot: Dictionary, side: String) -> bool:
	for occupant in slot.get("occupants", []):
		if occupant.get("side", "") == side:
			return true
	return false

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
