extends CanvasLayer
class_name CombatPanel

signal action_requested(action: int, target_limb: int, item_instance_id: String)
signal pass_requested
signal reaction_selected(reaction: int)

const CYAN := Color(0.28, 0.95, 0.88)
const AMBER := Color(1.0, 0.68, 0.25)
const CRIMSON := Color(1.0, 0.25, 0.34)
const MUTED := Color(0.42, 0.66, 0.62)

var _panel: PanelContainer
var _content: VBoxContainer
var _snapshot: Dictionary = {}
var _reaction_prompt: Dictionary = {}
var _feedback: String = ""
var _font: SystemFont
var _action_shortcuts: Array[Callable] = []

func _ready() -> void:
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_build_shell()
	_panel.visible = false

func open_panel() -> void:
	_panel.visible = true

func close_panel() -> void:
	if _panel:
		_panel.visible = false
	_snapshot.clear()
	_reaction_prompt.clear()
	_feedback = ""

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if not _snapshot.get("reaction_pending", false):
		_reaction_prompt.clear()
	_render()

func show_reaction(prompt: Dictionary) -> void:
	_reaction_prompt = prompt.duplicate(true)
	_render()

func show_feedback(message: String) -> void:
	_feedback = message
	_render()

func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func _build_shell() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -430.0
	_panel.offset_top = 18.0
	_panel.offset_right = -18.0
	_panel.offset_bottom = -18.0
	_panel.add_theme_stylebox_override("panel", _panel_style())
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 14
	_panel.theme = theme
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)

func _render() -> void:
	if not _panel or not _panel.visible:
		return
	_clear_content()
	_action_shortcuts.clear()
	_add_title("ARCCROSS COMBAT")

	if _snapshot.is_empty():
		_add_body("Awaiting encounter state.")
		return

	_add_body(
		"Round %d | Active: %s | AP: %d"
		% [
			_snapshot.get("round", 0),
			_snapshot.get("active_name", ""),
			_snapshot.get("ap", 0),
		]
	)
	_add_combatant(_snapshot.get("player", {}), "PLAYER")
	_add_combatant(_snapshot.get("enemy", {}), "ENEMY")

	if not _feedback.is_empty():
		var feedback := _add_body(_feedback)
		feedback.modulate = Color(0.95, 0.82, 0.35)

	if not _reaction_prompt.is_empty():
		_render_reaction_prompt()
		return

	if not _snapshot.get("is_player_turn", false):
		_add_body("Enemy turn. Waiting for combat resolution.")
		return
	if _snapshot.get("busy", false):
		_add_body("Resolving action...")
		return

	_add_section_title("ACTIONS")
	var actions: Array = _snapshot.get("actions", [])
	if actions.is_empty():
		_add_body("No legal actions are available.")
	for action_index in range(actions.size()):
		_add_action_row(actions[action_index], action_index)
	if _snapshot.get("can_pass", false):
		_add_button("[0] PASS / RESERVE AP", pass_requested.emit)

func _render_reaction_prompt() -> void:
	_add_section_title("REACTION")
	_add_body(
		"Incoming %s. Spend reserved AP or decline."
		% _reaction_prompt.get("trigger", "ATTACK")
	)
	for descriptor in _reaction_prompt.get("reactions", []):
		var reaction: int = descriptor.get("action", -1)
		_add_button(
			"%s [%d AP]" % [
				descriptor.get("label", "REACT"),
				descriptor.get("cost", 0),
			],
			_select_reaction.bind(reaction)
		)
	_add_button("DECLINE", _select_reaction.bind(-1))

func _add_combatant(snapshot: Dictionary, heading: String) -> void:
	_add_section_title(heading)
	var guard_marker := (
		" | RECOVERY GUARD"
		if snapshot.get("stance_recovery_guard", false)
		else ""
	)
	_add_body(
		(
			"%s | Lane %d | %s\n"
			+ "Blood %.1f/12 | Morale %.1f/12 | Stance %d/12 (%s)%s\n"
			+ "Weapon: %s | Kinetic: %s%s"
		) % [
			snapshot.get("archetype", snapshot.get("name", "Unknown")),
			snapshot.get("lane", -1),
			snapshot.get("name", ""),
			snapshot.get("blood", 0.0),
			snapshot.get("morale", 0.0),
			snapshot.get("stance", 0),
			snapshot.get("stance_state", ""),
			guard_marker,
			snapshot.get("weapon", "Unarmed"),
			snapshot.get("kinetic_tier", ""),
			" | ESCAPING" if snapshot.get("is_escaping", false) else "",
		]
	)
	_add_body(_limb_text(snapshot.get("limbs", [])))

