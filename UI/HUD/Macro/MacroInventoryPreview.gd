extends PanelContainer
class_name MacroInventoryPreview

signal open_requested

var _snapshot: Dictionary = {}

@onready var _gear_row: HBoxContainer = %GearRow
@onready var _capacity_label: Label = %CapacityLabel
@onready var _open_button: Button = %OpenInventoryButton


func _ready() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_capacity_label, "muted")
	HUDAssetLibrary.apply_button(_open_button, "inventory")
	_open_button.pressed.connect(open_requested.emit)


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	for child in _gear_row.get_children():
		child.queue_free()
	var equipment: Array = _snapshot.get("equipment", [])
	for item in equipment.slice(0, 6):
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(28, 28)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var sprite_path := str(item.get("sprite_path", ""))
		if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
			slot.texture = load(sprite_path) as Texture2D
		_gear_row.add_child(slot)
	_capacity_label.text = "CAP %d / %d" % [
		int(_snapshot.get("current_capacity", 0)),
		int(_snapshot.get("maximum_capacity", 0)),
	]
