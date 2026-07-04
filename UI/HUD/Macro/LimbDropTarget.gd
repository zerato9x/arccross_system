extends Control
class_name LimbDropTarget

signal item_dropped(instance_id: String, limb_region: int)

@export var limb_region: int = GameEnums.LimbRegion.HEAD

var _highlight: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_highlight()


func configure(region: int) -> void:
	limb_region = region
	tooltip_text = "Apply medical item to %s" % GameEnums.LimbRegion.keys()[region]


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var instance_id := str(data.get("instance_id", ""))
	var ok := not instance_id.is_empty()
	if _highlight:
		_highlight.visible = ok
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _highlight:
		_highlight.visible = false
	if not data is Dictionary:
		return
	var instance_id := str(data.get("instance_id", ""))
	if instance_id.is_empty():
		return
	item_dropped.emit(instance_id, limb_region)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _highlight:
		_highlight.visible = false


func _build_highlight() -> void:
	_highlight = ColorRect.new()
	_highlight.color = Color(0.3, 0.9, 0.4, 0.25)
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.visible = false
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight)
