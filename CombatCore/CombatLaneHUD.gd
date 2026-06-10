extends CanvasLayer
class_name CombatLaneHUD

const PANEL_COLOR := Color(0.015, 0.045, 0.045, 0.96)
const CYAN := Color(0.28, 0.95, 0.88)
const AMBER := Color(1.0, 0.68, 0.25)
const CRIMSON := Color(1.0, 0.25, 0.34)
const MUTED := Color(0.38, 0.62, 0.58)

var _root: Control
var _round_label: Label
var _active_label: Label
var _player_label: Label
var _enemy_label: Label
var _lane_view: CombatLaneView
var _snapshot: Dictionary = {}
var _font: SystemFont

func _ready() -> void:
	layer = 10
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_build_hud()
	_root.visible = false

func open_hud() -> void:
	if _root:
		_root.visible = true

func close_hud() -> void:
	if _root:
		_root.visible = false
	_snapshot.clear()

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if not _root:
		return
	_root.visible = true
	_render()

func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func is_showing_melee_lock() -> bool:
	return _lane_view != null and _lane_view.is_showing_melee_lock()

func play_action(side: String, action: int) -> void:
	if _lane_view:
		_lane_view.play_action(side, action)

func get_character_rig(side: String) -> ModularCombatRig:
	if not _lane_view:
		return null
	return _lane_view.get_character_rig(side)

func _build_hud() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.004, 0.012, 0.014, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24.0
	panel.offset_top = 18.0
	panel.offset_right = -458.0
	panel.offset_bottom = -24.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)

	var title := _label("ARCCROSS // TACTICAL LANE", 21, CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_round_label = _label("ROUND --", 15, MUTED)
	header.add_child(_round_label)

	_active_label = _label("AWAITING COMBAT", 15, AMBER)
	header.add_child(_active_label)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	column.add_child(status_row)

	_player_label = _status_label(CYAN)
	_player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_player_label)

	_enemy_label = _status_label(CRIMSON)
	_enemy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_enemy_label)

	_lane_view = CombatLaneView.new()
	_lane_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lane_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_lane_view)

	var legend := _label(
		"P PLAYER   E ENEMY   EX EXIT   # COVER   X OBSTACLE   ^ TRAP   ~ MUD   T TREES",
		12,
		MUTED
	)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(legend)

func _render() -> void:
	if _snapshot.is_empty():
		_round_label.text = "ROUND --"
		_active_label.text = "AWAITING COMBAT"
		_player_label.text = "PLAYER // NO SIGNAL"
		_enemy_label.text = "ENEMY // NO SIGNAL"
		_lane_view.show_snapshot({})
		return

	_round_label.text = "ROUND %02d" % int(_snapshot.get("round", 0))
	var active_side := str(_snapshot.get("active_side", ""))
	var active_color := CYAN if active_side == "player" else CRIMSON
	_active_label.modulate = active_color
	_active_label.text = "ACTIVE %s // AP %02d" % [
		str(_snapshot.get("active_name", "UNKNOWN")).to_upper(),
		int(_snapshot.get("ap", 0)),
	]

	_player_label.text = _combatant_text(
		_snapshot.get("player", {}),
		"PLAYER"
	)
	_enemy_label.text = _combatant_text(
		_snapshot.get("enemy", {}),
		"ENEMY"
	)
	_lane_view.show_snapshot(_snapshot)

func _combatant_text(data: Dictionary, heading: String) -> String:
	var active_marker := " [ACTIVE]" if data.get("is_active", false) else ""
	var escape_marker := " [ESCAPING]" if data.get("is_escaping", false) else ""
	var guard_marker := (
		" [GUARDED]"
		if data.get("stance_recovery_guard", false)
		else ""
	)
	return (
		"%s%s // SLOT %02d\n"
		+ "%s\n"
		+ "BLOOD %04.1f  STANCE %02d%s  MORALE %04.1f\n"
		+ "AP-R %02d  KINETIC %s  WEAPON %s%s\n"
		+ "%s"
	) % [
		heading,
		active_marker,
		int(data.get("lane", -1)),
		str(data.get("archetype", data.get("name", "UNKNOWN"))).to_upper(),
		float(data.get("blood", 0.0)),
		int(data.get("stance", 0)),
		guard_marker,
		float(data.get("morale", 0.0)),
		int(data.get("reserved_ap", 0)),
		str(data.get("kinetic_tier", "UNKNOWN")),
		str(data.get("weapon", "UNARMED")).to_upper(),
		escape_marker,
		_limb_text(data.get("limbs", [])),
	]

func _limb_text(limbs: Array) -> String:
	if limbs.size() < 7:
		return "LIMBS // NO SIGNAL"
	return "\n".join([
		"CORE " + _format_limb(limbs[0]) + " " + _format_limb(limbs[1]) + " " + _format_limb(limbs[2]),
		"ARMS " + _format_limb(limbs[3]) + " " + _format_limb(limbs[4]),
		"LEGS " + _format_limb(limbs[5]) + " " + _format_limb(limbs[6]),
	])

func _format_limb(limb: Dictionary) -> String:
	var trauma_marker := (
		"!"
		if limb.get("trauma", "NONE") != "NONE"
		else ""
	)
	return "%s%s %s/%s" % [
		limb.get("code", "??"),
		trauma_marker,
		_compact_number(float(limb.get("current", 0.0))),
		_compact_number(float(limb.get("maximum", 0.0))),
	]

func _compact_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _status_label(color: Color) -> Label:
	var label := _label("", 13, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 130.0
	label.add_theme_stylebox_override("normal", _status_style(color))
	return label

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = Color(0.12, 0.48, 0.44, 0.9)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _status_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r * 0.04, color.g * 0.04, color.b * 0.04, 0.82)
	style.border_color = Color(color.r, color.g, color.b, 0.55)
	style.set_border_width_all(1)
	style.content_margin_left = 10.0
	style.content_margin_top = 7.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 7.0
	return style
