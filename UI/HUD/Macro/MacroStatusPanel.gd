extends PanelContainer
class_name MacroStatusPanel

signal inventory_requested
signal settings_requested
signal body_scan_requested

enum Mode { COMPACT, DETAILED }

const MAX_SCALE := 12.0

@export var body_scan_opens_internal := true

var _snapshot: Dictionary = {}
var _mode := Mode.COMPACT
var _vital_rows: Dictionary = {}

@onready var _compact_view: Control = %CompactView
@onready var _detailed_view: Control = %DetailedView
@onready var _medical_monitor: MedicalMonitor = %MedicalMonitor
@onready var _location_label: Label = %LocationLabel
@onready var _time_label: Label = %TimeLabel
@onready var _warning_label: Label = %WarningLabel
@onready var _condition_icon: TextureRect = %ConditionIcon

var _condition_tween: Tween
@onready var _action_row: HBoxContainer = get_node_or_null("CompactView/ActionRow") as HBoxContainer
@onready var _body_scan_button: Button = %BodyScanButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _settings_button: Button = %SettingsButton

func _ready() -> void:
	_bind_vital_rows()
	_apply_assets()
	_body_scan_button.pressed.connect(_on_body_scan_pressed)
	_inventory_button.pressed.connect(inventory_requested.emit)
	_settings_button.pressed.connect(settings_requested.emit)
	_medical_monitor.closed.connect(_on_medical_closed)
	_set_mode(Mode.COMPACT)

func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_render_compact()
	if _mode == Mode.DETAILED:
		_medical_monitor.show_snapshot(_snapshot)

func toggle_body_scan() -> void:
	if _mode == Mode.COMPACT:
		_set_mode(Mode.DETAILED)
	else:
		_set_mode(Mode.COMPACT)

func set_clock_visible(clock_visible: bool) -> void:
	var icon := get_node_or_null("%TimeIcon") as TextureRect
	var label := get_node_or_null("%TimeLabel") as Label
	if icon:
		icon.visible = clock_visible
	if label:
		label.visible = clock_visible

func set_action_row_visible(actions_visible: bool) -> void:
	if _action_row:
		_action_row.visible = actions_visible

func set_corner_action_mode(body_scan_only: bool) -> void:
	if _action_row:
		_action_row.visible = true
	if _inventory_button:
		_inventory_button.visible = not body_scan_only
	if _settings_button:
		_settings_button.visible = not body_scan_only

func is_action_button_at(global_pos: Vector2) -> bool:
	var buttons: Array[Button] = [_body_scan_button]
	if _inventory_button and _inventory_button.visible:
		buttons.append(_inventory_button)
	if _settings_button and _settings_button.visible:
		buttons.append(_settings_button)
	for button in buttons:
		if button and button.get_global_rect().has_point(global_pos):
			return true
	return false

func is_detailed() -> bool:
	return _mode == Mode.DETAILED

func set_panel_scale(scale_value: float) -> void:
	scale = Vector2.ONE * scale_value

func _bind_vital_rows() -> void:
	var prefixes := {
		"blood": "Blood",
		"pain": "Stance",
		"hunger": "Hunger",
		"thirst": "Thirst",
		"fatigue": "Fatigue",
		"temperature": "Temperature",
	}
	for key in prefixes:
		var prefix: String = prefixes[key]
		_vital_rows[key] = {
			"icon": get_node("%" + prefix + "Icon") as TextureRect,
			"label": get_node("%" + prefix + "Label") as Label,
			"bar": get_node("%" + prefix + "Bar") as ProgressBar,
		}

func _apply_assets() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_button(_body_scan_button, "blood")
	HUDAssetLibrary.apply_button(_inventory_button, "inventory")
	HUDAssetLibrary.apply_button(_settings_button, "settings")
	HUDAssetLibrary.apply_label(_location_label, "body")
	HUDAssetLibrary.apply_label(_time_label, "body")
	HUDAssetLibrary.apply_label(_warning_label, "warning")
	%LocationIcon.texture = HUDAssetLibrary.status_icon("location")
	%TimeIcon.texture = HUDAssetLibrary.status_icon("time")
	_apply_vital_icon("blood", "blood", "blood")
	_apply_vital_icon("pain", "stance", "stance")
	_apply_vital_icon("hunger", "hunger", "warning")
	_apply_vital_icon("thirst", "thirst", "health")
	_apply_vital_icon("fatigue", "fatigue", "stance")
	_apply_vital_icon("temperature", "temperature", "anomaly")

func _apply_vital_icon(key: String, icon_name: String, fill_kind: String) -> void:
	var row: Dictionary = _vital_rows[key]
	(row["icon"] as TextureRect).texture = RevampedHUDAtlas.stat_icon(icon_name)
	HUDAssetLibrary.apply_label(row["label"], "body")
	RevampedHUDAtlas.apply_revamped_progress_bar(row["bar"], fill_kind)
	(row["bar"] as ProgressBar).max_value = MAX_SCALE

