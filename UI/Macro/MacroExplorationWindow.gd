extends CanvasLayer
class_name MacroExplorationWindow

signal poi_action_submitted(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String
)
signal poi_preview_requested(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String
)
signal inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary
)
signal interaction_closed
signal node_map_requested

const _InventorySlotScene := preload("res://UI/Inventory/InventorySlot.tscn")
const _SlotActionBuilder := preload("res://UI/Inventory/InventorySlotActionBuilder.gd")
const _ContextMenuHost := preload("res://UI/Inventory/InventorySlotContextMenuHost.gd")
const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const SiteCatalog := preload("res://WorldCore/SiteCatalog.gd")
const _PROP_SPRITE_SIZE := 170.0
const _PROP_OUTLINE_PADDING := 4.0
const _PROP_OUTLINE_WIDTH := 3
const _PROP_LOOTED_MODULATE := Color(0.42, 0.42, 0.42, 1.0)
const _BACKGROUND_VERTICAL_SHIFT := -72.0
const _ACTOR_TOKEN_DISPLAY_SCALE := 0.55
## Half-cell height (128/2) times display scale keeps feet on fixture anchors.
const _ACTOR_TOKEN_FEET_Y_OFFSET := 64.0 * _ACTOR_TOKEN_DISPLAY_SCALE
const _ACTOR_TOKEN_WALK_SECONDS := 0.35

@onready var _panel: PanelContainer = %ExplorationPanel
@onready var _content: HBoxContainer = %Content
@onready var _inventory_panel: PanelContainer = %InteractionInventoryPanel
@onready var _inventory_header: Label = %InteractionInventoryHeader
@onready var _inventory_hint: Label = %InteractionInventoryHint
@onready var _inventory_grid: GridContainer = %InteractionItemsGrid
@onready var _scene_root: Control = %SceneRoot
@onready var _background: TextureRect = %Background
@onready var _props_layer: Control = %PropsLayer
@onready var _search_frame: PanelContainer = %SearchFrame
@onready var _poi_name_label: Label = %PoiNameLabel
@onready var _right_panel: VBoxContainer = %RightPanel
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: Label = %BodyLabel
@onready var _mode_tabs: HBoxContainer = %ModeTabs
@onready var _search_button: Button = %SearchButton
@onready var _camp_button: Button = %CampButton
@onready var _node_map_button: Button = %NodeMapButton
@onready var _search_options_row: HBoxContainer = %SearchOptionsRow
@onready var _interaction_box: PanelContainer = %InteractionBox
@onready var _metric_box: VBoxContainer = %MetricBox
@onready var _search_frame_header: Label = %SearchFrameHeader
@onready var _drop_hint: Label = %DropHint
@onready var _search_drop_row: HBoxContainer = %DropRow
@onready var _camp_drop_grid: GridContainer = %CampDropGrid
@onready var _ground_grid: GridContainer = %GroundGrid
@onready var _action_row: HBoxContainer = %ActionRow
@onready var _submit_button: Button = %SubmitButton
@onready var _rest_button: Button = %RestButton
@onready var _stop_rest_button: Button = %StopRestButton
@onready var _continue_button: Button = %ContinueButton
@onready var _fixture_list: VBoxContainer = %FixtureList
@onready var _verb_row: HBoxContainer = %VerbRow
@onready var _interaction_header: Label = %InteractionHeader
@onready var _token_layer: Control = %TokenLayer
@onready var _actor_token: HumanoidTokenView = %ActorToken
@onready var _progress_overlay: PanelContainer = %ProgressOverlay
@onready var _progress_label: Label = %ProgressLabel
@onready var _action_progress: ProgressBar = %ActionProgressBar

var _session: Dictionary = {}
var _active_mode := GameEnums.PoiAction.SEARCH
var _selected_search_option_id := "primary_search"
var _selected_fixture_id := ""
var _pending_verb := ""
var _action_busy := false
var _search_drop_targets: Dictionary = {}
var _camp_drop_targets: Dictionary = {}
var _ground_slots: Array[InventorySlot] = []
var _inventory_slots: Array[InventorySlot] = []
var _prop_entries: Dictionary = {}
var _showing_result := false
var _context_drop_target: InteractionDropTarget
var _context_slot: InventorySlot
var _token_tween: Tween
var _progress_tween: Tween

