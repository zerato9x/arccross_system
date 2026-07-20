extends PanelContainer
class_name MacroInventoryPreview

signal open_requested

var _snapshot: Dictionary = {}

const PREVIEW_SLOTS := [
	{"slot": GameEnums.EquipmentSlot.HEAD, "label": "HEAD"},
	{"slot": GameEnums.EquipmentSlot.BACKPACK, "label": "PACK"},
	{"slot": GameEnums.EquipmentSlot.OUTER_TORSO, "label": "ARMOR"},
	{"slot": GameEnums.EquipmentSlot.HAND, "label": "HAND"},
	{"slot": GameEnums.EquipmentSlot.OFFHAND, "label": "OFF"},
]

@onready var _gear_row: HBoxContainer = %GearRow
@onready var _capacity_label: Label = %CapacityLabel
@onready var _open_button: Button = %OpenInventoryButton


func _ready() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_capacity_label, "muted")
	HUDAssetLibrary.apply_button(_open_button, "inventory")
	_open_button.text = "Open Pack"
	_open_button.pressed.connect(open_requested.emit)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	for child in _gear_row.get_children():
		child.queue_free()
	var equipment_by_slot := _equipment_by_slot(_snapshot.get("equipment", []))
	for slot_config: Dictionary in PREVIEW_SLOTS:
		_gear_row.add_child(_make_equipment_tile(slot_config, equipment_by_slot))
	_capacity_label.text = "Capacity %d / %d" % [
		int(_snapshot.get("current_capacity", 0)),
		int(_snapshot.get("maximum_capacity", 0)),
	]


func _equipment_by_slot(equipment: Array) -> Dictionary:
	var mapped := {}
	for item: Dictionary in equipment:
		mapped[int(item.get("equipment_slot", GameEnums.EquipmentSlot.NONE))] = item
	return mapped


func _make_equipment_tile(slot_config: Dictionary, equipment_by_slot: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(54, 42)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var item: Dictionary = equipment_by_slot.get(int(slot_config["slot"]), {})
	var filled := not item.is_empty()
	frame.add_theme_stylebox_override("panel", HUDAssetLibrary.macro_slot_style(filled))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(column)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(26, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sprite_path := str(item.get("sprite_path", ""))
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		icon.texture = load(sprite_path) as Texture2D
	column.add_child(icon)
	var label := Label.new()
	label.text = str(slot_config["label"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	HUDAssetLibrary.apply_label(label, "muted")
	column.add_child(label)
	if filled:
		HudMotion.fade_in(self, frame, 0.16, 0.35)
	return frame
