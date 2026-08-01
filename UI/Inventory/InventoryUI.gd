extends Control
class_name InventoryUI

signal inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary
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
const ACTION_REPAIR := GameEnums.MACRO_INV_REPAIR
const ACTION_INSPECT := GameEnums.MACRO_INV_INSPECT

enum PresentationMode {
	FULLSCREEN,
	SIDE_PANEL,
	EMBEDDED,
}

const SLOT_SCENE := preload("res://UI/Inventory/InventorySlot.tscn")
const PAPERDOLL_SCENE := preload("res://UI/Inventory/PaperDollModel.tscn")
const SLOT_ACTION_BUILDER := preload("res://UI/Inventory/InventorySlotActionBuilder.gd")
const CONTEXT_MENU_HOST := preload("res://UI/Inventory/InventorySlotContextMenuHost.gd")
const STAT_GAUGE_SCENE := preload("res://UI/Inventory/StatGaugeRow.tscn")
const EFFECT_CHIP_SCENE := preload("res://UI/Inventory/EffectChip.tscn")

const WEIGHT_DISPLAY_MAX := 24.0
const BULK_DISPLAY_MAX := 24.0
const PROTECTION_DISPLAY_MAX := 12.0

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
var _show_ground_in_side_panel := true

var _backdrop: ColorRect
var _shell: PanelContainer
var _ground_panel: PanelContainer

var _location_label: Label
var _capacity_label: Label
var _capacity_bar: ProgressBar
var _capacity_sources_label: Label
var _loadout_stats_label: Label
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
var _condition_bar: ProgressBar
var _stat_gauge_list: VBoxContainer
var _effect_chip_row: HFlowContainer
var _comparison_label: Label
var _filter_row: HFlowContainer
var _carried_scroll: ScrollContainer
var _ground_scroll: ScrollContainer
var _confirm_dialog: ConfirmationDialog
var _repair_button: Button
var _pending_confirm: Callable
var _active_filter := "all"
var _header_close_button: Button
var _context_menu_slot: InventorySlot
var _archetype_label: Label
var _pillar_list: VBoxContainer
var _loadout_gauge_list: VBoxContainer
var _identity_chip_row: HFlowContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_authored_interface()
	close_panel(false)

func _process(_delta: float) -> void:
	pass

func _bind_authored_interface() -> void:
	_backdrop = %Backdrop
	_shell = %InventoryShell
	_ground_panel = %GroundPanel
	_location_label = %LocationLabel
	_capacity_label = %CapacityLabel
	_capacity_bar = %CapacityBar
	_capacity_sources_label = %CapacitySourcesLabel
	_loadout_stats_label = %LoadoutStatsLabel
	_backpack_count_label = %BackpackCountLabel
	_ground_count_label = %GroundCountLabel
	_feedback_label = %FeedbackLabel
	_spill_warning = %SpillWarning
	_primary_button = %PrimaryButton
	_secondary_button = %SecondaryButton
	_hover_card = %InspectorPanel
	_hover_icon = %HoverIcon
	_hover_name = %HoverName
	_hover_meta = %HoverMeta
	_hover_description = %HoverDescription
	_hover_stats = %HoverStats
	_condition_bar = %ConditionBar
	_stat_gauge_list = %StatGaugeList
	_effect_chip_row = %EffectChipRow
	_comparison_label = %ComparisonLabel
	_filter_row = %FilterRow
	_carried_scroll = %CarriedScroll
	_ground_scroll = %GroundScroll
	_confirm_dialog = %ConfirmDialog
	_repair_button = %RepairButton
	_header_close_button = %CloseButton
	_archetype_label = %ArchetypeLabel
	_pillar_list = %PillarList
	_loadout_gauge_list = %LoadoutGaugeList
	_identity_chip_row = %IdentityChipRow
	dynamic_capacity_grids = %DynamicCapacityGrids
	ground_list = %GroundList
	paperdoll_model = %PaperDollModel

	HUDAssetLibrary.apply_panel(_shell, "neutral")
	HUDAssetLibrary.apply_panel(%PaperDollPanel, "neutral")
	HUDAssetLibrary.apply_panel(%ItemsPanel, "neutral")
	HUDAssetLibrary.apply_panel(_ground_panel, "neutral")
	HUDAssetLibrary.apply_panel(_hover_card, "warning")
	if _backdrop != null:
		_backdrop.color = Color(COLOR_BACKDROP, 0.92)
	HUDAssetLibrary.apply_progress_bar(_capacity_bar, "health")
	HUDAssetLibrary.apply_progress_bar(_condition_bar, "condition")
	_condition_bar.visible = false
	_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_capacity_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _hover_stats != null:
		_hover_stats.visible = false
	for button in [_primary_button, _secondary_button, _header_close_button, %RepairButton]:
		HUDAssetLibrary.apply_button(button)
	HUDAssetLibrary.apply_button(_header_close_button, "pass")
	_primary_button.pressed.connect(_activate_selected_primary)
	_secondary_button.pressed.connect(_activate_selected_secondary)
	_header_close_button.pressed.connect(close_panel)
	_confirm_dialog.confirmed.connect(_commit_pending_confirmation)
	_repair_button.pressed.connect(_activate_repair_tray)
	for child in _filter_row.get_children():
		if child is Button:
			var button := child as Button
			button.toggle_mode = true
			HUDAssetLibrary.apply_button(button)
			button.pressed.connect(_set_filter.bind(str(button.get_meta("filter_id", "all"))))
	_active_filter = "all"
	if _filter_row.get_child_count() > 0:
		(_filter_row.get_child(0) as Button).button_pressed = true

	equipment_slots_ui.clear()
	for node in %EquipmentSlots.find_children("*", "InventorySlot", true, false):
		var slot_ui := node as InventorySlot
		var slot := int(slot_ui.equipment_slot)
		if slot == GameEnums.EquipmentSlot.NONE or not EQUIPMENT_LAYOUT.has(slot):
			continue
		slot_ui.configure(
			InventorySlot.SOURCE_EQUIPMENT,
			slot,
			str(EQUIPMENT_LAYOUT[slot]["label"])
		)
		_bind_slot_signals(slot_ui)
		equipment_slots_ui[slot] = slot_ui
	_reset_inspector()