func _ready() -> void:
	_panel.visible = false
	HUDAssetLibrary.apply_panel(_panel, "warning")
	HUDAssetLibrary.apply_panel(_inventory_panel, "neutral")
	HUDAssetLibrary.apply_panel(_search_frame, "neutral")
	HUDAssetLibrary.apply_panel(_interaction_box, "neutral")
	HUDAssetLibrary.apply_panel(%GroundBox as PanelContainer, "neutral")
	HUDAssetLibrary.apply_panel(%PoiNamePlate as PanelContainer, "neutral")
	HUDAssetLibrary.apply_label(_inventory_header, "muted")
	HUDAssetLibrary.apply_label(_inventory_hint, "muted")
	HUDAssetLibrary.apply_label(_poi_name_label, "title")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_label(_body_label, "body")
	HUDAssetLibrary.apply_label(%InteractionHeader as Label, "muted")
	HUDAssetLibrary.apply_label(_search_frame_header, "muted")
	HUDAssetLibrary.apply_label(_drop_hint, "muted")
	HUDAssetLibrary.apply_label(%CampDropHint as Label, "muted")
	HUDAssetLibrary.apply_label(%GroundHeader as Label, "muted")
	HUDAssetLibrary.apply_label(_progress_label, "info")
	HUDAssetLibrary.apply_panel(_progress_overlay, "neutral")
	HUDAssetLibrary.apply_progress_bar(_action_progress, "discovery")
	HUDAssetLibrary.apply_button(_search_button)
	HUDAssetLibrary.apply_button(_camp_button)
	HUDAssetLibrary.apply_button(_node_map_button, "map")
	HUDAssetLibrary.apply_button(_submit_button)
	HUDAssetLibrary.apply_button(_rest_button)
	HUDAssetLibrary.apply_button(_stop_rest_button)
	HUDAssetLibrary.apply_button(_continue_button)
	_search_button.text = "Search"
	_camp_button.text = "Camp"
	_mode_tabs.visible = false
	_node_map_button.visible = false
	_continue_button.visible = false
	_progress_overlay.visible = false
	_submit_button.pressed.connect(_submit_action)
	_rest_button.pressed.connect(func(): _begin_fixture_verb(SiteCatalog.VERB_SLEEP))
	_stop_rest_button.pressed.connect(func(): _submit_action_for(GameEnums.PoiAction.STOP_REST))
	HUDAssetLibrary.apply_soft_edge(_panel, 0.18)
	_continue_button.pressed.connect(_on_continue_pressed)
	_scene_root.resized.connect(_rerender_prop_positions)
	_scene_root.clip_contents = true
	_apply_background_layout()
	if _actor_token != null:
		_actor_token.set_display_scale(_ACTOR_TOKEN_DISPLAY_SCALE)
		_actor_token.play_animation("Idle")
	_place_token_at(Vector2(0.12, 0.78), false)
	close_window(false)


func restyle() -> void:
	HUDAssetLibrary.apply_panel(_panel, "warning")
	HUDAssetLibrary.apply_panel(_inventory_panel, "neutral")
	HUDAssetLibrary.apply_panel(_search_frame, "neutral")
	HUDAssetLibrary.apply_panel(_interaction_box, "neutral")
	HUDAssetLibrary.apply_panel(%GroundBox as PanelContainer, "neutral")
	HUDAssetLibrary.apply_panel(%PoiNamePlate as PanelContainer, "neutral")
	HUDAssetLibrary.apply_label(_inventory_header, "muted")
	HUDAssetLibrary.apply_label(_inventory_hint, "muted")
	HUDAssetLibrary.apply_label(_poi_name_label, "title")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_label(_body_label, "body")
	HUDAssetLibrary.apply_label(%InteractionHeader as Label, "muted")
	HUDAssetLibrary.apply_label(_search_frame_header, "muted")
	HUDAssetLibrary.apply_label(_drop_hint, "muted")
	HUDAssetLibrary.apply_label(%CampDropHint as Label, "muted")
	HUDAssetLibrary.apply_label(%GroundHeader as Label, "muted")
	HUDAssetLibrary.apply_label(_progress_label, "info")
	HUDAssetLibrary.apply_panel(_progress_overlay, "neutral")
	HUDAssetLibrary.apply_progress_bar(_action_progress, "discovery")
	HUDAssetLibrary.apply_button(_search_button)
	HUDAssetLibrary.apply_button(_camp_button)
	HUDAssetLibrary.apply_button(_node_map_button, "map")
	HUDAssetLibrary.apply_button(_submit_button)
	HUDAssetLibrary.apply_button(_rest_button)
	HUDAssetLibrary.apply_button(_stop_rest_button)
	HUDAssetLibrary.apply_button(_continue_button)
	_search_button.text = "Search"
	_camp_button.text = "Camp"
	HUDAssetLibrary.apply_soft_edge(_panel, 0.18)


var _dock_host: Control


func dock_into(host: Control) -> void:
	_dock_host = host
	if _panel.get_parent() != host:
		var panel_parent := _panel.get_parent()
		if panel_parent:
			panel_parent.remove_child(_panel)
		host.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 0.0
	_panel.offset_top = 0.0
	_panel.offset_right = 0.0
	_panel.offset_bottom = 0.0
	_apply_docked_layout()
	_panel.visible = true
	visible = true


func present_as_stage_overlay(edge: float = 48.0) -> void:
	undock()
	layer = 41
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = edge
	_panel.offset_top = edge
	_panel.offset_right = -edge
	_panel.offset_bottom = -edge
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dock_host = null
	_apply_stage_overlay_layout()
	_panel.visible = true
	visible = true
	# Always expose an obvious leave path on the stage overlay.
	_continue_button.visible = true
	_continue_button.text = "Leave (Esc)"


func get_exploration_panel() -> PanelContainer:
	return _panel


func undock() -> void:
	if _panel.get_parent() != self:
		var panel_parent := _panel.get_parent()
		if panel_parent:
			panel_parent.remove_child(_panel)
		add_child(_panel)
	_panel.visible = false
	_dock_host = null
	layer = 22
	_apply_docked_layout()


func _apply_docked_layout() -> void:
	var compact := _dock_host != null and _dock_host.size.x < 800.0
	_inventory_panel.custom_minimum_size = Vector2(88.0 if compact else 180.0, 0.0)
	_inventory_grid.columns = 1 if compact else 3
	_scene_root.custom_minimum_size = Vector2(200.0 if compact else 500.0, 0.0)
	_right_panel.custom_minimum_size = Vector2(200.0 if compact else 260.0, 0.0)


