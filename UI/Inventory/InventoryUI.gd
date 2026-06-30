extends Control
class_name InventoryUI

signal inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int
)
signal inventory_closed

const ACTION_TAKE := GameEnums.MACRO_INV_TAKE
const ACTION_DROP := GameEnums.MACRO_INV_DROP
const ACTION_EQUIP := GameEnums.MACRO_INV_EQUIP
const ACTION_UNEQUIP := GameEnums.MACRO_INV_UNEQUIP
const ACTION_CONSUME := GameEnums.MACRO_INV_CONSUME
const ACTION_MOVE := GameEnums.MACRO_INV_MOVE
const ACTION_LOAD_MAGAZINE := GameEnums.MACRO_INV_LOAD_MAGAZINE
const ACTION_INTERACT := GameEnums.MACRO_INV_INTERACT

enum PresentationMode {
	FULLSCREEN,
	SIDE_PANEL,
}

const SLOT_SCENE := preload("res://UI/Inventory/InventorySlot.tscn")
const PAPERDOLL_SCENE := preload("res://UI/Inventory/PaperDollModel.tscn")

const COLOR_BACKDROP := Color("#080907")
const COLOR_PANEL := Color("#11140f")
const COLOR_PANEL_ALT := Color("#1a1b16")
const COLOR_BORDER := Color("#6f6752")
const COLOR_TEXT := Color("#e8dcc0")
const COLOR_MUTED := Color("#8e8b78")
const COLOR_ACCENT := Color("#b9a789")
const COLOR_GOLD := Color("#d69a43")
const COLOR_DANGER := Color("#b9493e")

const EQUIPMENT_LAYOUT := {
	GameEnums.EquipmentSlot.HEAD: {
		"position": Vector2(0.10, 0.08),
		"label": "HEAD",
		"texture": "",
	},
	GameEnums.EquipmentSlot.EYES: {
		"position": Vector2(0.10, 0.25),
		"label": "EYES",
		"texture": "",
	},
	GameEnums.EquipmentSlot.FACE: {
		"position": Vector2(0.10, 0.42),
		"label": "FACE",
		"texture": "",
	},
	GameEnums.EquipmentSlot.NECK: {
		"position": Vector2(0.10, 0.59),
		"label": "NECK",
		"texture": "",
	},
	GameEnums.EquipmentSlot.HAND: {
		"position": Vector2(0.10, 0.77),
		"label": "HAND",
		"texture": "",
	},
	GameEnums.EquipmentSlot.OFFHAND: {
		"position": Vector2(0.90, 0.77),
		"label": "OFFHAND",
		"texture": "",
	},
	GameEnums.EquipmentSlot.BACKPACK: {
		"position": Vector2(0.90, 0.08),
		"label": "PACK",
		"texture": "",
	},
	GameEnums.EquipmentSlot.SLING: {
		"position": Vector2(0.90, 0.25),
		"label": "SLING",
		"texture": "",
	},
	GameEnums.EquipmentSlot.OUTER_TORSO: {
		"position": Vector2(0.90, 0.42),
		"label": "ARMOR",
		"texture": "",
	},
	GameEnums.EquipmentSlot.VEST: {
		"position": Vector2(0.90, 0.59),
		"label": "RIG",
		"texture": "",
	},
	GameEnums.EquipmentSlot.BELT: {
		"position": Vector2(0.90, 0.91),
		"label": "BELT",
		"texture": "",
	},
	GameEnums.EquipmentSlot.ARMS: {
		"position": Vector2(0.24, 0.90),
		"label": "ARMS",
		"texture": "",
	},
	GameEnums.EquipmentSlot.INNER_TORSO: {
		"position": Vector2(0.42, 0.90),
		"label": "INNER",
		"texture": "",
	},
	GameEnums.EquipmentSlot.LEGS: {
		"position": Vector2(0.60, 0.90),
		"label": "LEGS",
		"texture": "",
	},
	GameEnums.EquipmentSlot.FEET: {
		"position": Vector2(0.78, 0.90),
		"label": "FEET",
		"texture": "",
	},
}

var equipment_slots_ui: Dictionary = {}
var backpack_slots_ui: Array[InventorySlot] = []
var ground_slots_ui: Array[InventorySlot] = []

var dynamic_capacity_grids: VBoxContainer
var ground_list: GridContainer
var paperdoll_model: PaperDollModel

