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
var _text_only_mode: bool = false

@onready var empty_background: TextureRect = %EmptyBackground
@onready var icon_rect: TextureRect = %IconRect
@onready var slot_label: Label = %SlotLabel
@onready var size_badge: Label = %SizeBadge
@onready var reservation_label: Label = %ReservationLabel
@onready var condition_rail: ProgressBar = %ConditionRail
@onready var state_badge: Label = %StateBadge

var _default_style: StyleBox
var _hover_style: StyleBox
var _selected_style: StyleBox

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_build_styles()
	HUDAssetLibrary.apply_progress_bar(condition_rail, "stance")
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

func set_text_only_mode(enabled: bool) -> void:
	_text_only_mode = enabled
	if is_node_ready():
		_update_visuals()

func has_item() -> bool:
	return not item_descriptor.is_empty() and not is_reservation

func _build_styles() -> void:
	_default_style = HUDAssetLibrary.pocket_slot_style(false)
	_hover_style = HUDAssetLibrary.pocket_slot_style(true)
	_selected_style = HUDAssetLibrary.pocket_slot_style(true)
	if _default_style == null:
		_default_style = _slot_style(
			Color(0.06, 0.09, 0.10, 0.94),
			Color("#3a4852"),
			1
		)
	if _hover_style == null:
		_hover_style = _slot_style(
			Color(0.10, 0.13, 0.14, 0.96),
			Color("#b99e7a"),
			2
		)
	if _selected_style == null:
		_selected_style = _slot_style(
			Color(0.16, 0.13, 0.08, 0.96),
			Color("#d6a652"),
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
	style.set_corner_radius_all(3)
	style.content_margin_left = 3.0
	style.content_margin_top = 3.0
	style.content_margin_right = 3.0
	style.content_margin_bottom = 3.0
	return style

func _apply_style(hovered: bool = false) -> void:
	if _text_only_mode:
		var transparent := StyleBoxEmpty.new()
		add_theme_stylebox_override("panel", transparent)
		return
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
	empty_background.visible = (
		not _text_only_mode
		and item_descriptor.is_empty()
		and not is_reservation
	)
	empty_background.modulate = Color(1, 1, 1, 0.33)
	icon_rect.texture = null
	icon_rect.visible = false
	size_badge.visible = false
	reservation_label.visible = false
	condition_rail.visible = false
	state_badge.visible = false

	if is_reservation:
		empty_background.visible = not _text_only_mode
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

		if bool(item_descriptor.get("condition_enabled", false)):
			var condition := clampf(
				float(item_descriptor.get("current_condition", 12.0)),
				0.0,
				12.0
			)
			condition_rail.value = condition
			condition_rail.visible = true
			var band := str(item_descriptor.get(
				"condition_band",
				ItemConditionRules.condition_band(condition)
			))
			if bool(item_descriptor.get("is_jammed", false)):
				state_badge.text = "JAM"
				state_badge.visible = true
			elif condition <= 0.0:
				state_badge.text = "BROKEN"
				state_badge.visible = true
			elif band in [ItemConditionRules.CONDITION_DAMAGED, ItemConditionRules.CONDITION_CRITICAL]:
				state_badge.text = band.to_upper()
				state_badge.visible = true

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