func _apply_stage_overlay_layout() -> void:
	_inventory_panel.custom_minimum_size = Vector2(180.0, 0.0)
	_inventory_grid.columns = 3
	_scene_root.custom_minimum_size = Vector2(500.0, 0.0)
	_right_panel.custom_minimum_size = Vector2(260.0, 0.0)


func open_landmark(session: Dictionary, inventory_snapshot: Dictionary = {}) -> void:
	_session = session.duplicate(true)
	_selected_fixture_id = str(_session.get("selected_fixture_id", ""))
	_selected_search_option_id = str(
		_session.get("selected_search_option_id", "primary_search")
	)
	_pending_verb = ""
	_action_busy = false
	_active_mode = GameEnums.PoiAction.SEARCH
	_panel.visible = true
	_progress_overlay.visible = false
	_bind_actor_token_appearance(inventory_snapshot)
	_place_token_at(Vector2(0.12, 0.78), false)
	_render_session()
	_request_preview()
	_walk_token_to_selected_fixture()


func _bind_actor_token_appearance(inventory_snapshot: Dictionary) -> void:
	if _actor_token == null:
		return
	_actor_token.set_display_scale(_ACTOR_TOKEN_DISPLAY_SCALE)
	_actor_token.set_appearance(
		HumanoidVisualCatalog.appearance_from_equipment_snapshot(
			inventory_snapshot.get("equipment", [])
		)
	)
	_actor_token.play_animation("Idle")


func show_result(title: String, message: String) -> void:
	_showing_result = true
	_panel.visible = true
	_title_label.text = title
	_body_label.text = message
	_action_row.visible = true
	_submit_button.visible = false
	_rest_button.visible = false
	_stop_rest_button.visible = false
	_continue_button.visible = true

func _on_continue_pressed() -> void:
	if _showing_result:
		_showing_result = false
		_continue_button.visible = false
		_render_session()
		_request_preview()
		return
	# Stage overlay leave affordance.
	close_window(true)

func collapse_to_preview() -> void:
	if _panel:
		_panel.visible = false
	_showing_result = false
	if _continue_button:
		_continue_button.visible = false
	_session.clear()
	_clear_ground_slots()
	_clear_inventory_slots()
	_prop_entries.clear()

func close_window(notify: bool = true) -> void:
	collapse_to_preview()
	layer = 22
	if notify:
		interaction_closed.emit()

func is_expanded() -> bool:
	return _panel != null and _panel.visible

func is_open() -> bool:
	return is_expanded()

func refresh_session_state(
	available_items: Array,
	ground_items: Array
) -> void:
	_session["available_items"] = available_items.duplicate(true)
	_session["ground_items"] = _normalized_ground_items(ground_items)
	_render_interaction_gear()
	_render_ground_items()

func refresh_ground_items(ground_items: Array) -> void:
	_session["ground_items"] = _normalized_ground_items(ground_items)
	_render_ground_items()

func show_poi_preview(action: GameEnums.PoiAction, metrics: Dictionary) -> void:
	for child in _metric_box.get_children():
		child.queue_free()
	for key in metrics.keys():
		var row := HBoxContainer.new()
		var metric_key := str(key)
		var label := Label.new()
		label.text = "%s: %.1f" % [metric_key.to_upper(), float(metrics.get(key, 0.0))]
		HUDAssetLibrary.apply_label(label, _metric_label_role(metric_key, float(metrics.get(key, 0.0))))
		var bar := ProgressBar.new()
		bar.max_value = GameEnums.SCALE_MAX
		bar.value = float(metrics.get(key, 0.0))
		bar.custom_minimum_size = Vector2(200, 12)
		HUDAssetLibrary.apply_progress_bar(bar, _metric_fill_kind(metric_key))
		row.add_child(label)
		row.add_child(bar)
		_metric_box.add_child(row)


func _metric_fill_kind(metric_key: String) -> String:
	var key := metric_key.to_lower()
	if key in ["hazard", "risk", "danger", "threat"]:
		return "warning"
	if key in ["success", "yield", "loot", "find", "discovery"]:
		return "discovery"
	if key in ["cost", "exertion", "fatigue", "ap", "time"]:
		return "ap"
	if key in ["anomaly", "contamination", "infection"]:
		return "anomaly"
	if key in ["blood", "trauma", "damage"]:
		return "critical"
	return "health"


func _metric_label_role(metric_key: String, value: float) -> String:
	var key := metric_key.to_lower()
	if key in ["hazard", "risk", "danger", "threat"]:
		if value > 0.7:
			return "critical"
		if value > 0.3:
			return "caution"
		return "muted"
	if key in ["success", "yield", "loot", "find", "discovery"]:
		return "discovery"
	if key in ["cost", "exertion", "fatigue", "ap", "time"]:
		return "caution"
	if key in ["anomaly", "contamination", "infection"]:
		return "anomaly"
	if key in ["blood", "trauma", "damage"]:
		return "critical"
	return "info"

func _render_session() -> void:
	_clear_right_panel()
	var site: Dictionary = _session.get("site", {})
	_title_label.text = str(site.get("display_name", _session.get("poi_name", "Explore")))
	_body_label.text = str(_session.get("scene_descriptor", {}).get("zone_name", ""))
	_interaction_header.text = "Here"
	_render_scene(_session.get("scene_descriptor", {}))
	_render_fixture_browser()
	_render_interaction_gear()
	_render_search_options()
	_render_drop_targets()
	_render_ground_items()
	_update_mode_buttons()
	_update_rest_buttons()
	_update_mode_visibility()
	if layer >= 40:
		_continue_button.visible = true
		_continue_button.text = "Leave (Esc)"