var _snapshot: Dictionary = {}
var _feedback: String = ""
var _selected_slot: InventorySlot
var _presentation_mode := PresentationMode.FULLSCREEN

var _backdrop: ColorRect
var _shell: PanelContainer
var _ground_panel: PanelContainer

var _location_label: Label
var _capacity_label: Label
var _capacity_bar: ProgressBar
var _capacity_sources_label: Label
var _backpack_count_label: Label
var _ground_count_label: Label
var _feedback_label: Label
var _spill_warning: Label
var _primary_button: Button
var _secondary_button: Button

var _hover_card: PanelContainer
var _hover_icon: TextureRect
var _hover_name: Label
var _hover_meta: Label
var _hover_description: Label
var _hover_stats: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_build_interface()
	close_panel(false)

func _process(_delta: float) -> void:
	if not visible or not _hover_card.visible:
		return
	var viewport_size := get_viewport_rect().size
	var card_size := _hover_card.size
	var target := get_viewport().get_mouse_position() + Vector2(18, 18)
	if target.x + card_size.x > viewport_size.x - 8.0:
		target.x -= card_size.x + 36.0
	if target.y + card_size.y > viewport_size.y - 8.0:
		target.y = viewport_size.y - card_size.y - 8.0
	_hover_card.position = Vector2(
		clampf(target.x, 8.0, maxf(8.0, viewport_size.x - card_size.x - 8.0)),
		clampf(target.y, 8.0, maxf(8.0, viewport_size.y - card_size.y - 8.0))
	)

func _unhandled_input(event: InputEvent) -> void:
	if (
		visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		close_panel()
		get_viewport().set_input_as_handled()

func open_inventory(snapshot: Dictionary, feedback: String = "") -> void:
	_presentation_mode = PresentationMode.FULLSCREEN
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	visible = true
	_apply_presentation_layout()
	_render()

func open_side_panel(snapshot: Dictionary, feedback: String = "") -> void:
	_presentation_mode = PresentationMode.SIDE_PANEL
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	visible = true
	_apply_presentation_layout()
	_render()

func is_side_panel() -> bool:
	return visible and _presentation_mode == PresentationMode.SIDE_PANEL

func close_panel(notify: bool = true) -> void:
	visible = false
	_presentation_mode = PresentationMode.FULLSCREEN
	_hover_card.visible = false
	_snapshot.clear()
	_feedback = ""
	_selected_slot = null
	_apply_presentation_layout()
	if notify:
		inventory_closed.emit()

func is_open() -> bool:
	return visible

func show_item_details(descriptor: Dictionary) -> void:
	if descriptor.is_empty():
		_hover_card.visible = false
		return

	var sprite_path := str(descriptor.get("sprite_path", ""))
	_hover_icon.texture = (
		load(sprite_path) as Texture2D
		if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path)
		else null
	)
	_hover_name.text = str(descriptor.get("name", "Unknown Item")).to_upper()
	_hover_meta.text = "%s  |  %s" % [
		_enum_name(GameEnums.ItemCategory, int(descriptor.get(
			"catalog_category",
			GameEnums.ItemCategory.MISC
		))),
		_equipment_slot_name(int(descriptor.get(
			"preferred_equipment_slot",
			GameEnums.EquipmentSlot.NONE
		))),
	]
	_hover_description.text = str(descriptor.get(
		"description",
		"No field notes available."
	))
	_hover_stats.text = _format_item_stats(descriptor)
	_hover_card.visible = true
	_hover_card.reset_size()
	_hover_card.size = _hover_card.get_combined_minimum_size()

func hide_item_details() -> void:
	_hover_card.visible = false

func _build_interface() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(COLOR_BACKDROP, 0.97)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_shell = PanelContainer.new()
	_shell.name = "InventoryShell"
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.offset_left = 10.0
	_shell.offset_top = 10.0
	_shell.offset_right = -10.0
	_shell.offset_bottom = -10.0
	HUDAssetLibrary.apply_panel(_shell, "neutral")
	add_child(_shell)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	_shell.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 9)
	margin.add_child(root_vbox)
	root_vbox.add_child(_build_header())

	var separator := HSeparator.new()
	separator.modulate = COLOR_BORDER
	root_vbox.add_child(separator)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	root_vbox.add_child(content)
	content.add_child(_build_paperdoll_column())
	content.add_child(_build_backpack_column())
	_ground_panel = _build_ground_column()
	content.add_child(_ground_panel)

	root_vbox.add_child(_build_action_bar())
	root_vbox.add_child(_build_footer())
	_build_hover_card()
	_apply_presentation_layout()

