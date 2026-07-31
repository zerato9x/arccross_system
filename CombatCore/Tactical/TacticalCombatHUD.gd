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

const DEFAULT_MENU_CATALOG := preload("res://CombatCore/Tactical/default_combat_command_menu.tres")

@onready var arena_view: TacticalArenaView = %TacticalArenaView
@onready var initiative_row: HBoxContainer = %InitiativeRow
@onready var ap_label: Label = %APLabel
@onready var actor_name: Label = %ActorName
@onready var actor_body: CombatBodyTargetView = %ActorBody
@onready var actor_status: Label = %ActorStatus
@onready var blood_bar: ProgressBar = %BloodBar
@onready var pain_bar: ProgressBar = %PainBar
@onready var shock_bar: ProgressBar = %ShockBar
@onready var consciousness_bar: ProgressBar = %ConsciousnessBar
@onready var wounds: VBoxContainer = %Wounds
@onready var items: VBoxContainer = %Items
@onready var target_name: Label = %TargetName
@onready var target_body: CombatBodyTargetView = %TargetBody
@onready var target_label: RichTextLabel = %TargetLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var forecast_label: Label = %ForecastLabel
@onready var command_button: Button = %CommandButton
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton
@onready var command_wheel: PanelContainer = %CommandWheel
@onready var wheel_buttons: Control = %WheelButtons
@onready var family_title: Label = %FamilyTitle
@onready var family_actions: VBoxContainer = %FamilyActions
@onready var context_menu: PanelContainer = %ContextMenu
@onready var context_title: Label = %ContextTitle
@onready var context_actions: VBoxContainer = %ContextActions
@onready var aim_panel: PanelContainer = %AimPanel
@onready var aim_title: Label = %AimTitle
@onready var aim_body: CombatBodyTargetView = %AimBody
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
var _definitions: Dictionary = {}
var _quote_by_action: Dictionary = {}
var _pending_aim_action := ""
var _menu_catalog: CombatCommandMenuCatalog = DEFAULT_MENU_CATALOG


func _ready() -> void:
	arena_view.sector_selected.connect(_on_sector_selected)
	arena_view.sector_hovered.connect(_on_sector_hovered)
	arena_view.sector_unhovered.connect(_render_target_context)
	command_button.pressed.connect(_toggle_command_wheel)
	cancel_button.pressed.connect(_cancel_selection)
	confirm_button.pressed.connect(func() -> void: action_confirmed.emit())
	aim_body.region_selected.connect(_on_body_region_selected)
	command_wheel.visible = false
	context_menu.visible = false
	aim_panel.visible = false
	reaction_panel.visible = false
	confirm_button.disabled = true
	feedback_label.text = "Select terrain to move or an entity for contextual actions."


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_selection()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		_toggle_command_wheel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") and current_quote != null and current_quote.legal and not aim_panel.visible:
		action_confirmed.emit()
		get_viewport().set_input_as_handled()


func configure_action_catalog(catalog: CombatActionCatalog) -> void:
	_definitions.clear()
	if catalog == null:
		return
	for definition in catalog.all():
		_definitions[definition.action_id] = definition
	_render_command_wheel()


func show_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	selected_actor_id = str(snapshot.get("active_actor_id", selected_actor_id))
	var arena: Dictionary = snapshot.get("arena", {})
	arena_view.set_meta("actor_snapshot", snapshot.get("actors", []))
	arena_view.show_snapshot(arena)
	_render_top()
	_render_actor_context()
	_render_target_context()


func show_quotes(value: Array[CombatActionQuote]) -> void:
	quotes = value
	_quote_by_action.clear()
	for action_quote in quotes:
		_quote_by_action[action_quote.action_id] = action_quote
	_render_command_wheel()
	_render_context_actions()


func show_quote(value: CombatActionQuote) -> void:
	current_quote = value
	arena_view.show_quote(value)
	confirm_button.disabled = not value.legal
	var definition := _definition(value.action_id)
	var label := definition.label if definition != null else value.action_id.replace("_", " ").capitalize()
	if value.legal:
		feedback_label.text = "%s staged. Confirm to commit." % label
	else:
		feedback_label.text = "%s: %s" % [value.denial_code.replace("_", " ").to_upper(), value.denial_message]
	_render_forecast(value)