func _limb_text(limbs: Array) -> String:
	if limbs.size() < 7:
		return "Limb structure unavailable."
	return "\n".join([
		"Core: " + _format_limb(limbs[0]) + " | " + _format_limb(limbs[1]) + " | " + _format_limb(limbs[2]),
		"Arms: " + _format_limb(limbs[3]) + " | " + _format_limb(limbs[4]),
		"Legs: " + _format_limb(limbs[5]) + " | " + _format_limb(limbs[6]),
	])

func _format_limb(limb: Dictionary) -> String:
	var trauma_marker := (
		"!"
		if limb.get("trauma", "NONE") != "NONE"
		else ""
	)
	return "%s%s %.1f/%.1f" % [
		limb.get("code", "??"),
		trauma_marker,
		float(limb.get("current", 0.0)),
		float(limb.get("maximum", 0.0)),
	]

func _add_action_row(descriptor: Dictionary, shortcut_index: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	var limb_selector: OptionButton
	var target_limbs: Array = descriptor.get("target_limbs", [])
	if not target_limbs.is_empty():
		limb_selector = OptionButton.new()
		limb_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(limb_selector)
		for limb in target_limbs:
			limb_selector.add_item(
				GameEnums.LimbRegion.keys()[limb].replace("_", " ")
			)
			limb_selector.set_item_metadata(
				limb_selector.item_count - 1,
				limb
			)
		row.add_child(limb_selector)

	var button := Button.new()
	var shortcut_text := (
		str(shortcut_index + 1)
		if shortcut_index < 9
		else "-"
	)
	button.text = "[%s] %s // %d AP" % [
		shortcut_text,
		descriptor.get("label", "ACTION"),
		descriptor.get("cost", 0),
	]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(button)
	var callback := _submit_action.bind(descriptor, limb_selector)
	button.pressed.connect(callback)
	if shortcut_index < 9:
		_action_shortcuts.append(callback)
	row.add_child(button)

func _submit_action(
	descriptor: Dictionary,
	limb_selector: OptionButton
) -> void:
	var target_limb := GameEnums.LimbRegion.UPPER_TORSO
	if limb_selector:
		target_limb = limb_selector.get_item_metadata(limb_selector.selected)
	action_requested.emit(
		descriptor.get("action", -1),
		target_limb,
		descriptor.get("item_instance_id", "")
	)

func _select_reaction(reaction: int) -> void:
	_reaction_prompt.clear()
	reaction_selected.emit(reaction)

func _add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", CYAN)
	_content.add_child(title)

func _add_section_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", AMBER)
	_content.add_child(title)

func _add_body(text: String) -> Label:
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", MUTED)
	_content.add_child(body)
	return body

func _add_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	_style_button(button)
	button.pressed.connect(callback)
	_content.add_child(button)
	return button

func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _panel or not _panel.visible or not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_0 and _snapshot.get("can_pass", false):
		pass_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.keycode < KEY_1 or event.keycode > KEY_9:
		return
	var shortcut_index := int(event.keycode - KEY_1)
	if shortcut_index < _action_shortcuts.size():
		_action_shortcuts[shortcut_index].call()
		get_viewport().set_input_as_handled()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.035, 0.036, 0.97)
	style.border_color = Color(0.18, 0.58, 0.53, 0.9)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _style_button(button: BaseButton) -> void:
	button.add_theme_color_override("font_color", CYAN)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", AMBER)
	button.add_theme_stylebox_override(
		"normal",
		_button_style(Color(0.02, 0.08, 0.075, 0.95), MUTED)
	)
	button.add_theme_stylebox_override(
		"hover",
		_button_style(Color(0.035, 0.15, 0.135, 0.98), CYAN)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_button_style(Color(0.16, 0.10, 0.025, 0.98), AMBER)
	)

func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 9.0
	style.content_margin_top = 6.0
	style.content_margin_right = 9.0
	style.content_margin_bottom = 6.0
	return style
