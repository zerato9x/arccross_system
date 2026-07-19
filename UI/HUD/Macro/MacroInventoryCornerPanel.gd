extends MacroCornerPanel
class_name MacroInventoryCornerPanel

signal fullscreen_requested

@export var inventory_ui: InventoryUI

var _preview_panel: MacroInventoryPreview


func _ready() -> void:
	panel_id = "inventory"
	panel_corner = PanelCorner.BOTTOM_LEFT
	preview_size = Vector2(322.0, 138.0)
	expand_width_ratio = 0.36
	expand_height_ratio = 0.48
	expanded_min_size = Vector2(880.0, 620.0)
	expanded_max_size = Vector2(1120.0, 780.0)
	super._ready()
	_install_preview_ui()


func _install_preview_ui() -> void:
	var root := get_node_or_null("%PreviewRoot") as Control
	if root == null:
		push_error("MacroInventoryCornerPanel requires PreviewRoot.")
		return
	_preview_panel = root.get_node_or_null("MacroInventoryPreview") as MacroInventoryPreview
	if _preview_panel == null:
		push_error("MacroInventoryCornerPanel requires MacroInventoryPreview under PreviewRoot.")
		return
	_preview_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_panel.open_requested.connect(fullscreen_requested.emit)


func _render_preview() -> void:
	if _preview_panel:
		_preview_panel.apply_snapshot(_snapshot)


func _render_expanded() -> void:
	# Inventory is a fullscreen work surface. The corner owns only its preview;
	# embedding the three-region inventory here crushes and hides its authored UI.
	fullscreen_requested.emit()


func _set_state(state: PanelState) -> void:
	if state == PanelState.EXPANDED:
		fullscreen_requested.emit()
		return
	super._set_state(state)


func _is_primary_action_click(global_pos: Vector2) -> bool:
	if _preview_panel and _preview_panel.get_global_rect().has_point(global_pos):
		return true
	return false