func _apply_presentation_layout() -> void:
	if _backdrop == null or _shell == null:
		return
	var canvas_layer := get_parent() as CanvasLayer
	if _presentation_mode == PresentationMode.SIDE_PANEL:
		_backdrop.visible = false
		_shell.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		_shell.offset_left = 20.0
		_shell.offset_top = -320.0
		_shell.offset_right = 460.0
		_shell.offset_bottom = 320.0
		if _ground_panel:
			_ground_panel.visible = false
		if canvas_layer:
			canvas_layer.layer = 21
	else:
		_backdrop.visible = true
		_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_shell.offset_left = 10.0
		_shell.offset_top = 10.0
		_shell.offset_right = -10.0
		_shell.offset_bottom = -10.0
		if _ground_panel:
			_ground_panel.visible = true
		if canvas_layer:
			canvas_layer.layer = 1

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 44.0
	header.add_theme_constant_override("separation", 16)

	var title_box := VBoxContainer.new()
	title_box.custom_minimum_size.x = 250.0
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)

	var title := Label.new()
	title.text = "FIELD LOADOUT"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title_box.add_child(title)

	_location_label = Label.new()
	_location_label.text = "HEX 0, 0"
	_location_label.add_theme_font_size_override("font_size", 11)
	_location_label.add_theme_color_override("font_color", COLOR_MUTED)
	title_box.add_child(_location_label)

	var capacity_box := VBoxContainer.new()
	capacity_box.custom_minimum_size.x = 260.0
	header.add_child(capacity_box)

	_capacity_label = Label.new()
	_capacity_label.text = "CAPACITY 0 / 0"
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_capacity_label.add_theme_color_override("font_color", COLOR_TEXT)
	capacity_box.add_child(_capacity_label)

	_capacity_bar = ProgressBar.new()
	_capacity_bar.custom_minimum_size.y = 14.0
	_capacity_bar.show_percentage = false
	HUDAssetLibrary.apply_progress_bar(_capacity_bar, "health")
	capacity_box.add_child(_capacity_bar)

	var close_button := Button.new()
	close_button.text = "CLOSE  [ESC]"
	close_button.custom_minimum_size = Vector2(120, 36)
	HUDAssetLibrary.apply_button(close_button)
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)
	return header

func _build_paperdoll_column() -> Control:
	var panel := PanelContainer.new()
	panel.name = "PaperDollPanel"
	panel.custom_minimum_size.x = 350.0
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	HUDAssetLibrary.apply_panel(panel, "neutral")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(_section_header("EQUIPMENT", "RIGHT CLICK TO UNEQUIP"))

	var stage := Control.new()
	stage.name = "PaperDollStage"
	stage.custom_minimum_size = Vector2(350, 340)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	column.add_child(stage)

	paperdoll_model = PAPERDOLL_SCENE.instantiate() as PaperDollModel
	stage.add_child(paperdoll_model)
	paperdoll_model.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var equipment_overlay := Control.new()
	equipment_overlay.name = "EquipmentSlots"
	equipment_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(equipment_overlay)

	for slot: int in EQUIPMENT_LAYOUT:
		var config: Dictionary = EQUIPMENT_LAYOUT[slot]
		var slot_ui := _make_slot(
			equipment_overlay,
			InventorySlot.SOURCE_EQUIPMENT,
			slot,
			str(config["label"]),
			str(config["texture"])
		)
		slot_ui.equipment_slot = slot as GameEnums.EquipmentSlot
		var anchor: Vector2 = config["position"]
		slot_ui.anchor_left = anchor.x
		slot_ui.anchor_right = anchor.x
		slot_ui.anchor_top = anchor.y
		slot_ui.anchor_bottom = anchor.y
		slot_ui.offset_left = -31.0
		slot_ui.offset_top = -31.0
		slot_ui.offset_right = 31.0
		slot_ui.offset_bottom = 31.0
		equipment_slots_ui[slot] = slot_ui

	return panel

