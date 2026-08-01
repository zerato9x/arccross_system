extends Control
class_name TacticalCombatHUD

signal sector_selected(coords: Vector2i)
signal action_selected(action_id: String)
signal action_confirmed
signal selection_cancelled
signal item_selected(instance_id: String)
signal wound_selected(wound_id: String)
signal body_region_selected(region: int)
signal reaction_selected(action_id: String)

enum Availability { HIDDEN, DISABLED, AVAILABLE }

const HUD_ASSETS := preload("res://UI/HUD/HUDAssetLibrary.gd")

@onready var arena_view: TacticalArenaView = %TacticalArenaView
@onready var initiative_row: HBoxContainer = %InitiativeRow
@onready var ap_label: Label = %APLabel
@onready var actor_name: Label = %ActorName
@onready var player_card: PanelContainer = %PlayerCard
@onready var actor_status: Label = %ActorStatus
@onready var active_weapon_card: CombatItemCard = %ActiveWeaponCard
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
@onready var hex_panel: PanelContainer = %HexPanel
@onready var hex_title: Label = %HexTitle
@onready var hex_summary: Label = %HexSummary
@onready var hex_details: RichTextLabel = %HexDetails
@onready var wounds: VBoxContainer = %Wounds
@onready var wound_heading: Label = %WoundHeading
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
@onready var reaction_actions: HBoxContainer = %ReactionActions

var snapshot: Dictionary = {}
var quotes: Array[CombatActionQuote] = []
var selected_sector := Vector2i(-1, -1)
var selected_actor_id := ""
var selected_item_id := ""
var selected_wound_id := ""
var selected_body_region := -1
var current_quote: CombatActionQuote
var interaction := CombatInteractionState.new()
var _definitions: Dictionary = {}
var _quote_by_action: Dictionary = {}
var _pending_aim_action := ""
var _context_shortcuts: Array[Button] = []


func _ready() -> void:
	_ensure_input_actions()
	_compact_weapon_card()
	_style_vitals()
	_apply_macro_aesthetic()
	resized.connect(_layout_corner_panels)
	arena_view.sector_selected.connect(_on_sector_selected)
	arena_view.sector_hovered.connect(_on_sector_hovered)
	arena_view.sector_unhovered.connect(_on_sector_unhovered)
	item_heading.pressed.connect(_toggle_pack)
	player_card.gui_input.connect(_on_player_card_input)
	player_card.mouse_filter = Control.MOUSE_FILTER_STOP
	cancel_button.pressed.connect(_cancel_selection)
	confirm_button.pressed.connect(_confirm_local)
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
	call_deferred("_layout_corner_panels")


func _compact_weapon_card() -> void:
	active_weapon_card.custom_minimum_size = Vector2(218.0, 72.0)
	var visual := active_weapon_card.get_node_or_null("Margin/Columns/Visual") as Control
	if visual != null:
		visual.custom_minimum_size = Vector2(76.0, 58.0)
	var margin := active_weapon_card.get_node_or_null("Margin") as MarginContainer
	if margin != null:
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			margin.add_theme_constant_override(side, 4)
	var grade := active_weapon_card.get_node_or_null("Margin/Columns/Info/GradeLabel") as Control
	var condition := active_weapon_card.get_node_or_null("Margin/Columns/Info/ConditionBar") as Control
	var details := active_weapon_card.get_node_or_null("Margin/Columns/Info/DetailLabel") as Control
	if grade != null:
		grade.visible = false
	if condition != null:
		condition.visible = false
	if details != null:
		details.visible = false
	active_weapon_card.weapon_name.add_theme_font_size_override("font_size", 13)
	active_weapon_card.ammo_label.add_theme_font_size_override("font_size", 13)
	active_weapon_card.state_label.add_theme_font_size_override("font_size", 11)


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
	for label in [actor_name, hex_title, target_name, aim_title]:
		HUD_ASSETS.apply_label(label as Label, "title")
	for label in [actor_status, hex_summary, target_summary, context_hint, aim_hint]:
		HUD_ASSETS.apply_label(label as Label, "muted")
	for label in [ap_label, forecast_label, aim_forecast]:
		HUD_ASSETS.apply_label(label as Label, "caution")
	HUD_ASSETS.apply_rich_label(hex_details, "body")
	HUD_ASSETS.apply_rich_label(target_label, "body")
	for button in [item_heading, cancel_button, confirm_button, aim_cancel_button, aim_confirm_button]:
		HUD_ASSETS.apply_button(button as Button)


