extends Control
class_name MacroWorldStatusPanel

signal settings_requested

var _snapshot: Dictionary = {}

@onready var _frame: PanelContainer = %Frame
@onready var _clock: PocketClockDisplay = %PocketClock
@onready var _day_icon: TextureRect = %DayIcon
@onready var _day_label: Label = %DayLabel
@onready var _calendar_label: Label = %CalendarLabel
@onready var _settings_button: Button = %SettingsButton


func _ready() -> void:
	custom_minimum_size = Vector2(260.0, 118.0)
	HUDAssetLibrary.apply_panel(_frame, "neutral")
	HUDAssetLibrary.apply_label(_day_label, "body")
	HUDAssetLibrary.apply_label(_calendar_label, "muted")
	HUDAssetLibrary.apply_button(_settings_button, "settings")
	_settings_button.text = "Settings"
	_settings_button.pressed.connect(func(): settings_requested.emit())


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var clock: Dictionary = snapshot.get("world_time", {})
	var calendar: Dictionary = snapshot.get("calendar", {})
	var hour := int(clock.get("hour", 0))
	var minute := int(clock.get("minute", 0))
	if _clock:
		_clock.visible = true
		_clock.set_time(hour, minute)
	var phase: String = RevampedHUDAtlas.time_of_day_phase(hour)
	if _day_icon:
		_day_icon.visible = true
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
