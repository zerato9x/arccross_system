extends Control
class_name NodeMapGraphView

## Draws campaign nodes/edges from a Node Map snapshot with pan/zoom camera.

signal node_selected(node_id: String)

const NODE_RADIUS := 22.0
const PULSE_SPEED := 2.4
const ZOOM_MIN := 0.4
const ZOOM_MAX := 2.75
const ZOOM_STEP := 0.12

var _nodes: Array = []
var _edges: Array = []
var _selected_id: String = ""
var _hovered_id: String = ""
var _world_layout: Dictionary = {} # node_id -> Vector2 world pos
var _layout: Dictionary = {} # node_id -> Vector2 view pos
var _pulse_t := 0.0
var _ordered_ids: Array[String] = []
var _pan := Vector2.ZERO
var _zoom := 1.0
var _panning := false
var _pan_last := Vector2.ZERO
var _camera_initialized := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true


func _process(delta: float) -> void:
	_pulse_t += delta * PULSE_SPEED
	if _has_active_node():
		queue_redraw()


func apply_snapshot(snapshot: Dictionary) -> void:
	_nodes = snapshot.get("nodes", []).duplicate(true)
	_edges = snapshot.get("edges", []).duplicate(true)
	_rebuild_order()
	if _selected_id.is_empty() or not _find_node(_selected_id):
		_selected_id = str(snapshot.get("active_node_id", ""))
		if _selected_id.is_empty() and not _ordered_ids.is_empty():
			_selected_id = _ordered_ids[0]
	_recompute_world_layout()
	if not _camera_initialized:
		_fit_camera_to_content()
		_camera_initialized = true
	_apply_camera()
	queue_redraw()


func get_selected_id() -> String:
	return _selected_id


func prepare_open() -> void:
	_camera_initialized = false
	_panning = false


func select_node(node_id: String, emit_signal: bool = true) -> void:
	if node_id.is_empty() or not _find_node(node_id):
		return
	_selected_id = node_id
	queue_redraw()
	if emit_signal:
		node_selected.emit(_selected_id)


func reset_camera() -> void:
	_fit_camera_to_content()
	_apply_camera()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			_zoom_at(mouse.position, _zoom + ZOOM_STEP)
			accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			_zoom_at(mouse.position, _zoom - ZOOM_STEP)
			accept_event()
			return
		if (
			mouse.button_index == MOUSE_BUTTON_MIDDLE
			or mouse.button_index == MOUSE_BUTTON_RIGHT
		):
			_panning = mouse.pressed
			_pan_last = mouse.position
			accept_event()
			return
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var hit := _hit_test(mouse.position)
			if not hit.is_empty():
				select_node(hit)
			grab_focus()
			accept_event()
			return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			_pan += motion.position - _pan_last
			_pan_last = motion.position
			_apply_camera()
			queue_redraw()
			accept_event()
			return
		var hit := _hit_test(motion.position)
		if hit != _hovered_id:
			_hovered_id = hit
			queue_redraw()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_UP, KEY_LEFT:
				_move_selection(-1)
				accept_event()
			KEY_DOWN, KEY_RIGHT:
				_move_selection(1)
				accept_event()
			KEY_HOME:
				reset_camera()
				accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recompute_world_layout()
		_apply_camera()
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.04, 0.05, 0.04, 0.92))
	draw_rect(rect, HUDAssetLibrary.COLOR_BORDER, false, 1.0)

	for edge in _edges:
		if not (edge is Dictionary):
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if not _layout.has(from_id) or not _layout.has(to_id):
			continue
		var from_node: Variant = _find_node(from_id)
		var to_node: Variant = _find_node(to_id)
		var unlocked_edge := (
			from_node != null
			and to_node != null
			and bool(from_node.get("unlocked", false))
			and bool(to_node.get("unlocked", false))
		)
		_draw_edge(
			_layout[from_id],
			_layout[to_id],
			unlocked_edge,
			bool(edge.get("eligible", false)),
			bool(edge.get("just_revealed", false))
		)

	for node in _nodes:
		if not (node is Dictionary):
			continue
		var node_id := str(node.get("id", ""))
		if not _layout.has(node_id):
			continue
		_draw_node(node, _layout[node_id])

	_draw_camera_hint()


func _draw_camera_hint() -> void:
	var font := ThemeDB.fallback_font
	var hint := "Scroll zoom · RMB/MMB pan · Home reset"
	draw_string(
		font,
		Vector2(10.0, size.y - 10.0),
		hint,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		HUDAssetLibrary.COLOR_MUTED
	)