func _layout_corner_panels() -> void:
	if not is_node_ready():
		return
	var margin := 12.0
	var top_y := 58.0
	var gap := 12.0
	var panel_width := clampf(size.x * 0.255, 340.0, 360.0)
	var usable_height := maxf(360.0, size.y - top_y - margin)
	var top_height := clampf(usable_height * 0.34, 175.0, 220.0)
	var bottom_height := maxf(180.0, usable_height - top_height - gap)
	player_card.position = Vector2(margin, top_y)
	player_card.size = Vector2(panel_width, top_height)
	inventory_panel.position = Vector2(margin, top_y + top_height + gap)
	inventory_panel.size = Vector2(panel_width, bottom_height)
	var right_x := size.x - margin - panel_width
	hex_panel.position = Vector2(right_x, top_y)
	hex_panel.size = Vector2(panel_width, top_height)
	right_panel.position = Vector2(right_x, top_y + top_height + gap)
	right_panel.size = Vector2(panel_width, bottom_height)
	var aim_width := clampf(size.x * 0.31, 350.0, 430.0)
	aim_target_panel.position = Vector2(size.x - margin - aim_width, top_y)
	aim_target_panel.size = Vector2(aim_width, usable_height)
	var camera_inset := panel_width + margin + gap
	var safe_width := maxf(320.0, size.x - camera_inset * 2.0)
	arena_view.set_camera_safe_rect(Rect2(
		Vector2((size.x - safe_width) * 0.5, 0.0),
		Vector2(safe_width, arena_view.size.y)
	))
	_position_context_menu()


func _ensure_input_actions() -> void:
	_register_input_action("combat_select", KEY_ENTER, JOY_BUTTON_A)
	_register_input_action("combat_cancel", KEY_ESCAPE, JOY_BUTTON_B)
	_register_input_action("combat_context", KEY_Q, JOY_BUTTON_X)
	_register_input_action("combat_move", KEY_M, JOY_BUTTON_INVALID)
	_register_input_action("combat_primary_attack", KEY_F, JOY_BUTTON_INVALID)
	_register_input_action("combat_items", KEY_I, JOY_BUTTON_Y)
	_register_input_action("combat_end_turn", KEY_E, JOY_BUTTON_INVALID)
	_register_input_action("combat_cycle_next", KEY_TAB, JOY_BUTTON_RIGHT_SHOULDER)
	_register_input_action("combat_cycle_previous", KEY_NONE, JOY_BUTTON_LEFT_SHOULDER)
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_selection()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_cancel") or event.is_action_pressed("ui_cancel"):
		_cancel_selection()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_select") or event.is_action_pressed("ui_accept"):
		if current_quote != null and current_quote.legal and aim_target_panel.visible:
			_confirm_aim_targeting()
			get_viewport().set_input_as_handled()
			return
		if current_quote != null and current_quote.legal and local_confirmation.visible:
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
		_select_player()
		items.visible = true
		item_heading.text = "ITEMS [I]  v"
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_primary_attack"):
		if _invoke_visible_action("fire") or _invoke_visible_action("strike"):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_move"):
		if _invoke_visible_action("move"):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("combat_end_turn"):
		_select_player()
		if _invoke_visible_action("end_turn"):
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
		if event.keycode == KEY_I:
			_toggle_pack()
			get_viewport().set_input_as_handled()
			return
		var number := int(event.keycode) - int(KEY_1)
		if number >= 0 and number < _context_shortcuts.size() and context_menu.visible:
			_context_shortcuts[number].pressed.emit()
			get_viewport().set_input_as_handled()
			return
		var mnemonic := {
			KEY_F: ["fire", "strike"],
			KEY_E: ["end_turn"],
			KEY_M: ["move"],
		}.get(event.keycode, []) as Array
		for action_id in mnemonic:
			if _invoke_visible_action(str(action_id)):
				get_viewport().set_input_as_handled()
				return


