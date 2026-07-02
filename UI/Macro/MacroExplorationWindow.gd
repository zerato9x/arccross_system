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
	equipment_slot: int
)
signal interaction_closed

const _InventorySlotScene := preload("res://UI/Inventory/InventorySlot.tscn")

@onready var _panel: PanelContainer = %ExplorationPanel
@onready var _content: HBoxContainer = %Content
@onready var _scene_root: Control = %SceneRoot
@onready var _background: TextureRect = %Background
@onready var _props_layer: Control = %PropsLayer
@onready var _poi_name_label: Label = %PoiNameLabel
@onready var _right_panel: VBoxContainer = %RightPanel
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: Label = %BodyLabel
@onready var _mode_tabs: HBoxContainer = %ModeTabs
@onready var _search_button: Button = %SearchButton
@onready var _camp_button: Button = %CampButton
@onready var _search_options_row: HBoxContainer = %SearchOptionsRow
@onready var _metric_box: VBoxContainer = %MetricBox
@onready var _drop_row: HBoxContainer = %DropRow
@onready var _ground_row: HBoxContainer = %GroundRow
@onready var _action_row: HBoxContainer = %ActionRow
@onready var _submit_button: Button = %SubmitButton
@onready var _rest_button: Button = %RestButton
@onready var _stop_rest_button: Button = %StopRestButton
@onready var _close_button: Button = %CloseButton

var _session: Dictionary = {}
var _active_mode := GameEnums.PoiAction.SEARCH
var _selected_search_option_id := "primary_search"
var _drop_targets: Dictionary = {}
var _ground_slots: Array[InventorySlot] = []
var _search_option_buttons: Dictionary = {}

func _ready() -> void:
	_panel.visible = false
	HUDAssetLibrary.apply_panel(_panel, "warning")
	HUDAssetLibrary.apply_panel(%InteractionBox as PanelContainer, "neutral")
	HUDAssetLibrary.apply_panel(%GroundBox as PanelContainer, "neutral")
	HUDAssetLibrary.apply_panel(%PoiNamePlate as PanelContainer, "neutral")
	HUDAssetLibrary.apply_label(_poi_name_label, "title")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_label(_body_label, "body")
	HUDAssetLibrary.apply_label(%InteractionHeader as Label, "muted")
	HUDAssetLibrary.apply_label(%DropHint as Label, "muted")
	HUDAssetLibrary.apply_label(%GroundHeader as Label, "muted")
	HUDAssetLibrary.apply_button(_search_button)
	HUDAssetLibrary.apply_button(_camp_button)
	HUDAssetLibrary.apply_button(_submit_button)
	HUDAssetLibrary.apply_button(_rest_button)
	HUDAssetLibrary.apply_button(_stop_rest_button)
	HUDAssetLibrary.apply_button(_close_button)
	_search_button.pressed.connect(func(): _set_mode(GameEnums.PoiAction.SEARCH))
	_camp_button.pressed.connect(func(): _set_mode(GameEnums.PoiAction.CAMP))
	_submit_button.pressed.connect(_submit_action)
	_rest_button.pressed.connect(func(): _submit_action_for(GameEnums.PoiAction.REST))
	_stop_rest_button.pressed.connect(func(): _submit_action_for(GameEnums.PoiAction.STOP_REST))
	_close_button.pressed.connect(close_window)
	close_window(false)

func open_landmark(session: Dictionary, inventory_snapshot: Dictionary = {}) -> void:
	_session = session.duplicate(true)
	if not inventory_snapshot.is_empty():
		_session["inventory_snapshot"] = inventory_snapshot.duplicate(true)
	_selected_search_option_id = str(
		_session.get("selected_search_option_id", "primary_search")
	)
	_active_mode = GameEnums.PoiAction.SEARCH
	_panel.visible = true
	_render_session()
	_request_preview()

func show_result(title: String, message: String) -> void:
	_panel.visible = true
	_clear_right_panel()
	_title_label.text = title
	_body_label.text = message
	_action_row.visible = true
	_submit_button.visible = false
	_rest_button.visible = false
	_stop_rest_button.visible = false

