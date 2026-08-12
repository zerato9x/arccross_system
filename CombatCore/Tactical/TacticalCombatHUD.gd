extends Control
class_name TacticalCombatHUD

signal sector_selected(coords: Vector2i)
signal action_selected(action_id: String)
signal action_confirmed
signal selection_cancelled
signal item_selected(instance_id: String)
signal wound_selected(wound_id: String)
signal body_region_selected(region: int)
signal route_context_selected(target_sector: Vector2i, approach_path: Array[Vector2i])
signal context_requested(coords: Vector2i)

enum Availability { HIDDEN, DISABLED, AVAILABLE }

const HUD_ASSETS := preload("res://PresentationCore/HUDAssetLibrary.gd")
const INTERACTION_STATE_SCRIPT := preload("res://CombatCore/Tactical/CombatInteractionState.gd")
const _SharedCornerPanelState := preload("res://PresentationCore/CornerPanelStateContract.gd")
const VISUAL_PROFILE = preload(
	"res://CombatCore/Tactical/readable_moody_visual_profile.tres"
)
const _SnapshotPresenter := preload(
	"res://CombatCore/Tactical/TacticalCombatSnapshotPresenter.gd"
)
const _InteractionCoordinator := preload(
	"res://CombatCore/Tactical/TacticalCombatInteractionCoordinator.gd"
)

@onready var arena_view: TacticalArenaView = %TacticalArenaView
@onready var initiative_row: HBoxContainer = %InitiativeRow
@onready var ap_label: Label = %APLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var actor_name: Label = %ActorName
@onready var player_card: PanelContainer = %PlayerCard
@onready var actor_status: Label = %ActorStatus
@onready var actor_intent: Label = %ActorIntent
@onready var active_weapon_card: CombatItemCard = %ActiveWeaponCard
@onready var weapon_actions: VBoxContainer = %WeaponActions
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var blood_bar: ProgressBar = %BloodBar
@onready var blood_value: Label = %BloodValue
@onready var pain_bar: ProgressBar = %PainBar
@onready var pain_value: Label = %PainValue
@onready var shock_bar: ProgressBar = %ShockBar
@onready var shock_value: Label = %ShockValue
@onready var consciousness_bar: ProgressBar = %ConsciousnessBar
@onready var consciousness_value: Label = %ConsciousnessValue
@onready var player_warnings: Label = %PlayerWarnings
@onready var target_heading: Label = %TargetHeading
@onready var hex_panel: PanelContainer = %HexPanel
@onready var hex_title: Label = %HexTitle
@onready var hex_summary: Label = %HexSummary
@onready var hex_details: RichTextLabel = %HexDetails
@onready var ground_items: VBoxContainer = %GroundItems
@onready var ground_item_heading: Label = %GroundItemHeading
@onready var wounds: VBoxContainer = %Wounds
@onready var wound_heading: Label = %WoundHeading
@onready var target_items: VBoxContainer = %TargetItems
@onready var target_item_heading: Label = %TargetItemHeading
@onready var items: VBoxContainer = %Items
@onready var item_heading: Button = %ItemHeading
@onready var right_panel: PanelContainer = %Right
@onready var target_name: Label = %TargetName
@onready var target_summary: Label = %TargetSummary
@onready var target_body: CombatBodyTargetView = %TargetBody
@onready var target_vitals: GridContainer = %TargetVitals
@onready var target_blood_bar: ProgressBar = %TargetBloodBar
@onready var target_blood_value: Label = %TargetBloodValue
@onready var target_pain_bar: ProgressBar = %TargetPainBar
@onready var target_pain_value: Label = %TargetPainValue
@onready var target_shock_bar: ProgressBar = %TargetShockBar
@onready var target_shock_value: Label = %TargetShockValue
@onready var target_consciousness_bar: ProgressBar = %TargetConsciousnessBar
@onready var target_consciousness_value: Label = %TargetConsciousnessValue
@onready var target_label: RichTextLabel = %TargetLabel
@onready var aim_target_panel: PanelContainer = %AimTargetPanel
@onready var aim_target_body: CombatBodyTargetView = %AimTargetBody
@onready var aim_title: Label = %AimTitle
@onready var aim_hint: Label = %AimHint
@onready var aim_forecast: Label = %AimForecast
@onready var aim_feedback: Label = %AimFeedback
@onready var aim_cancel_button: Button = %AimCancelButton
@onready var aim_confirm_button: Button = %AimConfirmButton
@onready var feedback_label: Label = %FeedbackLabel
@onready var forecast_label: Label = %ForecastLabel
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton
@onready var local_confirmation: HBoxContainer = %LocalConfirmation
@onready var context_menu: PanelContainer = %ContextMenu
@onready var context_title: Label = %ContextTitle
@onready var context_hint: Label = %ContextHint
@onready var context_actions: VBoxContainer = %ContextActions
@onready var context_scroll: ScrollContainer = %ContextScroll
@onready var reaction_panel: PanelContainer = %ReactionPanel
@onready var reaction_title: Label = %ReactionTitle
@onready var reaction_actions: HBoxContainer = %ReactionActions

var interaction = INTERACTION_STATE_SCRIPT.new()
var interaction_coordinator: TacticalCombatInteractionCoordinator
var snapshot: Dictionary = {}
var _snapshot_presenter := _SnapshotPresenter.new()
var quotes: Array[CombatActionQuote] = []
var selected_sector: Vector2i:
	get: return interaction.selected_sector
	set(value): interaction.selected_sector = value
var selected_actor_id: String:
	get: return interaction.controlled_actor_id
	set(value): interaction.controlled_actor_id = value
var selected_item_id: String:
	get: return interaction.selected_item_id
	set(value): interaction.selected_item_id = value
var selected_wound_id: String:
	get: return interaction.selected_wound_id
	set(value): interaction.selected_wound_id = value
var selected_body_region: int:
	get: return interaction.selected_body_region
	set(value): interaction.selected_body_region = value
var current_quote: CombatActionQuote:
	get: return interaction.current_quote
	set(value): interaction.current_quote = value
var _definitions: Dictionary = {}
var catalog: CombatActionCatalog
var _quote_by_action: Dictionary = {}
var _pending_aim_action := ""
var _context_shortcuts: Array[Button] = []
var _route_path: Array[Vector2i]:
	get: return interaction.route_path
	set(value): interaction.route_path = value
var _route_direction := 0
var _result_feed: Label
var _result_feed_entries: Array[String] = []
var _corner_panels: Dictionary = {}
var _corner_states: Dictionary = {}
var _corner_contents: Dictionary = {}
var _corner_buttons: Dictionary = {}
var _expanded_corner_id := ""
var _aim_restore_corner_id := ""
var _weapon_action_buttons: Dictionary = {}
var _interaction_debug: Label
var _debug_timeline_id := ""
var _corner_layout_queued := false


func _ready() -> void:
	_ensure_input_actions()
	_compact_weapon_card()
	_style_vitals()
	_apply_macro_aesthetic()
	resized.connect(_queue_corner_layout)
	arena_view.inspect_requested.connect(_on_arena_inspect_requested)
	arena_view.context_requested.connect(_on_arena_context_requested)
	# Compatibility signal for scripted fixtures; physical input uses the two
	# explicit intents above.
	arena_view.sector_selected.connect(_on_sector_selected)
	arena_view.sector_hovered.connect(_on_sector_hovered)
	arena_view.sector_unhovered.connect(_on_sector_unhovered)
	item_heading.pressed.connect(_toggle_pack)
	player_card.gui_input.connect(_on_player_card_input)
	player_card.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_button.pressed.connect(_cancel_selection)
	confirm_button.pressed.connect(_confirm_local)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	aim_target_body.region_selected.connect(_on_aim_body_region_selected)
	aim_cancel_button.pressed.connect(_cancel_aim_targeting)
	aim_confirm_button.pressed.connect(_confirm_aim_targeting)
	target_body.set_selectable(false)
	right_panel.visible = true
	hex_panel.visible = true
	aim_target_panel.visible = false
	context_menu.visible = false
	reaction_panel.visible = false
	local_confirmation.visible = false
	confirm_button.disabled = true
	feedback_label.text = ""
	_setup_corner_panels()
	_result_feed = Label.new()
	_result_feed.name = "ConsequenceFeed"
	_result_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_feed.add_theme_font_size_override("font_size", 12)
	_result_feed.add_theme_color_override("font_color", Color("d5dedb"))
	_result_feed.z_index = 40
	add_child(_result_feed)
	_setup_interaction_debug()
	call_deferred("_layout_corner_panels")


func _queue_corner_layout() -> void:
	if _corner_layout_queued:
		return
	_corner_layout_queued = true
	call_deferred("_apply_queued_corner_layout")


func _apply_queued_corner_layout() -> void:
	_corner_layout_queued = false
	_layout_corner_panels()


func set_interaction_state(value: CombatInteractionState) -> void:
	if value != null:
		interaction = value


func set_interaction_coordinator(value: TacticalCombatInteractionCoordinator) -> void:
	interaction_coordinator = value
	if value != null:
		interaction = value.state


func _coordinator() -> TacticalCombatInteractionCoordinator:
	if interaction_coordinator == null:
		interaction_coordinator = _InteractionCoordinator.new()
		interaction_coordinator.state = interaction
	return interaction_coordinator


func _set_phase(value: CombatInteractionState.Phase) -> void:
	# Only the coordinator mutates interaction phase. The HUD remains a passive
	# renderer even when compatibility fixtures call its private handlers.
	_coordinator().state.phase = value


func _select_interaction(kind: String, data: Dictionary) -> void:
	_coordinator().select(kind, data)


func _setup_interaction_debug() -> void:
	if not OS.is_debug_build():
		return
	_interaction_debug = Label.new()
	_interaction_debug.name = "InteractionDebug"
	_interaction_debug.position = Vector2(320.0, 52.0)
	_interaction_debug.size = Vector2(620.0, 54.0)
	_interaction_debug.z_index = 90
	_interaction_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction_debug.add_theme_font_size_override("font_size", 11)
	_interaction_debug.add_theme_color_override("font_color", Color("b9d9d4"))
	_interaction_debug.visible = false
	add_child(_interaction_debug)