func _render_interaction_gear() -> void:
	_clear_inventory_slots()
	var source: Array = _session.get("available_items", [])
	var role_filter := _current_role_filter()
	var rendered := 0
	for descriptor in source:
		if not descriptor is Dictionary:
			continue
		if not _descriptor_has_any_role(descriptor, role_filter):
			continue
		var slot := _InventorySlotScene.instantiate() as InventorySlot
		slot.configure(InventorySlot.SOURCE_BACKPACK, rendered, "", null)
		slot.set_item(descriptor)
		slot.slot_clicked.connect(_on_gear_slot_clicked)
		_inventory_grid.add_child(slot)
		_inventory_slots.append(slot)
		rendered += 1
	_inventory_header.text = "Your kit"
	_inventory_hint.text = (
		"Drag onto the selected thing, double-click to fill, or right-click for actions."
		if rendered > 0
		else _empty_inventory_hint()
	)

func _on_gear_slot_clicked(slot_node: InventorySlot, event: InputEventMouseButton) -> void:
	if not slot_node.has_item():
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_open_gear_context_menu(slot_node, event.global_position)
	elif event.double_click:
		_quick_assign_gear(slot_node.item_descriptor)

func _open_gear_context_menu(slot_node: InventorySlot, global_pos: Vector2) -> void:
	var entries := _SlotActionBuilder.build_for_exploration_gear(
		slot_node,
		_active_drop_targets()
	)
	if entries.is_empty():
		return
	_context_drop_target = null
	_context_slot = slot_node
	_show_slot_details(slot_node)
	_ContextMenuHost.request_open(
		get_tree(),
		global_pos,
		_SlotActionBuilder.menu_header_for_slot(slot_node),
		entries,
		_on_slot_context_menu_action,
		slot_node.item_descriptor
	)

func _open_ground_context_menu(slot_node: InventorySlot, global_pos: Vector2) -> void:
	var entries := _SlotActionBuilder.build_for_exploration_ground(slot_node)
	if entries.is_empty():
		return
	_context_drop_target = null
	_context_slot = slot_node
	_show_slot_details(slot_node)
	_ContextMenuHost.request_open(
		get_tree(),
		global_pos,
		_SlotActionBuilder.menu_header_for_slot(slot_node),
		entries,
		_on_slot_context_menu_action,
		slot_node.item_descriptor
	)

func _open_drop_target_context_menu(
	drop: InteractionDropTarget,
	global_pos: Vector2
) -> void:
	var entries := _SlotActionBuilder.build_for_drop_target(drop)
	if entries.is_empty():
		return
	_context_slot = null
	_context_drop_target = drop
	var payload := drop.get_assignment_payload()
	_show_drop_target_details(drop)
	_ContextMenuHost.request_open(
		get_tree(),
		global_pos,
		_SlotActionBuilder.menu_header_for_drop_target(drop),
		entries,
		_on_slot_context_menu_action,
		payload
	)

func _on_slot_context_menu_action(entry: Dictionary) -> void:
	match str(entry.get("kind", "")):
		_SlotActionBuilder.KIND_EXAMINE:
			if _context_drop_target != null:
				_show_drop_target_details(_context_drop_target)
			elif _context_slot != null:
				_show_slot_details(_context_slot)
		_SlotActionBuilder.KIND_INVENTORY:
			if _context_slot == null or not _context_slot.has_item():
				return
			inventory_action_requested.emit(
				str(entry.get("action_id", "")),
				str(_context_slot.item_descriptor.get("instance_id", "")),
				int(entry.get("equipment_slot", GameEnums.EquipmentSlot.NONE)),
				{}
			)
		_SlotActionBuilder.KIND_EXPLORATION_ASSIGN:
			_assign_gear_to_target(entry)
		_SlotActionBuilder.KIND_EXPLORATION_CLEAR:
			_clear_drop_target(entry)

func _assign_gear_to_target(entry: Dictionary) -> void:
	var drop: InteractionDropTarget = entry.get("drop_target", null)
	if drop == null or _context_slot == null or not _context_slot.has_item():
		return
	var descriptor: Dictionary = _context_slot.item_descriptor
	if not drop.accepts_descriptor(descriptor):
		return
	drop.set_assigned_instance(
		str(descriptor.get("instance_id", "")),
		str(descriptor.get("name", "")),
		str(descriptor.get("sprite_path", ""))
	)
	_persist_drop_assignments()
	_request_preview()

func _clear_drop_target(entry: Dictionary) -> void:
	var drop: InteractionDropTarget = entry.get("drop_target", null)
	if drop == null:
		return
	var cleared_id := drop.get_assigned_instance()
	if cleared_id.is_empty():
		return
	drop.clear_assignment()
	drop.item_cleared.emit(cleared_id, drop.target_id)
	_persist_drop_assignments()
	_request_preview()

func _show_drop_target_details(drop: InteractionDropTarget) -> void:
	var payload := drop.get_assignment_payload()
	if payload.is_empty():
		return
	_body_label.text = str(payload.get("name", drop.target_id))


func _show_slot_details(slot_node: InventorySlot) -> void:
	if slot_node == null or not slot_node.has_item():
		return
	var descriptor: Dictionary = slot_node.item_descriptor
	_body_label.text = "%s\n%s" % [
		str(descriptor.get("name", "Item")),
		str(descriptor.get("description", "")),
	]

