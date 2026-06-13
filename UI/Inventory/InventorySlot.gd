extends PanelContainer
class_name InventorySlot

signal slot_clicked(slot_node, event: InputEventMouseButton)
signal item_dropped(from_slot: InventorySlot, to_slot: InventorySlot)

@export var equipment_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
@export var empty_texture: Texture2D

var item_descriptor: Dictionary = {}

@onready var icon_rect: TextureRect = $MarginContainer/IconRect
@onready var empty_background: TextureRect = $EmptyBackground

var default_style: StyleBoxFlat
var hover_style: StyleBoxFlat

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	default_style = StyleBoxFlat.new()
	default_style.bg_color = Color(0, 0, 0, 0)
	
	hover_style = default_style.duplicate()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.1)
	hover_style.border_color = Color(0.4, 0.6, 0.9, 0.5)
	hover_style.border_width_bottom = 2
	hover_style.border_width_top = 2
	hover_style.border_width_left = 2
	hover_style.border_width_right = 2

	add_theme_stylebox_override("panel", default_style)

	if empty_texture:
		empty_background.texture = empty_texture

	_update_visuals()

func set_item(new_descriptor: Dictionary) -> void:
	item_descriptor = new_descriptor
	_update_visuals()

func _update_visuals() -> void:
	if not item_descriptor.is_empty():
		var sprite_path = item_descriptor.get("sprite_path", "")
		if sprite_path != "" and ResourceLoader.exists(sprite_path):
			icon_rect.texture = load(sprite_path)
			icon_rect.modulate = Color(1, 1, 1, 1.0)
		else:
			icon_rect.texture = null
		icon_rect.show()
		empty_background.hide()
	else:
		icon_rect.texture = null
		icon_rect.hide()
		empty_background.show()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		slot_clicked.emit(self, event)

func _on_mouse_entered() -> void:
	add_theme_stylebox_override("panel", hover_style)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_SINE)
	
	var ui = _get_inventory_ui()
	if ui and not item_descriptor.is_empty():
		ui.show_item_details(item_descriptor)

func _on_mouse_exited() -> void:
	add_theme_stylebox_override("panel", default_style)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE)

func _get_inventory_ui() -> Node:
	var current = self
	while current:
		if current.has_method("show_item_details"):
			return current
		current = current.get_parent()
	return null

# --- Drag and Drop ---
func _get_drag_data(at_position: Vector2) -> Variant:
	if item_descriptor.is_empty():
		return null
		
	var preview = TextureRect.new()
	preview.texture = icon_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(64, 64)
	preview.modulate = Color(1, 1, 1, 0.8)
	
	var preview_ctl = Control.new()
	preview_ctl.add_child(preview)
	preview.position = -preview.custom_minimum_size / 2.0
	
	set_drag_preview(preview_ctl)
	return self

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return data is InventorySlot and data != self

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var from_slot = data as InventorySlot
	item_dropped.emit(from_slot, self)