func _refresh_interaction_debug() -> void:
	if _interaction_debug == null or not _interaction_debug.visible:
		return
	var quote_text := "none"
	if current_quote != null:
		quote_text = "%s %s" % [current_quote.action_id, "LEGAL" if current_quote.legal else current_quote.denial_code]
	_interaction_debug.text = "MODE %s  SELECT %s@%s  STAGED %s  QUOTE %s\nAP %s  LOCK %s  TIMELINE %s" % [
		str(INTERACTION_STATE_SCRIPT.Phase.keys()[interaction.phase]), interaction.selected_kind, selected_sector,
		interaction.staged_action_id, quote_text, snapshot.get("ap", 0),
		"PRESENTATION" if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING else "NONE", _debug_timeline_id,
	]


func _compact_weapon_card() -> void:
	active_weapon_card.custom_minimum_size = Vector2(250.0, 112.0)
	var visual := active_weapon_card.get_node_or_null("Margin/Columns/Visual") as Control
	if visual != null:
		visual.custom_minimum_size = Vector2(72.0, 94.0)
	var margin := active_weapon_card.get_node_or_null("Margin") as MarginContainer
	if margin != null:
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			margin.add_theme_constant_override(side, 4)
	var grade := active_weapon_card.get_node_or_null("Margin/Columns/Info/GradeLabel") as Control
	var condition := active_weapon_card.get_node_or_null("Margin/Columns/Info/ConditionBar") as Control
	var details := active_weapon_card.get_node_or_null("Margin/Columns/Info/DetailLabel") as Control
	for field in [grade, condition, details]:
		if field != null:
			field.visible = true
	active_weapon_card.weapon_name.add_theme_font_size_override("font_size", 13)
	active_weapon_card.ammo_label.add_theme_font_size_override("font_size", 13)
	active_weapon_card.state_label.add_theme_font_size_override("font_size", 11)
	if grade != null:
		grade.add_theme_font_size_override("font_size", 9)
	if details != null:
		details.add_theme_font_size_override("font_size", 9)


func _style_vitals() -> void:
	for bar in [blood_bar, target_blood_bar]:
		HUD_ASSETS.apply_progress_bar(bar, "health")
	for bar in [consciousness_bar, target_consciousness_bar]:
		HUD_ASSETS.apply_progress_bar(bar, "caution")
	for bar in [pain_bar, target_pain_bar]:
		HUD_ASSETS.apply_progress_bar(bar, "warning")
	for bar in [shock_bar, target_shock_bar]:
		HUD_ASSETS.apply_progress_bar(bar, "critical")


func _apply_macro_aesthetic() -> void:
	for panel in [%TopStrip, player_card, inventory_panel, hex_panel, right_panel, aim_target_panel, context_menu, reaction_panel]:
		HUD_ASSETS.apply_panel(panel as PanelContainer, "neutral")
		(panel as PanelContainer).self_modulate.a = VISUAL_PROFILE.panel_opacity
	for label in [actor_name, hex_title, target_heading, target_name, aim_title, reaction_title]:
		HUD_ASSETS.apply_label(label as Label, "title")
	for label in [actor_status, hex_summary, target_summary, context_hint, aim_hint, ground_item_heading, target_item_heading]:
		HUD_ASSETS.apply_label(label as Label, "muted")
	for label in [ap_label, forecast_label, aim_forecast]:
		HUD_ASSETS.apply_label(label as Label, "caution")
	HUD_ASSETS.apply_rich_label(hex_details, "body")
	HUD_ASSETS.apply_rich_label(target_label, "body")
	for button in [item_heading, cancel_button, confirm_button, aim_cancel_button, aim_confirm_button, end_turn_button]:
		HUD_ASSETS.apply_button(button as Button)


func _setup_corner_panels() -> void:
	for entry in [
		["health", player_card],
		["loadout", inventory_panel],
		["site", hex_panel],
		["hostile", right_panel],
	]:
		var panel_id := str(entry[0])
		var panel := entry[1] as PanelContainer
		var content := panel.get_child(0) as Control
		panel.remove_child(content)
		var shell := VBoxContainer.new()
		shell.name = "CornerShell"
		shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var button := Button.new()
		button.name = "PreviewButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 58.0)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(_toggle_corner_panel.bind(panel_id))
		HUD_ASSETS.apply_button(button)
		panel.add_child(shell)
		shell.add_child(button)
		shell.add_child(content)
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.clip_contents = true
		var state: Variant = _SharedCornerPanelState.new()
		state.configure(panel_id, _SharedCornerPanelState.State.PREVIEW)
		_corner_panels[panel_id] = panel
		_corner_states[panel_id] = state
		_corner_contents[panel_id] = content
		_corner_buttons[panel_id] = button
	_apply_corner_states()


func _toggle_corner_panel(panel_id: String) -> void:
	if interaction.phase in [INTERACTION_STATE_SCRIPT.Phase.PRESENTING, INTERACTION_STATE_SCRIPT.Phase.REACTION] or aim_target_panel.visible:
		return
	if _expanded_corner_id == panel_id:
		collapse_corner_panels()
	else:
		_expanded_corner_id = panel_id
		for id in _corner_states:
			_corner_states[id].set_expanded(str(id) == panel_id)
		_apply_corner_states()
		_refresh_corner_previews()


func collapse_corner_panels() -> bool:
	if _expanded_corner_id.is_empty():
		return false
	_expanded_corner_id = ""
	for state in _corner_states.values():
		state.set_expanded(false)
	_apply_corner_states()
	_refresh_corner_previews()
	return true


func expanded_corner_id() -> String:
	return _expanded_corner_id


func _apply_corner_states() -> void:
	for panel_id in _corner_states:
		var expanded: bool = _corner_states[panel_id].is_expanded()
		(_corner_contents[panel_id] as Control).visible = expanded
		var button := _corner_buttons[panel_id] as Button
		button.tooltip_text = "Collapse panel" if expanded else "Expand panel"
	_layout_corner_panels()


func _set_corner_preview(panel_id: String, title: String, summary: String) -> void:
	var button := _corner_buttons.get(panel_id) as Button
	if button == null:
		return
	var marker := "  [CLOSE]" if panel_id == _expanded_corner_id else "  [OPEN]"
	button.text = "%s%s\n%s" % [title, marker, summary]


func _layout_corner_panels() -> void:
	if not is_node_ready():
		return
	var margin := 12.0
	var top_y := 58.0
	var gap := 10.0
	var preview_width := clampf(size.x * 0.16, 240.0, 300.0)
	var preview_height := 76.0
	var expanded_width := clampf(size.x * 0.30, 340.0, 460.0)
	var usable_height := maxf(360.0, size.y - top_y - margin)
	var expanded_height := minf(620.0, usable_height - preview_height - gap)
	_layout_corner_panel("health", Vector2(margin, top_y), true, preview_width, preview_height, expanded_width, expanded_height)
	_layout_corner_panel("loadout", Vector2(margin, size.y - margin - preview_height), false, preview_width, preview_height, expanded_width, expanded_height)
	var right_preview_x := size.x - margin - preview_width
	_layout_corner_panel("site", Vector2(right_preview_x, top_y), true, preview_width, preview_height, expanded_width, expanded_height)
	_layout_corner_panel("hostile", Vector2(right_preview_x, size.y - margin - preview_height), false, preview_width, preview_height, expanded_width, expanded_height)
	var aim_width := clampf(size.x * 0.31, 360.0, 430.0)
	aim_target_panel.position = Vector2(size.x - margin - aim_width, top_y)
	aim_target_panel.size = Vector2(aim_width, usable_height)
	var left_inset := expanded_width + margin + gap if _expanded_corner_id in ["health", "loadout"] else 0.0
	var right_inset := expanded_width + margin + gap if _expanded_corner_id in ["site", "hostile"] else 0.0
	var safe_width := maxf(320.0, size.x - left_inset - right_inset)
	arena_view.set_camera_safe_rect(Rect2(
		Vector2(left_inset, 0.0),
		Vector2(safe_width, maxf(220.0, arena_view.size.y))
	))
	if _result_feed != null:
		_result_feed.position = Vector2(maxf(12.0, (size.x - 420.0) * 0.5), size.y - 82.0)
		_result_feed.size = Vector2(minf(420.0, size.x - 24.0), 70.0)
	_position_context_menu()


func _layout_corner_panel(
	panel_id: String,
	preview_position: Vector2,
	is_top: bool,
	preview_width: float,
	preview_height: float,
	expanded_width: float,
	expanded_height: float
) -> void:
	var panel := _corner_panels.get(panel_id) as Control
	if panel == null:
		return
	var expanded := panel_id == _expanded_corner_id
	var width := expanded_width if expanded else preview_width
	var height := expanded_height if expanded else preview_height
	var position := preview_position
	if panel_id in ["site", "hostile"]:
		position.x = size.x - 12.0 - width
	if expanded and not is_top:
		position.y = size.y - 12.0 - height
	panel.position = position
	panel.size = Vector2(width, height)


func _ensure_input_actions() -> void:
	_register_input_action("combat_select", KEY_ENTER, JOY_BUTTON_A)
	_register_input_action("combat_cancel", KEY_ESCAPE, JOY_BUTTON_B)
	_register_input_action("combat_context", KEY_Q, JOY_BUTTON_X)
	_register_input_action("combat_items", KEY_I, JOY_BUTTON_Y)
	_register_input_action("combat_cycle_next", KEY_TAB, JOY_BUTTON_RIGHT_SHOULDER)
	_register_input_action("combat_cycle_previous", KEY_NONE, JOY_BUTTON_LEFT_SHOULDER)
	_register_input_action("combat_move_left", KEY_A, JOY_BUTTON_INVALID)
	_register_input_action("combat_move_right", KEY_D, JOY_BUTTON_INVALID)
	_register_input_action("combat_menu_up", KEY_W, JOY_BUTTON_INVALID)
	_register_input_action("combat_menu_down", KEY_S, JOY_BUTTON_INVALID)
	var previous_key := InputEventKey.new()
	previous_key.physical_keycode = KEY_TAB
	previous_key.shift_pressed = true
	if not InputMap.action_has_event("combat_cycle_previous", previous_key):
		InputMap.action_add_event("combat_cycle_previous", previous_key)


