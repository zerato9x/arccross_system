extends PanelContainer
class_name NodeMapPlayerPanel

## Player vitals / equipment strip for the Node Map System window only.

signal inventory_requested
signal medical_requested

const PREVIEW_SLOTS := [
	{"slot": GameEnums.EquipmentSlot.HEAD, "label": "HEAD"},
	{"slot": GameEnums.EquipmentSlot.BACKPACK, "label": "PACK"},
	{"slot": GameEnums.EquipmentSlot.OUTER_TORSO, "label": "ARMOR"},
	{"slot": GameEnums.EquipmentSlot.HAND, "label": "HAND"},
	{"slot": GameEnums.EquipmentSlot.OFFHAND, "label": "OFF"},
]

var _snapshot: Dictionary = {}

@onready var _blood_bar: ProgressBar = %BloodBar
@onready var _hunger_bar: ProgressBar = %HungerBar
@onready var _thirst_bar: ProgressBar = %ThirstBar
@onready var _fatigue_bar: ProgressBar = %FatigueBar
@onready var _condition_label: Label = %ConditionLabel
@onready var _morale_label: Label = %MoraleLabel
@onready var _emergency_label: Label = %EmergencyLabel
@onready var _capacity_label: Label = %CapacityLabel
@onready var _gear_row: HBoxContainer = %GearRow
@onready var _inventory_button: Button = %InventoryButton
@onready var _medical_button: Button = %MedicalButton


func _ready() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_progress_bar(_blood_bar, "blood")
	HUDAssetLibrary.apply_progress_bar(_hunger_bar, "warning")
	HUDAssetLibrary.apply_progress_bar(_thirst_bar, "condition")
	HUDAssetLibrary.apply_progress_bar(_fatigue_bar, "anomaly")
	HUDAssetLibrary.apply_label(_condition_label, "muted")
	HUDAssetLibrary.apply_label(_morale_label, "muted")
	HUDAssetLibrary.apply_label(_emergency_label, "warning")
	HUDAssetLibrary.apply_label(_capacity_label, "muted")
	HUDAssetLibrary.apply_button(_inventory_button, "inventory")
	HUDAssetLibrary.apply_button(_medical_button, "blood")
	_inventory_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size(110.0)
	_medical_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size(110.0)
	_inventory_button.pressed.connect(func(): inventory_requested.emit())
	_medical_button.pressed.connect(func(): medical_requested.emit())


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_set_bar(_blood_bar, float(_snapshot.get("blood", 0.0)), 10.0)
	_set_bar(_hunger_bar, float(_snapshot.get("hunger", 0.0)), 100.0)
	_set_bar(_thirst_bar, float(_snapshot.get("thirst", 0.0)), 100.0)
	_set_bar(_fatigue_bar, float(_snapshot.get("fatigue", 0.0)), 100.0)
	_condition_label.text = "Wounds  %d  •  Infection %.0f%%" % [
		int(_snapshot.get("wound_count", 0)),
		float(_snapshot.get("infection_risk", 0.0)) * 100.0,
	]
	_morale_label.text = "Morale  %d" % int(_snapshot.get("morale", 0))
	var emergencies: Array = _snapshot.get("emergencies", [])
	if emergencies.is_empty():
		_emergency_label.text = "No active emergencies"
		HUDAssetLibrary.apply_label(_emergency_label, "muted")
	else:
		_emergency_label.text = "Emergency  %s" % str(emergencies[0])
		HUDAssetLibrary.apply_label(_emergency_label, "critical")
	_capacity_label.text = "Capacity  %d / %d" % [
		int(_snapshot.get("current_capacity", 0)),
		int(_snapshot.get("maximum_capacity", 0)),
	]
	_render_equipment()


func _set_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value = clampf(value, 0.0, max_value)


func _render_equipment() -> void:
	for child in _gear_row.get_children():
		child.queue_free()
	var by_slot := {}
	for item in _snapshot.get("equipment", []):
		if item is Dictionary:
			by_slot[int(item.get("equipment_slot", GameEnums.EquipmentSlot.NONE))] = item
	for slot_config in PREVIEW_SLOTS:
		_gear_row.add_child(_make_equipment_tile(slot_config, by_slot))


func _make_equipment_tile(slot_config: Dictionary, by_slot: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(54, 42)
	HUDAssetLibrary.apply_panel(frame, "neutral")
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(column)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(26, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var item: Dictionary = by_slot.get(int(slot_config["slot"]), {})
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
	return frame
