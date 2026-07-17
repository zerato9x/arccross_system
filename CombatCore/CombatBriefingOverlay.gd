extends CanvasLayer
class_name CombatBriefingOverlay

signal combat_begin_requested

const COUNTDOWN_STEP_SECONDS := 0.65

@onready var mode_label: Label = %ModeLabel
@onready var opponent_label: Label = %OpponentLabel
@onready var context_label: Label = %ContextLabel
@onready var controls_label: Label = %ControlsLabel
@onready var begin_button: Button = %BeginButton
@onready var countdown_label: Label = %CountdownLabel

var _waiting := false
var _counting_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	begin_button.pressed.connect(_begin_countdown)


func open_briefing(data: Dictionary) -> void:
	_waiting = true
	_counting_down = false
	mode_label.text = str(data.get("mode", "COMBAT ENCOUNTER"))
	opponent_label.text = "OPPONENT  //  %s" % str(
		data.get("opponent", "UNKNOWN CONTACT")
	).to_upper()
	context_label.text = str(
		data.get("context", "The lane is loaded. Combat remains frozen until you begin.")
	)
	controls_label.text = str(data.get("controls", "Review your body and equipment before committing."))
	countdown_label.text = ""
	begin_button.text = "BEGIN COMBAT"
	begin_button.disabled = false
	visible = true
	begin_button.grab_focus()
	await combat_begin_requested


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _waiting or _counting_down:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_begin_countdown()
			get_viewport().set_input_as_handled()


func _begin_countdown() -> void:
	if not _waiting or _counting_down:
		return
	_counting_down = true
	begin_button.disabled = true
	begin_button.text = "COMBAT ARMING"
	for beat in ["3", "2", "1", "READY"]:
		countdown_label.text = beat
		await get_tree().create_timer(COUNTDOWN_STEP_SECONDS, true, false, true).timeout
	visible = false
	_waiting = false
	_counting_down = false
	combat_begin_requested.emit()