func _build_backpack_column() -> Control:
	var panel := PanelContainer.new()
	panel.name = "BackpackPanel"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	HUDAssetLibrary.apply_panel(panel, "neutral")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header := _section_header("INVENTORY", "SLOT CAPACITY")
	_backpack_count_label = header.get_child(1) as Label
	column.add_child(header)

	_capacity_sources_label = Label.new()
	_capacity_sources_label.add_theme_font_size_override("font_size", 10)
	_capacity_sources_label.add_theme_color_override("font_color", COLOR_MUTED)
	_capacity_sources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_capacity_sources_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	dynamic_capacity_grids = VBoxContainer.new()
	dynamic_capacity_grids.name = "DynamicCapacityGrids"
	dynamic_capacity_grids.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dynamic_capacity_grids.add_theme_constant_override("separation", 8)
	scroll.add_child(dynamic_capacity_grids)
	return panel

func _build_ground_column() -> Control:
	var panel := PanelContainer.new()
	panel.name = "GroundPanel"
	panel.custom_minimum_size.x = 215.0
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	HUDAssetLibrary.apply_panel(panel, "neutral")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header := _section_header("GROUND", "LOCAL CACHE")
	_ground_count_label = header.get_child(1) as Label
	column.add_child(header)

	var hint := Label.new()
	hint.text = "Double-click to take. Drag carried gear here to drop."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	ground_list = GridContainer.new()
	ground_list.name = "GroundList"
	ground_list.columns = 3
	ground_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground_list.add_theme_constant_override("h_separation", 5)
	ground_list.add_theme_constant_override("v_separation", 5)
	scroll.add_child(ground_list)
	return panel

func _build_action_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 34.0
	bar.add_theme_constant_override("separation", 8)

	var prompt := Label.new()
	prompt.text = "SELECTED ITEM"
	prompt.custom_minimum_size.x = 120.0
	prompt.add_theme_color_override("font_color", COLOR_MUTED)
	bar.add_child(prompt)

	_primary_button = Button.new()
	_primary_button.text = "NO ACTION"
	_primary_button.disabled = true
	_primary_button.custom_minimum_size.x = 125.0
	HUDAssetLibrary.apply_button(_primary_button)
	_primary_button.pressed.connect(_activate_selected_primary)
	bar.add_child(_primary_button)

	_secondary_button = Button.new()
	_secondary_button.text = "NO ACTION"
	_secondary_button.disabled = true
	_secondary_button.custom_minimum_size.x = 125.0
	HUDAssetLibrary.apply_button(_secondary_button)
	_secondary_button.pressed.connect(_activate_selected_secondary)
	bar.add_child(_secondary_button)

	_spill_warning = Label.new()
	_spill_warning.visible = false
	_spill_warning.text = "CAPACITY BREACH: EXCESS ITEMS WILL SPILL"
	_spill_warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spill_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_spill_warning.add_theme_color_override("font_color", COLOR_DANGER)
	bar.add_child(_spill_warning)
	return bar

func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 24.0

	_feedback_label = Label.new()
	_feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback_label.add_theme_font_size_override("font_size", 11)
	_feedback_label.add_theme_color_override("font_color", COLOR_ACCENT)
	footer.add_child(_feedback_label)

	var controls := Label.new()
	controls.text = "LMB SELECT  |  DOUBLE LMB USE  |  RMB QUICK ACTION  |  DRAG MOVE"
	controls.add_theme_font_size_override("font_size", 10)
	controls.add_theme_color_override("font_color", COLOR_MUTED)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(controls)
	return footer

func _build_hover_card() -> void:
	_hover_card = PanelContainer.new()
	_hover_card.name = "ItemHoverHUD"
	_hover_card.visible = false
	_hover_card.z_index = 100
	_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_card.custom_minimum_size.x = 360.0
	HUDAssetLibrary.apply_panel(_hover_card, "warning")
	add_child(_hover_card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 9)
	_hover_card.add_child(margin)

	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	_hover_icon = TextureRect.new()
	_hover_icon.custom_minimum_size = Vector2(76, 76)
	_hover_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hover_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(_hover_icon)

	var text_column := VBoxContainer.new()
	text_column.custom_minimum_size.x = 250.0
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_theme_constant_override("separation", 3)
	body.add_child(text_column)

	_hover_name = Label.new()
	_hover_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_name.add_theme_font_size_override("font_size", 17)
	_hover_name.add_theme_color_override("font_color", COLOR_GOLD)
	text_column.add_child(_hover_name)

	_hover_meta = Label.new()
	_hover_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_meta.add_theme_font_size_override("font_size", 10)
	_hover_meta.add_theme_color_override("font_color", COLOR_ACCENT)
	text_column.add_child(_hover_meta)

	_hover_description = Label.new()
	_hover_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_description.add_theme_font_size_override("font_size", 11)
	_hover_description.add_theme_color_override("font_color", COLOR_TEXT)
	text_column.add_child(_hover_description)

	_hover_stats = Label.new()
	_hover_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_stats.add_theme_font_size_override("font_size", 10)
	_hover_stats.add_theme_color_override("font_color", COLOR_MUTED)
	text_column.add_child(_hover_stats)