func clear_staged_action() -> void:
	current_quote = null
	selected_body_region = -1
	confirm_button.disabled = true
	forecast_label.text = "NO ACTION STAGED"
	arena_view.clear_quote()


func show_feedback(message: String) -> void:
	feedback_label.text = message


func show_aim_targeter(action_id: String) -> void:
	_pending_aim_action = action_id
	var target := _actor(_occupant_at(selected_sector))
	if target.is_empty():
		show_feedback("Select a hostile actor before choosing an aimed attack.")
		return
	aim_title.text = "%s // SELECT BODY REGION" % str(target.get("name", "TARGET")).to_upper()
	aim_body.set_actor_snapshot(target)
	aim_body.clear_selection()
	aim_body.set_selectable(true)
	aim_panel.visible = true
	command_wheel.visible = false
	context_menu.visible = false


func show_reaction(prompt: Dictionary) -> void:
	_clear_children(reaction_actions)
	reaction_panel.visible = true
	for action_id in prompt.get("actions", []):
		var button := Button.new()
		button.text = str(action_id).replace("_", " ").to_upper()
		button.pressed.connect(func() -> void:
			reaction_panel.visible = false
			reaction_selected.emit(str(action_id))
		)
		reaction_actions.add_child(button)
	var decline := Button.new()
	decline.text = "DECLINE"
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
		chip.text = "%s%s" % ["▶ " if active else "", str(actor.get("name", "ACTOR")).to_upper()]
		chip.add_theme_color_override("font_color", Color("f0ce76") if active else Color("8ea0a4"))
		initiative_row.add_child(chip)
	var reserved: Dictionary = snapshot.get("reserved_ap", {})
	ap_label.text = "ROUND %02d   AP %02d/12   RESERVED %02d" % [
		int(snapshot.get("round", 0)),
		int(snapshot.get("ap", 0)),
		int(reserved.get(snapshot.get("active_actor_id", ""), 0)),
	]


func _render_actor_context() -> void:
	var actor := _actor(selected_actor_id)
	if actor.is_empty():
		actor_name.text = "NO ACTOR"
		return
	actor_name.text = str(actor.get("name", selected_actor_id)).to_upper()
	actor_status.text = "%s  •  FACING %s" % [str(actor.get("posture", "standing")).to_upper(), str(actor.get("facing", "east")).to_upper()]
	actor_body.set_actor_snapshot(actor)
	_set_vital(blood_bar, float(actor.get("blood", 0.0)))
	_set_vital(pain_bar, float(actor.get("pain", 0.0)))
	_set_vital(shock_bar, float(actor.get("shock", 0.0)))
	_set_vital(consciousness_bar, float(actor.get("consciousness", 0.0)))
	_render_wounds(actor.get("wounds", []))
	_render_items(actor.get("items", []))


func _render_target_context(data: Dictionary = {}) -> void:
	var sector := data if not data.is_empty() else _sector(selected_sector)
	if sector.is_empty():
		target_name.text = "SECTOR CONTEXT"
		target_label.text = "Select or hover a sector."
		target_body.visible = false
		return
	var occupant_id := str(sector.get("occupant_id", ""))
	var occupant := _actor(occupant_id)
	target_body.visible = not occupant.is_empty()
	if not occupant.is_empty():
		target_name.text = str(occupant.get("name", occupant_id)).to_upper()
		target_body.set_actor_snapshot(occupant)
	else:
		target_name.text = "SECTOR %d,%d" % [sector.coords.x, sector.coords.y]
	var object_state: Dictionary = sector.get("object", {})
	target_label.text = "[b]%s[/b]  ELEV %+d\nMOVE %+d  CONCEAL %.0f%%\nCOVER %s\nHAZARDS %s\nOBJECT %s" % [
		str(sector.get("surface_label", "UNRESOLVED")),
		int(sector.get("elevation", 0)),
		int(sector.get("movement_modifier", 0)),
		float(sector.get("concealment", 0.0)) * 100.0,
		_cover_summary(sector.get("cover_edges", {})),
		", ".join(sector.get("hazards", {}).keys()) if not sector.get("hazards", {}).is_empty() else "NONE",
		str(object_state.get("label", "NONE")),
	]


