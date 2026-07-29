extends PanelContainer
class_name MacroHexTargetPanel

signal travel_requested(coords: Vector2i)

var _target: Dictionary = {}
var _title: Label
var _details: Label
var _travel_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	HUDAssetLibrary.apply_panel(self, "travel")
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	_title = Label.new()
	HUDAssetLibrary.apply_label(_title, "travel")
	column.add_child(_title)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_details, "muted")
	column.add_child(_details)
	_travel_button = Button.new()
	HUDAssetLibrary.apply_button(_travel_button, "travel")
	_travel_button.pressed.connect(_on_travel_pressed)
	column.add_child(_travel_button)
	visible = false


func apply_snapshot(snapshot: Dictionary) -> void:
	var current: Dictionary = snapshot.get("current_location", {})
	_target = snapshot.get("target_location", {}).duplicate(true)
	if _target.is_empty() or _target.get("coords") == current.get("coords"):
		visible = false
		return
	visible = true
	var coords: Vector2i = _target.get("coords", Vector2i.ZERO)
	_title.text = "TARGET // HEX %d,%d" % [coords.x, coords.y]
	var blocked_reason := str(_target.get("blocked_reason", ""))
	if not blocked_reason.is_empty():
		_details.text = "%s\n%s" % [
			str(_target.get("feature_title", "Unknown ground")), blocked_reason
		]
	else:
		_details.text = "%s  ·  %d min  ·  ~%.1f km" % [
			str(_target.get("feature_title", "Unknown ground")),
			int(_target.get("travel_minutes", 0)),
			float(_target.get("travel_km", 0.0)),
		]
	_travel_button.text = "Travel [T]" if bool(_target.get("can_travel", false)) else "Travel unavailable"
	_travel_button.disabled = not bool(_target.get("can_travel", false))


func restyle() -> void:
	HUDAssetLibrary.apply_panel(self, "travel")
	if _title:
		HUDAssetLibrary.apply_label(_title, "travel")
	if _details:
		HUDAssetLibrary.apply_label(_details, "muted")
	if _travel_button:
		HUDAssetLibrary.apply_button(_travel_button, "travel")


func _on_travel_pressed() -> void:
	travel_requested.emit(_target.get("coords", Vector2i.ZERO))