func _render() -> void:
	var current := int(_snapshot.get("current_capacity", 0))
	var maximum := int(_snapshot.get("maximum_capacity", 0))
	var coords: Vector2i = _snapshot.get("coords", Vector2i.ZERO)

	_location_label.text = (
		"HEX %d, %d  |  FIELD LOADOUT" % [coords.x, coords.y]
		if _presentation_mode == PresentationMode.SIDE_PANEL
		else "HEX %d, %d  |  EQUIPMENT AND LOCAL GROUND" % [coords.x, coords.y]
	)
	_capacity_label.text = "CAPACITY %d / %d" % [current, maximum]
	_capacity_bar.max_value = maxf(1.0, float(maximum))
	_capacity_bar.value = float(current)
	_capacity_bar.add_theme_stylebox_override(
		"fill",
		HUDAssetLibrary.bar_fill_style(
			"critical" if current > maximum else "health"
		)
	)
	_spill_warning.visible = current > maximum
	_feedback_label.text = _feedback

	var breakdown: Array = _snapshot.get("capacity_breakdown", [])
	var sources: PackedStringArray = []
	for source: Dictionary in breakdown:
		sources.append("%s +%d" % [
			str(source.get("name", "Capacity")),
			int(source.get("capacity", 0)),
		])
	_capacity_sources_label.text = "  |  ".join(sources)

	var equipment: Array = _snapshot.get("equipment", [])
	paperdoll_model.update_model(equipment)
	paperdoll_model.set_backdrop_visible(false)
	paperdoll_model.update_wounds(_snapshot.get("limbs", []))
	for slot_ui: InventorySlot in equipment_slots_ui.values():
		slot_ui.set_item({})
	for descriptor: Dictionary in equipment:
		var slot := int(descriptor.get(
			"equipment_slot",
			GameEnums.EquipmentSlot.NONE
		))
		if equipment_slots_ui.has(slot):
			equipment_slots_ui[slot].set_item(descriptor)

	_render_backpack(
		_snapshot.get("containers", []),
		_snapshot.get("backpack", []),
		maximum
	)
	if _presentation_mode == PresentationMode.FULLSCREEN:
		_render_ground(_snapshot.get("ground", []))
	else:
		_render_ground([])
	_clear_selection()

func _render_backpack(
	containers: Array,
	legacy_items: Array,
	maximum_capacity: int
) -> void:
	_clear_container(dynamic_capacity_grids)
	backpack_slots_ui.clear()

	if containers.is_empty() and maximum_capacity > 0:
		containers = [{
			"slot": GameEnums.EquipmentSlot.BACKPACK,
			"name": "LEGACY STORAGE",
			"capacity": maximum_capacity,
			"used": int(_snapshot.get("current_capacity", 0)),
			"combat_accessible": false,
			"items": legacy_items,
		}]

	var rendered_items := 0
	for container: Dictionary in containers:
		var container_slot := int(container.get(
			"slot",
			GameEnums.EquipmentSlot.NONE
		)) as GameEnums.EquipmentSlot
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		dynamic_capacity_grids.add_child(section)

		var title := Label.new()
		title.text = "%s  %d/%d%s" % [
			str(container.get("name", "STORAGE")).to_upper(),
			int(container.get("used", 0)),
			int(container.get("capacity", 0)),
			"  [COMBAT]" if container.get("combat_accessible", false) else "",
		]
		title.add_theme_font_size_override("font_size", 10)
		title.add_theme_color_override(
			"font_color",
			COLOR_GOLD
				if container.get("combat_accessible", false)
				else COLOR_MUTED
		)
		section.add_child(title)

		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		section.add_child(grid)

		var occupied_units := 0
		var items: Array = container.get("items", [])
		for descriptor: Dictionary in items:
			var item_slot := _make_slot(
				grid,
				InventorySlot.SOURCE_BACKPACK,
				occupied_units,
				"",
				"",
				container_slot
			)
			item_slot.set_item(descriptor)
			backpack_slots_ui.append(item_slot)
			rendered_items += 1
			var item_size := maxi(1, int(descriptor.get("size_cost", 1)))
			occupied_units += 1
			for unit in range(1, item_size):
				var reserved := _make_slot(
					grid,
					InventorySlot.SOURCE_BACKPACK,
					occupied_units,
					"",
					"",
					container_slot
				)
				reserved.set_reserved(descriptor)
				backpack_slots_ui.append(reserved)
				occupied_units += 1

		var capacity := int(container.get("capacity", 0))
		while occupied_units < capacity:
			var empty_slot := _make_slot(
				grid,
				InventorySlot.SOURCE_BACKPACK,
				occupied_units,
				"",
				"",
				container_slot
			)
			backpack_slots_ui.append(empty_slot)
			occupied_units += 1

	if containers.is_empty():
		var empty_notice := Label.new()
		empty_notice.text = "NO WORN STORAGE"
		empty_notice.add_theme_color_override("font_color", COLOR_DANGER)
		dynamic_capacity_grids.add_child(empty_notice)

	_backpack_count_label.text = "%d ITEMS / %d UNITS" % [
		rendered_items,
		int(_snapshot.get("current_capacity", 0)),
	]