func _quick_assign_gear(descriptor: Dictionary) -> void:
	var instance_id := str(descriptor.get("instance_id", ""))
	if instance_id.is_empty():
		return
	for drop in _active_drop_targets():
		if not drop.get_assigned_instance().is_empty():
			continue
		if not drop.accepts_descriptor(descriptor):
			continue
		drop.set_assigned_instance(
			instance_id,
			str(descriptor.get("name", "")),
			str(descriptor.get("sprite_path", ""))
		)
		_persist_drop_assignments()
		_request_preview()
		return

func _active_drop_targets() -> Array:
	var drops: Array = []
	for child in _search_drop_row.get_children():
		if child is InteractionDropTarget:
			drops.append(child)
	return drops

func _empty_inventory_hint() -> String:
	return "Drag a tool, bedroll, or trap onto the selected thing."

func _current_role_filter() -> Array[int]:
	var fixture := _selected_fixture()
	var roles: Array[int] = []
	for role in fixture.get("accepted_roles", []):
		roles.append(int(role))
	if roles.is_empty():
		return [
			GameEnums.InteractionItemRole.SEARCH_TOOL,
			GameEnums.InteractionItemRole.CAMP_GEAR,
			GameEnums.InteractionItemRole.TRAP_GEAR,
		]
	return roles

func _descriptor_has_any_role(descriptor: Dictionary, roles: Array[int]) -> bool:
	if roles.is_empty():
		return true
	var descriptor_roles: Array = descriptor.get(
		"interaction_roles",
		descriptor.get("roles", [])
	)
	for role in roles:
		if descriptor_roles.has(role):
			return true
	return false

func _get_ground_items() -> Array:
	return _session.get("ground_items", [])

func _normalized_ground_items(items: Array) -> Array:
	var normalized: Array = []
	for entry in items:
		var descriptor := _normalize_ground_descriptor(entry)
		if not descriptor.is_empty():
			normalized.append(descriptor)
	return normalized