func configure_action_catalog(catalog: CombatActionCatalog) -> void:
	_definitions.clear()
	if catalog == null:
		return
	for definition in catalog.all():
		_definitions[definition.action_id] = definition


func show_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
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
	_render_context_actions()


func show_quotes(value: Array[CombatActionQuote]) -> void:
	quotes = value
	_quote_by_action.clear()
	for action_quote in quotes:
		_quote_by_action[action_quote.action_id] = action_quote
	_render_context_actions()


func show_quote(value: CombatActionQuote) -> void:
	current_quote = value
	arena_view.show_quote(value)
	interaction.stage(value.action_id, value.legal)
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
	context_menu.visible = true
	call_deferred("_position_context_menu")


func clear_staged_action() -> void:
	current_quote = null
	selected_body_region = -1
	confirm_button.disabled = true
	local_confirmation.visible = false
	forecast_label.text = "CHOOSE AN ACTION"
	feedback_label.text = ""
	aim_target_body.set_selectable(false)
	_close_aim_panel()
	arena_view.clear_quote()


func show_feedback(message: String) -> void:
	if aim_target_panel.visible:
		aim_feedback.text = "" if message == aim_forecast.text else message
		return
	feedback_label.text = message
	if not interaction.selected_kind.is_empty():
		context_menu.visible = true


func show_presentation_action(sequence: CombatPresentationSequence) -> void:
	if sequence == null:
		return
	interaction.begin_presentation()
	arena_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_menu.visible = false
	_close_aim_panel()
	active_weapon_card.play_turn_action(sequence.action_id, sequence.total_duration())


func finish_presentation() -> void:
	interaction.finish_presentation()
	arena_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_render_inspector()


func show_aim_targeter(action_id: String) -> void:
	_pending_aim_action = action_id
	var target := _actor(_occupant_at(selected_sector))
	if target.is_empty():
		show_feedback("Select a hostile actor first.")
		return
	interaction.begin_targeting(action_id)
	aim_title.text = "%s: SELECT REGION" % str(_definition(action_id).label if _definition(action_id) != null else action_id).to_upper()
	aim_hint.text = "Choose a body region, review the result, then confirm here."
	aim_forecast.text = "SELECT A REGION"
	aim_feedback.text = ""
	aim_confirm_button.disabled = true
	aim_target_body.set_actor_snapshot(target)
	aim_target_body.set_selectable(true)
	aim_target_panel.visible = true
	hex_panel.visible = false
	right_panel.visible = false
	context_menu.visible = false
	local_confirmation.visible = false


func show_reaction(prompt: Dictionary) -> void:
	_clear_children(reaction_actions)
	reaction_panel.visible = true
	for action_id in prompt.get("actions", []):
		var button := Button.new()
		button.text = str(action_id).replace("_", " ").to_upper()
		HUD_ASSETS.apply_button(button)
		button.pressed.connect(func() -> void:
			reaction_panel.visible = false
			reaction_selected.emit(str(action_id))
		)
		reaction_actions.add_child(button)
	var decline := Button.new()
	decline.text = "DECLINE"
	HUD_ASSETS.apply_button(decline)
	decline.pressed.connect(func() -> void:
		reaction_panel.visible = false
		reaction_selected.emit("decline")
	)
	reaction_actions.add_child(decline)


func hide_reaction() -> void:
	reaction_panel.visible = false


func selected_context() -> Dictionary:
	return {
		"target_sector": selected_sector,
		"target_actor_id": _occupant_at(selected_sector),
		"item_instance_id": selected_item_id,
		"wound_id": selected_wound_id,
		"body_region": selected_body_region,
		"facing": "",
	}


func _render_top() -> void:
	_clear_children(initiative_row)
	for actor in snapshot.get("actors", []):
		var chip := Label.new()
		var active := str(actor.get("actor_id", "")) == str(snapshot.get("active_actor_id", ""))
		chip.text = "%s%s" % ["> " if active else "", str(actor.get("name", "ACTOR")).to_upper()]
		chip.add_theme_color_override("font_color", Color("f0ce76") if active else Color("8ea0a4"))
		initiative_row.add_child(chip)
	var reserved: Dictionary = snapshot.get("reserved_ap", {})
	ap_label.text = "ROUND %02d   AP %02d/12   RESERVED %02d" % [
		int(snapshot.get("round", 0)),
		int(snapshot.get("ap", 0)),
		int(reserved.get(snapshot.get("active_actor_id", ""), 0)),
	]