func _render_ground(items: Array) -> void:
	_clear_container(ground_list)
	ground_slots_ui.clear()

	var index := 0
	for descriptor: Dictionary in items:
		var slot := _make_slot(
			ground_list,
			InventorySlot.SOURCE_GROUND,
			index,
			"",
			""
		)
		slot.set_item(descriptor)
		ground_slots_ui.append(slot)
		index += 1

	var drop_target := _make_slot(
		ground_list,
		InventorySlot.SOURCE_GROUND,
		index,
		"DROP",
		""
	)
	ground_slots_ui.append(drop_target)
	_ground_count_label.text = "%d ITEMS" % items.size()

func _make_slot(
	parent: Control,
	source_kind: String,
	index: int,
	label: String,
	_empty_texture_path: String,
	container_slot: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
) -> InventorySlot:
	var slot := SLOT_SCENE.instantiate() as InventorySlot
	parent.add_child(slot)
	slot.configure(source_kind, index, label, null, container_slot)
	slot.set_text_only_mode(_presentation_mode == PresentationMode.SIDE_PANEL)
	slot.slot_clicked.connect(_on_slot_clicked)
	slot.item_dropped.connect(_on_item_dropped)
	slot.item_hovered.connect(_on_slot_hovered)
	slot.item_unhovered.connect(_on_slot_unhovered)
	return slot

func _on_slot_clicked(
	slot: InventorySlot,
	event: InputEventMouseButton
) -> void:
	_select_slot(slot)
	if event.double_click:
		_execute_primary(slot)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if slot.source_kind == InventorySlot.SOURCE_BACKPACK:
			_execute_secondary(slot)
		else:
			_execute_primary(slot)

func _on_slot_hovered(slot: InventorySlot) -> void:
	show_item_details(slot.item_descriptor)

func _on_slot_unhovered(_slot: InventorySlot) -> void:
	hide_item_details()

func _on_item_dropped(
	from_slot: InventorySlot,
	to_slot: InventorySlot
) -> void:
	var descriptor := from_slot.item_descriptor
	if descriptor.is_empty():
		return
	var instance_id := str(descriptor.get("instance_id", ""))

	match to_slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT:
			inventory_action_requested.emit(
				ACTION_EQUIP,
				instance_id,
				to_slot.equipment_slot
			)
		InventorySlot.SOURCE_BACKPACK:
			if from_slot.source_kind == InventorySlot.SOURCE_EQUIPMENT:
				inventory_action_requested.emit(
					ACTION_UNEQUIP,
					instance_id,
					from_slot.equipment_slot
				)
			elif from_slot.source_kind == InventorySlot.SOURCE_GROUND:
				inventory_action_requested.emit(
					ACTION_TAKE,
					instance_id,
					to_slot.container_slot
				)
			elif (
				from_slot.source_kind == InventorySlot.SOURCE_BACKPACK
				and from_slot.container_slot != to_slot.container_slot
			):
				inventory_action_requested.emit(
					ACTION_MOVE,
					instance_id,
					to_slot.container_slot
				)
		InventorySlot.SOURCE_GROUND:
			inventory_action_requested.emit(
				ACTION_DROP,
				instance_id,
				GameEnums.EquipmentSlot.NONE
			)

func _select_slot(slot: InventorySlot) -> void:
	_clear_selection()
	if not slot.has_item():
		return
	_selected_slot = slot
	slot.set_selected(true)
	_refresh_action_buttons()

