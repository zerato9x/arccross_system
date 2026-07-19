extends SceneTree

const HUD_SCENE := preload("res://UI/HUD/Macro/MacroWorldStatusPanel.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hud := HUD_SCENE.instantiate() as MacroWorldStatusPanel
	root.add_child(hud)
	await process_frame
	await process_frame
	if hud == null:
		return _fail("World Signal Log scene did not instantiate.")
	if hud.size.distance_to(MacroWorldStatusPanel.PANEL_SIZE) > 2.0:
		return _fail("World Signal Log ignored its authored 420x316 footprint.")
	if hud.get_node_or_null("%PocketClock") != null or hud.get_node_or_null("%DayIcon") != null:
		return _fail("Retired pocket-clock/time-atlas nodes are still in the World Signal Log.")
	var emblem := hud.get_node_or_null("%WorldSignalIcon") as TextureRect
	if emblem == null or emblem.texture == null:
		return _fail("Original world-signal emblem is missing.")
	if emblem.texture.resource_path != "res://Asset/UI/HUD/icons/status/world_signal_128.png":
		return _fail("World Signal Log is not using the original Arccross emblem.")
	hud.apply_snapshot({
		"world_time": {"hour": 18, "minute": 42, "day": 12},
		"calendar": {"day": 12, "month": 7, "year": 3},
	})
	hud.append_log("Entered the eastern route.")
	hud.append_log("Landmark discovered: relay tower.")
	hud.append_log("Hostile movement detected.")
	await process_frame
	if (hud.get_node("%TimeLabel") as Label).text != "18:42":
		return _fail("Native clock did not render the snapshot time.")
	if hud.get_latest_log_kind() != "danger":
		return _fail("Semantic log classification did not mark a hostile event as danger.")
	if hud.get_log_entry_count() != 4:
		return _fail("World Signal Log did not retain its system entry plus three probes.")
	var kinds: Array[String] = []
	for row in hud.get_node("%LogList").get_children():
		kinds.append(str(row.get_meta("log_kind", "")))
	for expected in ["system", "travel", "discovery", "danger"]:
		if not kinds.has(expected):
			return _fail("Missing semantic log row: " + expected)
	var rect := hud.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect):
		return _fail("World Signal Log escaped the 1280x720 viewport.")
	print("[WORLD_STATUS_HUD_SMOKE] PASS // original emblem, native clock, semantic feed")
	quit(0)


func _fail(message: String) -> void:
	push_error("[WORLD_STATUS_HUD_SMOKE] FAIL // " + message)
	quit(1)