func _render_forecast(value: CombatActionQuote) -> void:
	if not value.legal:
		forecast_label.text = value.denial_message
		return
	var parts: Array[String] = ["%d AP" % value.ap_cost]
	if value.movement_cost > 0:
		parts.append("MOVE %d" % value.movement_cost)
	if value.forecast != null and value.forecast.hit_probability > 0.0:
		parts.append("HIT %d%%" % roundi(value.forecast.hit_probability * 100.0))
		parts.append("ARMOR %s" % value.forecast.armor_result.to_upper())
		parts.append("WOUND %s" % value.forecast.severe_wound_risk.to_upper())
		parts.append("BLEED %s" % value.forecast.bleeding_risk.to_upper())
		parts.append("INCAP %s" % value.forecast.incapacity_risk.to_upper())
	if not value.reaction_threat_ids.is_empty():
		parts.append("REACTIONS %d" % value.reaction_threat_ids.size())
	forecast_label.text = "   •   ".join(parts)


func _render_command_wheel() -> void:
	if not is_node_ready():
		return
	_clear_children(wheel_buttons)
	var visible_families: Array[String] = []
	for family in _menu_catalog.ordered_ids():
		if _family_has_visible_actions(family):
			visible_families.append(family)
	var center := Vector2(250.0, 165.0)
	var radius := Vector2(190.0, 125.0)
	for index in range(visible_families.size()):
		var family := visible_families[index]
		var angle := -PI * 0.5 + TAU * float(index) / float(maxi(1, visible_families.size()))
		var button := Button.new()
		var family_definition := _menu_catalog.definition(family)
		button.text = "%s  %s" % [family_definition.glyph, family_definition.label]
		button.add_theme_color_override("font_color", family_definition.accent_color)
		button.custom_minimum_size = Vector2(108.0, 36.0)
		button.position = center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) - Vector2(54.0, 18.0)
		button.pressed.connect(_on_family_selected.bind(family))
		wheel_buttons.add_child(button)


func _render_context_actions() -> void:
	if not is_node_ready() or selected_sector == Vector2i(-1, -1):
		return
	_clear_children(context_actions)
	var occupant_id := _occupant_at(selected_sector)
	if occupant_id.is_empty() or occupant_id == selected_actor_id:
		context_menu.visible = false
		return
	context_title.text = str(_actor(occupant_id).get("name", "TARGET")).to_upper()
	for action_quote in _sorted_quotes():
		var definition := _definition(action_quote.action_id)
		if definition == null or definition.target_mode != CombatActionDefinition.TARGET_ACTOR:
			continue
		if definition.menu_family not in ["attack", "aim", "maneuver", "guard", "interact"]:
			continue
		context_actions.add_child(_action_button(definition, action_quote))
	context_menu.visible = context_actions.get_child_count() > 0
	call_deferred("_position_context_menu")


func _show_family(family: String) -> void:
	var family_definition := _menu_catalog.definition(family)
	family_title.text = family_definition.label if family_definition != null else family.to_upper()
	if family_definition != null:
		family_title.add_theme_color_override("font_color", family_definition.accent_color)
	_clear_children(family_actions)
	for action_quote in _sorted_quotes():
		var definition := _definition(action_quote.action_id)
		if definition == null or definition.menu_family != family:
			continue
		if not _action_is_contextually_visible(definition):
			continue
		family_actions.add_child(_action_button(definition, action_quote))


func _action_button(definition: CombatActionDefinition, action_quote: CombatActionQuote) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(190.0, 34.0)
	var family_definition := _menu_catalog.definition(definition.menu_family)
	var glyph := family_definition.glyph if family_definition != null else "•"
	button.text = "%s  %s   %s" % [glyph, definition.label.to_upper(), "%d AP" % action_quote.ap_cost if action_quote.legal else action_quote.denial_code.replace("_", " ").to_upper()]
	if family_definition != null:
		button.add_theme_color_override("font_color", family_definition.accent_color)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_entered.connect(show_quote.bind(action_quote))
	button.focus_entered.connect(show_quote.bind(action_quote))
	button.pressed.connect(_on_action_button.bind(definition.action_id, action_quote))
	return button


