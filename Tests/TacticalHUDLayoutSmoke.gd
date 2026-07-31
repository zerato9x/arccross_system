extends SceneTree

const HUD_SCENE := preload("res://CombatCore/Tactical/TacticalCombatHUD.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in [Vector2i(1024, 576), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		await _verify_size(viewport_size)
	if _failures.is_empty():
		print("TACTICAL_HUD_LAYOUT_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_size(viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	get_root().add_child(viewport)
	var hud: TacticalCombatHUD = HUD_SCENE.instantiate()
	viewport.add_child(hud)
	await process_frame
	hud.configure_action_catalog(load("res://CombatCore/Tactical/default_combat_action_catalog.tres"))
	hud.show_quotes(_sample_quotes())
	await process_frame
	await process_frame
	var expected := Vector2(viewport_size)
	if not hud.size.is_equal_approx(expected):
		_fail("HUD root %s did not fill its %s viewport (got %s)." % [viewport_size, viewport_size, hud.size])
	var bottom: Control = hud.get_node("Bottom")
	var main: Control = hud.get_node("Main")
	_assert_inside(hud.get_global_rect(), bottom.get_global_rect(), "bottom tray", viewport_size)
	_assert_inside(hud.get_global_rect(), main.get_global_rect(), "main arena row", viewport_size)
	_assert_inside(hud.get_global_rect(), hud.command_wheel.get_global_rect(), "command wheel", viewport_size)
	if hud.wheel_buttons.get_child_count() > 8:
		_fail("Command wheel exposed more than eight top-level families at %s." % viewport_size)
	if hud.confirm_button.size.y < 32.0:
		_fail("Confirmation control collapsed at %s." % viewport_size)
	viewport.queue_free()
	await process_frame


func _sample_quotes() -> Array[CombatActionQuote]:
	var result: Array[CombatActionQuote] = []
	var catalog: CombatActionCatalog = load("res://CombatCore/Tactical/default_combat_action_catalog.tres")
	for definition in catalog.all():
		var quote := CombatActionQuote.new()
		quote.action_id = definition.action_id
		quote.ap_cost = 3
		quote.legal = definition.context_visibility != "reaction_only"
		quote.denial_code = "specific_denial_reason"
		result.append(quote)
	return result


func _assert_inside(parent_rect: Rect2, child_rect: Rect2, label: String, viewport_size: Vector2i) -> void:
	if child_rect.position.x < parent_rect.position.x - 0.5 or child_rect.end.x > parent_rect.end.x + 0.5:
		_fail("%s overflowed horizontally at %s: %s outside %s." % [label, viewport_size, child_rect, parent_rect])
	if child_rect.position.y < parent_rect.position.y - 0.5 or child_rect.end.y > parent_rect.end.y + 0.5:
		_fail("%s overflowed vertically at %s: %s outside %s." % [label, viewport_size, child_rect, parent_rect])


func _fail(message: String) -> void:
	_failures.append(message)
