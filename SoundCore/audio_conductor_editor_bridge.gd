@tool
extends EditorInspectorPlugin
class_name AudioConductorInspector

## Editor inspector plugin that adds AudioConductor preview controls
## when the AudioConductor autoload node is selected in the editor.
## Uses the godot_ai addon's game_eval (when game is running) to
## send commands to the live AudioConductor, or previews tracks
## directly in the editor when the game is not running.

func _can_handle(object: Object) -> bool:
	if object is Node:
		var script = object.get_script()
		if script and script.resource_path.ends_with("audio_conductor.gd"):
			return true
	return false

func _parse_begin(object: Object) -> void:
	# Scene selector
	var scene_label := Label.new()
	scene_label.text = "🎵 Audio Conductor Controls"
	add_custom_control(scene_label)

	var scene_dropdown := OptionButton.new()
	scene_dropdown.add_item("SILENT", 0)
	scene_dropdown.add_item("MACRO_DAY (Dawn)", 1)
	scene_dropdown.add_item("MACRO_NIGHT (Storm)", 2)
	scene_dropdown.add_item("COMBAT_STANDARD", 3)
	scene_dropdown.add_item("COMBAT_SPECIAL (Waiting→War)", 4)
	scene_dropdown.add_item("GAME_OVER (Survivor)", 5)
	scene_dropdown.item_selected.connect(_on_scene_selected)
	add_custom_control(scene_dropdown)

	# EQ Controls
	var eq_label := Label.new()
	eq_label.text = "EQ (Low / Mid / High)"
	add_custom_control(eq_label)

	for band_name in ["Low", "Mid", "High"]:
		var slider := HSlider.new()
		slider.min_value = -60.0
		slider.max_value = 24.0
		slider.value = 0.0
		slider.step = 0.5
		slider.tooltip_text = band_name + " EQ (dB)"
		slider.custom_minimum_size.x = 200
		slider.name = "EQ_" + band_name
		slider.value_changed.connect(_on_eq_changed.bind(band_name))
		add_custom_control(slider)

	# Gain
	var gain_label := Label.new()
	gain_label.text = "Gain (dB)"
	add_custom_control(gain_label)

	var gain_slider := HSlider.new()
	gain_slider.min_value = -80.0
	gain_slider.max_value = 24.0
	gain_slider.value = 0.0
	gain_slider.step = 0.5
	gain_slider.custom_minimum_size.x = 200
	gain_slider.value_changed.connect(_on_gain_changed)
	add_custom_control(gain_slider)

	# Time Stretch
	var time_label := Label.new()
	time_label.text = "Time Stretch"
	add_custom_control(time_label)

	var time_slider := HSlider.new()
	time_slider.min_value = 0.1
	time_slider.max_value = 2.0
	time_slider.value = 1.0
	time_slider.step = 0.01
	time_slider.custom_minimum_size.x = 200
	time_slider.value_changed.connect(_on_time_stretch_changed)
	add_custom_control(time_slider)

	# Trigger buttons
	var btn_container := HBoxContainer.new()

	var overlay_btn := Button.new()
	overlay_btn.text = "Toggle Critical Overlay"
	overlay_btn.pressed.connect(_on_toggle_overlay)
	btn_container.add_child(overlay_btn)

	var first_strike_btn := Button.new()
	first_strike_btn.text = "Trigger First Strike"
	first_strike_btn.pressed.connect(_on_trigger_first_strike)
	btn_container.add_child(first_strike_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset Params"
	reset_btn.pressed.connect(_on_reset_params)
	btn_container.add_child(reset_btn)

	add_custom_control(btn_container)

# Store current EQ values for batch sending
var _eq_low: float = 0.0
var _eq_mid: float = 0.0
var _eq_high: float = 0.0
var _overlay_on: bool = false

func _on_scene_selected(index: int) -> void:
	_game_eval("AudioConductor.enter_scene(%d)" % index)

func _on_eq_changed(value: float, band: String) -> void:
	match band:
		"Low": _eq_low = value
		"Mid": _eq_mid = value
		"High": _eq_high = value
	_game_eval("AudioConductor.set_3band_eq(%f, %f, %f)" % [_eq_low, _eq_mid, _eq_high])

func _on_gain_changed(value: float) -> void:
	_game_eval("AudioConductor.set_gain(%f)" % value)

func _on_time_stretch_changed(value: float) -> void:
	_game_eval("AudioConductor.set_time_stretch(%f)" % value)

func _on_toggle_overlay() -> void:
	_overlay_on = not _overlay_on
	_game_eval("AudioConductor.set_critical_overlay(%s)" % str(_overlay_on).to_lower())

func _on_trigger_first_strike() -> void:
	_game_eval("AudioConductor.on_first_strike(GameEnums.ActionType.STRIKE)")

func _on_reset_params() -> void:
	_eq_low = 0.0
	_eq_mid = 0.0
	_eq_high = 0.0
	_overlay_on = false
	_game_eval("AudioConductor._reset_algorave_params()")

func _game_eval(code: String) -> void:
	# Try to use godot_ai's game_eval if available, otherwise print the command
	var helper = Engine.get_singleton("EngineDebugger") if Engine.has_singleton("EngineDebugger") else null
	if helper and EngineDebugger.is_active():
		EngineDebugger.send_message("mcp:eval", ["audio_preview", code])
	else:
		print("[CONDUCTOR BRIDGE] Game not running. Would eval: ", code)
