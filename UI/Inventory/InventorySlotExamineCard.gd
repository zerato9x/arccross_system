extends PanelContainer
class_name InventorySlotExamineCard

const CARD_MIN_WIDTH := 320.0
const CARD_GAP := 14.0
const VIEWPORT_PADDING := 8.0

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _meta_label: Label = %MetaLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _stats_label: Label = %StatsLabel


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = CARD_MIN_WIDTH
	HUDAssetLibrary.apply_panel(self, "warning")


func show_descriptor(descriptor: Dictionary) -> void:
	if descriptor.is_empty():
		hide_card()
		return

	var sprite_path := str(descriptor.get("sprite_path", ""))
	_icon.texture = (
		load(sprite_path) as Texture2D
		if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path)
		else null
	)
	_name_label.text = str(descriptor.get("name", "Unknown Item")).to_upper()
	_meta_label.text = "%s  |  %s" % [
		_enum_name(GameEnums.ItemCategory, int(descriptor.get(
			"catalog_category",
			GameEnums.ItemCategory.MISC
		))),
		_equipment_slot_name(int(descriptor.get(
			"preferred_equipment_slot",
			GameEnums.EquipmentSlot.NONE
		))),
	]
	_description_label.text = str(descriptor.get(
		"description",
		"No field notes available."
	))
	_stats_label.text = _format_stats(descriptor)
	visible = true
	reset_size()
	size = get_combined_minimum_size()


func hide_card() -> void:
	visible = false


func position_beside_menu(menu_rect: Rect2) -> void:
	if not visible:
		return
	reset_size()
	size = get_combined_minimum_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var target := menu_rect.position + Vector2(menu_rect.size.x + CARD_GAP, 0.0)
	if target.x + size.x > viewport_size.x - VIEWPORT_PADDING:
		target.x = menu_rect.position.x - size.x - CARD_GAP
	if target.y + size.y > viewport_size.y - VIEWPORT_PADDING:
		target.y = viewport_size.y - size.y - VIEWPORT_PADDING
	global_position = Vector2(
		clampf(target.x, VIEWPORT_PADDING, maxf(VIEWPORT_PADDING, viewport_size.x - size.x - VIEWPORT_PADDING)),
		clampf(target.y, VIEWPORT_PADDING, maxf(VIEWPORT_PADDING, viewport_size.y - size.y - VIEWPORT_PADDING))
	)


func _enum_name(enum_dictionary: Dictionary, value: int) -> String:
	for key in enum_dictionary:
		if int(enum_dictionary[key]) == value:
			return str(key).replace("_", " ").capitalize()
	return "Unknown"


func _equipment_slot_name(slot: int) -> String:
	if slot == GameEnums.EquipmentSlot.NONE:
		return "CARRIED"
	return _enum_name(GameEnums.EquipmentSlot, slot)


func _format_stats(descriptor: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("WEIGHT %.1f  //  BULK %.1f  //  THREAT %.1f" % [
		float(descriptor.get("weight", 0.0)),
		float(descriptor.get("bulk", 0.0)),
		float(descriptor.get("threat", 0.0)),
	])
	lines.append("PROTECTION  BLUNT %.1f  /  SHARP %.1f  /  BALLISTIC %.1f" % [
		float(descriptor.get("protection_blunt", 0.0)),
		float(descriptor.get("protection_sharp", 0.0)),
		float(descriptor.get("protection_ballistic", 0.0)),
	])
	var utility := PackedStringArray()
	var capacity := int(descriptor.get("capacity_bonus", 0))
	var insulation := float(descriptor.get("insulation", 0.0))
	if capacity != 0:
		utility.append("CAPACITY +%d" % capacity)
	if insulation != 0.0:
		utility.append("INSULATION %.1f" % insulation)
	if not utility.is_empty():
		lines.append("  //  ".join(utility))
	if int(descriptor.get("item_type", GameEnums.ItemType.JUNK)) == GameEnums.ItemType.WEAPON:
		lines.append("DAMAGE  FLESH %.1f  /  STANCE %.1f  //  PEN %.1f" % [
			float(descriptor.get("flesh_damage", 0.0)),
			float(descriptor.get("stance_damage", 0.0)),
			float(descriptor.get("armor_penetration", 0.0)),
		])
	return "\n".join(lines)