func open_inventory(snapshot: Dictionary, feedback: String = "", show_ground: bool = true) -> void:
	_presentation_mode = PresentationMode.FULLSCREEN
	_show_ground_in_side_panel = show_ground
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	visible = true
	_apply_presentation_layout()
	_render()

func open_side_panel(snapshot: Dictionary, feedback: String = "", show_ground: bool = true) -> void:
	_presentation_mode = PresentationMode.SIDE_PANEL
	_show_ground_in_side_panel = show_ground
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	visible = true
	_apply_presentation_layout()
	_render()

func open_loadout_panel(snapshot: Dictionary, feedback: String = "") -> void:
	open_side_panel(snapshot, feedback, false)


func open_embedded_panel(host: Control, snapshot: Dictionary, feedback: String = "") -> void:
	_presentation_mode = PresentationMode.EMBEDDED
	_show_ground_in_side_panel = false
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	visible = true
	if get_parent() != host:
		reparent(host)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_presentation_layout()
	_render()


func is_embedded() -> bool:
	return visible and _presentation_mode == PresentationMode.EMBEDDED

func is_side_panel() -> bool:
	return visible and _presentation_mode == PresentationMode.SIDE_PANEL

func is_fullscreen() -> bool:
	return visible and _presentation_mode == PresentationMode.FULLSCREEN

func refresh_snapshot(snapshot: Dictionary, feedback: String = "") -> void:
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	if visible:
		_apply_presentation_layout()
		_render()

func close_panel(notify: bool = true) -> void:
	visible = false
	_presentation_mode = PresentationMode.FULLSCREEN
	_show_ground_in_side_panel = true
	_hover_card.visible = true
	_snapshot.clear()
	_feedback = ""
	_selected_slot = null
	_reset_inspector()
	_apply_presentation_layout()
	if notify:
		inventory_closed.emit()

func is_open() -> bool:
	return visible


func close_top_surface() -> bool:
	if not visible:
		return false
	if _confirm_dialog != null and _confirm_dialog.visible:
		_confirm_dialog.hide()
		_pending_confirm = Callable()
		return true
	for node in get_tree().get_nodes_in_group("slot_context_menu_host"):
		var menu := node.get_node_or_null("InventorySlotContextMenu") as InventorySlotContextMenu
		if menu != null and menu.visible:
			menu.close_menu()
			return true
	close_panel()
	return true