func close_window(notify: bool = true) -> void:
	if _panel:
		_panel.visible = false
	_session.clear()
	_clear_ground_slots()
	if notify:
		interaction_closed.emit()

func is_open() -> bool:
	return _panel != null and _panel.visible

func refresh_ground_items(ground_items: Array) -> void:
	_session["ground_items"] = ground_items.duplicate(true)
	_render_ground_items()

func show_poi_preview(action: GameEnums.PoiAction, metrics: Dictionary) -> void:
	if action != _active_mode:
		return
	for child in _metric_box.get_children():
		child.queue_free()
	for key in metrics.keys():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s: %.1f" % [str(key).to_upper(), float(metrics.get(key, 0.0))]
		var bar := ProgressBar.new()
		bar.max_value = GameEnums.SCALE_MAX
		bar.value = float(metrics.get(key, 0.0))
		bar.custom_minimum_size = Vector2(180, 12)
		HUDAssetLibrary.apply_progress_bar(bar, "health")
		row.add_child(label)
		row.add_child(bar)
		_metric_box.add_child(row)

func _render_session() -> void:
	_clear_right_panel()
	_title_label.text = "EXPLORATION"
	_body_label.text = str(_session.get("scene_descriptor", {}).get("zone_name", ""))
	_render_scene(_session.get("scene_descriptor", {}))
	_render_search_options()
	_render_drop_targets()
	_render_ground_items()
	_update_mode_buttons()
	_update_rest_buttons()

func _render_scene(descriptor: Dictionary) -> void:
	for child in _props_layer.get_children():
		child.queue_free()
	var bg_path: String = str(descriptor.get("background_path", ""))
	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		_background.texture = load(bg_path)
	else:
		_background.texture = load(EventBgCatalog.PLAINS_BG) if ResourceLoader.exists(EventBgCatalog.PLAINS_BG) else null
	_poi_name_label.text = str(_session.get("poi_name", "LOCATION")).to_upper()
	for prop in descriptor.get("props", []):
		if not prop is Dictionary:
			continue
		var sprite_path: String = str(prop.get("sprite_path", ""))
		if sprite_path.is_empty() or not ResourceLoader.exists(sprite_path):
			continue
		var sprite := TextureRect.new()
		sprite.texture = load(sprite_path)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.custom_minimum_size = Vector2(140, 140)
		var anchor: Vector2 = prop.get("anchor", Vector2(0.5, 0.5))
		sprite.position = Vector2(
			anchor.x * _scene_root.size.x - 70.0,
			anchor.y * _scene_root.size.y - 120.0
		)
		_props_layer.add_child(sprite)

func _render_search_options() -> void:
	for child in _search_options_row.get_children():
		child.queue_free()
	_search_option_buttons.clear()
	if _active_mode != GameEnums.PoiAction.SEARCH:
		_search_options_row.visible = false
		return
	_search_options_row.visible = true
	for option in _session.get("search_options", []):
		if not option is Dictionary:
			continue
		var option_id := str(option.get("id", ""))
		var button := Button.new()
		button.text = str(option.get("label", "Target"))
		button.toggle_mode = true
		button.button_pressed = option_id == _selected_search_option_id
		button.disabled = bool(option.get("locked", false))
		button.pressed.connect(func(): _select_search_option(option_id))
		HUDAssetLibrary.apply_button(button)
		_search_options_row.add_child(button)
		_search_option_buttons[option_id] = button

func _select_search_option(option_id: String) -> void:
	_selected_search_option_id = option_id
	_session["selected_search_option_id"] = option_id
	for id in _search_option_buttons:
		_search_option_buttons[id].button_pressed = id == option_id
	_render_drop_targets()
	_request_preview()