func _render_player_card() -> void:
	var actor := _actor(selected_actor_id)
	if actor.is_empty():
		actor_name.text = "NO ACTOR"
		return
	actor_name.text = str(actor.get("name", selected_actor_id)).to_upper()
	actor_status.text = "%s · FACING %s" % [
		str(actor.get("posture", "standing")).to_upper(),
		str(actor.get("facing", "east")).to_upper(),
	]
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
		if float(wound.get("severity", 0.0)) >= 6.0 or float(wound.get("bleeding_rate", 0.0)) >= 1.0:
			warnings.append("SEVERE WOUND")
			break
	player_warnings.text = "  ".join(warnings)
	var ranged_weapon: Dictionary = actor.get("ranged_weapon", {})
	var weapon: Dictionary = ranged_weapon if not ranged_weapon.is_empty() else actor.get("melee_weapon", {})
	active_weapon_card.visible = not weapon.is_empty()
	if not weapon.is_empty():
		active_weapon_card.show_descriptor(weapon, not ranged_weapon.is_empty())
	_render_items(actor.get("items", []))


func _render_inspector() -> void:
	var showing_aim_targeter := aim_target_panel.visible
	right_panel.visible = not showing_aim_targeter
	hex_panel.visible = not showing_aim_targeter
	var sector := _sector(selected_sector)
	if sector.is_empty():
		var player := _actor(selected_actor_id)
		sector = _sector(player.get("sector", Vector2i(-1, -1)))
	_render_sector_inspector(sector)
	var occupant: Dictionary = {}
	var selected_occupant := _actor(str(sector.get("occupant_id", "")))
	if not selected_occupant.is_empty() and str(selected_occupant.get("team_id", "")) != "player":
		occupant = selected_occupant
	if occupant.is_empty():
		for candidate in snapshot.get("actors", []):
			if str(candidate.get("team_id", "")) != "player":
				occupant = candidate
				break
	if not occupant.is_empty():
		_render_actor_inspector(occupant)


