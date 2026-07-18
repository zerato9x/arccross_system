extends Control
class_name TravelBeatPresenter

signal beat_finished

@onready var _panel: PanelContainer = %TravelPanel
@onready var _title: Label = %TravelTitle
@onready var _body: Label = %TravelBody
@onready var _tag_row: HFlowContainer = %TravelTagRow

var _auto_timer: SceneTreeTimer
var _tween: Tween
var _blocking := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if _panel:
		HUDAssetLibrary.apply_panel(_panel, "neutral")
	if _title:
		HUDAssetLibrary.apply_label(_title, "title")
	if _body:
		HUDAssetLibrary.apply_label(_body, "body")


func present(session: Dictionary) -> void:
	_cancel_auto()
	_blocking = bool(session.get("blocking", false))
	mouse_filter = (
		Control.MOUSE_FILTER_STOP if _blocking else Control.MOUSE_FILTER_IGNORE
	)
	visible = true
	_title.text = str(session.get("title", "EXPLORING"))
	_body.text = str(session.get("body", ""))
	_render_tags(session.get("tags", []))
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.96, 0.96)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.18)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	var auto_ms := int(session.get("auto_ms", 1600))
	if not _blocking and auto_ms > 0:
		_auto_timer = get_tree().create_timer(float(auto_ms) / 1000.0)
		_auto_timer.timeout.connect(_fade_out)


func dismiss(immediate: bool = false) -> void:
	_cancel_auto()
	if immediate or not visible:
		visible = false
		_panel.modulate.a = 1.0
		beat_finished.emit()
		return
	_fade_out()


func is_showing() -> bool:
	return visible


func _fade_out() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.22)
	_tween.tween_callback(func():
		visible = false
		_panel.modulate.a = 1.0
		beat_finished.emit()
	)


func _cancel_auto() -> void:
	if _auto_timer != null:
		if _auto_timer.timeout.is_connected(_fade_out):
			_auto_timer.timeout.disconnect(_fade_out)
		_auto_timer = null


func _render_tags(tags: Array) -> void:
	for child in _tag_row.get_children():
		_tag_row.remove_child(child)
		child.queue_free()
	for tag in tags:
		var chip := PanelContainer.new()
		HUDAssetLibrary.apply_panel(chip, "neutral")
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_top", 2)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_bottom", 2)
		chip.add_child(margin)
		var label := Label.new()
		label.text = str(tag)
		HUDAssetLibrary.apply_label(label, "muted")
		margin.add_child(label)
		_tag_row.add_child(chip)
