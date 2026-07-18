extends Control
class_name DuelReadabilityEffects

const TELEGRAPH_COLORS := {
	GameEnums.DuelActionType.LIGHT_STRIKE: Color(1.0, 0.76, 0.28, 1.0),
	GameEnums.DuelActionType.HEAVY_STRIKE: Color(1.0, 0.35, 0.2, 1.0),
	GameEnums.DuelActionType.COMBO_FINISHER: Color(1.0, 0.12, 0.12, 1.0),
	GameEnums.DuelActionType.PUSH: Color(0.92, 0.56, 0.22, 1.0),
	GameEnums.DuelActionType.GUARD: Color(0.35, 0.72, 1.0, 1.0),
	GameEnums.DuelActionType.BLIND_FIRE: Color(1.0, 0.66, 0.22, 1.0),
	GameEnums.DuelActionType.AIMED_FIRE: Color(1.0, 0.18, 0.12, 1.0),
}

@onready var threat_panel: PanelContainer = %ThreatPanel
@onready var threat_title: Label = %ThreatTitle
@onready var threat_hint: Label = %ThreatHint
@onready var threat_bar: ProgressBar = %ThreatBar
@onready var danger_vignette: ColorRect = %DangerVignette
@onready var popup_root: Control = %PopupRoot

var _telegraph_remaining := 0.0
var _telegraph_duration := 0.0
var _last_telegraph := ""
var _last_hint := ""
var _last_popup_side := ""
var _last_popup_position := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	threat_panel.visible = false
	danger_vignette.visible = false
	set_process(false)

func show_event(event: Dictionary, _melee_locked: bool, actor_anchors: Dictionary = {}) -> void:
	var event_type := str(event.get("type", ""))
	if (
		event_type == "action_timeline"
		and str(event.get("side", "")) == "enemy"
	):
		_show_enemy_telegraph(event)
		return

	var side := str(event.get("side", event.get("target_side", "")))
	var anchor := actor_anchors.get(side, Vector2.ZERO) as Vector2
	match event_type:
		"parry":
			_show_popup("PARRY", Color(0.4, 0.9, 1.0, 1.0), 0.95, side, anchor)
		"block":
			_show_popup("BLOCK", Color(0.55, 0.75, 1.0, 1.0), 0.7, side, anchor)
		"heavy_cancel":
			_show_popup("FEINT", Color(0.95, 0.72, 0.32, 1.0), 0.65, side, anchor)
		"hazard_trip":
			_show_popup("TRIPPED", Color(0.9, 0.4, 0.25, 1.0), 0.85, side, anchor)
		"damage":
			_show_popup(_damage_text(event), Color(1.0, 0.28, 0.22, 1.0), 0.55, side, anchor)

func clear_telegraph() -> void:
	_telegraph_remaining = 0.0
	threat_panel.visible = false
	danger_vignette.visible = false
	if popup_root.get_child_count() == 0:
		set_process(false)

func get_active_telegraph_text() -> String:
	return _last_telegraph if _telegraph_remaining > 0.0 else ""

func get_active_telegraph_hint() -> String:
	return _last_hint if _telegraph_remaining > 0.0 else ""

func get_last_popup_side() -> String:
	return _last_popup_side

func get_last_popup_position() -> Vector2:
	return _last_popup_position

func get_telegraph_descriptor(action: int) -> Dictionary:
	return _telegraph_descriptor(action)

func _process(delta: float) -> void:
	if _telegraph_remaining <= 0.0:
		return
	_telegraph_remaining = maxf(0.0, _telegraph_remaining - delta)
	threat_bar.value = _telegraph_remaining
	if _telegraph_remaining <= 0.0:
		threat_panel.visible = false
		danger_vignette.visible = false
		if popup_root.get_child_count() == 0:
			set_process(false)