func _draw_edge(
	from_pos: Vector2,
	to_pos: Vector2,
	unlocked_edge: bool,
	eligible: bool = false,
	just_revealed: bool = false
) -> void:
	var color := (
		HUDAssetLibrary.COLOR_CAUTION if eligible or just_revealed else HUDAssetLibrary.COLOR_NORMAL
		if unlocked_edge
		else HUDAssetLibrary.COLOR_MUTED.darkened(0.25)
	)
	var width := (4.5 if eligible else 3.0 + sin(_pulse_t) if just_revealed else 2.5) * _zoom
	if unlocked_edge:
		draw_line(from_pos, to_pos, color, width)
	else:
		_draw_dashed_line(from_pos, to_pos, color, maxf(1.5, width))


func _draw_dashed_line(from_pos: Vector2, to_pos: Vector2, color: Color, width: float) -> void:
	var delta := to_pos - from_pos
	var length := delta.length()
	if length < 1.0:
		return
	var dir := delta / length
	var dash := 8.0 * _zoom
	var gap := 6.0 * _zoom
	var t := 0.0
	while t < length:
		var a := from_pos + dir * t
		var b := from_pos + dir * minf(t + dash, length)
		draw_line(a, b, color, width)
		t += dash + gap


func _draw_node(node: Dictionary, pos: Vector2) -> void:
	var node_id := str(node.get("id", ""))
	var is_active := bool(node.get("is_active", false))
	var is_next := bool(node.get("is_next", false))
	var unlocked := bool(node.get("unlocked", false))
	var completed := bool(node.get("traversed", false))
	var selected := node_id == _selected_id
	var hovered := node_id == _hovered_id
	var just_revealed := bool(node.get("just_revealed", false))

	var fill := HUDAssetLibrary.COLOR_PANEL_ALT
	var border := HUDAssetLibrary.COLOR_BORDER
	if completed:
		fill = Color("#1a2a1a")
		border = HUDAssetLibrary.COLOR_NORMAL
	elif is_active:
		fill = HUDAssetLibrary.COLOR_PANEL_WARM
		border = HUDAssetLibrary.COLOR_CAUTION
	elif unlocked:
		fill = Color("#1a1c16")
		border = HUDAssetLibrary.COLOR_TEXT
	elif bool(node.get("discovered", false)):
		fill = Color("#12140f")
		border = HUDAssetLibrary.COLOR_MUTED
	else:
		fill = Color("#0a0b09")
		border = HUDAssetLibrary.COLOR_BORDER_DARK

	var radius := NODE_RADIUS * _zoom
	if is_active or just_revealed:
		radius += (2.0 + sin(_pulse_t) * 2.0) * _zoom
	if just_revealed:
		border = HUDAssetLibrary.COLOR_CAUTION
	if selected or hovered:
		draw_circle(pos, radius + 5.0 * _zoom, Color(border.r, border.g, border.b, 0.28))
	draw_circle(pos, radius, fill)
	draw_arc(pos, radius, 0.0, TAU, 32, border, 2.0 if selected else 1.5)

	var font := ThemeDB.fallback_font
	var show_label := _zoom >= 0.66 or selected or hovered or is_active
	var role := int(node.get("role", GameEnums.MacroNodeRole.RANDOM_ZONE))
	if role in [
		GameEnums.MacroNodeRole.CENTRAL_CORE,
		GameEnums.MacroNodeRole.GATEWAY,
		GameEnums.MacroNodeRole.ARM_CORE,
	]:
		show_label = true
	if show_label:
		var label := _compact_node_label(node, _zoom < 0.66)
		var font_size := maxi(8, int(round(11.0 * _zoom)))
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(
			font,
			pos + Vector2(-text_size.x * 0.5, radius + 16.0 * _zoom),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			HUDAssetLibrary.COLOR_TEXT if unlocked else HUDAssetLibrary.COLOR_MUTED
		)

	if is_active:
		_draw_badge(pos + Vector2(0.0, -radius - 14.0 * _zoom), "YOU ARE HERE", HUDAssetLibrary.COLOR_CAUTION)
	elif is_next:
		_draw_badge(pos + Vector2(0.0, -radius - 14.0 * _zoom), "NEXT", HUDAssetLibrary.COLOR_NORMAL)


func _compact_node_label(node: Dictionary, compact: bool) -> String:
	if bool(node.get("detail_hidden", false)):
		return "?"
	var label := str(node.get("display_name", node.get("id", "")))
	if not compact:
		return label
	var arm_index := int(node.get("arm_direction", GameEnums.MacroArmDirection.NONE))
	var arm_letter := ""
	if arm_index > GameEnums.MacroArmDirection.NONE:
		arm_letter = str(GameEnums.MacroArmDirection.keys()[arm_index]).left(1)
	match int(node.get("role", GameEnums.MacroNodeRole.RANDOM_ZONE)):
		GameEnums.MacroNodeRole.CENTRAL_CORE:
			return "CORE"
		GameEnums.MacroNodeRole.GATEWAY:
			return arm_letter + " GATE"
		GameEnums.MacroNodeRole.ARM_CORE:
			return arm_letter + " CORE"
		_:
			return label