func _render_actor_inspector(actor: Dictionary) -> void:
	target_name.text = str(actor.get("name", "ACTOR")).to_upper()
	target_summary.text = "%s · FACING %s" % [
		str(actor.get("posture", "standing")).to_upper(),
		str(actor.get("facing", "east")).to_upper(),
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
	target_label.text = _weapon_summary(actor)


func _render_sector_inspector(sector: Dictionary) -> void:
	if sector.is_empty():
		hex_title.text = "BATTLE SITE"
		hex_summary.text = "Select a sector to inspect it."
		hex_details.text = "Terrain details remain pinned here."
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
	hex_details.text = "
".join(details)


func _render_forecast(value: CombatActionQuote) -> void:
	forecast_label.text = _forecast_text(value)


func _forecast_text(value: CombatActionQuote) -> String:
	if not value.legal:
		return value.denial_message
	var parts: Array[String] = ["%d AP" % value.ap_cost]
	if value.movement_cost > 0:
		parts.append("MOVE %d" % value.movement_cost)
	if value.forecast != null and value.forecast.hit_probability > 0.0:
		parts.append("HIT %d%%" % roundi(value.forecast.hit_probability * 100.0))
		parts.append("WOUND %s" % value.forecast.severe_wound_risk.to_upper())
	if not value.reaction_threat_ids.is_empty():
		parts.append("REACTIONS %d" % value.reaction_threat_ids.size())
	return " · ".join(parts)


func _render_context_actions() -> void:
	if not is_node_ready() or selected_sector == Vector2i(-1, -1):
		return
	_clear_children(context_actions)
	_context_shortcuts.clear()
	var occupant_id := _occupant_at(selected_sector)
	var context := _selection_context(occupant_id)
	context_title.text = str(_actor(occupant_id).get("name", "MOVE HERE")).to_upper() if not occupant_id.is_empty() else "MOVE HERE"
	if context == CombatActionDefinition.CONTEXT_SECTOR:
		var move_quote := _quote("move")
		var move_definition := _definition("move")
		if move_quote != null and move_definition != null:
			_add_context_action(move_definition, move_quote)
	for action_quote in _sorted_quotes():
		var definition := _definition(action_quote.action_id)
		if definition == null or definition.action_id == "move":
			continue
		var availability := _availability(definition, action_quote, context)
		if availability == Availability.HIDDEN:
			continue
		_add_context_action(definition, action_quote, availability)
	context_scroll.custom_minimum_size.y = clampf(float(_context_shortcuts.size()) * 40.0, 36.0, 280.0)
	interaction.open_actions()
	context_menu.visible = true
	if current_quote == null:
		local_confirmation.visible = false
		context_hint.text = "Choose what you want to do here."
	call_deferred("_position_context_menu")


func _add_context_action(
	definition: CombatActionDefinition,
	action_quote: CombatActionQuote,
	availability: Availability = Availability.AVAILABLE
) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(250.0, 36.0)
	HUD_ASSETS.apply_button(button)
	var suffix := "%d AP" % action_quote.ap_cost if action_quote.legal else _short_denial(action_quote)
	button.text = "%s    %s" % [definition.label.to_upper(), suffix]
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
	button.pressed.connect(_on_action_button.bind(definition.action_id, action_quote))
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
	if definition.context_visibility == "reaction_only":
		return Availability.HIDDEN
	if context not in definition.inferred_selection_contexts():
		return Availability.HIDDEN
	var player := _actor(selected_actor_id)
	if "ranged_weapon" in definition.required_equipment_tags and player.get("ranged_weapon", {}).is_empty():
		return Availability.HIDDEN
	if definition.action_id == "take_cover" and not _arena_has_cover():
		return Availability.HIDDEN
	if definition.action_id == "strip":
		var target := _actor(_occupant_at(selected_sector))
		if not bool(target.get("dead", false)) and not bool(target.get("incapacitated", false)):
			return Availability.HIDDEN
	if definition.action_id == "stand" and str(player.get("posture", "standing")) == "standing":
		return Availability.HIDDEN
	if definition.action_id == "crouch" and str(player.get("posture", "standing")) == "crouched":
		return Availability.HIDDEN
	return Availability.AVAILABLE if action_quote.legal else Availability.DISABLED


func _on_action_button(action_id: String, action_quote: CombatActionQuote) -> void:
	if not action_quote.legal and action_quote.denial_code != "body_region_required":
		return
	if action_id in ["aimed_strike", "aimed_fire"]:
		show_aim_targeter(action_id)
		return
	show_quote(action_quote)
	action_selected.emit(action_id)


func _on_aim_body_region_selected(region: int) -> void:
	selected_body_region = region
	body_region_selected.emit(region)
	action_selected.emit(_pending_aim_action)


func _confirm_aim_targeting() -> void:
	if current_quote != null and current_quote.legal:
		action_confirmed.emit()


func _cancel_aim_targeting() -> void:
	if interaction.phase == CombatInteractionState.Phase.PRESENTING:
		return
	current_quote = null
	selected_body_region = -1
	arena_view.clear_quote()
	_close_aim_panel()
	interaction.cancel_one_step()
	selection_cancelled.emit()
	_render_context_actions()


func _close_aim_panel() -> void:
	_pending_aim_action = ""
	aim_target_panel.visible = false
	aim_target_body.set_selectable(false)
	hex_panel.visible = true
	right_panel.visible = true


func _toggle_pack() -> void:
	items.visible = not items.visible
	item_heading.text = "ITEMS [I]  %s" % ["v" if items.visible else ">"]


func _confirm_local() -> void:
	if current_quote != null and current_quote.legal:
		action_confirmed.emit()


func _cancel_selection() -> void:
	if interaction.phase == CombatInteractionState.Phase.PRESENTING:
		return
	if aim_target_panel.visible:
		_cancel_aim_targeting()
		return
	interaction.cancel_one_step()
	clear_staged_action()
	selection_cancelled.emit()
	if interaction.phase == CombatInteractionState.Phase.IDLE:
		context_menu.visible = false
		selected_sector = Vector2i(-1, -1)
		arena_view.select_sector(selected_sector)
	else:
		_render_context_actions()


func _on_sector_selected(coords: Vector2i) -> void:
	if interaction.phase == CombatInteractionState.Phase.PRESENTING:
		return
	selected_sector = coords
	selected_item_id = ""
	selected_wound_id = ""
	selected_body_region = -1
	var occupant_id := _occupant_at(coords)
	interaction.select("actor" if not occupant_id.is_empty() else "sector", {
		"actor_id": occupant_id,
		"sector": coords,
	})
	sector_selected.emit(coords)
	_render_inspector()
	_render_context_actions()


func _on_player_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_player()
		accept_event()


func _select_player() -> void:
	var player := _actor(selected_actor_id)
	var sector: Vector2i = player.get("sector", Vector2i(-1, -1))
	if sector != Vector2i(-1, -1):
		arena_view.select_sector(sector)
		_on_sector_selected(sector)


func _cycle_actor(direction: int) -> void:
	var actors: Array = snapshot.get("actors", [])
	if actors.is_empty():
		return
	var current_id := _occupant_at(selected_sector)
	var current_index := -1
	for index in range(actors.size()):
		if str(actors[index].get("actor_id", "")) == current_id:
			current_index = index
			break
	var next_index := posmod(current_index + direction, actors.size())
	var sector: Vector2i = actors[next_index].get("sector", Vector2i(-1, -1))
	if sector != Vector2i(-1, -1):
		arena_view.select_sector(sector)
		_on_sector_selected(sector)


func _on_sector_hovered(coords: Vector2i) -> void:
	var sector := _sector(coords)
	if not sector.is_empty():
		arena_view.tooltip_text = str(sector.get("surface_label", "Sector"))


func _on_sector_unhovered() -> void:
	arena_view.tooltip_text = ""


func _render_wounds(actor_wounds: Array) -> void:
	_clear_children(wounds)
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
		button.pressed.connect(func() -> void:
			selected_wound_id = wound_id
			interaction.select("wound", {"wound_id": wound_id, "sector": selected_sector})
			wound_selected.emit(wound_id)
			_render_context_actions()
		)
		wounds.add_child(button)
	if actor_wounds.is_empty():
		var none := Label.new()
		none.text = "No visible wounds"
		none.add_theme_color_override("font_color", Color("70807d"))
		wounds.add_child(none)


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
		button.pressed.connect(func() -> void:
			var player := _actor(selected_actor_id)
			var player_sector: Vector2i = player.get("sector", Vector2i(-1, -1))
			if player_sector != Vector2i(-1, -1):
				selected_sector = player_sector
				arena_view.select_sector(player_sector)
			selected_item_id = instance_id
			interaction.select("item", {"item_id": instance_id, "sector": selected_sector})
			item_selected.emit(instance_id)
			_render_context_actions()
		)
		items.add_child(button)


func _position_context_menu() -> void:
	if not context_menu.visible or selected_sector == Vector2i(-1, -1):
		return
	context_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var menu_size := context_menu.get_combined_minimum_size()
	menu_size.x = clampf(menu_size.x, 280.0, 300.0)
	menu_size.y = clampf(menu_size.y, 120.0, minf(520.0, arena_view.size.y - 16.0))
	context_menu.size = menu_size
	var desired := arena_view.global_position + arena_view.sector_center(selected_sector) + Vector2(20.0, -40.0)
	var arena_rect := arena_view.get_global_rect().grow(-8.0)
	var corner_clearance := player_card.size.x + 20.0
	arena_rect.position.x = maxf(arena_rect.position.x, corner_clearance)
	arena_rect.size.x = minf(arena_rect.end.x, size.x - corner_clearance) - arena_rect.position.x
	var max_pos := arena_rect.end - context_menu.size
	var clamped := desired.clamp(arena_rect.position, max_pos)
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
		return CombatActionDefinition.CONTEXT_ITEM
	if occupant_id == selected_actor_id:
		return CombatActionDefinition.CONTEXT_SELF
	if not occupant_id.is_empty():
		return CombatActionDefinition.CONTEXT_HOSTILE_ACTOR
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
	return str(_sector(coords).get("occupant_id", ""))


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
	return "
".join(lines)


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
