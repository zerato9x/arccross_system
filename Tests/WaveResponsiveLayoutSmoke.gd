extends SceneTree

const WAVE_SCENE := preload("res://CombatCore/WaveMode.tscn")
const TEST_SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for test_size in TEST_SIZES:
		var viewport := SubViewport.new()
		viewport.size = test_size
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		root.add_child(viewport)
		var wave_mode := WAVE_SCENE.instantiate() as WaveMode
		viewport.add_child(wave_mode)
		await process_frame
		await process_frame
		var screen := wave_mode.get_node("UILayer/PreCombatScreen") as Control
		var main := wave_mode.get_node("UILayer/PreCombatScreen/Workspace/MainVBox") as Control
		var header := main.get_node("HeaderPanel") as Control
		var body := main.get_node("BodyRow") as Control
		var bottom := main.get_node("BottomPanel") as Control
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(test_size))
		if screen.size != Vector2(test_size):
			_fail("Screen did not follow viewport at %s: %s" % [test_size, screen.size])
			return
		if not viewport_rect.encloses(main.get_global_rect()):
			_fail("Main workstation clips at %s: %s" % [test_size, main.get_global_rect()])
			return
		if header.size.y <= 0.0 or body.size.y <= 0.0 or bottom.size.y <= 0.0:
			_fail("A primary responsive region collapsed at %s." % test_size)
			return
		if body.size.x < 1000.0 or bottom.position.y + bottom.size.y > main.size.y + 0.5:
			_fail("Responsive containers produced an invalid workstation at %s." % test_size)
			return
		viewport.queue_free()
		await process_frame

	print("[WAVE_RESPONSIVE_LAYOUT_SMOKE] PASS // 1280x720 1920x1080")
	quit(0)

func _fail(message: String) -> void:
	push_error("[WAVE_RESPONSIVE_LAYOUT_SMOKE] " + message)
	quit(1)