func show_item_details(descriptor: Dictionary) -> void:
	if descriptor.is_empty():
		_reset_inspector()
		return

	_hover_card.visible = true
	var sprite_path := str(descriptor.get("sprite_path", ""))
	_hover_icon.texture = (
		load(sprite_path) as Texture2D
		if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path)
		else null
	)
	_hover_name.text = str(descriptor.get("name", "Unknown Item")).to_upper()
	_hover_meta.text = "%s  |  %s  |  %s" % [
		_enum_name(GameEnums.ItemGrade, int(descriptor.get(
			"item_grade",
			GameEnums.ItemGrade.CIVILIAN
		))),
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
	_populate_item_stat_gauges(descriptor)
	_populate_item_effect_chips(descriptor)
	_condition_bar.visible = false
	_comparison_label.text = _comparison_text(descriptor)

func hide_item_details() -> void:
	if is_instance_valid(_selected_slot) and _selected_slot.has_item():
		show_item_details(_selected_slot.item_descriptor)
		return
	_reset_inspector()

func _reset_inspector() -> void:
	_hover_icon.texture = null
	_hover_name.text = "SELECT AN ITEM"
	_hover_meta.text = "GRADE  |  CATEGORY  |  LOCATION"
	_hover_description.text = "Field notes and contribution details appear after selection."
	if _hover_stats != null:
		_hover_stats.text = ""
		_hover_stats.visible = false
	_condition_bar.value = 0.0
	_condition_bar.visible = false
	_comparison_label.text = "COMPARISON: select carried gear"
	if _stat_gauge_list != null:
		_clear_container(_stat_gauge_list)
	if _effect_chip_row != null:
		_clear_container(_effect_chip_row)

func _comparison_text(descriptor: Dictionary) -> String:
	var equipped: Dictionary = {}
	var preferred := int(descriptor.get("preferred_equipment_slot", GameEnums.EquipmentSlot.NONE))
	for candidate: Dictionary in _snapshot.get("equipment", []):
		if int(candidate.get("equipment_slot", GameEnums.EquipmentSlot.NONE)) == preferred:
			equipped = candidate
			break
	if equipped.is_empty() or equipped.get("instance_id", "") == descriptor.get("instance_id", ""):
		return "COMPARISON: no different equipped item in the relevant slot"
	return "VS %s  |  Flesh %+.1f  Impact %+.1f  Pen %+.1f  Prot %+.1f  Weight %+.1f  Bulk %+.1f" % [
		str(equipped.get("name", "EQUIPPED")).to_upper(),
		float(descriptor.get("flesh_damage", 0.0)) - float(equipped.get("flesh_damage", 0.0)),
		float(descriptor.get("balance_impact", 0.0)) - float(equipped.get("balance_impact", 0.0)),
		float(descriptor.get("armor_penetration", 0.0)) - float(equipped.get("armor_penetration", 0.0)),
		_total_protection(descriptor) - _total_protection(equipped),
		float(descriptor.get("weight", 0.0)) - float(equipped.get("weight", 0.0)),
		float(descriptor.get("bulk", 0.0)) - float(equipped.get("bulk", 0.0)),
	]

func _total_protection(descriptor: Dictionary) -> float:
	return (
		float(descriptor.get("protection_blunt", 0.0))
		+ float(descriptor.get("protection_sharp", 0.0))
		+ float(descriptor.get("protection_ballistic", 0.0))
	)

func _build_interface() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(COLOR_BACKDROP, 0.92)
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
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backdrop.visible = false
		_shell.scale = Vector2.ONE
		_shell.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		_shell.offset_left = 20.0
		_shell.offset_top = -320.0
		_shell.offset_right = 970.0
		_shell.offset_bottom = 320.0
		if _ground_panel:
			_ground_panel.visible = _show_ground_in_side_panel
		if _header_close_button:
			_header_close_button.visible = true
		%PaperDollPanel.visible = false
		%InspectorPanel.visible = true
		if canvas_layer:
			canvas_layer.layer = 21
	elif _presentation_mode == PresentationMode.EMBEDDED:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backdrop.visible = false
		_fit_shell_to_embedded_host()
		if _ground_panel:
			_ground_panel.visible = false
		if _header_close_button:
			_header_close_button.visible = false
		%PaperDollPanel.visible = false
		%InspectorPanel.visible = false
		if canvas_layer:
			canvas_layer.layer = 8
	else:
		# Fullscreen inventory is a true modal work surface. PASS allowed clicks
		# on transparent/backdrop areas to fall through into the hex world.
		mouse_filter = Control.MOUSE_FILTER_STOP
		_backdrop.visible = true
		_shell.scale = Vector2.ONE
		_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_shell.offset_left = 10.0
		_shell.offset_top = 10.0
		_shell.offset_right = -10.0
		_shell.offset_bottom = -10.0
		if _ground_panel:
			_ground_panel.visible = true
		if _header_close_button:
			_header_close_button.visible = true
		%PaperDollPanel.visible = true
		%InspectorPanel.visible = true
		if canvas_layer:
			canvas_layer.layer = 20

func _fit_shell_to_embedded_host() -> void:
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.scale = Vector2.ONE
	_shell.offset_left = 0.0
	_shell.offset_top = 0.0
	_shell.offset_right = 0.0
	_shell.offset_bottom = 0.0

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

	_loadout_stats_label = Label.new()
	_loadout_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_loadout_stats_label.add_theme_font_size_override("font_size", 10)
	_loadout_stats_label.add_theme_color_override("font_color", COLOR_GOLD)
	_loadout_stats_label.tooltip_text = "Equipped totals. Protection is shown by damage type: blunt / sharp / ballistic."
	capacity_box.add_child(_loadout_stats_label)

	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(120, 36)
	HUDAssetLibrary.apply_button(close_button)
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)
	_header_close_button = close_button
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
	column.add_child(_section_header("EQUIPMENT", "RMB CONTEXT MENU"))

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
	controls.text = "LMB SELECT  |  DOUBLE LMB USE  |  RMB CONTEXT MENU  |  DRAG MOVE"
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
	var selected_id := ""
	if is_instance_valid(_selected_slot) and _selected_slot.has_item():
		selected_id = str(_selected_slot.item_descriptor.get("instance_id", ""))
	var carried_scroll := _carried_scroll.scroll_vertical
	var ground_scroll := _ground_scroll.scroll_vertical
	_selected_slot = null
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
	var capacity_fill := "critical" if current > maximum else "health"
	HUDAssetLibrary.apply_progress_bar(_capacity_bar, capacity_fill)
	HudMotion.lerp_progress(self, _capacity_bar, float(current), HudMotion.PANEL_ENTER_SEC)
	if current > maximum:
		HudMotion.severity_flash(self, _capacity_bar, "critical")
	_spill_warning.visible = current > maximum
	_feedback_label.text = _feedback
	var loadout: Dictionary = _snapshot.get("loadout_stats", {})
	_loadout_stats_label.text = "KINETIC %s" % str(loadout.get("kinetic_tier", "FLUID"))
	_render_character_strip(loadout)

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
	%PaperDollSummary.text = "%d / %d SLOTS  //  %s" % [
		equipment.size(),
		equipment_slots_ui.size(),
		str(loadout.get("kinetic_tier", "FLUID")),
	]

	_render_backpack(
		_snapshot.get("containers", []),
		_snapshot.get("backpack", []),
		maximum
	)
	if _presentation_mode == PresentationMode.FULLSCREEN:
		_render_ground(_snapshot.get("ground", []))
	else:
		_render_ground(_snapshot.get("ground", []) if _show_ground_in_side_panel else [])
	_restore_selection_and_scroll(selected_id, carried_scroll, ground_scroll)

func _restore_selection_and_scroll(
	selected_id: String,
	carried_scroll: int,
	ground_scroll: int
) -> void:
	for slot: InventorySlot in _all_navigable_slots():
		if str(slot.item_descriptor.get("instance_id", "")) == selected_id:
			_select_slot(slot)
			break
	_carried_scroll.set_deferred("scroll_vertical", carried_scroll)
	_ground_scroll.set_deferred("scroll_vertical", ground_scroll)

func _set_filter(filter_id: String) -> void:
	_active_filter = filter_id
	for child in _filter_row.get_children():
		if child is Button:
			(child as Button).button_pressed = str(child.get_meta("filter_id", "all")) == filter_id
	_render()

