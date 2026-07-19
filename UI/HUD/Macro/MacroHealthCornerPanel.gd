extends MacroCornerPanel
class_name MacroHealthCornerPanel

signal inventory_requested
signal settings_requested
signal medical_action_requested(instance_id: String, limb_region: int)

var _preview_hud: FieldHealthHUD
var _detail_hud: FieldHealthHUD
var _flash_tween: Tween


func _ready() -> void:
	panel_id = "health"
	panel_corner = PanelCorner.TOP_LEFT
	preview_size = Vector2(548.0, 418.0)
	expanded_min_size = Vector2(760.0, 520.0)
	expanded_max_size = Vector2(960.0, 660.0)
	super._ready()
	_install_health_huds()


func _install_health_huds() -> void:
	_preview_hud = %PreviewRoot.get_node_or_null("FieldHealthPreview") as FieldHealthHUD
	_detail_hud = %ExpandedRoot.get_node_or_null("FieldHealthDetail") as FieldHealthHUD
	if _preview_hud == null or _detail_hud == null:
		push_error("MacroHealthCornerPanel requires both FieldHealthHUD instances.")
		return
	_preview_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_hud.details_requested.connect(expand)
	_preview_hud.inventory_requested.connect(inventory_requested.emit)
	_preview_hud.settings_requested.connect(settings_requested.emit)
	_detail_hud.limb_treatment_requested.connect(
		func(instance_id: String, region: int):
			medical_action_requested.emit(instance_id, region)
	)


func _render_preview() -> void:
	if _snapshot.is_empty():
		return
	if _preview_hud:
		_preview_hud.apply_snapshot(_snapshot)
	var emergencies: Array = _snapshot.get("emergencies", [])
	_set_emergency_flash(not emergencies.is_empty(), emergencies)


func _render_expanded() -> void:
	if _detail_hud:
		_detail_hud.apply_snapshot(_snapshot)


func _set_emergency_flash(active: bool, _emergencies: Array) -> void:
	set_emergency_active(active)
	if _flash_tween:
		_flash_tween.kill()
	if not active or _emergency_overlay == null:
		return
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(_emergency_overlay, "modulate:a", 0.18, 0.8)
	_flash_tween.tween_property(_emergency_overlay, "modulate:a", 0.48, 0.8)


func _set_state(state: PanelState) -> void:
	super._set_state(state)
	if state == PanelState.EXPANDED:
		_render_expanded()


func _is_primary_action_click(global_pos: Vector2) -> bool:
	return _preview_hud != null and _preview_hud.is_action_button_at(global_pos)