func _register_input_action(action: StringName, keycode: Key, joy_button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if keycode != KEY_NONE:
		var key := InputEventKey.new()
		key.physical_keycode = keycode
		if not InputMap.action_has_event(action, key):
			InputMap.action_add_event(action, key)
	if joy_button != JOY_BUTTON_INVALID:
		var button := InputEventJoypadButton.new()
		button.button_index = joy_button
		if not InputMap.action_has_event(action, button):
			InputMap.action_add_event(action, button)


func _unhandled_input(event: InputEvent) -> void:
	if _is_key_pressed(event, KEY_F10) and _interaction_debug != null:
		_interaction_debug.visible = not _interaction_debug.visible
		_refresh_interaction_debug()
		get_viewport().set_input_as_handled()
		return
	# Arena RMB is consumed by TacticalArenaView and arrives as context_requested.
	# RMB elsewhere is deliberately inert; Escape/B remain the cancellation keys.
	if event.is_action_pressed("combat_cancel") or event.is_action_pressed("ui_cancel"):
		if _has_active_interaction():
			_cancel_selection()
		elif collapse_corner_panels():
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		return
	if _is_move_left(event) or event.is_action_pressed("ui_left"):
		if _handle_left_navigation():
			get_viewport().set_input_as_handled()
		return
	if _is_move_right(event) or event.is_action_pressed("ui_right"):
		if _handle_right_navigation():
			get_viewport().set_input_as_handled()
		return
	if _is_menu_up(event) or event.is_action_pressed("ui_up"):
		if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.BUMP_MENU and _move_context_highlight(-1):
			get_viewport().set_input_as_handled()
		return
	if _is_menu_down(event) or event.is_action_pressed("ui_down"):
		if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.BUMP_MENU and _move_context_highlight(1):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_select") or event.is_action_pressed("ui_accept"):
		if current_quote != null and current_quote.legal and aim_target_panel.visible:
			_confirm_aim_targeting()
			get_viewport().set_input_as_handled()
			return
		if current_quote != null and current_quote.legal and (
			local_confirmation.visible or interaction.phase == INTERACTION_STATE_SCRIPT.Phase.ROUTE_PREVIEW
		):
			_confirm_local()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("combat_context"):
		if selected_sector == Vector2i(-1, -1):
			_select_player()
		else:
			_render_context_actions()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_items"):
		var player := _actor(selected_actor_id)
		var player_sector: Vector2i = player.get("sector", Vector2i(-1, -1))
		if player_sector != selected_sector:
			_select_player()
		_toggle_pack()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_cycle_next"):
		_cycle_actor(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_cycle_previous"):
		_cycle_actor(-1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var number := int(event.keycode) - int(KEY_1)
		if number >= 0 and number < _context_shortcuts.size() and context_menu.visible:
			_context_shortcuts[number].pressed.emit()
			get_viewport().set_input_as_handled()
			return


func _is_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and (
		event.keycode == keycode or event.physical_keycode == keycode
	)


func _is_move_left(event: InputEvent) -> bool:
	return event.is_action_pressed("combat_move_left") or _is_key_pressed(event, KEY_A)


func _is_move_right(event: InputEvent) -> bool:
	return event.is_action_pressed("combat_move_right") or _is_key_pressed(event, KEY_D)


func _is_menu_up(event: InputEvent) -> bool:
	return event.is_action_pressed("combat_menu_up") or _is_key_pressed(event, KEY_W)


func _is_menu_down(event: InputEvent) -> bool:
	return event.is_action_pressed("combat_menu_down") or _is_key_pressed(event, KEY_S)


func _handle_left_navigation() -> bool:
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING:
		return false
	if aim_target_panel.visible:
		_cancel_aim_targeting()
		return true
	match interaction.phase:
		INTERACTION_STATE_SCRIPT.Phase.CONFIRMATION, INTERACTION_STATE_SCRIPT.Phase.ACTION_PREVIEW:
			_go_back_to_bump_menu()
			return true
		INTERACTION_STATE_SCRIPT.Phase.BUMP_MENU:
			_go_back_to_route_preview()
			return true
		INTERACTION_STATE_SCRIPT.Phase.ROUTE_PREVIEW:
			_stage_route_step(-1)
			return true
		_:
			_stage_route_step(-1)
			return true


func _handle_right_navigation() -> bool:
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING:
		return false
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.BUMP_MENU:
		_activate_context_selection()
		return true
	if aim_target_panel.visible:
		if current_quote != null and current_quote.legal:
			_confirm_aim_targeting()
		return true
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.CONFIRMATION:
		_confirm_local()
		return true
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.ACTION_PREVIEW:
		if current_quote != null and current_quote.legal:
			_confirm_local()
			return true
		return false
	_stage_route_step(1)
	return true


func _move_context_highlight(direction: int) -> bool:
	if _context_shortcuts.is_empty():
		return false
	var current := -1
	for index in range(_context_shortcuts.size()):
		if _context_shortcuts[index].has_focus():
			current = index
			break
	var next := current
	for _step in range(_context_shortcuts.size()):
		next = posmod(next + direction, _context_shortcuts.size())
		if not _context_shortcuts[next].disabled:
			_context_shortcuts[next].grab_focus()
			interaction.highlighted_action_index = next
			return true
	return false


func _activate_context_selection() -> void:
	for button in _context_shortcuts:
		if button.has_focus() and not button.disabled:
			button.pressed.emit()
			return
	for button in _context_shortcuts:
		if not button.disabled:
			button.pressed.emit()
			return


func _stage_route_step(direction: int) -> void:
	var player := _actor(selected_actor_id)
	var origin: Vector2i = player.get("sector", Vector2i(-1, -1))
	if origin == Vector2i(-1, -1):
		return
	if _route_path.is_empty():
		_route_path = [origin]
		_route_direction = direction
	elif _route_path.size() > 1 and direction == -_route_direction:
		_route_path.pop_back()
		if _route_path.size() == 1:
			_route_direction = 0
		_preview_staged_route()
		return
	else:
		_route_direction = direction
	var current: Vector2i = _route_path.back()
	var candidate: Vector2i = current + Vector2i(direction, 0)
	var sector := _sector(candidate)
	if sector.is_empty():
		show_feedback("The route ends at the arena boundary.")
		return
	if not _occupant_ids(sector).is_empty():
		_open_bump_menu(candidate)
		return
	if bool(sector.get("blocked", false)):
		show_feedback("That sector is blocked.")
		return
	_route_path.append(candidate)
	_preview_staged_route()


func _preview_staged_route() -> void:
	if _route_path.size() < 2:
		_set_phase(INTERACTION_STATE_SCRIPT.Phase.INSPECTING)
		current_quote = null
		local_confirmation.visible = false
		context_menu.visible = false
		return
	selected_sector = _route_path.back()
	interaction.route_path = _route_path.duplicate()
	interaction.projected_origin = selected_sector
	_coordinator().begin_route()
	current_quote = null
	local_confirmation.visible = false
	context_menu.visible = false
	arena_view.select_sector(selected_sector)
	_render_inspector()
	route_context_selected.emit(selected_sector, _route_path.duplicate())


func _open_bump_menu(coords: Vector2i) -> void:
	if _route_path.is_empty():
		var player := _actor(selected_actor_id)
		_route_path = [player.get("sector", Vector2i(-1, -1))]
	selected_sector = coords
	interaction.route_path = _route_path.duplicate()
	interaction.projected_origin = _route_path.back()
	interaction.bumped_actor_id = _occupant_at(coords)
	interaction.highlighted_action_index = 0
	_set_phase(INTERACTION_STATE_SCRIPT.Phase.ACTION_MENU)
	current_quote = null
	local_confirmation.visible = false
	arena_view.select_sector(coords)
	_render_inspector()
	_render_context_actions()
	route_context_selected.emit(coords, _route_path.duplicate())


func _go_back_to_bump_menu() -> void:
	if _route_path.is_empty():
		_cancel_complete_chain()
		return
	current_quote = null
	local_confirmation.visible = false
	_close_aim_panel()
	interaction.staged_action_id = ""
	_set_phase(INTERACTION_STATE_SCRIPT.Phase.ACTION_MENU)
	context_menu.visible = true
	_render_context_actions()


func _go_back_to_route_preview() -> void:
	current_quote = null
	local_confirmation.visible = false
	context_menu.visible = false
	interaction.staged_action_id = ""
	interaction.bumped_actor_id = ""
	_coordinator().begin_route()
	if not _route_path.is_empty():
		selected_sector = _route_path.back()
		arena_view.select_sector(selected_sector)
		_render_inspector()
		route_context_selected.emit(selected_sector, _route_path.duplicate())


func _cancel_complete_chain() -> void:
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING:
		return
	_route_path.clear()
	_route_direction = 0
	current_quote = null
	local_confirmation.visible = false
	_close_aim_panel()
	_coordinator().clear_selection()
	context_menu.visible = false
	selected_sector = Vector2i(-1, -1)
	arena_view.select_sector(selected_sector)
	arena_view.clear_quote()
	selection_cancelled.emit()


func configure_action_catalog(catalog: CombatActionCatalog) -> void:
	self.catalog = catalog
	_definitions.clear()
	if catalog == null:
		return
	for definition in catalog.all():
		_definitions[definition.action_id] = definition


func show_snapshot(value: Dictionary) -> void:
	snapshot = _snapshot_presenter.compose(value)
	for actor in snapshot.get("actors", []):
		if str(actor.get("team_id", "")) == "player":
			selected_actor_id = str(actor.get("actor_id", "player"))
			break
	var arena: Dictionary = snapshot.get("arena", {})
	arena_view.set_meta("actor_snapshot", snapshot.get("actors", []))
	arena_view.show_snapshot(arena)
	_render_top()
	_render_player_card()
	_render_inspector()
	_refresh_corner_previews()
	_refresh_global_actions()
	_render_weapon_actions()
	_refresh_interaction_debug()


func show_quotes(value: Array[CombatActionQuote]) -> void:
	quotes = value
	_quote_by_action.clear()
	for action_quote in quotes:
		_quote_by_action[action_quote.action_id] = action_quote
	_refresh_global_actions()
	_render_weapon_actions()
	_refresh_interaction_debug()


func show_quote(value: CombatActionQuote) -> void:
	current_quote = value
	_refresh_interaction_debug()
	arena_view.show_quote(value)
	_coordinator().stage_quote(value.action_id, value.legal)
	if aim_target_panel.visible and value.action_id == _pending_aim_action:
		aim_confirm_button.disabled = not value.legal
		aim_forecast.text = _forecast_text(value)
		aim_feedback.text = "Region selected." if value.legal else ""
		context_menu.visible = false
		local_confirmation.visible = false
		return
	confirm_button.disabled = not value.legal
	local_confirmation.visible = true
	var definition := _definition(value.action_id)
	var label := definition.label if definition != null else value.action_id.replace("_", " ").capitalize()
	context_hint.text = _action_explanation(definition)
	feedback_label.text = "%s staged." % label if value.legal else value.denial_message
	_render_forecast(value)
	context_actions.visible = true
	context_menu.visible = true
	call_deferred("_position_context_menu")
	_refresh_global_actions()


func show_route_quote(value: CombatActionQuote) -> void:
	current_quote = value
	arena_view.show_quote(value)
	interaction.staged_action_id = "move"
	_coordinator().begin_route()
	local_confirmation.visible = true
	context_actions.visible = false
	context_title.text = "ROUTE PREVIEW"
	context_hint.text = "D extends the route. A retracts one cell. ENTER confirms movement."
	context_menu.visible = true
	confirm_button.disabled = not value.legal
	feedback_label.text = "Route staged. ENTER to confirm; A retracts."
	_render_forecast(value)
	call_deferred("_position_context_menu")


func clear_staged_action() -> void:
	current_quote = null
	_route_path.clear()
	_route_direction = 0
	selected_body_region = -1
	confirm_button.disabled = true
	local_confirmation.visible = false
	context_actions.visible = true
	forecast_label.text = "CHOOSE AN ACTION"
	feedback_label.text = ""
	aim_target_body.set_selectable(false)
	_close_aim_panel()
	interaction.route_path.clear()
	interaction.projected_origin = selected_sector
	interaction.bumped_actor_id = ""
	interaction.staged_action_id = ""
	arena_view.clear_quote()
	if interaction.phase != INTERACTION_STATE_SCRIPT.Phase.PRESENTING:
		_set_phase(INTERACTION_STATE_SCRIPT.Phase.INSPECTING)
	_refresh_global_actions()


func show_feedback(message: String) -> void:
	if aim_target_panel.visible:
		aim_feedback.text = "" if message == aim_forecast.text else message
		return
	feedback_label.text = message


func show_result_events(outcome: CombatActionOutcome) -> void:
	if outcome == null:
		return
	var messages: Array[String] = []
	for event in outcome.presentation_events:
		var label := _result_event_label(event)
		if not label.is_empty():
			messages.append(label)
	for event in outcome.result_events:
		var label := _result_event_label(event)
		if not label.is_empty():
			messages.append(label)
	for wound in outcome.wound_events:
		messages.append("WOUND: %s" % _region_label(int(wound.get("region", -1))).to_upper())
	for reaction in outcome.reactions:
		messages.append("OPPORTUNITY: %s" % str(reaction.get("actor_id", "THREAT")).to_upper())
	if outcome.interrupted:
		messages.append("INTERRUPTED: ACTION CANCELLED")
	if messages.is_empty() and not outcome.message.is_empty():
		messages.append(outcome.message.to_upper())
	for message in messages:
		_result_feed_entries.push_front(message)
	while _result_feed_entries.size() > 3:
		_result_feed_entries.pop_back()
	if _result_feed != null:
		_result_feed.text = "CONSEQUENCES\n" + "\n".join(_result_feed_entries)


func push_consequence(message: String) -> void:
	if message.is_empty():
		return
	_result_feed_entries.push_front(message.to_upper())
	while _result_feed_entries.size() > 3:
		_result_feed_entries.pop_back()
	if _result_feed != null:
		_result_feed.text = "CONSEQUENCES\n" + "\n".join(_result_feed_entries)


func _result_event_label(event: Dictionary) -> String:
	var result := str(event.get("result", ""))
	if result.is_empty():
		var event_type := str(event.get("type", ""))
		if event_type == "composite_interrupted":
			return "MOVEMENT INTERRUPTED: ACTION CANCELLED"
		if event_type == "opportunity_reaction":
			return "OPPORTUNITY: %s" % str(event.get("actor_id", "THREAT")).to_upper()
		return ""
	var region := int(event.get("region", event.get("body_region", -1)))
	var suffix := ""
	if region >= 0:
		suffix = " (%s)" % _region_label(region).to_upper()
	return (result.replace("_", " ").to_upper() + suffix).strip_edges()


func show_presentation_action(sequence: CombatPresentationSequence) -> void:
	if sequence == null:
		return
	_coordinator().begin_presentation()
	_debug_timeline_id = sequence.timeline_id
	_refresh_interaction_debug()
	arena_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_menu.visible = false
	_close_aim_panel()
	active_weapon_card.play_turn_action(sequence.action_id, sequence.total_duration())


func finish_presentation() -> void:
	_coordinator().finish_presentation()
	_debug_timeline_id = ""
	_refresh_interaction_debug()
	arena_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_render_inspector()


func show_aim_targeter(action_id: String) -> void:
	# Compatibility sink. Body-region targeting is no longer a player-facing
	# branch; the authoritative attack quote resolves the legal result.
	_pending_aim_action = ""
	_close_aim_panel()
	show_feedback("Body-region targeting is resolved by the combat quote.")


func show_reaction(prompt: Dictionary) -> void:
	# Reaction input was retired from the canonical tactical contract. Keep this
	# method as a compatibility sink for old serialized callers; production no
	# longer connects a reaction signal or opens a reaction surface.
	reaction_panel.visible = false
	_set_phase(INTERACTION_STATE_SCRIPT.Phase.INSPECTING if not interaction.selected_kind.is_empty() else INTERACTION_STATE_SCRIPT.Phase.IDLE)


func hide_reaction() -> void:
	reaction_panel.visible = false
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.REACTION:
		_set_phase(INTERACTION_STATE_SCRIPT.Phase.INSPECTING if not interaction.selected_kind.is_empty() else INTERACTION_STATE_SCRIPT.Phase.IDLE)


func selected_context() -> Dictionary:
	return {
		"target_sector": selected_sector,
		"target_actor_id": _selected_occupant_id(),
		"item_instance_id": selected_item_id,
		"wound_id": selected_wound_id,
		"body_region": selected_body_region,
		"shove_direction": interaction.selected_shove_direction,
		"declared_neutral_attack_confirmation": interaction.declared_neutral_attack_confirmation,
		"facing": "",
	}


func staged_route() -> Array[Vector2i]:
	return _route_path.duplicate()


func _render_top() -> void:
	_clear_children(initiative_row)
	var actors_by_id: Dictionary = {}
	for actor in snapshot.get("actors", []):
		actors_by_id[str(actor.get("actor_id", ""))] = actor
	var order: Array = snapshot.get("initiative_order", [])
	if order.is_empty():
		order = actors_by_id.keys()
	for actor_id in order:
		var actor: Dictionary = actors_by_id.get(str(actor_id), {})
		if actor.is_empty():
			continue
		var chip := Label.new()
		var active := str(actor_id) == str(snapshot.get("active_actor_id", ""))
		chip.text = "%s%s" % ["> " if active else "", str(actor.get("name", "ACTOR")).to_upper()]
		chip.add_theme_color_override("font_color", Color("f0ce76") if active else Color("8ea0a4"))
		initiative_row.add_child(chip)
	var communication_points: Dictionary = snapshot.get("arena", {}).get("communication_points", {})
	if communication_points.is_empty():
		communication_points = snapshot.get("arena", {}).get("squad_points", {})
	ap_label.text = "ROUND %02d   AP %02d/12" % [
		int(snapshot.get("round", 0)),
		int(snapshot.get("ap", 0)),
	]
	ap_label.text += "   CP %02d/%02d" % [
		int(communication_points.get("current", 0)),
		int(communication_points.get("initial", 0)),
	]


func _render_player_card() -> void:
	var actor := _actor(selected_actor_id)
	if actor.is_empty():
		actor_name.text = "NO ACTOR"
		return
	actor_name.text = str(actor.get("name", selected_actor_id)).to_upper()
	actor_status.text = "STANCE %.1f/%.1f" % [
		float(actor.get("stance", 0.0)),
		float(actor.get("max_stance", 0.0)),
	]
	var public_intent: Dictionary = actor.get("public_intent", {})
	actor_intent.text = (
		"INTENT  %s" % str(public_intent.get("readable_label", "HOLDING"))
		if not public_intent.is_empty()
		else "INTENT  HOLDING"
	)
	_set_vital(blood_bar, blood_value, float(actor.get("blood", 0.0)))
	_set_vital(consciousness_bar, consciousness_value, float(actor.get("consciousness", 0.0)))
	_set_vital(pain_bar, pain_value, float(actor.get("pain", 0.0)))
	_set_vital(shock_bar, shock_value, float(actor.get("shock", 0.0)))
	var warnings: Array[String] = []
	if float(actor.get("pain", 0.0)) >= 2.0:
		warnings.append("PAIN %d" % roundi(float(actor.get("pain", 0.0))))
	if float(actor.get("shock", 0.0)) >= 2.0:
		warnings.append("SHOCK %d" % roundi(float(actor.get("shock", 0.0))))
	for wound in actor.get("wounds", []):
		var severity := float(wound.get("severity", 0.0))
		var bleeding := float(wound.get("bleeding_rate", 0.0))
		if severity >= 6.0 or bleeding >= 1.0:
			warnings.append("%s BLEED %.1f" % [_region_label(int(wound.get("body_region", -1))).to_upper(), bleeding])
	player_warnings.text = "  ".join(warnings)
	var ranged_weapon: Dictionary = actor.get("ranged_weapon", {})
	var weapon: Dictionary = ranged_weapon if not ranged_weapon.is_empty() else actor.get("melee_weapon", {})
	active_weapon_card.visible = not weapon.is_empty()
	if not weapon.is_empty():
		active_weapon_card.show_descriptor(weapon, not ranged_weapon.is_empty())
	_render_weapon_actions()
	_render_items(actor.get("items", []))


func _render_inspector() -> void:
	var showing_aim_targeter := aim_target_panel.visible
	right_panel.visible = not showing_aim_targeter
	hex_panel.visible = not showing_aim_targeter
	var has_selected_sector := selected_sector != Vector2i(-1, -1)
	var sector := _sector(selected_sector) if has_selected_sector else {}
	if sector.is_empty():
		var player := _actor(selected_actor_id)
		sector = _sector(player.get("sector", Vector2i(-1, -1)))
	_render_sector_inspector(sector)
	if not has_selected_sector:
		_clear_target_inspector()
		_refresh_corner_previews()
		return
	var occupant: Dictionary = {}
	var selected_occupant := _actor(_selected_occupant_id())
	if not selected_occupant.is_empty():
		occupant = selected_occupant
	if not occupant.is_empty():
		_render_actor_inspector(occupant)
	else:
		_clear_target_inspector()
	_refresh_corner_previews()


func _refresh_corner_previews() -> void:
	if _corner_buttons.is_empty():
		return
	var player := _actor(selected_actor_id)
	_set_corner_preview(
		"health",
		"FIELD HEALTH",
		"%s  BLOOD %d/12  AWARE %d/12" % [
			str(player.get("name", "PLAYER")).to_upper(),
			roundi(float(player.get("blood", 0.0))),
			roundi(float(player.get("consciousness", 0.0))),
		]
	)
	var weapon: Dictionary = player.get("ranged_weapon", {})
	if weapon.is_empty():
		weapon = player.get("melee_weapon", {})
	var weapon_summary := "UNARMED" if weapon.is_empty() else str(weapon.get("name", "WEAPON")).to_upper()
	if int(weapon.get("max_magazine", 0)) > 0:
		weapon_summary += "  %d/%d" % [int(weapon.get("current_magazine", 0)), int(weapon.get("max_magazine", 0))]
	_set_corner_preview("loadout", "HANDS & LOADOUT", weapon_summary)
	var sector := _sector(selected_sector)
	if sector.is_empty():
		sector = _sector(player.get("sector", Vector2i(-1, -1)))
	var coords: Vector2i = sector.get("coords", Vector2i.ZERO)
	_set_corner_preview(
		"site",
		"BATTLE SITE",
		"SECTOR %d,%d  %s" % [coords.x, coords.y, str(sector.get("surface_label", "TERRAIN")).to_upper()]
	)
	var inspected := _actor(_selected_occupant_id(sector.get("coords", Vector2i(-1, -1))))
	var hostile_summary := "NO ACTOR SELECTED"
	if not inspected.is_empty():
		hostile_summary = "%s  BLOOD %d/12" % [
			str(inspected.get("name", "ACTOR")).to_upper(),
			roundi(float(inspected.get("blood", 0.0))),
		]
	_set_corner_preview("hostile", "FIELD CONDITION", hostile_summary)


func _clear_target_inspector() -> void:
	target_heading.visible = false
	target_heading.text = "SELECTED CONDITION"
	target_name.text = "NO TARGET"
	target_summary.text = "Select an actor to inspect injuries and equipment."
	target_label.text = ""
	target_body.visible = false
	target_vitals.visible = false
	wound_heading.visible = false
	target_item_heading.visible = false
	_clear_children(wounds)
	_clear_children(target_items)


func _render_actor_inspector(actor: Dictionary) -> void:
	var is_player := str(actor.get("team_id", "")) == "player"
	target_heading.visible = true
	target_heading.text = "FIELD CONDITION" if is_player else "HOSTILE CONDITION"
	target_name.text = str(actor.get("name", "ACTOR")).to_upper()
	var condition_parts: Array[String] = []
	if bool(actor.get("broken", false)):
		condition_parts.append("BROKEN")
	if bool(actor.get("incapacitated", false)):
		condition_parts.append("INCAPACITATED")
	if bool(actor.get("surrendered", false)):
		condition_parts.append("SURRENDERED")
	var condition_label := "ACTIVE" if condition_parts.is_empty() else " / ".join(condition_parts)
	target_summary.text = "%s · STANCE %.1f/%.1f" % [
		condition_label,
		float(actor.get("stance", 0.0)),
		float(actor.get("max_stance", 0.0)),
	]
	target_body.visible = true
	target_vitals.visible = true
	wound_heading.visible = true
	target_body.set_actor_snapshot(actor)
	_set_vital(target_blood_bar, target_blood_value, float(actor.get("blood", 0.0)))
	_set_vital(target_pain_bar, target_pain_value, float(actor.get("pain", 0.0)))
	_set_vital(target_shock_bar, target_shock_value, float(actor.get("shock", 0.0)))
	_set_vital(target_consciousness_bar, target_consciousness_value, float(actor.get("consciousness", 0.0)))
	_render_wounds(actor.get("wounds", []))
	_render_target_items(actor.get("items", []), str(actor.get("actor_id", "")))
	target_label.text = _weapon_summary(actor)


func _render_sector_inspector(sector: Dictionary) -> void:
	if sector.is_empty():
		hex_title.text = "BATTLE SITE"
		hex_summary.text = "Select a sector to inspect it."
		hex_details.text = "Terrain details remain pinned here."
		_render_ground_items([])
		return
	hex_title.text = "SECTOR %d,%d" % [sector.coords.x, sector.coords.y]
	hex_summary.text = str(sector.get("surface_label", "Terrain"))
	var details: Array[String] = []
	var move_modifier := int(sector.get("movement_modifier", 0))
	details.append("Movement: %s" % ("normal" if move_modifier == 0 else "%+d AP" % move_modifier))
	var concealment := float(sector.get("concealment", 0.0))
	if concealment > 0.0:
		details.append("Concealment: %d%%" % roundi(concealment * 100.0))
	var cover := _cover_summary(sector.get("cover_edges", {}))
	if not cover.is_empty():
		details.append("Cover: %s" % cover)
	var hazards: Dictionary = sector.get("hazards", {})
	if not hazards.is_empty():
		details.append("Hazards: %s" % ", ".join(hazards.keys()))
	var object_state: Dictionary = sector.get("object", {})
	if not object_state.is_empty() and not str(object_state.get("label", "")).is_empty():
		details.append("Object: %s" % str(object_state.get("label", "")))
	_render_ground_items(sector.get("ground_items", []))
	hex_details.text = "\n".join(details)


func _render_forecast(value: CombatActionQuote) -> void:
	forecast_label.text = _forecast_text(value)


func _forecast_text(value: CombatActionQuote) -> String:
	if not value.legal:
		return value.denial_message
	var parts: Array[String] = []
	if value.movement_ap_cost > 0 and value.action_ap_cost > 0:
		parts.append("MOVE %d + ACTION %d = %d AP" % [value.movement_ap_cost, value.action_ap_cost, value.ap_cost])
	elif value.movement_ap_cost > 0:
		parts.append("MOVE %d AP" % value.movement_ap_cost)
	else:
		parts.append("%d AP" % value.ap_cost)
	# Only attack-like actions have a hit/armour/bleed forecast.  Maintenance,
	# communication, End Turn, and object actions may carry a compatibility
	# forecast object, but showing it here makes an otherwise valid action look
	# like a failed attack (for example: END TURN | HIT 0%).
	var has_attack_forecast := value.action_id in ["strike", "power_strike", "fire", "aimed_fire", "aimed_strike", "composite_move_attack"]
	if value.forecast != null and has_attack_forecast:
		parts.append("HIT %d%%" % roundi(value.forecast.hit_probability * 100.0))
		parts.append("ARMOR %s" % value.forecast.armor_result.to_upper())
		parts.append("BLEED %s" % value.forecast.bleeding_risk.to_upper())
		parts.append("SEVERE %s" % value.forecast.severe_wound_risk.to_upper())
		parts.append("INCAP %s" % value.forecast.incapacity_risk.to_upper())
		if not value.stance_forecast.is_empty():
			parts.append("STANCE %s" % str(value.stance_forecast.get("summary", "QUOTED")).to_upper())
	if value.action_id in ["fire", "aimed_fire", "reload", "cycle", "clear_malfunction"]:
		var actor := _actor(value.actor_id)
		var weapon: Dictionary = actor.get("ranged_weapon", {})
		if not weapon.is_empty():
			parts.append("AMMO %d/%d" % [int(weapon.get("current_magazine", 0)), int(weapon.get("max_magazine", 0))])
			parts.append("READY %s" % str(weapon.get("readiness", {}).get("reason", "ready")).to_upper())
	if value.cover_strength > 0.0:
		parts.append("COVER %d%%" % roundi(value.cover_strength * 100.0))
	if value.collateral_risk > 0.0:
		parts.append("COLLATERAL %d%%" % roundi(value.collateral_risk * 100.0))
	if not value.communication_acceptance_forecast.is_empty():
		var acceptance := bool(value.communication_acceptance_forecast.get("accepted", false))
		parts.append("RESPONSE %s" % ("LIKELY" if acceptance else "REFUSAL LIKELY"))
	return "  |  ".join(parts)


func _render_context_actions() -> void:
	if not is_node_ready() or selected_sector == Vector2i(-1, -1):
		return
	_clear_children(context_actions)
	_context_shortcuts.clear()
	var occupant_id := _selected_occupant_id()
	var context := _selection_context(occupant_id)
	var selected_sector_data := _sector(selected_sector)
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.ROOT_MENU:
		context_title.text = "CONTEXT"
		context_hint.text = "Choose a branch."
		if _has_context_branch(context, false):
			_add_context_branch("ACTION", false)
		if _has_context_branch(context, true):
			_add_context_branch("COMMUNICATION", true)
		context_menu.visible = not _context_shortcuts.is_empty()
		context_scroll.custom_minimum_size.y = clampf(float(_context_shortcuts.size()) * 36.0, 32.0, 176.0)
		call_deferred("_position_context_menu")
		call_deferred("_focus_first_context_action")
		return
	if not occupant_id.is_empty():
		context_title.text = str(_actor(occupant_id).get("name", "TARGET")).to_upper()
	elif context == CombatActionDefinition.CONTEXT_OBJECT:
		context_title.text = str(selected_sector_data.get("object", {}).get("label", "OBJECT")).to_upper()
	elif context == CombatActionDefinition.CONTEXT_ITEM:
		context_title.text = "ITEM AT SECTOR"
	else:
		context_title.text = "MOVE HERE"
	var communication_branch: bool = interaction.phase == INTERACTION_STATE_SCRIPT.Phase.COMMUNICATION_MENU
	if not communication_branch and context in [CombatActionDefinition.CONTEXT_HOSTILE_ACTOR, CombatActionDefinition.CONTEXT_NEUTRAL_ACTOR]:
		var attack_quote := _preferred_semantic_quote(["fire", "strike"])
		if attack_quote != null:
			var attack_label := "APPROACH + ATTACK" if attack_quote.approach_path.size() > 1 else "ATTACK"
			var attack_availability := Availability.AVAILABLE if attack_quote.legal else Availability.DISABLED
			if context == CombatActionDefinition.CONTEXT_NEUTRAL_ACTOR and attack_quote.denial_code == "neutral_attack_confirmation_required":
				attack_availability = Availability.AVAILABLE
				attack_label = "ATTACK — CONFIRM"
			_add_context_action(_definition(attack_quote.action_id), attack_quote, attack_availability, attack_label)
		# A shared sector is an Engagement. Shove exposes the four legal cardinal
		# destinations as a small contextual choice; the controller re-quotes the
		# chosen direction, so this surface never becomes a second rules engine.
		var target := _actor(occupant_id)
		var player := _actor(selected_actor_id)
		if not target.is_empty() and not player.is_empty() and target.get("sector", Vector2i(-1, -1)) == player.get("sector", Vector2i(-1, -1)):
			var shove_quote := _quote("shove")
			for direction in ["north", "east", "south", "west"]:
				_add_context_action(_definition("shove"), shove_quote, Availability.AVAILABLE, "SHOVE %s" % direction.to_upper(), direction)
	for action_quote in _sorted_quotes():
		var definition := _definition(action_quote.action_id)
		if definition == null or definition.action_id == "move" or not _is_player_visible(definition.action_id):
			continue
		if _is_communication_action(definition.action_id) != communication_branch:
			continue
		if definition.action_id in ["strike", "fire", "reload", "cycle", "clear_malfunction", "end_turn"]:
			continue
		var availability := _availability(definition, action_quote, context)
		if availability == Availability.HIDDEN:
			continue
		_add_context_action(definition, action_quote, availability)
	# The list scrolls inside the menu; its minimum height is deliberately
	# bounded so the menu remains usable at 1152x648 and 1280x720.
	context_scroll.custom_minimum_size.y = clampf(float(_context_shortcuts.size()) * 36.0, 32.0, 176.0)
	context_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if communication_branch:
		_coordinator().open_communication_menu()
	else:
		_coordinator().open_action_menu()
	context_menu.visible = true
	if current_quote == null:
		local_confirmation.visible = false
		context_hint.text = "Choose what you want to do here."
	call_deferred("_position_context_menu")
	call_deferred("_focus_first_context_action")


func _is_communication_action(action_id: String) -> bool:
	return action_id in ["offense", "defense", "support", "flee", "threaten", "ceasefire"]


func _has_context_branch(context: String, communication: bool) -> bool:
	for action_quote in _sorted_quotes():
		var definition := _definition(action_quote.action_id)
		if definition == null or not _is_player_visible(definition.action_id):
			continue
		if _is_communication_action(definition.action_id) != communication:
			continue
		if _availability(definition, action_quote, context) != Availability.HIDDEN:
			return true
	return false


func _add_context_branch(label: String, communication: bool) -> void:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.text = label
	HUD_ASSETS.apply_button(button)
	button.pressed.connect(func() -> void:
		if communication:
			_coordinator().open_communication_menu()
		else:
			_coordinator().open_action_menu()
		_render_context_actions()
	)
	_context_shortcuts.append(button)
	context_actions.add_child(button)


func _preferred_semantic_quote(action_ids: Array[String], allow_region_prompt: bool = false) -> CombatActionQuote:
	var player := _actor(selected_actor_id)
	var has_firearm: bool = not player.get("ranged_weapon", {}).is_empty()
	for action_id in action_ids:
		if action_id in ["fire", "aimed_fire"] and not has_firearm:
			continue
		var candidate := _quote(action_id)
		if candidate != null and (candidate.legal or (allow_region_prompt and candidate.denial_code == "body_region_required")):
			return candidate
	var preferred := action_ids[0] if has_firearm else action_ids[-1]
	return _quote(preferred)


func _focus_first_context_action() -> void:
	if not context_menu.visible:
		return
	for button in _context_shortcuts:
		if button.has_focus():
			return
	for button in _context_shortcuts:
		if not button.disabled:
			button.grab_focus()
			return


func _add_context_action(
	definition: CombatActionDefinition,
	action_quote: CombatActionQuote,
	availability: Availability = Availability.AVAILABLE,
	label_override: String = "",
	shove_direction: String = ""
) -> void:
	if definition == null:
		return
	var button := Button.new()
	button.custom_minimum_size = Vector2(250.0, 36.0)
	HUD_ASSETS.apply_button(button)
	var suffix := "%d AP" % action_quote.ap_cost if action_quote.legal else _short_denial(action_quote)
	var action_label := label_override if not label_override.is_empty() else definition.label.to_upper()
	button.text = "%s    %s" % [action_label, suffix]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = _action_explanation(definition)
	button.disabled = availability == Availability.DISABLED
	button.set_meta("action_id", definition.action_id)
	button.mouse_entered.connect(func() -> void:
		context_hint.text = _action_explanation(definition)
		_render_forecast(action_quote)
	)
	button.focus_entered.connect(func() -> void:
		context_hint.text = _action_explanation(definition)
		_render_forecast(action_quote)
	)
	button.pressed.connect(_on_action_button.bind(definition.action_id, action_quote, shove_direction))
	var index := _context_shortcuts.size()
	if index < 9:
		button.text = "[%d]  %s" % [index + 1, button.text]
	_context_shortcuts.append(button)
	context_actions.add_child(button)


func _availability(
	definition: CombatActionDefinition,
	action_quote: CombatActionQuote,
	context: String
) -> Availability:
	if not _is_player_visible(definition.action_id) or definition.context_visibility == "reaction_only":
		return Availability.HIDDEN
	if definition.context_visibility != "always" and context not in definition.inferred_selection_contexts():
		return Availability.HIDDEN
	var player := _actor(selected_actor_id)
	if definition.action_id == "leave_battle" and bool(snapshot.get("arena", {}).get("player_hostile_active", true)):
		return Availability.HIDDEN
	if "ranged_weapon" in definition.required_equipment_tags and player.get("ranged_weapon", {}).is_empty():
		return Availability.HIDDEN
	if definition.action_id == "take_cover" and not _arena_has_cover():
		return Availability.HIDDEN
	if definition.action_id == "strip":
		var target := _actor(_selected_occupant_id())
		if not bool(target.get("dead", false)) and not bool(target.get("incapacitated", false)):
			return Availability.HIDDEN
	if definition.action_id in ["incapacitate", "execute"]:
		var terminal_target := _actor(_selected_occupant_id())
		if not bool(terminal_target.get("broken", false)) and not bool(terminal_target.get("incapacitated", false)):
			return Availability.HIDDEN
		if definition.action_id == "incapacitate" and bool(terminal_target.get("incapacitated", false)):
			return Availability.HIDDEN
	if definition.action_id == "stand" and str(player.get("posture", "standing")) == "standing":
		return Availability.HIDDEN
	if definition.action_id == "crouch" and str(player.get("posture", "standing")) == "crouched":
		return Availability.HIDDEN
	return Availability.AVAILABLE if action_quote.legal else Availability.DISABLED


func _on_action_button(action_id: String, action_quote: CombatActionQuote, shove_direction: String = "") -> void:
	if action_id == "shove" and not shove_direction.is_empty():
		interaction.selected_shove_direction = shove_direction
	if action_quote != null and action_quote.denial_code == "neutral_attack_confirmation_required":
		interaction.declared_neutral_attack_confirmation = true
	if not action_quote.legal and action_quote.denial_code not in ["body_region_required", "cardinal_direction_required"]:
		if action_quote.denial_code == "neutral_attack_confirmation_required":
			action_selected.emit(action_id)
			return
		return
	var definition := _definition(action_id)
	if definition != null and not definition.requires_confirmation:
		action_selected.emit(action_id)
		return
	show_quote(action_quote)
	action_selected.emit(action_id)


func _on_end_turn_pressed() -> void:
	var action_quote := _quote("end_turn")
	if action_quote == null or not action_quote.legal:
		show_feedback(action_quote.denial_message if action_quote != null else "End turn is unavailable.")
		return
	show_quote(action_quote)
	action_selected.emit("end_turn")


func _is_player_visible(action_id: String) -> bool:
	return catalog != null and catalog.is_player_visible(action_id)


func _refresh_global_actions() -> void:
	if not is_node_ready():
		return
	var action_quote := _quote("end_turn")
	var active_player := str(snapshot.get("active_actor_id", "")) == selected_actor_id
	end_turn_button.disabled = not active_player or interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING or reaction_panel.visible or action_quote == null or not action_quote.legal
	end_turn_button.tooltip_text = "Finish the turn and pass initiative." if not end_turn_button.disabled else (action_quote.denial_message if action_quote != null else "End turn is unavailable.")


func _render_weapon_actions() -> void:
	if not is_node_ready():
		return
	_clear_children(weapon_actions)
	_weapon_action_buttons.clear()
	var weapon: Dictionary = _actor(selected_actor_id).get("ranged_weapon", {})
	weapon_actions.visible = not weapon.is_empty()
	if weapon.is_empty():
		return
	_add_weapon_action("reload", true)
	var readiness := str(weapon.get("readiness", {}).get("reason", "ready"))
	if readiness in ["jammed", "malfunction"] or bool(weapon.get("is_jammed", false)):
		_add_weapon_action("cycle", true)
	if bool(weapon.get("requires_ready_action", false)):
		_add_weapon_action("ready", true)


func _add_weapon_action(action_id: String, visible: bool) -> void:
	if not visible:
		return
	var action_quote := _quote(action_id)
	var definition := _definition(action_id)
	if definition == null:
		return
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	HUD_ASSETS.apply_button(button)
	var reason := "%d AP" % action_quote.ap_cost if action_quote != null and action_quote.legal else _weapon_denial_text(action_id, action_quote)
	button.text = "%s  —  %s" % [definition.label.to_upper(), reason]
	button.disabled = action_quote == null or not action_quote.legal
	button.tooltip_text = action_quote.denial_message if action_quote != null and not action_quote.legal else definition.description
	button.set_meta("action_id", action_id)
	button.pressed.connect(_on_action_button.bind(action_id, action_quote))
	weapon_actions.add_child(button)
	_weapon_action_buttons[action_id] = button


func _weapon_denial_text(action_id: String, action_quote: CombatActionQuote) -> String:
	if action_quote == null:
		return "UNAVAILABLE"
	match action_quote.denial_code:
		"reload_not_needed":
			return "MAGAZINE FULL"
		"ammunition_unavailable":
			return "NO COMPATIBLE AMMO"
		"cycle_not_needed":
			return "WEAPON ALREADY READY"
		"no_malfunction":
			return "NO MALFUNCTION"
		"weapon_already_ready":
			return "WEAPON ALREADY READY"
		"weapon_not_ready":
			return "CLEAR JAM FIRST"
	return _short_denial(action_quote).to_upper()


func _on_aim_body_region_selected(region: int) -> void:
	selected_body_region = region
	body_region_selected.emit(region)
	action_selected.emit(_pending_aim_action)


func _confirm_aim_targeting() -> void:
	if current_quote != null and current_quote.legal:
		action_confirmed.emit()


func _cancel_aim_targeting() -> void:
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING:
		return
	current_quote = null
	selected_body_region = -1
	arena_view.clear_quote()
	_close_aim_panel()
	interaction.cancel_one_step()
	selection_cancelled.emit()
	_render_context_actions()


func _close_aim_panel() -> void:
	var restore_id := _aim_restore_corner_id
	_pending_aim_action = ""
	aim_target_panel.visible = false
	aim_target_body.set_selectable(false)
	hex_panel.visible = true
	right_panel.visible = true
	_aim_restore_corner_id = ""
	if not restore_id.is_empty() and _corner_states.has(restore_id):
		_expanded_corner_id = restore_id
		for id in _corner_states:
			_corner_states[id].set_expanded(str(id) == restore_id)
	_apply_corner_states()
	_refresh_global_actions()


func _toggle_pack() -> void:
	items.visible = not items.visible
	item_heading.text = "ITEMS [I]  %s" % ["v" if items.visible else ">"]


func _confirm_local() -> void:
	if current_quote != null and current_quote.legal:
		action_confirmed.emit()


func _cancel_selection() -> void:
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING:
		return
	if aim_target_panel.visible:
		_cancel_aim_targeting()
		return
	if current_quote != null or local_confirmation.visible:
		current_quote = null
		interaction.staged_action_id = ""
		local_confirmation.visible = false
		arena_view.clear_quote()
		if _selection_context(_selected_occupant_id()) == CombatActionDefinition.CONTEXT_HOSTILE_ACTOR:
			_set_phase(INTERACTION_STATE_SCRIPT.Phase.ACTION_MENU)
			_render_context_actions()
		else:
			_set_phase(INTERACTION_STATE_SCRIPT.Phase.INSPECTING)
			context_menu.visible = false
		selection_cancelled.emit()
		return
	if context_menu.visible:
		context_menu.visible = false
		_set_phase(INTERACTION_STATE_SCRIPT.Phase.ROUTE_PREVIEW if not _route_path.is_empty() else INTERACTION_STATE_SCRIPT.Phase.INSPECTING)
		selection_cancelled.emit()
		return
	_cancel_complete_chain()


func _has_active_interaction() -> bool:
	return aim_target_panel.visible or context_menu.visible or current_quote != null or not _route_path.is_empty()


func _on_sector_selected(coords: Vector2i) -> void:
	if current_quote != null and current_quote.action_id == "move" and current_quote.legal and coords == current_quote.target_sector:
		action_confirmed.emit()
		return
	var occupant_id := _occupant_for_selection(coords, selected_sector, interaction.selected_actor_id)
	if occupant_id == selected_actor_id and not occupant_id.is_empty():
		_on_arena_inspect_requested(coords, occupant_id)
		return
	_on_arena_context_requested(coords, occupant_id)
	_coordinator().open_action_menu()
	_render_context_actions()


func _on_arena_inspect_requested(coords: Vector2i, actor_id: String) -> void:
	if interaction.phase == INTERACTION_STATE_SCRIPT.Phase.PRESENTING:
		return
	clear_staged_action()
	selected_sector = coords
	selected_item_id = ""
	selected_wound_id = ""
	selected_body_region = -1
	_select_interaction("actor" if not actor_id.is_empty() else "sector", {
		"actor_id": actor_id,
		"sector": coords,
	})
	_render_inspector()
	context_menu.visible = false
	_set_phase(INTERACTION_STATE_SCRIPT.Phase.INSPECTING)


func _on_arena_context_requested(coords: Vector2i, actor_id: String) -> void:
	_on_arena_inspect_requested(coords, actor_id)
	_coordinator().open_root_menu()
	context_requested.emit(coords)
	_render_context_actions()


func _on_player_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_player()
		accept_event()


func _select_player() -> void:
	var player := _actor(selected_actor_id)
	var sector: Vector2i = player.get("sector", Vector2i(-1, -1))
	if sector != Vector2i(-1, -1):
		if sector == selected_sector:
			_render_inspector()
			_render_context_actions()
			return
		arena_view.select_sector(sector)
		_on_sector_selected(sector)


func _cycle_actor(direction: int) -> void:
	if selected_sector == Vector2i(-1, -1):
		return
	var occupants: Array[String] = []
	var sector_data := _sector(selected_sector)
	for raw_id in sector_data.get("occupant_ids", []):
		var occupant_id := str(raw_id)
		if not occupant_id.is_empty():
			occupants.append(occupant_id)
	if occupants.is_empty():
		var legacy_id := str(sector_data.get("occupant_id", ""))
		if not legacy_id.is_empty():
			occupants.append(legacy_id)
	if occupants.size() < 2:
		return
	var current_id := _selected_occupant_id()
	var current_index := occupants.find(current_id)
	var next_index := posmod(current_index + direction, occupants.size())
	interaction.selected_actor_id = occupants[next_index]
	interaction.selected_kind = "actor"
	interaction.declared_neutral_attack_confirmation = false
	_render_inspector()
	_render_context_actions()


func _on_sector_hovered(coords: Vector2i) -> void:
	var sector := _sector(coords)
	if not sector.is_empty():
		arena_view.tooltip_text = str(sector.get("surface_label", "Sector"))


func _on_sector_unhovered() -> void:
	arena_view.tooltip_text = ""


func _render_wounds(actor_wounds: Array) -> void:
	_clear_children(wounds)
	wound_heading.visible = not actor_wounds.is_empty()
	for wound in actor_wounds:
		var button := Button.new()
		HUD_ASSETS.apply_button(button)
		var region := _region_label(int(wound.get("body_region", -1)))
		var state := "STABLE" if bool(wound.get("stabilized", false)) else "BLEED %.1f" % float(wound.get("bleeding_rate", 0.0))
		button.text = "%s · %s · S%.1f · %s" % [
			region,
			str(wound.get("wound_type", "wound")).capitalize(),
			float(wound.get("severity", 0.0)),
			state,
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var wound_id := str(wound.get("wound_id", ""))
		button.pressed.connect(_on_wound_button.bind(wound_id))
		wounds.add_child(button)
	if actor_wounds.is_empty():
		var none := Label.new()
		none.text = "No visible wounds"
		none.add_theme_color_override("font_color", Color("70807d"))
		wounds.add_child(none)
		wound_heading.visible = true


func _render_target_items(actor_items: Array, actor_id: String) -> void:
	_clear_children(target_items)
	var show_items := not actor_id.is_empty() and actor_id != selected_actor_id and not actor_items.is_empty()
	target_item_heading.visible = show_items
	if not show_items:
		return
	for item in actor_items:
		var button := Button.new()
		HUD_ASSETS.apply_button(button)
		button.text = "%s · %s" % [
			str(item.get("name", "ITEM")),
			str(item.get("access", "carried")).capitalize(),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var instance_id := str(item.get("instance_id", ""))
		button.pressed.connect(_on_target_item_button.bind(instance_id, actor_id))
		target_items.add_child(button)


func _render_ground_items(ground_item_descriptors: Array) -> void:
	_clear_children(ground_items)
	ground_item_heading.visible = not ground_item_descriptors.is_empty()
	if ground_item_descriptors.is_empty():
		return
	for item in ground_item_descriptors:
		var button := Button.new()
		HUD_ASSETS.apply_button(button)
		button.text = "%s · %s" % [
			str(item.get("name", "GROUND ITEM")),
			str(item.get("access", "ground")).capitalize(),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var instance_id := str(item.get("instance_id", ""))
		button.pressed.connect(_on_ground_item_button.bind(instance_id))
		ground_items.add_child(button)


func _render_items(actor_items: Array) -> void:
	_clear_children(items)
	for item in actor_items:
		var button := Button.new()
		HUD_ASSETS.apply_button(button)
		button.text = "%s · %s · %d/12" % [
			str(item.get("name", "ITEM")),
			str(item.get("access", "unknown")).capitalize(),
			roundi(float(item.get("condition", 0.0))),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var instance_id := str(item.get("instance_id", ""))
		button.pressed.connect(_on_inventory_item_button.bind(instance_id))
		items.add_child(button)


func _on_wound_button(wound_id: String) -> void:
	clear_staged_action()
	selected_wound_id = wound_id
	selected_item_id = ""
	_select_interaction("wound", {"wound_id": wound_id, "sector": selected_sector})
	wound_selected.emit(wound_id)
	_render_context_actions()


func _on_target_item_button(instance_id: String, actor_id: String) -> void:
	clear_staged_action()
	selected_item_id = instance_id
	selected_wound_id = ""
	_select_interaction("item", {"item_id": instance_id, "sector": selected_sector, "actor_id": actor_id})
	item_selected.emit(instance_id)
	_render_context_actions()


func _on_ground_item_button(instance_id: String) -> void:
	clear_staged_action()
	selected_item_id = instance_id
	selected_wound_id = ""
	_select_interaction("item", {"item_id": instance_id, "sector": selected_sector})
	item_selected.emit(instance_id)
	_render_context_actions()


func _on_inventory_item_button(instance_id: String) -> void:
	clear_staged_action()
	var player := _actor(selected_actor_id)
	var player_sector: Vector2i = player.get("sector", Vector2i(-1, -1))
	if player_sector != Vector2i(-1, -1) and player_sector != selected_sector:
		selected_sector = player_sector
		arena_view.select_sector(player_sector)
		_render_inspector()
	selected_item_id = instance_id
	# Keep a selected wound active so the treatment action has both required targets.
	if selected_wound_id.is_empty():
		_select_interaction("item", {"item_id": instance_id, "sector": selected_sector})
	else:
		_select_interaction("wound", {"wound_id": selected_wound_id, "item_id": instance_id, "sector": selected_sector})
	item_selected.emit(instance_id)
	_render_context_actions()


func _position_context_menu() -> void:
	if not context_menu.visible or selected_sector == Vector2i(-1, -1):
		return
	context_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var arena_rect := arena_view.get_global_rect().grow(-8.0)
	var menu_size := context_menu.get_combined_minimum_size()
	menu_size.x = clampf(menu_size.x, 280.0, minf(300.0, maxf(280.0, arena_rect.size.x - 16.0)))
	menu_size.y = clampf(menu_size.y, 120.0, maxf(120.0, arena_rect.size.y - 16.0))
	context_menu.size = menu_size
	var desired := arena_view.global_position + arena_view.sector_center(selected_sector) + Vector2(20.0, -40.0)
	# Compact previews are overlays, not permanent camera columns. Only an
	# expanded left panel changes the menu's safe bounds; the preview may be
	# temporarily covered by a contextual surface and remains one click away.
	var corner_clearance := 16.0
	if _expanded_corner_id in ["health", "loadout"]:
		var expanded_panel := _corner_panels.get(_expanded_corner_id) as Control
		corner_clearance = expanded_panel.size.x + 20.0 if expanded_panel != null else 16.0
	arena_rect.position.x = maxf(arena_rect.position.x, corner_clearance)
	arena_rect.size.x = minf(arena_rect.end.x, size.x - corner_clearance) - arena_rect.position.x
	var max_pos := Vector2(
		maxf(arena_rect.position.x, arena_rect.end.x - context_menu.size.x),
		maxf(arena_rect.position.y, arena_rect.end.y - context_menu.size.y)
	)
	var clamped := Vector2(
		clampf(desired.x, arena_rect.position.x, max_pos.x),
		clampf(desired.y, arena_rect.position.y, max_pos.y)
	)
	context_menu.position = clamped - global_position


func _invoke_visible_action(action_id: String) -> bool:
	for button in _context_shortcuts:
		if not button.disabled and str(button.get_meta("action_id", "")) == action_id:
			button.pressed.emit()
			return true
	return false


func _selection_context(occupant_id: String) -> String:
	if not selected_wound_id.is_empty():
		return CombatActionDefinition.CONTEXT_WOUND
	if not selected_item_id.is_empty():
		var occupant := _actor(occupant_id)
		if not occupant.is_empty() and occupant_id != selected_actor_id:
			return CombatActionDefinition.CONTEXT_HOSTILE_ACTOR
		return CombatActionDefinition.CONTEXT_ITEM
	if occupant_id == selected_actor_id:
		return CombatActionDefinition.CONTEXT_SELF
	if not occupant_id.is_empty():
		match _relation_for_ids(selected_actor_id, occupant_id):
			0:
				return CombatActionDefinition.CONTEXT_FRIENDLY_ACTOR
			1:
				return CombatActionDefinition.CONTEXT_NEUTRAL_ACTOR
			_:
				return CombatActionDefinition.CONTEXT_HOSTILE_ACTOR
	var sector := _sector(selected_sector)
	if not sector.get("object", {}).is_empty():
		return CombatActionDefinition.CONTEXT_OBJECT
	return CombatActionDefinition.CONTEXT_SECTOR


func _sorted_quotes() -> Array[CombatActionQuote]:
	var ordered := quotes.duplicate()
	ordered.sort_custom(func(left: CombatActionQuote, right: CombatActionQuote) -> bool:
		var left_definition := _definition(left.action_id)
		var right_definition := _definition(right.action_id)
		var left_priority := left_definition.menu_priority if left_definition != null else 0
		var right_priority := right_definition.menu_priority if right_definition != null else 0
		return left_priority < right_priority
	)
	return ordered


func _definition(action_id: String) -> CombatActionDefinition:
	return _definitions.get(action_id) as CombatActionDefinition


func _quote(action_id: String) -> CombatActionQuote:
	return _quote_by_action.get(action_id) as CombatActionQuote


func _actor(actor_id: String) -> Dictionary:
	for actor in snapshot.get("actors", []):
		if str(actor.get("actor_id", "")) == actor_id:
			return actor
	return {}


func _sector(coords: Vector2i) -> Dictionary:
	for sector in snapshot.get("arena", {}).get("sectors", []):
		if sector.get("coords", Vector2i(-1, -1)) == coords:
			return sector
	return {}


func _occupant_at(coords: Vector2i) -> String:
	var sector := _sector(coords)
	var ids := _occupant_ids(sector)
	return str(ids[0]) if not ids.is_empty() else ""


func _selected_occupant_id(coords: Vector2i = Vector2i(-1, -1)) -> String:
	if coords == Vector2i(-1, -1):
		coords = selected_sector
	var ids := _occupant_ids(_sector(coords))
	if ids.is_empty():
		return ""
	# Shared sectors can be cycled by clicking the same hex.  The interaction
	# state owns that typed selection; never silently fall back to occupant slot
	# zero when building the authoritative request.
	if coords == selected_sector and interaction.selected_kind == "actor":
		var selected: String = str(interaction.selected_actor_id)
		if not selected.is_empty() and selected in ids:
			return selected
	return str(ids[0])


func _occupant_for_selection(coords: Vector2i, prior_sector: Vector2i, prior_actor_id: String) -> String:
	var ids := _occupant_ids(_sector(coords))
	if ids.is_empty():
		return ""
	if prior_sector == coords and prior_actor_id in ids and ids.size() > 1:
		var current := ids.find(prior_actor_id)
		return str(ids[(current + 1) % ids.size()])
	return str(ids[0])


func _occupant_ids(sector: Dictionary) -> Array:
	if sector.is_empty():
		return []
	var ids: Array = sector.get("occupant_ids", [])
	if ids.is_empty() and not str(sector.get("occupant_id", "")).is_empty():
		ids = [str(sector.get("occupant_id", ""))]
	return ids


func _relation_for_ids(left_id: String, right_id: String) -> int:
	if left_id.is_empty() or right_id.is_empty() or left_id == right_id:
		return 0
	var relationships: Dictionary = snapshot.get("arena", {}).get("relationships", {})
	var relation_by_pair: Dictionary = relationships.get("relation_by_pair", {})
	var pair := [left_id, right_id]
	pair.sort()
	var key := "%s|%s" % [pair[0], pair[1]]
	if relation_by_pair.has(key):
		return int(relation_by_pair[key])
	var left := _actor(left_id)
	var right := _actor(right_id)
	var left_team := str(left.get("team_id", ""))
	var right_team := str(right.get("team_id", ""))
	if not left_team.is_empty() and left_team == right_team:
		return 0
	return 2


func _cover_summary(edges: Dictionary) -> String:
	var active: Array[String] = []
	for edge in edges:
		if float(edges[edge]) > 0.0:
			active.append("%s %d%%" % [str(edge).capitalize(), roundi(float(edges[edge]) * 100.0)])
	return ", ".join(active)


func _arena_has_cover() -> bool:
	for sector in snapshot.get("arena", {}).get("sectors", []):
		if not _cover_summary(sector.get("cover_edges", {})).is_empty():
			return true
	return false


func _weapon_summary(actor: Dictionary) -> String:
	var weapon: Dictionary = actor.get("ranged_weapon", {})
	if weapon.is_empty():
		weapon = actor.get("melee_weapon", {})
	if weapon.is_empty():
		return "Unarmed"
	var lines: Array[String] = ["[b]%s[/b]" % str(weapon.get("name", "Weapon"))]
	if int(weapon.get("max_magazine", 0)) > 0:
		lines.append("Ammunition: %d/%d · %s" % [
			int(weapon.get("current_magazine", 0)),
			int(weapon.get("max_magazine", 0)),
			str(weapon.get("readiness", {}).get("reason", "ready")).capitalize(),
		])
	lines.append("Condition: %d/12" % roundi(float(weapon.get("condition", 0.0))))
	return "\n".join(lines)


func _action_explanation(definition: CombatActionDefinition) -> String:
	if definition == null:
		return ""
	if not definition.player_consequence.strip_edges().is_empty():
		return definition.player_consequence
	if not definition.description.strip_edges().is_empty():
		return definition.description
	return definition.label


func _short_denial(action_quote: CombatActionQuote) -> String:
	return {
		"insufficient_ap": "NEEDS MORE AP",
		"target_out_of_range": "OUT OF RANGE",
		"cardinal_reach_required": "NEEDS ADJACENCY",
		"line_of_sight_blocked": "NO CLEAR SHOT",
		"empty": "EMPTY",
		"weapon_empty": "EMPTY",
		"cycle_required": "NEEDS CYCLING",
		"malfunction": "MALFUNCTION",
		"body_region_required": "CHOOSE REGION",
		"invalid_target_item": "CHOOSE ITEM",
		"invalid_target_wound": "CHOOSE WOUND",
		"object_missing": "NO OBJECT",
	}.get(action_quote.denial_code, action_quote.denial_code.replace("_", " ").to_upper())


func _region_label(region: int) -> String:
	if region < 0 or region >= GameEnums.LimbRegion.size():
		return "Body"
	return str(GameEnums.LimbRegion.keys()[region]).replace("_", " ").capitalize()


func _set_vital(bar: ProgressBar, value_label: Label, value: float) -> void:
	bar.max_value = GameEnums.SCALE_MAX
	bar.value = clampf(value, 0.0, GameEnums.SCALE_MAX)
	if value_label != null:
		value_label.text = "%d/12" % roundi(value)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