func _matches_filter(descriptor: Dictionary) -> bool:
	if _active_filter == "all":
		return true
	var item_type := int(descriptor.get("item_type", GameEnums.ItemType.JUNK))
	var category := int(descriptor.get("catalog_category", GameEnums.ItemCategory.MISC))
	match _active_filter:
		"weapons":
			return item_type == GameEnums.ItemType.WEAPON
		"armor":
			return item_type == GameEnums.ItemType.ARMOR
		"aid":
			return category == GameEnums.ItemCategory.MEDICINE
		"tools":
			return item_type == GameEnums.ItemType.TOOL
		"ammunition":
			return item_type == GameEnums.ItemType.AMMUNITION
		"materials_misc":
			return item_type in [
				GameEnums.ItemType.MATERIAL,
				GameEnums.ItemType.JUNK,
				GameEnums.ItemType.ATTACHMENT,
			]
	return true

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
			if not _matches_filter(descriptor):
				continue
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
		if not _matches_filter(descriptor):
			continue
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
	_bind_slot_signals(slot)
	return slot

func _bind_slot_signals(slot: InventorySlot) -> void:
	slot.slot_clicked.connect(_on_slot_clicked)
	slot.item_dropped.connect(_on_item_dropped)
	slot.item_hovered.connect(_on_slot_hovered)
	slot.item_unhovered.connect(_on_slot_unhovered)
	slot.focus_mode = Control.FOCUS_ALL
	slot.focus_entered.connect(_select_slot.bind(slot))

func _on_slot_clicked(
	slot: InventorySlot,
	event: InputEventMouseButton
) -> void:
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	_select_slot(slot)
	if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_execute_safe_default(slot)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_open_slot_context_menu(slot, event.global_position)

func _open_slot_context_menu(slot: InventorySlot, global_pos: Vector2) -> void:
	if not slot.has_item():
		return
	var entries: Array = SLOT_ACTION_BUILDER.build_for_inventory_slot(slot)
	if entries.is_empty():
		return
	hide_item_details()
	_context_menu_slot = slot
	CONTEXT_MENU_HOST.request_open(
		get_tree(),
		global_pos,
		SLOT_ACTION_BUILDER.menu_header_for_slot(slot),
		entries,
		_on_slot_context_menu_action,
		slot.item_descriptor
	)

func _on_slot_context_menu_action(entry: Dictionary) -> void:
	if not is_instance_valid(_context_menu_slot):
		return
	match str(entry.get("kind", "")):
		SLOT_ACTION_BUILDER.KIND_EXAMINE:
			show_item_details(_context_menu_slot.item_descriptor)
		SLOT_ACTION_BUILDER.KIND_INVENTORY:
			_execute_inventory_action(
				str(entry.get("action_id", "")),
				_context_menu_slot,
				int(entry.get("equipment_slot", GameEnums.EquipmentSlot.NONE))
			)

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
				to_slot.equipment_slot,
				{}
			)
		InventorySlot.SOURCE_BACKPACK:
			if from_slot.source_kind == InventorySlot.SOURCE_EQUIPMENT:
				inventory_action_requested.emit(
					ACTION_UNEQUIP,
					instance_id,
					from_slot.equipment_slot,
					{}
				)
			elif from_slot.source_kind == InventorySlot.SOURCE_GROUND:
				inventory_action_requested.emit(
					ACTION_TAKE,
					instance_id,
					to_slot.container_slot,
					{}
				)
			elif (
				from_slot.source_kind == InventorySlot.SOURCE_BACKPACK
				and from_slot.container_slot != to_slot.container_slot
			):
				inventory_action_requested.emit(
					ACTION_MOVE,
					instance_id,
					to_slot.container_slot,
					{}
				)
		InventorySlot.SOURCE_GROUND:
			_request_confirmation(
				"Drop %s?" % str(descriptor.get("name", "item")),
				Callable(self, "_emit_inventory_action").bind(
				ACTION_DROP,
				instance_id,
				GameEnums.EquipmentSlot.NONE,
				{}
				)
			)

func _select_slot(slot: InventorySlot) -> void:
	_clear_selection()
	if not slot.has_item():
		return
	_selected_slot = slot
	slot.set_selected(true)
	show_item_details(slot.item_descriptor)
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
	_repair_button.disabled = true
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
	_refresh_repair_button()

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
	match slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT:
			_execute_inventory_action(
				ACTION_UNEQUIP,
				slot,
				slot.equipment_slot
			)
		InventorySlot.SOURCE_GROUND:
			_execute_inventory_action(
				ACTION_TAKE
					if descriptor.get("can_pick_up", true)
					else ACTION_INTERACT,
				slot,
				GameEnums.EquipmentSlot.NONE
			)
		InventorySlot.SOURCE_BACKPACK:
			if descriptor.get("can_load_magazine", false):
				_execute_inventory_action(
					ACTION_LOAD_MAGAZINE,
					slot,
					slot.container_slot
				)
			elif descriptor.get("can_equip", false):
				_execute_inventory_action(
					ACTION_EQUIP,
					slot,
					int(descriptor.get(
						"preferred_equipment_slot",
						GameEnums.EquipmentSlot.NONE
					))
				)
			elif descriptor.get("can_consume", false):
				_execute_inventory_action(
					ACTION_CONSUME,
					slot,
					GameEnums.EquipmentSlot.NONE
				)

func _execute_inventory_action(
	action_id: String,
	slot: InventorySlot,
	equipment_slot: int
) -> void:
	if action_id.is_empty() or not slot.has_item():
		return
	var instance_id := str(slot.item_descriptor.get("instance_id", ""))
	if action_id in [ACTION_CONSUME, ACTION_DROP]:
		_request_confirmation(
			"%s %s?" % [action_id.capitalize(), str(slot.item_descriptor.get("name", "item"))],
			Callable(self, "_emit_inventory_action").bind(
				action_id,
				instance_id,
				equipment_slot,
				{}
			)
		)
		return
	_emit_inventory_action(
		action_id,
		instance_id,
		equipment_slot,
		{}
	)