func _draw_badge(center: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(8, int(round(9.0 * _zoom)))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(6.0, 3.0) * _zoom
	var rect := Rect2(center - text_size * 0.5 - pad, text_size + pad * 2.0)
	draw_rect(rect, Color(0.05, 0.06, 0.05, 0.9))
	draw_rect(rect, color, false, 1.0)
	draw_string(
		font,
		rect.position + Vector2(pad.x, pad.y + text_size.y - 2.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)


func _recompute_world_layout() -> void:
	_world_layout.clear()
	if _nodes.is_empty() or size.x < 8.0 or size.y < 8.0:
		return

	var min_pos := Vector2i(9999, 9999)
	var max_pos := Vector2i(-9999, -9999)
	for node in _nodes:
		if not (node is Dictionary):
			continue
		var gp: Vector2i = node.get("graph_pos", Vector2i.ZERO)
		min_pos.x = mini(min_pos.x, gp.x)
		min_pos.y = mini(min_pos.y, gp.y)
		max_pos.x = maxi(max_pos.x, gp.x)
		max_pos.y = maxi(max_pos.y, gp.y)

	var span := Vector2(
		maxi(1, max_pos.x - min_pos.x),
		maxi(1, max_pos.y - min_pos.y)
	)
	# World space uses a fixed comfortable spacing independent of current zoom.
	var spacing := Vector2(140.0, 110.0)
	for node in _nodes:
		if not (node is Dictionary):
			continue
		var node_id := str(node.get("id", ""))
		var gp: Vector2i = node.get("graph_pos", Vector2i.ZERO)
		var nx := float(gp.x - min_pos.x)
		var ny := float(gp.y - min_pos.y)
		# North path grows in +y; draw upward (smaller y = north).
		_world_layout[node_id] = Vector2(nx * spacing.x, (span.y - ny) * spacing.y)


func _fit_camera_to_content() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	if _world_layout.is_empty():
		return
	var bounds := _world_bounds()
	if bounds.size.x <= 1.0 or bounds.size.y <= 1.0:
		_pan = size * 0.5 - bounds.get_center()
		return
	var margin := 80.0
	var zoom_x := (size.x - margin * 2.0) / bounds.size.x
	var zoom_y := (size.y - margin * 2.0) / bounds.size.y
	_zoom = clampf(minf(zoom_x, zoom_y), ZOOM_MIN, ZOOM_MAX)
	_pan = size * 0.5 - bounds.get_center() * _zoom


func _world_bounds() -> Rect2:
	var first := true
	var bounds := Rect2()
	for pos in _world_layout.values():
		var p: Vector2 = pos
		if first:
			bounds = Rect2(p, Vector2.ZERO)
			first = false
		else:
			bounds = bounds.expand(p)
	return bounds.grow(NODE_RADIUS + 24.0)


func _apply_camera() -> void:
	_layout.clear()
	for node_id in _world_layout.keys():
		_layout[node_id] = _world_to_view(_world_layout[node_id])


func _world_to_view(world_pos: Vector2) -> Vector2:
	return world_pos * _zoom + _pan


func _view_to_world(view_pos: Vector2) -> Vector2:
	if is_zero_approx(_zoom):
		return view_pos
	return (view_pos - _pan) / _zoom


func _zoom_at(view_pos: Vector2, new_zoom: float) -> void:
	var before := _view_to_world(view_pos)
	_zoom = clampf(new_zoom, ZOOM_MIN, ZOOM_MAX)
	_pan = view_pos - before * _zoom
	_apply_camera()
	queue_redraw()


func _rebuild_order() -> void:
	_ordered_ids.clear()
	var sortable: Array = []
	for node in _nodes:
		if node is Dictionary:
			sortable.append(node)
	sortable.sort_custom(func(a, b):
		var pa: Vector2i = a.get("graph_pos", Vector2i.ZERO)
		var pb: Vector2i = b.get("graph_pos", Vector2i.ZERO)
		if pa.y == pb.y:
			return pa.x < pb.x
		return pa.y < pb.y
	)
	for node in sortable:
		_ordered_ids.append(str(node.get("id", "")))


func _move_selection(delta: int) -> void:
	if _ordered_ids.is_empty():
		return
	var index := _ordered_ids.find(_selected_id)
	if index < 0:
		index = 0
	else:
		index = clampi(index + delta, 0, _ordered_ids.size() - 1)
	select_node(_ordered_ids[index])


func _hit_test(local_pos: Vector2) -> String:
	var best_id := ""
	var best_dist := NODE_RADIUS * _zoom + 10.0
	for node_id in _layout.keys():
		var dist := local_pos.distance_to(_layout[node_id])
		if dist <= best_dist:
			best_dist = dist
			best_id = str(node_id)
	return best_id


func _find_node(node_id: String) -> Variant:
	for node in _nodes:
		if node is Dictionary and str(node.get("id", "")) == node_id:
			return node
	return null


func _has_active_node() -> bool:
	for node in _nodes:
		if node is Dictionary and bool(node.get("is_active", false)):
			return true
	return false
