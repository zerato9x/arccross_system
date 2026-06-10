extends SceneTree

const OUTPUT_PATH := "res://Tests/combat_rig_preview.png"

func _initialize() -> void:
	call_deferred("_render")

func _render() -> void:
	root.size = Vector2i(1440, 900)
	var holder := Node.new()
	holder.name = "RenderHolder"
	root.add_child(holder)
	var arena_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	var arena = arena_scene.instantiate()
	holder.add_child(arena)
	await process_frame

	var player_definition := load(
		"res://BiologicalCore/player_def.tres"
	) as EntityDefinition
	var enemy_definition := load(
		"res://BiologicalCore/scavenger_def.tres"
	) as EntityDefinition
	var player: HumanoidCore = arena._fabricate_humanoid(
		"Render_Player",
		player_definition,
		false
	)
	arena.setup_duel(
		player,
		{
			"entity_id": "render_enemy",
			"definition": enemy_definition.to_state(),
			"runtime": {},
		}
	)
	await process_frame

	var snapshot: Dictionary = arena.command_adapter.get_snapshot()
	var enemy: Dictionary = snapshot.get("enemy", {})
	enemy["weapon"] = "KAR98"
	enemy["weapon_id"] = "kar98_bolt_rifle"
	enemy["weapon_class"] = "RIFLE"
	snapshot["enemy"] = enemy
	arena.lane_hud.show_snapshot(snapshot)
	arena.combat_panel.show_snapshot(snapshot)
	arena.lane_hud.play_action("player", GameEnums.ActionType.SHOOT)
	arena.lane_hud.play_action("enemy", GameEnums.ActionType.SHOOT)

	await create_timer(0.26).timeout
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Could not save combat rig preview: " + str(error))
		quit(1)
		return
	print("[RENDER PASS] " + OUTPUT_PATH)
	arena.turn_manager.halt_loop()
	quit(0)