func _emit_inventory_action(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	payload: Dictionary
) -> void:
	inventory_action_requested.emit(action_id, instance_id, equipment_slot, payload)

func request_repair(
	target_instance_id: String,
	tool_instance_id: String,
	material_instance_id: String,
	repair_context: String = "field"
) -> void:
	var payload := {
			"target_instance_id": target_instance_id,
			"tool_instance_id": tool_instance_id,
			"material_instance_id": material_instance_id,
			"repair_context": repair_context,
		}
	_request_confirmation(
		"Commit a 30 minute %s repair?" % repair_context,
		Callable(self, "_emit_inventory_action").bind(
			ACTION_REPAIR,
			target_instance_id,
			GameEnums.EquipmentSlot.NONE,
			payload
		)
	)

func _request_confirmation(prompt: String, callback: Callable) -> void:
	_pending_confirm = callback
	_confirm_dialog.dialog_text = prompt
	_confirm_dialog.popup_centered()

func _commit_pending_confirmation() -> void:
	if _pending_confirm.is_valid():
		_pending_confirm.call()
	_pending_confirm = Callable()

func _execute_safe_default(slot: InventorySlot) -> void:
	if not slot.has_item():
		return
	match slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT:
			_execute_inventory_action(ACTION_UNEQUIP, slot, slot.equipment_slot)
		InventorySlot.SOURCE_GROUND:
			if slot.item_descriptor.get("can_pick_up", true):
				_execute_inventory_action(ACTION_TAKE, slot, GameEnums.EquipmentSlot.NONE)
		InventorySlot.SOURCE_BACKPACK:
			if slot.item_descriptor.get("can_equip", false):
				_execute_inventory_action(
					ACTION_EQUIP,
					slot,
					int(slot.item_descriptor.get("preferred_equipment_slot", GameEnums.EquipmentSlot.NONE))
				)

func _refresh_repair_button() -> void:
	_repair_button.disabled = true
	_repair_button.text = "REPAIR"
	if not is_instance_valid(_selected_slot) or not _selected_slot.has_item():
		return
	var target := _selected_slot.item_descriptor
	if (
		not bool(target.get("condition_enabled", true))
		or float(target.get("current_condition", 12.0)) >= 12.0
	):
		return
	var pair := _repair_pair_for(target)
	if pair.is_empty():
		_repair_button.text = "MISSING PARTS"
		return
	_repair_button.disabled = false
	_repair_button.text = "REPAIR +2"

func _activate_repair_tray() -> void:
	if not is_instance_valid(_selected_slot):
		return
	var pair := _repair_pair_for(_selected_slot.item_descriptor)
	if pair.is_empty():
		return
	request_repair(
		str(_selected_slot.item_descriptor.get("instance_id", "")),
		str(pair.tool.get("instance_id", "")),
		str(pair.material.get("instance_id", "")),
		"field"
	)

func _repair_pair_for(target: Dictionary) -> Dictionary:
	var recipes := {
		GameEnums.RepairDomain.FIREARM: ["gun_cleaner", "rag"],
		GameEnums.RepairDomain.TEXTILE: ["sewing_kit", "rag"],
		GameEnums.RepairDomain.RIGID_MECHANICAL: ["multitool", "bolts"],
	}
	var recipe: Array = recipes.get(int(target.get("repair_domain", GameEnums.RepairDomain.NONE)), [])
	var tool := _find_carried_descriptor(str(recipe[0])) if recipe.size() == 2 else {}
	var material := _find_carried_descriptor(str(recipe[1])) if recipe.size() == 2 else {}
	if tool.is_empty() or material.is_empty():
		tool = _find_carried_descriptor("pliers")
		material = _find_carried_descriptor("ducttape")
	if tool.is_empty() or material.is_empty():
		return {}
	return {"tool": tool, "material": material}

func _find_carried_descriptor(item_id: String) -> Dictionary:
	for descriptor: Dictionary in _snapshot.get("equipment", []):
		if str(descriptor.get("item_id", "")) == item_id:
			return descriptor
	for descriptor: Dictionary in _snapshot.get("backpack", []):
		if str(descriptor.get("item_id", "")) == item_id:
			return descriptor
	return {}

