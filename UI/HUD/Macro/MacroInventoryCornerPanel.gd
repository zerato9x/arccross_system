extends MacroCornerPanel
class_name MacroInventoryCornerPanel

signal inventory_open_requested

@export var inventory_ui: InventoryUI

var _gear_row: HBoxContainer
var _capacity_label: Label
var _open_button: Button


func _ready() -> void:
	panel_id = "inventory"
	panel_corner = PanelCorner.BOTTOM_LEFT
	preview_size = Vector2(320.0, 128.0)
	super._ready()
	_build_preview_ui()


func _build_preview_ui() -> void:
	var root := %PreviewRoot
	if root == null:
		return
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)

	_gear_row = HBoxContainer.new()
	_gear_row.add_theme_constant_override("separation", 4)
	column.add_child(_gear_row)

	_capacity_label = Label.new()
	HUDAssetLibrary.apply_label(_capacity_label, "muted")
	column.add_child(_capacity_label)

	_open_button = Button.new()
	_open_button.text = "OPEN INVENTORY"
	HUDAssetLibrary.apply_button(_open_button, "inventory")
	_open_button.pressed.connect(expand)
	column.add_child(_open_button)


func _render_preview() -> void:
	var equipment: Array = _snapshot.get("equipment", [])
	if _gear_row:
		for child in _gear_row.get_children():
			child.queue_free()
		for item in equipment.slice(0, 6):
			var slot := TextureRect.new()
			slot.custom_minimum_size = Vector2(28, 28)
			slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var sprite_path := str(item.get("sprite_path", ""))
			if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
				slot.texture = load(sprite_path) as Texture2D
			_gear_row.add_child(slot)
	if _capacity_label:
		_capacity_label.text = "CAP %d / %d" % [
			int(_snapshot.get("current_capacity", 0)),
			int(_snapshot.get("maximum_capacity", 0)),
		]


func _render_expanded() -> void:
	if inventory_ui == null:
		return
	var host := %ExpandedRoot
	if host:
		inventory_ui.open_embedded_panel(host, _snapshot)


func _set_state(state: PanelState) -> void:
	super._set_state(state)
	if state == PanelState.PREVIEW and inventory_ui and inventory_ui.is_embedded():
		inventory_ui.close_panel(false)
	elif state == PanelState.EXPANDED:
		_render_expanded()


func _is_primary_action_click(global_pos: Vector2) -> bool:
	if _open_button and _open_button.get_global_rect().has_point(global_pos):
		return true
	return false
