extends MacroCornerPanel
class_name MacroHealthCornerPanel

signal inventory_requested
signal settings_requested
signal medical_action_requested(instance_id: String, limb_region: int)

var _status_panel: MacroStatusPanel
var _medical_monitor: MedicalMonitor
var _flash_tween: Tween


func _ready() -> void:
	panel_id = "health"
	panel_corner = PanelCorner.TOP_LEFT
	preview_size = Vector2(398.0, 220.0)
	super._ready()
	_install_status_preview()
	_build_expanded_ui()


func _install_status_preview() -> void:
	_status_panel = %PreviewRoot.get_node_or_null("MacroStatusPanel") as MacroStatusPanel
	if _status_panel == null:
		push_error("MacroHealthCornerPanel requires MacroStatusPanel under PreviewRoot.")
		return
	_status_panel.body_scan_opens_internal = false
	_status_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_panel.body_scan_requested.connect(expand)
	_status_panel.inventory_requested.connect(inventory_requested.emit)
	_status_panel.settings_requested.connect(settings_requested.emit)
	_status_panel.set_clock_visible(false)
	_status_panel.set_corner_action_mode(true)


func _build_expanded_ui() -> void:
	_medical_monitor = %ExpandedRoot.get_node_or_null("MedicalMonitor") as MedicalMonitor
	if _medical_monitor == null:
		push_error("MacroHealthCornerPanel requires MedicalMonitor under ExpandedRoot.")
		return
	_medical_monitor.set_embedded_fit(true)
	_medical_monitor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_medical_monitor.closed.connect(collapse)
	_medical_monitor.limb_treatment_requested.connect(
		func(instance_id: String, region: int):
			medical_action_requested.emit(instance_id, region)
	)


func _render_preview() -> void:
	if _snapshot.is_empty():
		return
	if _status_panel:
		_status_panel.apply_snapshot(_snapshot)
	var emergencies: Array = _snapshot.get("emergencies", [])
	_set_emergency_flash(not emergencies.is_empty(), emergencies)


func _render_expanded() -> void:
	if _medical_monitor:
		_medical_monitor.open_monitor(_snapshot)


func _set_emergency_flash(active: bool, _emergencies: Array) -> void:
	set_emergency_active(active)
	if _flash_tween:
		_flash_tween.kill()
	if not active or _emergency_overlay == null:
		return
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(_emergency_overlay, "modulate:a", 0.15, 0.45)
	_flash_tween.tween_property(_emergency_overlay, "modulate:a", 0.55, 0.45)


func _set_state(state: PanelState) -> void:
	super._set_state(state)
	if state == PanelState.EXPANDED:
		_render_expanded()
	elif _medical_monitor and _medical_monitor.is_open():
		_medical_monitor.close_monitor()


func _is_primary_action_click(global_pos: Vector2) -> bool:
	return _status_panel != null and _status_panel.is_action_button_at(global_pos)