func _clear_selection() -> void:
	if is_instance_valid(_selected_slot):
		_selected_slot.set_selected(false)
	_selected_slot = null
	_refresh_action_buttons()

func _refresh_action_buttons() -> void:
	_primary_button.disabled = true
	_primary_button.text = "NO ACTION"
	_secondary_button.disabled = true
	_secondary_button.text = "NO ACTION"
	if not is_instance_valid(_selected_slot) or not _selected_slot.has_item():
		return

	var descriptor := _selected_slot.item_descriptor
	match _selected_slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT:
			_primary_button.text = "UNEQUIP"
			_primary_button.disabled = false
			_secondary_button.text = "DROP"
			_secondary_button.disabled = false
		InventorySlot.SOURCE_GROUND:
			_primary_button.text = (
				"TAKE"
				if descriptor.get("can_pick_up", true)
				else "INTERACT"
			)
			_primary_button.disabled = false
		InventorySlot.SOURCE_BACKPACK:
			if descriptor.get("can_load_magazine", false):
				_primary_button.text = "LOAD ROUNDS"
				_primary_button.disabled = false
			elif descriptor.get("can_equip", false):
				_primary_button.text = "EQUIP"
				_primary_button.disabled = false
			elif descriptor.get("can_consume", false):
				_primary_button.text = "USE"
				_primary_button.disabled = false
			_secondary_button.text = "DROP"
			_secondary_button.disabled = false

func _activate_selected_primary() -> void:
	if is_instance_valid(_selected_slot):
		_execute_primary(_selected_slot)

func _activate_selected_secondary() -> void:
	if is_instance_valid(_selected_slot):
		_execute_secondary(_selected_slot)

func _execute_primary(slot: InventorySlot) -> void:
	if not slot.has_item():
		return
	var descriptor := slot.item_descriptor
	var instance_id := str(descriptor.get("instance_id", ""))
	match slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT:
			inventory_action_requested.emit(
				ACTION_UNEQUIP,
				instance_id,
				slot.equipment_slot
			)
		InventorySlot.SOURCE_GROUND:
			inventory_action_requested.emit(
				ACTION_TAKE
					if descriptor.get("can_pick_up", true)
					else ACTION_INTERACT,
				instance_id,
				GameEnums.EquipmentSlot.NONE
			)
		InventorySlot.SOURCE_BACKPACK:
			if descriptor.get("can_load_magazine", false):
				inventory_action_requested.emit(
					ACTION_LOAD_MAGAZINE,
					instance_id,
					slot.container_slot
				)
			elif descriptor.get("can_equip", false):
				inventory_action_requested.emit(
					ACTION_EQUIP,
					instance_id,
					int(descriptor.get(
						"preferred_equipment_slot",
						GameEnums.EquipmentSlot.NONE
					))
				)
			elif descriptor.get("can_consume", false):
				inventory_action_requested.emit(
					ACTION_CONSUME,
					instance_id,
					GameEnums.EquipmentSlot.NONE
				)

func _execute_secondary(slot: InventorySlot) -> void:
	if not slot.has_item():
		return
	var instance_id := str(slot.item_descriptor.get("instance_id", ""))
	match slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT:
			inventory_action_requested.emit(
				ACTION_DROP,
				instance_id,
				GameEnums.EquipmentSlot.NONE
			)
		InventorySlot.SOURCE_GROUND:
			_execute_primary(slot)
		InventorySlot.SOURCE_BACKPACK:
			inventory_action_requested.emit(
				ACTION_DROP,
				instance_id,
				GameEnums.EquipmentSlot.NONE
			)

