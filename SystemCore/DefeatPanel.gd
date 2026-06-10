extends CanvasLayer
class_name DefeatPanel

signal restart_requested
signal load_requested

var _overlay: ColorRect
var _load_button: Button

func _ready() -> void:
	layer = 100
	_build_panel()
	close_panel()

func open_panel(can_load: bool) -> void:
	_overlay.visible = true
	_load_button.disabled = not can_load

func close_panel() -> void:
	if _overlay:
		_overlay.visible = false

func is_open() -> bool:
	return _overlay != null and _overlay.visible

func _build_panel() -> void:
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.025, 0.02, 0.025, 0.96)
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440.0, 280.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var title := Label.new()
	title.text = "RUN ENDED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)

	var body := Label.new()
	body.text = (
		"This body cannot continue. The defeated runtime state remains "
		+ "authoritative until you begin a new run or load a save."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(body)

	var restart_button := Button.new()
	restart_button.text = "BEGIN NEW RUN"
	restart_button.pressed.connect(restart_requested.emit)
	content.add_child(restart_button)

	_load_button = Button.new()
	_load_button.text = "LOAD SAVED RUN"
	_load_button.pressed.connect(load_requested.emit)
	content.add_child(_load_button)
