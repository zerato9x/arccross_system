extends MacroCornerPanel
class_name MacroHexCornerPanel

signal expand_requested_hex(coords: Vector2i)
signal travel_requested_hex(coords: Vector2i)

var _hex: Dictionary = {}
var _preview_panel: MacroHexPreviewPanel


func _ready() -> void:
	panel_id = "hex"
	panel_corner = PanelCorner.TOP_RIGHT
	preview_size = Vector2(362.0, 360.0)
	expand_width_ratio = 0.42
	expand_height_ratio = 0.50
	expanded_min_size = Vector2(1080.0, 640.0)
	expanded_max_size = Vector2(1220.0, 780.0)
	super._ready()
	_install_preview_ui()


func _install_preview_ui() -> void:
	var root := get_node_or_null("%PreviewRoot") as Control
	if root == null:
		push_error("MacroHexCornerPanel requires PreviewRoot.")
		return
	_preview_panel = root.get_node_or_null("MacroHexPreviewPanel") as MacroHexPreviewPanel
	if _preview_panel == null:
		push_error("MacroHexCornerPanel requires MacroHexPreviewPanel under PreviewRoot.")
		return
	_preview_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_panel.expand_requested.connect(expand_requested_hex.emit)
	_preview_panel.travel_requested.connect(travel_requested_hex.emit)


func apply_snapshot(snapshot: Dictionary) -> void:
	super.apply_snapshot(snapshot)
	var selected_hex: Dictionary = snapshot.get("selected_hex", {})
	visible = not selected_hex.is_empty()


func _render_preview() -> void:
	_hex = _snapshot.get("selected_hex", {}).duplicate(true)
	if _hex.is_empty():
		visible = false
		return
	visible = true
	var scene_descriptor: Dictionary = _snapshot.get("selected_scene_descriptor", {})
	if _preview_panel:
		_preview_panel.show_hex(_hex, scene_descriptor)


func _render_expanded() -> void:
	pass


func dock_session(_session: Dictionary) -> void:
	# POI sessions are hosted by MacroExplorationStage; hex panel stays preview-only.
	pass


func restyle_scheme() -> void:
	super.restyle_scheme()
	if _preview_panel and _preview_panel.has_method("restyle"):
		_preview_panel.restyle()
	if not _hex.is_empty() and _preview_panel:
		_preview_panel.show_hex(_hex, _snapshot.get("selected_scene_descriptor", {}))


func _is_primary_action_click(global_pos: Vector2) -> bool:
	if _preview_panel and _preview_panel.get_global_rect().has_point(global_pos):
		return true
	return false