func _format_item_stats(descriptor: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Size %s  |  %d units  |  Weight %.1f  |  Bulk %.1f" % [
		_enum_name(GameEnums.ItemSize, int(descriptor.get(
			"item_size",
			GameEnums.ItemSize.SMALL
		))),
		int(descriptor.get("size_cost", 1)),
		float(descriptor.get("weight", 0.0)),
		float(descriptor.get("bulk", 0.0)),
	])
	var stack_count := int(descriptor.get("stack_count", 1))
	var stack_limit := int(descriptor.get("stack_limit", 1))
	if stack_limit > 1:
		lines.append("Stack %d / %d" % [stack_count, stack_limit])
	var magazine_capacity := int(descriptor.get("magazine_capacity", 0))
	if magazine_capacity > 0:
		lines.append("Magazine %d / %d  |  %s" % [
			int(descriptor.get("loaded_rounds", 0)),
			magazine_capacity,
			str(descriptor.get("accepted_ammunition_id", "UNKNOWN")).to_upper(),
		])

	var capacity_bonus := int(descriptor.get("capacity_bonus", 0))
	if capacity_bonus != 0:
		lines.append("Capacity bonus: +%d" % capacity_bonus)

	var item_type := int(descriptor.get(
		"item_type",
		GameEnums.ItemType.JUNK
	))
	if item_type == GameEnums.ItemType.WEAPON:
		lines.append("Flesh %.1f  |  Stance %.1f  |  Pen %.1f" % [
			float(descriptor.get("flesh_damage", 0.0)),
			float(descriptor.get("stance_damage", 0.0)),
			float(descriptor.get("armor_penetration", 0.0)),
		])
		lines.append("Accuracy %.1f  |  Range %d-%d" % [
			float(descriptor.get("accuracy_rating", 0.0)),
			int(descriptor.get("optimal_range", 0)),
			int(descriptor.get("effective_range", 0)),
		])
		var max_magazine := int(descriptor.get("max_magazine", 0))
		if max_magazine > 0:
			lines.append("Loaded %d / %d%s" % [
				int(descriptor.get("current_magazine", 0)),
				max_magazine,
				"  |  NEEDS CYCLE"
					if descriptor.get("needs_cycling", false)
					else "",
			])

	var protection_total := (
		float(descriptor.get("protection_blunt", 0.0))
		+ float(descriptor.get("protection_sharp", 0.0))
		+ float(descriptor.get("protection_ballistic", 0.0))
	)
	if protection_total > 0.0:
		lines.append("Protection B %.1f  S %.1f  R %.1f" % [
			float(descriptor.get("protection_blunt", 0.0)),
			float(descriptor.get("protection_sharp", 0.0)),
			float(descriptor.get("protection_ballistic", 0.0)),
		])

	var threat := float(descriptor.get("threat", 0.0))
	var insulation := float(descriptor.get("insulation", 0.0))
	if threat != 0.0 or insulation != 0.0:
		lines.append("Threat %.1f  |  Insulation %.1f" % [
			threat,
			insulation,
		])

	if item_type == GameEnums.ItemType.CONSUMABLE:
		lines.append("Potency %.1f  |  %s" % [
			float(descriptor.get("consumable_potency", 0.0)),
			_enum_name(GameEnums.ConsumableEffect, int(descriptor.get(
				"consumable_effect",
				GameEnums.ConsumableEffect.RESTORE_HUNGER
			))),
		])

	var interaction_values := [
		float(descriptor.get("search_loot_bonus", 0.0)),
		float(descriptor.get("search_safety_bonus", 0.0)),
		float(descriptor.get("search_sneak_bonus", 0.0)),
		float(descriptor.get("camp_sleep_bonus", 0.0)),
		float(descriptor.get("camp_shelter_bonus", 0.0)),
		float(descriptor.get("camp_healing_bonus", 0.0)),
	]
	var has_interaction_bonus := false
	for value: float in interaction_values:
		if value != 0.0:
			has_interaction_bonus = true
			break
	if has_interaction_bonus:
		lines.append("Search L %.1f / Safe %.1f / Sneak %.1f" % [
			interaction_values[0],
			interaction_values[1],
			interaction_values[2],
		])
		lines.append("Camp Sleep %.1f / Shelter %.1f / Heal %.1f" % [
			interaction_values[3],
			interaction_values[4],
			interaction_values[5],
		])
	return "\n".join(lines)

func _section_header(title_text: String, side_text: String) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 26.0

	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	header.add_child(title)

	var side := Label.new()
	side.text = side_text
	side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_theme_font_size_override("font_size", 9)
	side.add_theme_color_override("font_color", COLOR_MUTED)
	header.add_child(side)
	return header

func _panel_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_top = 7.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 7.0
	return style

func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _equipment_slot_name(slot: int) -> String:
	if slot == GameEnums.EquipmentSlot.NONE:
		return "CARRIED"
	return _enum_name(GameEnums.EquipmentSlot, slot)

func _enum_name(enum_dictionary: Dictionary, value: int) -> String:
	for key in enum_dictionary:
		if int(enum_dictionary[key]) == value:
			return str(key).replace("_", " ")
	return "UNKNOWN"
