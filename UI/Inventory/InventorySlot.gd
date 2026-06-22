extends PanelContainer
class_name InventorySlot

signal slot_clicked(slot_node: InventorySlot, event: InputEventMouseButton)
signal item_dropped(from_slot: InventorySlot, to_slot: InventorySlot)
signal item_hovered(slot_node: InventorySlot)
signal item_unhovered(slot_node: InventorySlot)

const SOURCE_EQUIPMENT := "equipment"
const SOURCE_BACKPACK := "backpack"
const SOURCE_GROUND := "ground"

@export var equipment_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
@export var empty_texture: Texture2D

var item_descriptor: Dictionary = {}
var source_kind: String = SOURCE_BACKPACK
var slot_index: int = -1
var container_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
var is_reservation: bool = false
var is_selected: bool = false
var _configured_label: String = ""

@onready var empty_background: TextureRect = %EmptyBackground
@onready var icon_rect: TextureRect = %IconRect
@onready var slot_label: Label = %SlotLabel
@onready var size_badge: Label = %SizeBadge
@onready var reservation_label: Label = %ReservationLabel

var _default_style: StyleBoxFlat
var _hover_style: StyleBoxFlat
var _selected_style: StyleBoxFlat

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_build_styles()
	if empty_texture:
		empty_background.texture = empty_texture
	slot_label.text = _configured_label
	_update_visuals()

func configure(
	new_source_kind: String,
	new_slot_index: int,
	new_label: String = "",
	new_empty_texture: Texture2D = null,
	new_container_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
) -> void:
	source_kind = new_source_kind
	slot_index = new_slot_index
	container_slot = new_container_slot
	_configured_label = new_label
	if new_empty_texture:
		empty_texture = new_empty_texture
	if not is_node_ready():
		return
	slot_label.text = _configured_label
	if new_empty_texture:
		empty_background.texture = new_empty_texture
	_update_visuals()

func set_item(new_descriptor: Dictionary) -> void:
	item_descriptor = new_descriptor.duplicate(true)
	is_reservation = false
	_update_visuals()

func set_reserved(owner_descriptor: Dictionary) -> void:
	item_descriptor = owner_descriptor.duplicate(true)
	is_reservation = true
	_update_visuals()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_apply_style()

func has_item() -> bool:
	return not item_descriptor.is_empty() and not is_reservation

func _build_styles() -> void:
	_default_style = _slot_style(
		Color("#132128"),
		Color("#4b6670"),
		2
	)
	_hover_style = _slot_style(
		Color("#2d4650"),
		Color("#efe1bd"),
		2
	)
	_selected_style = _slot_style(
		Color("#4a3a2c"),
		Color("#f0d899"),
		2
	)
	_apply_style()

func _slot_style(
	background: Color,
	border: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4.0)
	return style

func _apply_style(hovered: bool = false) -> void:
	if is_selected:
		add_theme_stylebox_override("panel", _selected_style)
	elif hovered:
		add_theme_stylebox_override("panel", _hover_style)
	else:
		add_theme_stylebox_override("panel", _default_style)

func _update_visuals() -> void:
	if not is_node_ready():
		return

	empty_background.texture = empty_texture
	empty_background.visible = item_descriptor.is_empty() and not is_reservation
	empty_background.modulate = Color(1, 1, 1, 0.33)
	icon_rect.texture = null
	icon_rect.visible = false
	size_badge.visible = false
	reservation_label.visible = false

	if is_reservation:
		empty_background.visible = true
		empty_background.modulate = Color(0.35, 0.42, 0.45, 0.28)
		reservation_label.visible = true
		reservation_label.text = "+"
	elif not item_descriptor.is_empty():
		var sprite_path := str(item_descriptor.get("sprite_path", ""))
		if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
			icon_rect.texture = load(sprite_path)
			icon_rect.visible = true

		var stack_count := int(item_descriptor.get("stack_count", 1))
		var item_size := maxi(1, int(item_descriptor.get("size_cost", 1)))
		if stack_count > 1:
			size_badge.text = "x%d" % stack_count
			size_badge.visible = true
		elif item_size > 1:
			size_badge.text = "%du" % item_size
			size_badge.visible = true

	slot_label.visible = (
		not slot_label.text.is_empty()
		and (
			item_descriptor.is_empty()
			or source_kind == SOURCE_EQUIPMENT
		)
	)
	_apply_style()

func _on_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and not is_reservation
	):
		slot_clicked.emit(self, event)
		accept_event()

func _on_mouse_entered() -> void:
	_apply_style(true)
	if has_item():
		item_hovered.emit(self)

func _on_mouse_exited() -> void:
	_apply_style(false)
	if has_item():
		item_unhovered.emit(self)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not has_item():
		return null

	var preview := TextureRect.new()
	preview.texture = icon_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(56, 56)
	preview.modulate = Color(1, 1, 1, 0.88)
	var preview_control := Control.new()
	preview_control.add_child(preview)
	preview.position = -preview.custom_minimum_size * 0.5
	set_drag_preview(preview_control)
	return self

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is InventorySlot or data == self:
		return false
	var from_slot := data as InventorySlot
	if from_slot.is_reservation:
		return false

	match source_kind:
		SOURCE_EQUIPMENT:
			return (
				from_slot.source_kind == SOURCE_BACKPACK
				and equipment_slot in from_slot.item_descriptor.get(
					"allowed_equipment_slots",
					[]
				)
			)
		SOURCE_BACKPACK:
			return from_slot.source_kind in [
				SOURCE_EQUIPMENT,
				SOURCE_GROUND,
				SOURCE_BACKPACK,
			]
		SOURCE_GROUND:
			return from_slot.source_kind in [SOURCE_BACKPACK, SOURCE_EQUIPMENT]
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(data as InventorySlot, self)
