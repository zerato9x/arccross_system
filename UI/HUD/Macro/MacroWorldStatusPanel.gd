extends Control
class_name MacroWorldStatusPanel

signal settings_requested

const PANEL_MARGIN := 14.0

var _clock: PocketClockDisplay
var _day_icon: TextureRect
var _day_label: Label
var _calendar_label: Label
var _settings_button: Button
var _snapshot: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(236.0, 118.0)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -PANEL_MARGIN - custom_minimum_size.x
	offset_top = -PANEL_MARGIN - custom_minimum_size.y
	offset_right = -PANEL_MARGIN
	offset_bottom = -PANEL_MARGIN
	_build_ui()


func _build_ui() -> void:
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HUDAssetLibrary.apply_panel(frame, "neutral")
	add_child(frame)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)

	_clock = PocketClockDisplay.new()
	_clock.custom_minimum_size = Vector2(96, 48)
	top.add_child(_clock)

	_day_icon = TextureRect.new()
	_day_icon.custom_minimum_size = Vector2(48, 48)
	_day_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_day_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_day_icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(text_col)

	_day_label = Label.new()
	HUDAssetLibrary.apply_label(_day_label, "body")
	text_col.add_child(_day_label)

	_calendar_label = Label.new()
	HUDAssetLibrary.apply_label(_calendar_label, "muted")
	text_col.add_child(_calendar_label)

	_settings_button = Button.new()
	_settings_button.text = "SET"
	HUDAssetLibrary.apply_button(_settings_button, "settings")
	_settings_button.pressed.connect(func(): settings_requested.emit())
	column.add_child(_settings_button)


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var clock: Dictionary = snapshot.get("world_time", {})
	var calendar: Dictionary = snapshot.get("calendar", {})
	var hour := int(clock.get("hour", 0))
	var minute := int(clock.get("minute", 0))
	if _clock:
		_clock.set_time(hour, minute)
	var phase: String = RevampedHUDAtlas.time_of_day_phase(hour)
	if _day_icon:
		_day_icon.texture = RevampedHUDAtlas.time_of_day_icon(phase)
	if _day_label:
		_day_label.text = "DAY %03d" % int(calendar.get("day", clock.get("day", 1)))
	if _calendar_label:
		_calendar_label.text = "%s %04d" % [
			_month_name(int(calendar.get("month", 1))),
			int(calendar.get("year", 1)),
		]


func _month_name(month: int) -> String:
	const NAMES := [
		"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
		"JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
	]
	return NAMES[clampi(month - 1, 0, 11)]
