extends RefCounted
class_name MacroHudLayoutManager

signal viewport_insets_changed(insets: Rect2i)
signal expanded_count_changed(count: int)

const MAX_EXPANDED := 3

var _panels: Dictionary = {}
var _expanded: Array[String] = []
var _world_status_panel: Control


func register_panel(panel_id: String, panel: MacroCornerPanel) -> void:
	_panels[panel_id] = panel
	panel.state_changed.connect(_on_panel_state_changed)


func register_world_status(panel: Control) -> void:
	_world_status_panel = panel


func get_expanded_count() -> int:
	return _expanded.size()


func is_any_expanded() -> bool:
	return not _expanded.is_empty()


func collapse_all() -> void:
	for panel_id in _expanded.duplicate():
		var panel: MacroCornerPanel = _panels.get(panel_id)
		if panel:
			panel.collapse()


func compute_viewport_insets() -> Rect2i:
	var left := 0
	var top := 0
	var right := 0
	var bottom := 0
	for panel_id in _expanded:
		var panel: MacroCornerPanel = _panels.get(panel_id)
		if panel == null or not panel.is_expanded():
			continue
		var rect := panel.get_occupied_rect()
		if rect.size.x <= 0.0:
			continue
		match panel.panel_corner:
			MacroCornerPanel.PanelCorner.TOP_LEFT:
				left = maxi(left, int(rect.size.x + MacroCornerPanel.PREVIEW_MARGIN))
				top = maxi(top, int(rect.size.y + MacroCornerPanel.PREVIEW_MARGIN))
			MacroCornerPanel.PanelCorner.BOTTOM_LEFT:
				left = maxi(left, int(rect.size.x + MacroCornerPanel.PREVIEW_MARGIN))
				bottom = maxi(bottom, int(rect.size.y + MacroCornerPanel.PREVIEW_MARGIN))
			MacroCornerPanel.PanelCorner.TOP_RIGHT:
				right = maxi(right, int(rect.size.x + MacroCornerPanel.PREVIEW_MARGIN))
				top = maxi(top, int(rect.size.y + MacroCornerPanel.PREVIEW_MARGIN))
			MacroCornerPanel.PanelCorner.BOTTOM_RIGHT:
				right = maxi(right, int(rect.size.x + MacroCornerPanel.PREVIEW_MARGIN))
	return Rect2i(left, top, right, bottom)


func _on_panel_state_changed(panel_id: String, state: int) -> void:
	if state == MacroCornerPanel.PanelState.EXPANDED:
		if not _expanded.has(panel_id):
			if _expanded.size() >= MAX_EXPANDED:
				var oldest: String = _expanded[0]
				var old_panel: MacroCornerPanel = _panels.get(oldest)
				if old_panel:
					old_panel.collapse()
				_expanded.erase(oldest)
			_expanded.append(panel_id)
	else:
		_expanded.erase(panel_id)
	var insets := compute_viewport_insets()
	viewport_insets_changed.emit(insets)
	expanded_count_changed.emit(_expanded.size())
