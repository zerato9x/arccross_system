extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var conductor := SfxConductor.new()
	root.add_child(conductor)
	await process_frame

	var before := int(conductor.get("_next_player_idx"))
	conductor.call(
		"_on_world_action_presentation",
		{
			"actor_id": "npc_worker",
			"presentation": {
				"sfx": "work_miss",
				"audio_policy": "silent",
			},
		}
	)
	if int(conductor.get("_next_player_idx")) != before:
		_fail("An off-screen NPC receipt produced player-facing world SFX.")
		return

	conductor.call(
		"_on_world_action_presentation",
		{
			"actor_id": "player",
			"presentation": {
				"sfx": "work_miss",
				"audio_policy": "player",
			},
		}
	)
	if int(conductor.get("_next_player_idx")) == before:
		_fail("A player-owned world receipt did not reach the SFX conductor.")
		return

	print("MACRO_AUDIO_SCOPE_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("[MACRO_AUDIO_SCOPE_SMOKE] FAIL // " + message)
	quit(1)
