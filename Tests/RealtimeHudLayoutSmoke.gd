extends SceneTree

const TARGET_SIZE := Vector2i(2048, 1152)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = TARGET_SIZE
	var packed := load("res://CombatCore/Realtime/RealtimeDuelHUD.tscn") as PackedScene
	if packed == null:
		return _fail("Realtime HUD scene did not load.")
	var hud := packed.instantiate() as RealtimeDuelHUD
	root.add_child(hud)
	await process_frame
	await process_frame

	var expected_scale := minf(
		float(TARGET_SIZE.x) / 1920.0,
		float(TARGET_SIZE.y) / 1080.0
	)
	if absf(hud.ui_root.scale.x - expected_scale) > 0.01:
		return _fail("HUD root is not using the bounded 1080p reference scale.")
	if hud.ui_root.size.distance_to(Vector2(TARGET_SIZE) / expected_scale) > 2.0:
		return _fail("HUD root does not preserve the viewport after UI scaling.")

	var command := hud.get_node("UILayer/UIRoot/CommandPanel") as Control
	var player_weapon := hud.player_weapon_card as Control
	var enemy_weapon := hud.enemy_weapon_card as Control
	if command.get_global_rect().intersects(player_weapon.get_global_rect()):
		return _fail("Command panel overlaps the player weapon card.")
	if command.get_global_rect().intersects(enemy_weapon.get_global_rect()):
		return _fail("Command panel overlaps the enemy weapon card.")

	var player_rect := hud.player_panel.get_global_rect()
	var enemy_rect := hud.enemy_panel.get_global_rect()
	if player_rect.size.x > 460.0 or enemy_rect.size.x > 460.0:
		return _fail("Actor panels are oversized at 2048x1152.")

	var stage_bounds := hud.lane_view.get_stage_bounds_global()
	var camera_bounds := hud.lane_view.get_camera_bounds_global()
	var viewport_aspect := float(TARGET_SIZE.x) / float(TARGET_SIZE.y)
	var stage_aspect := stage_bounds.size.x / stage_bounds.size.y
	if absf(stage_aspect - viewport_aspect) > 0.02:
		return _fail("Combat stage does not preserve the target viewport aspect.")
	if hud.wide_camera.limit_right != roundi(camera_bounds.end.x):
		return _fail("Wide camera is not clamped to the combat-stage boundary.")
	if camera_bounds.position.x >= stage_bounds.position.x:
		return _fail("Combat stage has no camera-safe terrain bleed for edge duels.")
	if hud.camera_focus.global_position.distance_to(
		hud.lane_view.get_stage_center_global()
	) > 1.0:
		return _fail("Wide camera is not centered on the visible combat stage.")

	hud.queue_free()
	await process_frame
	print("[REALTIME_HUD_LAYOUT_SMOKE] PASS // 2048x1152 stage, camera, and panels")
	quit(0)


func _fail(message: String) -> void:
	push_error("[REALTIME_HUD_LAYOUT_SMOKE] " + message)
	quit(1)
