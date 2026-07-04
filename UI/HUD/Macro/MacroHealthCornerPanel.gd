extends MacroCornerPanel
class_name MacroHealthCornerPanel

signal medical_action_requested(instance_id: String, limb_region: int)

const MAX_SCALE := 12.0
const VITAL_KEYS := ["blood", "hunger", "thirst", "stance"]

var _vital_rows: Dictionary = {}
var _warning_label: Label
var _emergency_icon: TextureRect
var _body_scan_button: Button
var _medical_monitor: MedicalMonitor
var _flash_tween: Tween


func _ready() -> void:
	panel_id = "health"
	panel_corner = PanelCorner.TOP_LEFT
	preview_size = Vector2(398.0, 220.0)
	super._ready()
	_build_preview_ui()
	_build_expanded_ui()


func _build_preview_ui() -> void:
	var root := %PreviewRoot
	if root == null:
		return
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)

	_warning_label = Label.new()
	_warning_label.text = "BODY SIGNAL STABLE"
	HUDAssetLibrary.apply_label(_warning_label, "warning")
	column.add_child(_warning_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	for key in VITAL_KEYS:
		grid.add_child(_build_vital_row(key))
	column.add_child(grid)

	_body_scan_button = Button.new()
	_body_scan_button.text = "BODY SCAN"
	HUDAssetLibrary.apply_button(_body_scan_button, "blood")
	_body_scan_button.pressed.connect(expand)
	column.add_child(_body_scan_button)

	_emergency_icon = TextureRect.new()
	_emergency_icon.custom_minimum_size = Vector2(24, 24)
	_emergency_icon.visible = false
	_emergency_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emergency_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_emergency_icon)


func _build_vital_row(key: String) -> Control:
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.texture = RevampedHUDAtlas.stat_icon(key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 12)
	bar.max_value = MAX_SCALE
	RevampedHUDAtlas.apply_revamped_progress_bar(bar, key)
	row.add_child(bar)
	_vital_rows[key] = bar
	return row


func _build_expanded_ui() -> void:
	var root := %ExpandedRoot
	if root == null:
		return
	_medical_monitor = preload("res://UI/HUD/MedicalMonitor.tscn").instantiate()
	_medical_monitor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_medical_monitor.closed.connect(collapse)
	_medical_monitor.limb_treatment_requested.connect(
		func(instance_id: String, region: int):
			medical_action_requested.emit(instance_id, region)
	)
	root.add_child(_medical_monitor)


func _render_preview() -> void:
	if _snapshot.is_empty():
		return
	for key in VITAL_KEYS:
		var bar: ProgressBar = _vital_rows.get(key)
		if bar:
			bar.value = clampf(float(_snapshot.get(key, 0.0)), 0.0, MAX_SCALE)
	var emergencies: Array = _snapshot.get("emergencies", [])
	if _warning_label:
		_warning_label.text = (
			" / ".join(emergencies)
			if not emergencies.is_empty()
			else "BODY SIGNAL STABLE"
		)
	_set_emergency_flash(not emergencies.is_empty(), emergencies)


func _render_expanded() -> void:
	if _medical_monitor:
		_medical_monitor.open_monitor(_snapshot)


func _set_emergency_flash(active: bool, emergencies: Array) -> void:
	set_emergency_active(active)
	if _emergency_icon and not emergencies.is_empty():
		_emergency_icon.texture = RevampedHUDAtlas.emergency_condition_icon(
			str(emergencies[0])
		)
		_emergency_icon.visible = true
	elif _emergency_icon:
		_emergency_icon.visible = false
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
	if _body_scan_button and _body_scan_button.get_global_rect().has_point(global_pos):
		return true
	return false
