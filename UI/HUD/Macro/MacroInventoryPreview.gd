extends PanelContainer
class_name MacroInventoryPreview

signal open_requested

var _snapshot: Dictionary = {}

@onready var _gear_list: VBoxContainer = %GearList
@onready var _gear_header: Label = %GearHeader
@onready var _capacity_label: Label = %CapacityLabel
@onready var _open_button: Button = %OpenInventoryButton
@onready var _paper_doll: PaperDollModel = %PaperDollModel


func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 268.0)
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_gear_header, "info")
	HUDAssetLibrary.apply_label(_capacity_label, "muted")
	HUDAssetLibrary.apply_button(_open_button, "inventory")
	_open_button.text = "PACK [I]"
	_open_button.pressed.connect(open_requested.emit)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _paper_doll:
		_paper_doll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_paper_doll.set_backdrop_visible(false)
	HUDAssetLibrary.apply_soft_edge(self, 0.18)


func restyle() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_gear_header, "info")
	HUDAssetLibrary.apply_label(_capacity_label, "muted")
	HUDAssetLibrary.apply_button(_open_button, "inventory")
	_open_button.text = "PACK [I]"
	HUDAssetLibrary.apply_soft_edge(self, 0.18)
	if not _snapshot.is_empty():
		apply_snapshot(_snapshot)


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var equipment: Array = PaperDollPresenter.equipment_from_inventory_snapshot(_snapshot)
	var backpack: Array = _snapshot.get("backpack", [])
	var limbs: Array = PaperDollPresenter.limbs_from_inventory_snapshot(_snapshot)
	PaperDollPresenter.apply_to_doll(_paper_doll, equipment, limbs)
	_render_key_gear(PaperDollPresenter.key_gear_tiles(equipment, backpack))
	_capacity_label.text = "Capacity %d / %d" % [
		int(_snapshot.get("current_capacity", 0)),
		int(_snapshot.get("maximum_capacity", 0)),
	]


func _render_key_gear(tiles: Array) -> void:
	if _gear_list == null:
		return
	for child in _gear_list.get_children():
		child.queue_free()
	if tiles.is_empty():
		var empty := Label.new()
		empty.text = "NO KEY GEAR"
		HUDAssetLibrary.apply_label(empty, "muted")
		_gear_list.add_child(empty)
		return
	for raw_tile in tiles:
		if not raw_tile is Dictionary:
			continue
		_gear_list.add_child(_make_gear_tile(raw_tile))


func _make_gear_tile(tile: Dictionary) -> Control:
	var item: Dictionary = tile.get("item", {})
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, 34)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_theme_stylebox_override(
		"panel",
		HUDAssetLibrary.macro_slot_style(not item.is_empty())
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	frame.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(26, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sprite_path := str(item.get("sprite_path", ""))
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		icon.texture = load(sprite_path) as Texture2D
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 0)
	row.add_child(text_col)

	var name_label := Label.new()
	var item_name := str(item.get("name", "")).to_upper()
	if item_name.is_empty():
		item_name = "EMPTY"
	name_label.text = "%s // %s" % [str(tile.get("label", "?")), item_name]
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	HUDAssetLibrary.apply_label(name_label, "body")
	name_label.add_theme_font_size_override("font_size", 10)
	text_col.add_child(name_label)

	var condition := Label.new()
	condition.text = PaperDollPresenter.condition_label(item)
	HUDAssetLibrary.apply_label(
		condition,
		PaperDollPresenter.condition_role(item)
	)
	condition.add_theme_font_size_override("font_size", 9)
	text_col.add_child(condition)
	HudMotion.fade_in(self, frame, 0.16, 0.35)
	return frame
