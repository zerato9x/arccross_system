extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.macro_hud == null:
		_fail("Macro HUD did not initialize.")
		return

	var hud := macro_map.macro_hud
	if hud.get_node_or_null("%MacroHealthPanel") == null:
		_fail("Health corner panel missing.")
		return
	if hud.get_node_or_null("%MacroInventoryPanel") == null:
		_fail("Inventory corner panel missing.")
		return
	if hud.get_node_or_null("%MacroHexPanel") == null:
		_fail("Hex corner panel missing.")
		return
	if hud.get_node_or_null("%MacroWorldStatusPanel") == null:
		_fail("World status panel missing.")
		return

	hud.toggle_health_panel()
	await process_frame
	var vp: Vector2 = hud.get_viewport_rect().size
	var health := hud.get_node("%MacroHealthPanel") as MacroHealthCornerPanel
	if health.get_node("%PreviewRoot").get_node_or_null("MacroStatusPanel") == null:
		_fail("Health corner is not using MacroStatusPanel as preview.")
		return
	var expected_w: float = vp.x * MacroCornerPanel.EXPAND_WIDTH_RATIO
	if abs(health.size.x - expected_w) > 8.0:
		_fail("Expanded health panel width mismatch.")
		return

	hud.toggle_inventory_panel()
	await process_frame
	var inventory := hud.get_node("%MacroInventoryPanel") as MacroInventoryCornerPanel
	if inventory.get_node("%PreviewRoot").get_node_or_null("MacroInventoryPreview") == null:
		_fail("Inventory corner is not using MacroInventoryPreview.")
		return
	var hex := hud.get_node("%MacroHexPanel") as MacroHexCornerPanel
	if hex.get_node("%PreviewRoot").get_node_or_null("MacroHexPreviewPanel") == null:
		_fail("Hex corner is not using MacroHexPreviewPanel as preview.")
		return
	var insets := hud.get_layout_manager().compute_viewport_insets()
	if insets == Rect2i():
		_fail("Viewport insets should be non-zero with expanded panels.")
		return

	var camera := macro_map.get_node_or_null("Camera2D") as MacroCamera
	if camera == null:
		_fail("Macro camera missing.")
		return

	hud.get_layout_manager().collapse_all()
	await process_frame
	print("[TEST PASS] Macro HUD corner layout and camera wiring.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
