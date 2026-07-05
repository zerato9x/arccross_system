extends RefCounted
class_name MacroHudLayoutManager

signal viewport_insets_changed(insets: Rect2i)
signal expanded_count_changed(count: int)

var _panels: Dictionary = {}
var _expanded: Array[String] = []
var _world_status_panel: Control
var _viewport: Viewport


func register_panel(panel_id: String, panel: MacroCornerPanel) -> void:
	_panels[panel_id] = panel
	panel.state_changed.connect(_on_panel_state_changed)
	if _viewport == null:
		_viewport = panel.get_viewport()
		if _viewport and not _viewport.size_changed.is_connected(_on_viewport_size_changed):
			_viewport.size_changed.connect(_on_viewport_size_changed)


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
			_expanded.append(panel_id)
	else:
		_expanded.erase(panel_id)
	_apply_layout_constraints()
	var insets := compute_viewport_insets()
	viewport_insets_changed.emit(insets)
	expanded_count_changed.emit(_expanded.size())


func _on_viewport_size_changed() -> void:
	_apply_layout_constraints()
	var insets := compute_viewport_insets()
	viewport_insets_changed.emit(insets)


func _apply_layout_constraints() -> void:
	for panel in _panels.values():
		if panel is MacroCornerPanel:
			(panel as MacroCornerPanel).set_expanded_available_override(Vector2.ZERO)
	if _expanded.is_empty():
		return
	var viewport_size := _viewport.get_visible_rect().size if _viewport else Vector2.ZERO
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var margin := MacroCornerPanel.PREVIEW_MARGIN
	var defaults := {}
	for panel_id in _expanded:
		defaults[panel_id] = Vector2(
			maxf(1.0, viewport_size.x - margin * 2.0),
			maxf(1.0, viewport_size.y - margin * 2.0)
		)
	_apply_vertical_pair_limit(
		defaults,
		MacroCornerPanel.PanelCorner.TOP_LEFT,
		MacroCornerPanel.PanelCorner.BOTTOM_LEFT,
		(viewport_size.y - margin * 3.0) * 0.5
	)
	_apply_vertical_pair_limit(
		defaults,
		MacroCornerPanel.PanelCorner.TOP_RIGHT,
		MacroCornerPanel.PanelCorner.BOTTOM_RIGHT,
		(viewport_size.y - margin * 3.0) * 0.5
	)
	_apply_horizontal_pair_limit(
		defaults,
		MacroCornerPanel.PanelCorner.TOP_LEFT,
		MacroCornerPanel.PanelCorner.TOP_RIGHT,
		(viewport_size.x - margin * 3.0) * 0.5
	)
	_apply_horizontal_pair_limit(
		defaults,
		MacroCornerPanel.PanelCorner.BOTTOM_LEFT,
		MacroCornerPanel.PanelCorner.BOTTOM_RIGHT,
		(viewport_size.x - margin * 3.0) * 0.5
	)
	_apply_world_status_limit(defaults)
	for panel_id in defaults:
		var panel: MacroCornerPanel = _panels.get(panel_id)
		if panel:
			panel.set_expanded_available_override(defaults[panel_id])


func _apply_vertical_pair_limit(
	limits: Dictionary,
	top_corner: MacroCornerPanel.PanelCorner,
	bottom_corner: MacroCornerPanel.PanelCorner,
	max_height: float
) -> void:
	var top_ids := _expanded_ids_for_corner(top_corner)
	var bottom_ids := _expanded_ids_for_corner(bottom_corner)
	if top_ids.is_empty() or bottom_ids.is_empty():
		return
	for panel_id in top_ids + bottom_ids:
		var limit: Vector2 = limits.get(panel_id, Vector2.ZERO)
		limit.y = minf(limit.y, maxf(1.0, max_height))
		limits[panel_id] = limit


func _apply_horizontal_pair_limit(
	limits: Dictionary,
	left_corner: MacroCornerPanel.PanelCorner,
	right_corner: MacroCornerPanel.PanelCorner,
	max_width: float
) -> void:
	var left_ids := _expanded_ids_for_corner(left_corner)
	var right_ids := _expanded_ids_for_corner(right_corner)
	if left_ids.is_empty() or right_ids.is_empty():
		return
	for panel_id in left_ids + right_ids:
		var limit: Vector2 = limits.get(panel_id, Vector2.ZERO)
		limit.x = minf(limit.x, maxf(1.0, max_width))
		limits[panel_id] = limit


func _apply_world_status_limit(limits: Dictionary) -> void:
	if _world_status_panel == null or not _world_status_panel.visible:
		return
	var status_rect := _world_status_panel.get_global_rect()
	if status_rect.size.x <= 0.0 or status_rect.size.y <= 0.0:
		return
	var margin := MacroCornerPanel.PREVIEW_MARGIN
	for panel_id in _expanded_ids_for_corner(MacroCornerPanel.PanelCorner.TOP_RIGHT):
		var limit: Vector2 = limits.get(panel_id, Vector2.ZERO)
		limit.y = minf(limit.y, maxf(1.0, status_rect.position.y - margin * 2.0))
		limits[panel_id] = limit
	for panel_id in _expanded_ids_for_corner(MacroCornerPanel.PanelCorner.BOTTOM_LEFT):
		var limit: Vector2 = limits.get(panel_id, Vector2.ZERO)
		limit.x = minf(limit.x, maxf(1.0, status_rect.position.x - margin * 2.0))
		limits[panel_id] = limit


func _expanded_ids_for_corner(corner: MacroCornerPanel.PanelCorner) -> Array[String]:
	var ids: Array[String] = []
	for panel_id in _expanded:
		var panel: MacroCornerPanel = _panels.get(panel_id)
		if panel and panel.panel_corner == corner and panel.is_expanded():
			ids.append(panel_id)
	return ids