func _render_drop_targets() -> void:
	for child in _drop_row.get_children():
		child.queue_free()
	_drop_targets.clear()
	var targets: Array = (
		_session.get("search_drop_targets", [])
		if _active_mode == GameEnums.PoiAction.SEARCH
		else _session.get("camp_drop_targets", [])
	)
	var visible_targets: Array = []
	if _active_mode == GameEnums.PoiAction.SEARCH:
		for target in targets:
			if not target is Dictionary:
				continue
			if str(target.get("id", "")) == _selected_search_option_id:
				visible_targets.append(target)
				break
		if visible_targets.is_empty() and not targets.is_empty():
			visible_targets = [targets[0]]
	else:
		visible_targets = targets

	for target in visible_targets:
		if not target is Dictionary:
			continue
		var drop := InteractionDropTarget.new()
		drop.configure(
			str(target.get("label", "Target")),
			target.get("accepted_roles", [])
		)
		drop.item_dropped.connect(_on_item_dropped)
		if not str(target.get("assigned_instance_id", "")).is_empty():
			drop.set_assigned_instance(
				str(target.get("assigned_instance_id", "")),
				str(target.get("assigned_name", ""))
			)
		_drop_targets[str(target.get("id", drop.target_id))] = drop
		_drop_row.add_child(drop)

func _render_ground_items() -> void:
	_clear_ground_slots()
	var index := 0
	for descriptor in _session.get("ground_items", []):
		if not descriptor is Dictionary:
			continue
		var slot := _InventorySlotScene.instantiate() as InventorySlot
		slot.configure(InventorySlot.SOURCE_GROUND, index, "", null)
		slot.set_item(descriptor)
		slot.slot_clicked.connect(_on_ground_slot_clicked)
		_ground_row.add_child(slot)
		_ground_slots.append(slot)
		index += 1

func _clear_ground_slots() -> void:
	for slot in _ground_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_ground_slots.clear()

func _clear_right_panel() -> void:
	for child in _metric_box.get_children():
		child.queue_free()
	for child in _drop_row.get_children():
		child.queue_free()
	for child in _search_options_row.get_children():
		child.queue_free()
	_drop_targets.clear()
	_search_option_buttons.clear()

func _set_mode(mode: GameEnums.PoiAction) -> void:
	if mode == GameEnums.PoiAction.CAMP and not _session.get("camp_allowed", false):
		show_result(
			"CAMP UNAVAILABLE",
			str(_session.get("camp_block_reason", "This location is unsafe."))
		)
		return
	_active_mode = mode
	_render_search_options()
	_render_drop_targets()
	_update_mode_buttons()
	_update_rest_buttons()
	_request_preview()

func _update_mode_buttons() -> void:
	_search_button.disabled = _active_mode == GameEnums.PoiAction.SEARCH
	_camp_button.disabled = _active_mode == GameEnums.PoiAction.CAMP

func _update_rest_buttons() -> void:
	var resting := bool(_session.get("rest_in_progress", false))
	_rest_button.visible = _active_mode == GameEnums.PoiAction.CAMP and not resting
	_stop_rest_button.visible = _active_mode == GameEnums.PoiAction.CAMP and resting
	_submit_button.visible = _active_mode == GameEnums.PoiAction.SEARCH

func _on_item_dropped(_instance_id: String, _target_id: String) -> void:
	_request_preview()

func _on_ground_slot_clicked(slot_node: InventorySlot, event: InputEventMouseButton) -> void:
	if not slot_node.has_item():
		return
	if event.double_click:
		inventory_action_requested.emit(
			GameEnums.MACRO_INV_TAKE,
			str(slot_node.item_descriptor.get("instance_id", "")),
			GameEnums.EquipmentSlot.NONE
		)

func _selected_item_ids() -> Array:
	var ids: Array = []
	for drop in _drop_targets.values():
		var assigned: String = drop.get_assigned_instance()
		if not assigned.is_empty() and not ids.has(assigned):
			ids.append(assigned)
	return ids

func _request_preview() -> void:
	if _active_mode == GameEnums.PoiAction.SEARCH:
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
	_submit_action_for(_active_mode)

func _submit_action_for(action: GameEnums.PoiAction) -> void:
	poi_action_submitted.emit(
		action,
		_selected_item_ids(),
		_selected_search_option_id if action == GameEnums.PoiAction.SEARCH else ""
	)