func _all_navigable_slots() -> Array[InventorySlot]:
	var slots: Array[InventorySlot] = []
	for slot: InventorySlot in equipment_slots_ui.values():
		if not slot.is_reservation:
			slots.append(slot)
	for slot: InventorySlot in backpack_slots_ui:
		if not slot.is_reservation:
			slots.append(slot)
	for slot: InventorySlot in ground_slots_ui:
		if not slot.is_reservation:
			slots.append(slot)
	return slots

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE:
		close_top_surface()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_F10 and key.shift_pressed and is_instance_valid(_selected_slot):
		_open_slot_context_menu(_selected_slot, _selected_slot.global_position)
		get_viewport().set_input_as_handled()
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER] and is_instance_valid(_selected_slot):
		_execute_safe_default(_selected_slot)
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_TAB:
		_focus_next_region(key.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if key.keycode in [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]:
		_focus_adjacent_slot(-1 if key.keycode in [KEY_LEFT, KEY_UP] else 1)
		get_viewport().set_input_as_handled()

func _focus_adjacent_slot(direction: int) -> void:
	var slots := _all_navigable_slots()
	if slots.is_empty():
		return
	var current := slots.find(get_viewport().gui_get_focus_owner())
	var next := 0 if current < 0 else posmod(current + direction, slots.size())
	slots[next].grab_focus()

func _focus_next_region(reverse: bool) -> void:
	var regions: Array = [
		Array(equipment_slots_ui.values()),
		backpack_slots_ui,
		ground_slots_ui,
	]
	var focused := get_viewport().gui_get_focus_owner()
	var region_index := 0
	for index in range(regions.size()):
		if focused in regions[index]:
			region_index = index
			break
	var direction := -1 if reverse else 1
	for offset in range(1, regions.size() + 1):
		var candidate_region: Array = regions[posmod(region_index + direction * offset, regions.size())]
		for candidate in candidate_region:
			if candidate is InventorySlot and not candidate.is_reservation:
				candidate.grab_focus()
				return

func _execute_secondary(slot: InventorySlot) -> void:
	if not slot.has_item():
		return
	match slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT, InventorySlot.SOURCE_BACKPACK:
			_execute_inventory_action(
				ACTION_DROP,
				slot,
				GameEnums.EquipmentSlot.NONE
			)
		InventorySlot.SOURCE_GROUND:
			_execute_primary(slot)

func _render_character_strip(loadout: Dictionary) -> void:
	if _pillar_list == null or _loadout_gauge_list == null or _identity_chip_row == null:
		return
	var character: Dictionary = _snapshot.get("character", {})
	if _archetype_label != null:
		_archetype_label.text = str(character.get("archetype_name", "Unknown")).to_upper()
	_clear_container(_pillar_list)
	_add_stat_gauge(
		_pillar_list,
		"Brawn",
		float(character.get("brawn", 6)),
		12.0,
		"%d / 12" % int(character.get("brawn", 6)),
		"health",
		HUDAssetLibrary.condition_icon("stable")
	)
	_add_stat_gauge(
		_pillar_list,
		"Finesse",
		float(character.get("finesse", 6)),
		12.0,
		"%d / 12" % int(character.get("finesse", 6)),
		"condition",
		HUDAssetLibrary.condition_icon("precaution_y")
	)
	_add_stat_gauge(
		_pillar_list,
		"Fortitude",
		float(character.get("fortitude", 6)),
		12.0,
		"%d / 12" % int(character.get("fortitude", 6)),
		"health",
		HUDAssetLibrary.condition_icon("healing")
	)
	_add_stat_gauge(
		_pillar_list,
		"Will",
		float(character.get("will", 6)),
		12.0,
		"%d / 12" % int(character.get("will", 6)),
		"condition",
		HUDAssetLibrary.condition_icon("precaution_o")
	)

	_clear_container(_loadout_gauge_list)
	_add_stat_gauge(
		_loadout_gauge_list,
		"Weight",
		float(loadout.get("weight", 0.0)),
		WEIGHT_DISPLAY_MAX,
		"%.1f" % float(loadout.get("weight", 0.0)),
		"warning",
		HUDAssetLibrary.condition_icon("precaution_y")
	)
	_add_stat_gauge(
		_loadout_gauge_list,
		"Bulk",
		float(loadout.get("bulk", 0.0)),
		BULK_DISPLAY_MAX,
		"%.1f" % float(loadout.get("bulk", 0.0)),
		"warning",
		HUDAssetLibrary.condition_icon("precaution_y")
	)
	_add_stat_gauge(
		_loadout_gauge_list,
		"Threat",
		float(loadout.get("threat", 0.0)),
		12.0,
		"%.1f / 12" % float(loadout.get("threat", 0.0)),
		"critical",
		HUDAssetLibrary.condition_icon("danger")
	)
	var insulation := float(loadout.get("insulation", 0.0))
	if insulation != 0.0:
		_add_stat_gauge(
			_loadout_gauge_list,
			"Insul",
			insulation,
			12.0,
			"%.1f / 12" % insulation,
			"condition",
			HUDAssetLibrary.condition_icon("precaution_o")
		)
	_add_stat_gauge(
		_loadout_gauge_list,
		"Prot B",
		float(loadout.get("protection_blunt", 0.0)),
		PROTECTION_DISPLAY_MAX,
		"%.1f" % float(loadout.get("protection_blunt", 0.0)),
		"health",
		HUDAssetLibrary.condition_icon("precaution_y")
	)
	_add_stat_gauge(
		_loadout_gauge_list,
		"Prot S",
		float(loadout.get("protection_sharp", 0.0)),
		PROTECTION_DISPLAY_MAX,
		"%.1f" % float(loadout.get("protection_sharp", 0.0)),
		"health",
		HUDAssetLibrary.condition_icon("precaution_y")
	)
	_add_stat_gauge(
		_loadout_gauge_list,
		"Prot R",
		float(loadout.get("protection_ballistic", 0.0)),
		PROTECTION_DISPLAY_MAX,
		"%.1f" % float(loadout.get("protection_ballistic", 0.0)),
		"health",
		HUDAssetLibrary.condition_icon("precaution_y")
	)

	_clear_container(_identity_chip_row)
	var occupation: Dictionary = character.get("occupation", {})
	if occupation.is_empty():
		_add_effect_chip(_identity_chip_row, "Occupation", "NONE", null, "neutral")
	else:
		_add_effect_chip(
			_identity_chip_row,
			str(occupation.get("display_name", "Occupation")),
			"",
			HUDAssetLibrary.condition_icon("stable"),
			"warning"
		)
	var bonus_key := "trai" + "ts"
	var bonus_list: Array = character.get(bonus_key, [])
	if bonus_list.is_empty():
		_add_effect_chip(_identity_chip_row, "Bonus", "NONE", null, "neutral")
	else:
		for entry in bonus_list:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var chip_data: Dictionary = entry
			_add_effect_chip(
				_identity_chip_row,
				str(chip_data.get("display_name", "Bonus")),
				"",
				HUDAssetLibrary.condition_icon("healing"),
				"neutral"
			)
	var penalty_list: Array = character.get("flaws", [])
	if penalty_list.is_empty():
		_add_effect_chip(_identity_chip_row, "Flaw", "NONE", null, "neutral")
	else:
		for entry in penalty_list:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var chip_data: Dictionary = entry
			_add_effect_chip(
				_identity_chip_row,
				str(chip_data.get("display_name", "Flaw")),
				"",
				HUDAssetLibrary.condition_icon("danger"),
				"critical"
			)


func _populate_item_stat_gauges(descriptor: Dictionary) -> void:
	_clear_container(_stat_gauge_list)
	if bool(descriptor.get("condition_enabled", true)):
		var condition := float(descriptor.get("current_condition", 12.0))
		var band := str(descriptor.get("condition_band", "Fine"))
		_add_stat_gauge(
			_stat_gauge_list,
			"Condition",
			condition,
			12.0,
			"%.1f / 12  %s" % [condition, band.to_upper()],
			"condition",
			HUDAssetLibrary.condition_icon("stable")
		)
	_add_stat_gauge(
		_stat_gauge_list,
		"Weight",
		float(descriptor.get("weight", 0.0)),
		WEIGHT_DISPLAY_MAX,
		"%.1f" % float(descriptor.get("weight", 0.0)),
		"warning",
		HUDAssetLibrary.condition_icon("precaution_y")
	)
	_add_stat_gauge(
		_stat_gauge_list,
		"Bulk",
		float(descriptor.get("bulk", 0.0)),
		BULK_DISPLAY_MAX,
		"%.1f" % float(descriptor.get("bulk", 0.0)),
		"warning",
		HUDAssetLibrary.condition_icon("precaution_y")
	)
	var threat := float(descriptor.get("threat", 0.0))
	if threat != 0.0:
		_add_stat_gauge(
			_stat_gauge_list,
			"Threat",
			threat,
			12.0,
			"%.1f / 12" % threat,
			"critical",
			HUDAssetLibrary.condition_icon("danger")
		)
	var insulation := float(descriptor.get("insulation", 0.0))
	if insulation != 0.0:
		_add_stat_gauge(
			_stat_gauge_list,
			"Insul",
			insulation,
			12.0,
			"%.1f / 12" % insulation,
			"condition",
			HUDAssetLibrary.condition_icon("precaution_o")
		)

	var item_type := int(descriptor.get("item_type", GameEnums.ItemType.JUNK))
	if item_type == GameEnums.ItemType.WEAPON:
		_add_stat_gauge(
			_stat_gauge_list,
			"Flesh",
			float(descriptor.get("flesh_damage", 0.0)),
			12.0,
			"%.1f" % float(descriptor.get("flesh_damage", 0.0)),
			"critical",
			HUDAssetLibrary.condition_icon("danger")
		)
		_add_stat_gauge(
			_stat_gauge_list,
			"Balance impact",
			float(descriptor.get("balance_impact", 0.0)),
			12.0,
			"%.1f" % float(descriptor.get("balance_impact", 0.0)),
			"condition",
			HUDAssetLibrary.condition_icon("healing")
		)
		_add_stat_gauge(
			_stat_gauge_list,
			"Pen",
			float(descriptor.get("armor_penetration", 0.0)),
			12.0,
			"%.1f" % float(descriptor.get("armor_penetration", 0.0)),
			"warning",
			HUDAssetLibrary.condition_icon("precaution_y")
		)
		_add_stat_gauge(
			_stat_gauge_list,
			"Accuracy",
			float(descriptor.get("accuracy_rating", 0.0)),
			12.0,
			"%.1f / 12" % float(descriptor.get("accuracy_rating", 0.0)),
			"health",
			HUDAssetLibrary.condition_icon("stable")
		)
		var optimal: Vector2i = descriptor.get("optimal_range_cells", Vector2i.ZERO)
		var maximum := int(descriptor.get("maximum_range_cells", 0))
		_add_stat_gauge(
			_stat_gauge_list,
			"Range",
			float(maximum),
			10.0,
			"%d-%d / %d" % [optimal.x, optimal.y, maximum],
			"travel",
			HUDAssetLibrary.condition_icon("precaution_o")
		)
		var max_magazine := int(descriptor.get("max_magazine", 0))
		if max_magazine <= 0:
			max_magazine = int(descriptor.get("magazine_capacity", 0))
		if max_magazine > 0:
			var loaded := int(descriptor.get("current_magazine", descriptor.get("loaded_rounds", 0)))
			_add_stat_gauge(
				_stat_gauge_list,
				"Loaded",
				float(loaded),
				float(max_magazine),
				"%d / %d" % [loaded, max_magazine],
				"condition",
				HUDAssetLibrary.condition_icon("healing")
			)

	var protection_blunt := float(descriptor.get("protection_blunt", 0.0))
	var protection_sharp := float(descriptor.get("protection_sharp", 0.0))
	var protection_ballistic := float(descriptor.get("protection_ballistic", 0.0))
	if protection_blunt + protection_sharp + protection_ballistic > 0.0:
		_add_stat_gauge(
			_stat_gauge_list,
			"Prot B",
			protection_blunt,
			PROTECTION_DISPLAY_MAX,
			"%.1f" % protection_blunt,
			"health",
			HUDAssetLibrary.condition_icon("precaution_y")
		)
		_add_stat_gauge(
			_stat_gauge_list,
			"Prot S",
			protection_sharp,
			PROTECTION_DISPLAY_MAX,
			"%.1f" % protection_sharp,
			"health",
			HUDAssetLibrary.condition_icon("precaution_y")
		)
		_add_stat_gauge(
			_stat_gauge_list,
			"Prot R",
			protection_ballistic,
			PROTECTION_DISPLAY_MAX,
			"%.1f" % protection_ballistic,
			"health",
			HUDAssetLibrary.condition_icon("precaution_y")
		)

	if item_type == GameEnums.ItemType.CONSUMABLE:
		_add_stat_gauge(
			_stat_gauge_list,
			"Potency",
			float(descriptor.get("consumable_potency", 0.0)),
			12.0,
			"%.1f / 12" % float(descriptor.get("consumable_potency", 0.0)),
			"health",
			HUDAssetLibrary.condition_icon("healing")
		)


func _populate_item_effect_chips(descriptor: Dictionary) -> void:
	_clear_container(_effect_chip_row)
	var capacity_bonus := int(descriptor.get("capacity_bonus", 0))
	if capacity_bonus != 0:
		_add_effect_chip(
			_effect_chip_row,
			"Capacity",
			"%+d" % capacity_bonus,
			HUDAssetLibrary.condition_icon("stable"),
			"warning"
		)
	if bool(descriptor.get("is_jammed", false)):
		_add_effect_chip(
			_effect_chip_row,
			"Jammed",
			"",
			HUDAssetLibrary.condition_icon("danger"),
			"critical"
		)
	var fault := float(descriptor.get("fault_chance", 0.0))
	if fault > 0.0:
		_add_effect_chip(
			_effect_chip_row,
			"Fault",
			"%.0f%%" % (fault * 100.0),
			HUDAssetLibrary.condition_icon("danger"),
			"critical"
		)

	var item_type := int(descriptor.get("item_type", GameEnums.ItemType.JUNK))
	if item_type == GameEnums.ItemType.CONSUMABLE:
		_add_effect_chip(
			_effect_chip_row,
			_enum_name(GameEnums.ConsumableEffect, int(descriptor.get(
				"consumable_effect",
				GameEnums.ConsumableEffect.RESTORE_HUNGER
			))),
			"",
			HUDAssetLibrary.condition_icon("healing"),
			"neutral"
		)

	var effect_specs := [
		{"key": "search_loot_bonus", "label": "Search Loot", "icon": "stable"},
		{"key": "search_safety_bonus", "label": "Search Safe", "icon": "precaution_y"},
		{"key": "search_sneak_bonus", "label": "Sneak", "icon": "precaution_o"},
		{"key": "camp_sleep_bonus", "label": "Camp Sleep", "icon": "healing"},
		{"key": "camp_shelter_bonus", "label": "Shelter", "icon": "precaution_y"},
		{"key": "camp_healing_bonus", "label": "Camp Heal", "icon": "healing"},
		{"key": "camp_concealment_bonus", "label": "Conceal", "icon": "precaution_o"},
		{"key": "camp_alertness_bonus", "label": "Alert", "icon": "danger"},
	]
	for spec: Dictionary in effect_specs:
		var amount := float(descriptor.get(str(spec["key"]), 0.0))
		if amount == 0.0:
			continue
		_add_effect_chip(
			_effect_chip_row,
			str(spec["label"]),
			"%+.1f" % amount,
			HUDAssetLibrary.condition_icon(str(spec["icon"])),
			"warning" if amount > 0.0 else "critical"
		)

	var stack_limit := int(descriptor.get("stack_limit", 1))
	if stack_limit > 1:
		_add_effect_chip(
			_effect_chip_row,
			"Stack",
			"%d / %d" % [
				int(descriptor.get("stack_count", 1)),
				stack_limit,
			],
			HUDAssetLibrary.condition_icon("stable"),
			"neutral"
		)
	_add_effect_chip(
		_effect_chip_row,
		"Size",
		_enum_name(GameEnums.ItemSize, int(descriptor.get(
			"item_size",
			GameEnums.ItemSize.SMALL
		))),
		null,
		"neutral"
	)


func _add_stat_gauge(
	container: Node,
	display_name: String,
	value: float,
	max_value: float,
	value_text: String,
	fill_kind: String,
	icon: Texture2D
) -> void:
	if container == null:
		return
	var row := STAT_GAUGE_SCENE.instantiate() as StatGaugeRow
	container.add_child(row)
	row.configure(display_name, value, max_value, value_text, fill_kind, icon)


func _add_effect_chip(
	container: Node,
	display_name: String,
	value_text: String,
	icon: Texture2D,
	tone: String
) -> void:
	if container == null:
		return
	var chip := EFFECT_CHIP_SCENE.instantiate() as EffectChip
	container.add_child(chip)
	chip.configure(display_name, value_text, icon, tone)


func _format_item_stats(descriptor: Dictionary) -> String:
	# Legacy text path retained for smoke tests / debug dumps.
	var lines := PackedStringArray()
	if bool(descriptor.get("condition_enabled", true)):
		lines.append("Condition %.2f / 12  |  %s  |  Fault %.2f%%" % [
			float(descriptor.get("current_condition", 12.0)),
			str(descriptor.get("condition_band", "Fine")),
			float(descriptor.get("fault_chance", 0.0)) * 100.0,
		])
		if bool(descriptor.get("is_jammed", false)):
			lines.append("MALFUNCTION: JAMMED")
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
		lines.append("Flesh %.1f  |  Impact %.1f  |  Pen %.1f" % [
			float(descriptor.get("flesh_damage", 0.0)),
			float(descriptor.get("balance_impact", 0.0)),
			float(descriptor.get("armor_penetration", 0.0)),
		])
		var optimal: Vector2i = descriptor.get("optimal_range_cells", Vector2i.ZERO)
		lines.append("Accuracy %.1f  |  Optimal %d-%d  |  Maximum %d" % [
			float(descriptor.get("accuracy_rating", 0.0)),
			optimal.x,
			optimal.y,
			int(descriptor.get("maximum_range_cells", 0)),
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