func _on_action_button(action_id: String, action_quote: CombatActionQuote) -> void:
	show_quote(action_quote)
	if not action_quote.legal and action_quote.denial_code != "body_region_required":
		return
	if action_id in ["aimed_strike", "aimed_fire"]:
		show_aim_targeter(action_id)
		return
	command_wheel.visible = false
	context_menu.visible = false
	action_selected.emit(action_id)


func _on_body_region_selected(region: int) -> void:
	selected_body_region = region
	aim_panel.visible = false
	body_region_selected.emit(region)
	action_selected.emit(_pending_aim_action)


func _on_family_selected(family: String) -> void:
	if family == "end_turn":
		var action_quote := _quote("end_turn")
		if action_quote != null:
			_on_action_button("end_turn", action_quote)
		return
	_show_family(family)


func _toggle_command_wheel() -> void:
	command_wheel.visible = not command_wheel.visible
	context_menu.visible = false
	if command_wheel.visible:
		_show_family("move")


func _cancel_selection() -> void:
	command_wheel.visible = false
	context_menu.visible = false
	aim_panel.visible = false
	clear_staged_action()
	selection_cancelled.emit()


func _on_sector_selected(coords: Vector2i) -> void:
	var confirming_move := coords == selected_sector and current_quote != null and current_quote.action_id in ["move", "disengage"] and current_quote.legal
	selected_sector = coords
	selected_body_region = -1
	sector_selected.emit(coords)
	_render_target_context()
	if confirming_move:
		action_confirmed.emit()


func _on_sector_hovered(coords: Vector2i) -> void:
	_render_target_context(_sector(coords))


func _render_wounds(actor_wounds: Array) -> void:
	_clear_children(wounds)
	for wound in actor_wounds:
		var button := Button.new()
		button.text = "%s  S%.1f  B%.1f" % [str(wound.get("wound_type", "WOUND")).to_upper(), float(wound.get("severity", 0.0)), float(wound.get("bleeding_rate", 0.0))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var wound_id := str(wound.get("wound_id", ""))
		button.pressed.connect(func() -> void:
			selected_wound_id = wound_id
			wound_selected.emit(wound_id)
		)
		wounds.add_child(button)


func _render_items(actor_items: Array) -> void:
	_clear_children(items)
	for item in actor_items:
		var button := Button.new()
		button.text = "%s  [%s]" % [str(item.get("name", "ITEM")).to_upper(), str(item.get("access", "unknown")).to_upper()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var instance_id := str(item.get("instance_id", ""))
		button.pressed.connect(func() -> void:
			selected_item_id = instance_id
			item_selected.emit(instance_id)
		)
		items.add_child(button)


func _position_context_menu() -> void:
	if not context_menu.visible:
		return
	var desired := arena_view.global_position + arena_view.sector_center(selected_sector) + Vector2(24.0, -30.0)
	var maximum := size - context_menu.size - Vector2(8.0, 112.0)
	context_menu.global_position = desired.clamp(Vector2(8.0, 58.0), maximum)


func _family_has_visible_actions(family: String) -> bool:
	for action_quote in quotes:
		var definition := _definition(action_quote.action_id)
		if definition != null and definition.menu_family == family and _action_is_contextually_visible(definition):
			return true
	return false


func _action_is_contextually_visible(definition: CombatActionDefinition) -> bool:
	if definition.context_visibility == "reaction_only":
		return false
	if definition.context_visibility == "target_context" and _occupant_at(selected_sector).is_empty():
		return false
	return true


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
			active.append("%s %.0f%%" % [str(edge).left(1).to_upper(), float(edges[edge]) * 100.0])
	return ", ".join(active) if not active.is_empty() else "NONE"


func _set_vital(bar: ProgressBar, value: float) -> void:
	bar.max_value = GameEnums.SCALE_MAX
	bar.value = clampf(value, 0.0, GameEnums.SCALE_MAX)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()