func _set_mode(mode: Mode) -> void:
	_mode = mode
	_compact_view.visible = mode == Mode.COMPACT
	_detailed_view.visible = mode == Mode.DETAILED
	_body_scan_button.text = "Compact" if mode == Mode.DETAILED else "Body Scan"
	if mode == Mode.DETAILED:
		custom_minimum_size = Vector2(910, 520)
		size = custom_minimum_size
		_medical_monitor.open_monitor(_snapshot)
	else:
		custom_minimum_size = Vector2.ZERO
		size = Vector2(398, 220)
		if _medical_monitor.is_open():
			_medical_monitor.close_monitor()

func _on_medical_closed() -> void:
	if _mode == Mode.DETAILED:
		_set_mode(Mode.COMPACT)

func _on_body_scan_pressed() -> void:
	if body_scan_opens_internal:
		toggle_body_scan()
	else:
		body_scan_requested.emit()

func _render_compact() -> void:
	if _snapshot.is_empty():
		_location_label.text = "HEX --, --"
		_time_label.text = "DAY -- // --:--"
		_warning_label.text = "NO BODY SIGNAL"
		_update_condition_icon([])
		return
	var coords: Vector2i = _snapshot.get("coords", Vector2i.ZERO)
	var clock: Dictionary = _snapshot.get("world_time", {})
	_location_label.text = "HEX %d, %d" % [coords.x, coords.y]
	_time_label.text = "DAY %02d // %02d:%02d" % [
		int(clock.get("day", 1)),
		int(clock.get("hour", 0)),
		int(clock.get("minute", 0)),
	]
	_update_vital("blood", float(_snapshot.get("blood", 0.0)), "BLOOD")
	_update_vital("pain", float(_snapshot.get("pain", 0.0)), "PAIN")
	_update_vital("hunger", float(_snapshot.get("hunger", 0.0)), "HUNGER")
	_update_vital("thirst", float(_snapshot.get("thirst", 0.0)), "THIRST")
	_update_vital("fatigue", float(_snapshot.get("fatigue", 0.0)), "FATIGUE", true)
	var temperature := float(_snapshot.get("core_temperature", 37.0))
	_update_vital(
		"temperature",
		clampf((temperature - 30.0) / 12.0 * MAX_SCALE, 0.0, MAX_SCALE),
		"TEMP %.1fC" % temperature
	)
	_warning_label.text = _warning_text()
	_update_condition_icon(_snapshot.get("emergencies", []))

func _update_condition_icon(emergencies: Array) -> void:
	if _condition_icon == null:
		return
	if _condition_tween:
		_condition_tween.kill()
		_condition_tween = null
	if emergencies.is_empty():
		_condition_icon.visible = true
		_condition_icon.texture = RevampedHUDAtlas.condition_icon("fine")
		_condition_icon.modulate = Color.WHITE
		return
	var primary := str(emergencies[0])
	_condition_icon.visible = true
	_condition_icon.texture = RevampedHUDAtlas.emergency_condition_icon(primary)
	_condition_icon.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_condition_tween = create_tween().set_loops()
	_condition_tween.tween_property(_condition_icon, "modulate:a", 0.35, 0.45)
	_condition_tween.tween_property(_condition_icon, "modulate:a", 1.0, 0.45)

func _update_vital(
	key: String,
	value: float,
	label_text: String,
	inverted: bool = false
) -> void:
	var row: Dictionary = _vital_rows[key]
	var label := row["label"] as Label
	var bar := row["bar"] as ProgressBar
	bar.value = clampf(value, 0.0, MAX_SCALE)
	var display_value := MAX_SCALE - bar.value if inverted else bar.value
	label.text = "%s  %04.1f/12" % [label_text, display_value]

func _warning_text() -> String:
	var warnings := PackedStringArray()
	if float(_snapshot.get("blood", 0.0)) <= 4.0:
		warnings.append("LOW BLOOD")
	if float(_snapshot.get("hunger", 0.0)) <= 3.0:
		warnings.append("STARVING")
	if float(_snapshot.get("thirst", 0.0)) <= 3.0:
		warnings.append("DEHYDRATED")
	if float(_snapshot.get("fatigue", 0.0)) >= 9.0:
		warnings.append("EXHAUSTED")
	if float(_snapshot.get("bleeding_rate", 0.0)) > 0.0:
		warnings.append("BLEED %.2f/TICK" % float(_snapshot.get("bleeding_rate", 0.0)))
	if float(_snapshot.get("pain", 0.0)) >= 8.0:
		warnings.append("SEVERE PAIN")
	if warnings.is_empty():
		return "BODY SIGNAL STABLE"
	return " / ".join(warnings)