func _show_enemy_telegraph(event: Dictionary) -> void:
	var action := int(event.get("action", GameEnums.DuelActionType.NONE))
	var descriptor := _telegraph_descriptor(action)
	if descriptor.is_empty():
		return
	var impact_time := maxf(0.25, float(event.get("impact_time", 0.5)))
	_telegraph_duration = impact_time
	_telegraph_remaining = impact_time
	_last_telegraph = str(descriptor.get("title", "ENEMY ACTION"))
	_last_hint = str(descriptor.get("hint", "READ THE MOTION"))
	threat_title.text = _last_telegraph
	threat_hint.text = _last_hint
	threat_title.modulate = TELEGRAPH_COLORS.get(action, Color.WHITE)
	threat_bar.max_value = impact_time
	threat_bar.value = impact_time
	# The top duel timeline owns telegraph text. This component retains the
	# synchronized state and vignette without spawning a second overlapping card.
	threat_panel.visible = false
	danger_vignette.visible = bool(descriptor.get("danger", false))
	set_process(true)

func _telegraph_descriptor(action: int) -> Dictionary:
	match action:
		GameEnums.DuelActionType.LIGHT_STRIKE:
			return {
				"title": "QUICK STRIKE",
				"hint": "SPACE NEAR IMPACT: PARRY  |  HOLD EARLY: BLOCK",
				"camera": 0.35,
			}
		GameEnums.DuelActionType.HEAVY_STRIKE:
			return {
				"title": "HEAVY WIND-UP",
				"hint": "WAIT FOR THE COMMIT, THEN SPACE",
				"camera": 0.65,
				"danger": true,
			}
		GameEnums.DuelActionType.COMBO_FINISHER:
			return {
				"title": "COMBO FINISHER",
				"hint": "PARRY THE IMPACT OR BREAK THE LOCK",
				"camera": 0.9,
				"danger": true,
			}
		GameEnums.DuelActionType.PUSH:
			return {
				"title": "SHOVE",
				"hint": "BRACE WITH SPACE; EXPECT THE FOLLOW-UP",
				"camera": 0.5,
			}
		GameEnums.DuelActionType.GUARD:
			return {
				"title": "GUARD RAISED",
				"hint": "DELAY, FEINT, OR RESET THE EXCHANGE",
				"camera": 0.2,
			}
		GameEnums.DuelActionType.BLIND_FIRE:
			return {
				"title": "BLIND FIRE",
				"hint": "MOVE TO COVER OR DISRUPT THE SHOT",
			}
		GameEnums.DuelActionType.AIMED_FIRE:
			return {
				"title": "AIMED SHOT",
				"hint": "BREAK AIM, MOVE, OR FIRE FIRST",
				"danger": true,
			}
	return {}

func _show_popup(
	text: String,
	color: Color,
	duration: float,
	side: String,
	anchor: Vector2
) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.position = anchor + Vector2(-110.0, -92.0)
	label.size = Vector2(220.0, 44.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_root.add_child(label)
	_last_popup_side = side
	_last_popup_position = label.position
	set_process(true)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 54.0, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration).set_delay(duration * 0.35)
	tween.finished.connect(_finish_popup.bind(label))

func _finish_popup(label: Label) -> void:
	label.tree_exited.connect(_stop_if_idle, CONNECT_ONE_SHOT)
	label.queue_free()

func _stop_if_idle() -> void:
	if _telegraph_remaining <= 0.0 and popup_root.get_child_count() == 0:
		set_process(false)

func _damage_text(event: Dictionary) -> String:
	var flesh := float(event.get("flesh_damage", 0.0))
	var stance := float(event.get("stance_damage", 0.0))
	if flesh > 0.0 and stance > 0.0:
		return "HIT  -%.1f BLOOD  -%.0f STANCE" % [flesh, stance]
	if flesh > 0.0:
		return "WOUND  -%.1f BLOOD" % flesh
	return "IMPACT  -%.0f STANCE" % stance