func _normalize_ground_descriptor(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var source: Dictionary = entry
	if source.has("sprite_path") and source.has("instance_id"):
		return source.duplicate(true)
	if not source.has("definition"):
		return {}
	var item := ItemData.from_runtime_state(source)
	return {
		"instance_id": item.instance_id,
		"name": item.display_name,
		"sprite_path": item.get_inventory_sprite_path(),
		"interaction_roles": item.interaction_roles.duplicate(),
		"roles": item.interaction_roles.duplicate(),
		"size_cost": item.get_inventory_cost(),
	}

func _render_scene(descriptor: Dictionary) -> void:
	for child in _props_layer.get_children():
		child.queue_free()
	_prop_entries.clear()
	_apply_background_layout()
	var bg_path: String = str(descriptor.get("background_path", ""))
	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		_background.texture = load(bg_path)
	else:
		_background.texture = (
			load(EventBgCatalog.PLAINS_BG)
			if ResourceLoader.exists(EventBgCatalog.PLAINS_BG)
			else null
		)
	_poi_name_label.text = str(_session.get("poi_name", "LOCATION")).to_upper()
	if not _session.get("has_search", true):
		return

	var searched_targets: Array = _session.get("searched_targets", [])
	for prop in descriptor.get("props", []):
		if not prop is Dictionary:
			continue
		var sprite_path: String = str(prop.get("sprite_path", ""))
		if sprite_path.is_empty() or not ResourceLoader.exists(sprite_path):
			continue
		var option_id := str(prop.get("search_option_id", prop.get("id", "")))
		var depleted := searched_targets.has(option_id)
		var label := str(prop.get("label", "Search Target"))
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(
			_PROP_SPRITE_SIZE + _PROP_OUTLINE_PADDING * 2.0,
			_PROP_SPRITE_SIZE + _PROP_OUTLINE_PADDING * 2.0
		)
		var anchor: Vector2 = prop.get("anchor", Vector2(0.5, 0.5))
		wrapper.position = Vector2(
			anchor.x * _props_layer.size.x - wrapper.custom_minimum_size.x * 0.5,
			anchor.y * _props_layer.size.y - wrapper.custom_minimum_size.y * 0.85
		)

		var outline := Panel.new()
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.add_theme_stylebox_override("panel", _build_prop_outline_style(false))
		wrapper.add_child(outline)

		var button := TextureButton.new()
		button.texture_normal = load(sprite_path)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(_PROP_SPRITE_SIZE, _PROP_SPRITE_SIZE)
		button.position = Vector2(_PROP_OUTLINE_PADDING, _PROP_OUTLINE_PADDING)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = depleted
		button.tooltip_text = (
			label + " (LOOTED)" if depleted else label
		)
		if depleted:
			button.modulate = _PROP_LOOTED_MODULATE
		if not depleted:
			button.pressed.connect(func(): _select_search_option(option_id))
		wrapper.add_child(button)
		_props_layer.add_child(wrapper)
		_prop_entries[option_id] = {
			"wrapper": wrapper,
			"outline": outline,
			"button": button,
			"depleted": depleted,
		}

	if not _prop_entries.is_empty():
		if (
			_selected_search_option_id.is_empty()
			or _is_option_depleted(_selected_search_option_id)
			or not _prop_entries.has(_selected_search_option_id)
		):
			_select_first_available_option()
		else:
			_update_prop_selection_highlight()

func _apply_background_layout() -> void:
	_background.offset_top = _BACKGROUND_VERTICAL_SHIFT
	_background.offset_bottom = -_BACKGROUND_VERTICAL_SHIFT
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

func _build_prop_outline_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.set_corner_radius_all(4)
	style.set_border_width_all(_PROP_OUTLINE_WIDTH)
	style.border_color = (
		HUDAssetLibrary.COLOR_INFO if selected else Color.TRANSPARENT
	)
	return style

func _is_option_depleted(option_id: String) -> bool:
	if not _prop_entries.has(option_id):
		return _session.get("searched_targets", []).has(option_id)
	return bool(_prop_entries[option_id].get("depleted", false))

func _select_first_available_option() -> void:
	for option_id in _prop_entries:
		if not _is_option_depleted(option_id):
			_select_search_option(option_id)
			return
	_selected_search_option_id = ""
	_update_prop_selection_highlight()

func _update_prop_selection_highlight() -> void:
	for option_id in _prop_entries:
		var entry: Dictionary = _prop_entries[option_id]
		var outline: Panel = entry.get("outline")
		if outline == null:
			continue
		var selected: bool = (
			option_id == _selected_search_option_id
			and not bool(entry.get("depleted", false))
		)
		outline.add_theme_stylebox_override("panel", _build_prop_outline_style(selected))

func _render_search_options() -> void:
	for child in _search_options_row.get_children():
		child.queue_free()
	_search_options_row.visible = false

func _select_search_option(option_id: String) -> void:
	if _is_option_depleted(option_id):
		return
	_selected_search_option_id = option_id
	_session["selected_search_option_id"] = option_id
	_update_prop_selection_highlight()
	_request_preview()

func _render_drop_targets() -> void:
	_persist_drop_assignments()
	_clear_drop_targets()
	var targets: Array = _session.get(
		"fixture_drop_targets",
		_session.get("search_drop_targets", [])
	)
	if targets.is_empty():
		targets = _session.get("camp_drop_targets", [])
	for target in targets:
		_add_drop_target(target, _search_drop_row, _search_drop_targets)

func _add_drop_target(
	target: Variant,
	parent: Container,
	registry: Dictionary
) -> void:
	if not target is Dictionary:
		return
	var drop := InteractionDropTarget.new()
	drop.configure(
		str(target.get("id", "")),
		str(target.get("label", "Target")),
		target.get("accepted_roles", [])
	)
	drop.item_dropped.connect(_on_item_dropped)
	drop.item_cleared.connect(_on_item_cleared)
	drop.context_menu_requested.connect(
		_on_drop_target_context_menu_requested.bind(drop)
	)
	var saved_assignments: Dictionary = _session.get("gear_assignments", {})
	var target_id := str(target.get("id", ""))
	if saved_assignments.has(target_id):
		var saved: Dictionary = saved_assignments[target_id]
		drop.set_assigned_instance(
			str(saved.get("instance_id", "")),
			str(saved.get("name", "")),
			str(saved.get("sprite_path", ""))
		)
	elif not str(target.get("assigned_instance_id", "")).is_empty():
		drop.set_assigned_instance(
			str(target.get("assigned_instance_id", "")),
			str(target.get("assigned_name", ""))
		)
	registry[str(target.get("id", drop.target_id))] = drop
	parent.add_child(drop)

func _render_ground_items() -> void:
	_clear_ground_slots()
	var index := 0
	for entry in _get_ground_items():
		var descriptor := _normalize_ground_descriptor(entry)
		if descriptor.is_empty():
			continue
		var slot := _InventorySlotScene.instantiate() as InventorySlot
		slot.configure(InventorySlot.SOURCE_GROUND, index, "", null)
		slot.set_item(descriptor)
		slot.slot_clicked.connect(_on_ground_slot_clicked)
		_ground_grid.add_child(slot)
		_ground_slots.append(slot)
		index += 1

func _clear_ground_slots() -> void:
	for slot in _ground_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_ground_slots.clear()
	if _ground_grid:
		for child in _ground_grid.get_children():
			child.queue_free()

func _clear_inventory_slots() -> void:
	for slot in _inventory_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_inventory_slots.clear()
	if _inventory_grid:
		for child in _inventory_grid.get_children():
			child.queue_free()

func _clear_drop_targets() -> void:
	for child in _search_drop_row.get_children():
		_search_drop_row.remove_child(child)
		child.queue_free()
	for child in _camp_drop_grid.get_children():
		_camp_drop_grid.remove_child(child)
		child.queue_free()
	_search_drop_targets.clear()
	_camp_drop_targets.clear()

func _clear_right_panel() -> void:
	for child in _metric_box.get_children():
		child.queue_free()
	_clear_drop_targets()
	for child in _search_options_row.get_children():
		child.queue_free()
	if _fixture_list:
		for child in _fixture_list.get_children():
			child.queue_free()
	if _verb_row:
		for child in _verb_row.get_children():
			child.queue_free()
	_prop_entries.clear()

func _set_mode(mode: GameEnums.PoiAction) -> void:
	_active_mode = mode
	_render_interaction_gear()
	_render_drop_targets()
	_update_mode_buttons()
	_update_rest_buttons()
	_update_mode_visibility()
	_request_preview()


func _update_mode_visibility() -> void:
	_mode_tabs.visible = false
	_search_frame.visible = true
	_interaction_box.visible = true
	_search_frame_header.text = "Outlook"
	HUDAssetLibrary.apply_label(_search_frame_header, "discovery")
	_drop_hint.text = "Select a thing in the place, then Search / Sleep / Trap."
	HUDAssetLibrary.apply_label(_drop_hint, "muted")


func _update_mode_buttons() -> void:
	_search_button.visible = false
	_camp_button.visible = false


func _update_rest_buttons() -> void:
	var resting := bool(_session.get("rest_in_progress", false))
	var fixture := _selected_fixture()
	var verbs: Array = fixture.get("verbs", [])
	_rest_button.visible = false
	_stop_rest_button.visible = resting
	_submit_button.visible = false
	_stop_rest_button.text = "Pack Up"
	_render_verb_row(verbs, resting)


func _on_item_dropped(_instance_id: String, _target_id: String) -> void:
	_persist_drop_assignments()
	_request_preview()


func _on_item_cleared(_instance_id: String, _target_id: String) -> void:
	_persist_drop_assignments()
	_request_preview()


func _persist_drop_assignments() -> void:
	var assignments: Dictionary = {}
	var containers: Array[Container] = [_search_drop_row, _camp_drop_grid]
	for container in containers:
		for child in container.get_children():
			if child is InteractionDropTarget:
				var payload: Dictionary = child.get_assignment_payload()
				if not payload.is_empty():
					assignments[child.target_id] = payload
	_session["gear_assignments"] = assignments


func _on_drop_target_context_menu_requested(
	global_pos: Vector2,
	drop: InteractionDropTarget
) -> void:
	_open_drop_target_context_menu(drop, global_pos)


func _on_ground_slot_clicked(slot_node: InventorySlot, event: InputEventMouseButton) -> void:
	if not slot_node.has_item():
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_open_ground_context_menu(slot_node, event.global_position)
	elif event.double_click:
		inventory_action_requested.emit(
			GameEnums.MACRO_INV_TAKE,
			str(slot_node.item_descriptor.get("instance_id", "")),
			GameEnums.EquipmentSlot.NONE,
			{}
		)


func _selected_fixture() -> Dictionary:
	var site: Dictionary = _session.get("site", {})
	return SiteCatalog.fixture_by_id(site, _selected_fixture_id)


func _render_fixture_browser() -> void:
	if _fixture_list == null:
		return
	for child in _fixture_list.get_children():
		child.queue_free()
	var site: Dictionary = _session.get("site", {})
	var rooms: Array = site.get("rooms", [])
	var searched: Array = _session.get("searched_targets", [])
	for room in rooms:
		if not room is Dictionary:
			continue
		if bool(room.get("deferred", false)):
			continue
		var room_id := str(room.get("id", ""))
		var room_label := Label.new()
		room_label.text = str(room.get("label", room_id)).to_upper()
		HUDAssetLibrary.apply_label(room_label, "caution")
		_fixture_list.add_child(room_label)
		for fixture in SiteCatalog.fixtures_in_room(site, room_id):
			if not fixture is Dictionary:
				continue
			var fixture_id := str(fixture.get("id", ""))
			var option_id := str(fixture.get("search_option_id", ""))
			var depleted := (
				not option_id.is_empty() and searched.has(option_id)
			)
			var button := Button.new()
			button.text = str(fixture.get("label", fixture_id))
			if depleted:
				button.text += " (looted)"
			button.set_meta("fixture_id", fixture_id)
			button.disabled = depleted and SiteCatalog.VERB_SEARCH in fixture.get("verbs", []) and fixture.get("verbs", []).size() == 1
			button.toggle_mode = true
			button.button_pressed = fixture_id == _selected_fixture_id
			HUDAssetLibrary.apply_button(button)
			button.pressed.connect(_on_fixture_pressed.bind(fixture_id))
			_fixture_list.add_child(button)
	if _selected_fixture_id.is_empty():
		_selected_fixture_id = str(site.get("fixtures", [{}])[0].get("id", "")) if not site.get("fixtures", []).is_empty() else ""
	_sync_fixture_selection()


func _on_fixture_pressed(fixture_id: String) -> void:
	_select_fixture(fixture_id)


func _select_fixture(fixture_id: String) -> void:
	_selected_fixture_id = fixture_id
	_session["selected_fixture_id"] = fixture_id
	var fixture := _selected_fixture()
	var option_id := str(fixture.get("search_option_id", ""))
	if not option_id.is_empty():
		_selected_search_option_id = option_id
		_session["selected_search_option_id"] = option_id
	_session["fixture_drop_targets"] = _PoiController.build_fixture_drop_targets(
		_session.get("site", {}),
		fixture_id
	)
	_body_label.text = str(fixture.get("description", ""))
	_sync_fixture_selection()
	_render_interaction_gear()
	_render_drop_targets()
	_update_rest_buttons()
	_walk_token_to_selected_fixture()
	_request_preview()


func _sync_fixture_selection() -> void:
	if _fixture_list == null:
		return
	for child in _fixture_list.get_children():
		if child is Button:
			var button := child as Button
			button.button_pressed = str(button.get_meta("fixture_id", "")) == _selected_fixture_id


func _render_verb_row(verbs: Array, resting: bool) -> void:
	if _verb_row == null:
		return
	for child in _verb_row.get_children():
		child.queue_free()
	if resting:
		return
	for verb in verbs:
		var button := Button.new()
		match str(verb):
			SiteCatalog.VERB_SEARCH:
				button.text = "Search"
			SiteCatalog.VERB_SLEEP:
				button.text = "Sleep here"
			SiteCatalog.VERB_TRAP:
				button.text = "Set trap"
			_:
				button.text = str(verb).capitalize()
		HUDAssetLibrary.apply_button(button)
		button.disabled = _action_busy
		button.pressed.connect(_begin_fixture_verb.bind(str(verb)))
		_verb_row.add_child(button)


func _place_token_at(anchor: Vector2, animate: bool) -> void:
	if _actor_token == null or _token_layer == null:
		return
	var target := Vector2(
		anchor.x * maxf(_token_layer.size.x, 1.0),
		anchor.y * maxf(_token_layer.size.y, 1.0) - _ACTOR_TOKEN_FEET_Y_OFFSET
	)
	if _token_tween != null and _token_tween.is_valid():
		_token_tween.kill()
		_actor_token.play_animation("Idle", false)
	if animate:
		var move_delta := target - _actor_token.position
		_actor_token.face_direction(move_delta)
		_actor_token.play_animation("Walk")
		_token_tween = create_tween()
		_token_tween.tween_property(
			_actor_token,
			"position",
			target,
			_ACTOR_TOKEN_WALK_SECONDS
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_token_tween.finished.connect(
			func() -> void:
				if _actor_token != null:
					_actor_token.play_animation("Idle")
		)
	else:
		_actor_token.position = target
		_actor_token.play_animation("Idle", false)


func _walk_token_to_selected_fixture() -> void:
	var fixture := _selected_fixture()
	var anchor: Vector2 = fixture.get("anchor", Vector2(0.5, 0.65))
	if fixture.is_empty():
		anchor = Vector2(0.12, 0.78)
	_place_token_at(anchor, true)


func _begin_fixture_verb(verb: String) -> void:
	if _action_busy:
		return
	var fixture := _selected_fixture()
	if fixture.is_empty():
		return
	if verb == SiteCatalog.VERB_SLEEP and not bool(_session.get("camp_allowed", false)):
		show_result(
			"SLEEP UNAVAILABLE",
			str(_session.get("camp_block_reason", "This location is unsafe."))
		)
		return
	_pending_verb = verb
	_walk_token_to_selected_fixture()
	var minutes := GameTimeRules.ACTION_MINUTES
	var label := "Working…"
	var action := GameEnums.PoiAction.SEARCH
	match verb:
		SiteCatalog.VERB_SEARCH:
			minutes = int(fixture.get("minutes_search", GameTimeRules.SEARCH_MINUTES))
			label = "Searching %s…" % str(fixture.get("label", "fixture"))
			action = GameEnums.PoiAction.SEARCH
			_active_mode = GameEnums.PoiAction.SEARCH
			var option_id := str(fixture.get("search_option_id", ""))
			if not option_id.is_empty():
				_selected_search_option_id = option_id
		SiteCatalog.VERB_SLEEP:
			minutes = GameTimeRules.ACTION_MINUTES * 2
			label = "Settling in to sleep…"
			action = GameEnums.PoiAction.REST
			_active_mode = GameEnums.PoiAction.CAMP
		SiteCatalog.VERB_TRAP:
			minutes = GameTimeRules.ACTION_MINUTES
			label = "Arming trap…"
			action = GameEnums.PoiAction.CAMP
			_active_mode = GameEnums.PoiAction.CAMP
	_play_action_progress(label, minutes, action)


func _play_action_progress(label: String, minutes: int, action: GameEnums.PoiAction) -> void:
	_action_busy = true
	_progress_overlay.visible = true
	_progress_label.text = "%s  ·  %d min" % [label, minutes]
	_action_progress.value = 0.0
	if _progress_tween != null and _progress_tween.is_valid():
		_progress_tween.kill()
	var duration := clampf(float(minutes) / 60.0, 0.45, 1.8)
	_progress_tween = create_tween()
	_progress_tween.tween_property(_action_progress, "value", 1.0, duration)
	_progress_tween.tween_callback(func():
		_progress_overlay.visible = false
		_action_busy = false
		_submit_action_for(action)
	)


func _selected_item_ids() -> Array:
	var ids: Array = []
	var containers: Array[Container] = [_search_drop_row, _camp_drop_grid]
	for container in containers:
		for child in container.get_children():
			if child is InteractionDropTarget:
				var assigned: String = child.get_assigned_instance()
				if not assigned.is_empty() and not ids.has(assigned):
					ids.append(assigned)
	return ids

func _request_preview() -> void:
	var fixture := _selected_fixture()
	var verbs: Array = fixture.get("verbs", [])
	if SiteCatalog.VERB_SEARCH in verbs and not str(fixture.get("search_option_id", "")).is_empty():
		poi_preview_requested.emit(
			GameEnums.PoiAction.SEARCH,
			_selected_item_ids(),
			_selected_search_option_id
		)
	else:
		poi_preview_requested.emit(
			GameEnums.PoiAction.CAMP,
			_selected_item_ids(),
			""
		)

func _submit_action() -> void:
	if _pending_verb == SiteCatalog.VERB_SLEEP:
		_submit_action_for(GameEnums.PoiAction.REST)
	elif _pending_verb == SiteCatalog.VERB_TRAP:
		_submit_action_for(GameEnums.PoiAction.CAMP)
	else:
		_submit_action_for(GameEnums.PoiAction.SEARCH)

func _submit_action_for(action: GameEnums.PoiAction) -> void:
	poi_action_submitted.emit(
		action,
		_selected_item_ids(),
		_selected_search_option_id if action == GameEnums.PoiAction.SEARCH else ""
	)

func _rerender_prop_positions() -> void:
	if _session.is_empty():
		return
	_render_scene(_session.get("scene_descriptor", {}))
	_walk_token_to_selected_fixture()
