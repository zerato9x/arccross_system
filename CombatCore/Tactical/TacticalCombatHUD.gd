extends Control
class_name TacticalCombatHUD

signal sector_selected(coords: Vector2i)
signal action_selected(action_id: String)
signal item_selected(instance_id: String)
signal wound_selected(wound_id: String)
signal reaction_selected(action_id: String)

@onready var arena_view: TacticalArenaView = %TacticalArenaView
@onready var top_label: Label = %TopLabel
@onready var actor_label: RichTextLabel = %ActorLabel
@onready var target_label: RichTextLabel = %TargetLabel
@onready var actions: GridContainer = %Actions
@onready var items: VBoxContainer = %Items
@onready var wounds: VBoxContainer = %Wounds
@onready var feedback_label: Label = %FeedbackLabel
@onready var reaction_panel: PanelContainer = %ReactionPanel
@onready var reaction_actions: HBoxContainer = %ReactionActions

var snapshot: Dictionary = {}
var quotes: Array[CombatActionQuote] = []
var selected_sector := Vector2i(-1, -1)
var selected_actor_id := ""
var selected_item_id := ""
var selected_wound_id := ""


func _ready() -> void:
	arena_view.sector_selected.connect(_on_sector_selected)
	arena_view.sector_hovered.connect(_on_sector_hovered)
	arena_view.sector_unhovered.connect(_render_target_context)
	reaction_panel.visible = false
	feedback_label.text = "Select a sector, then choose an action."


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
	_render_actions()


func show_quote(value: CombatActionQuote) -> void:
	arena_view.show_quote(value)
	if value.legal:
		feedback_label.text = "%s AP %d | PATH %d | RANGE %d | %s" % [
			value.action_id.to_upper(),
			value.ap_cost,
			value.movement_cost,
			value.range_cells,
			"LOS" if value.has_line_of_sight else "NO LOS",
		]
	else:
		feedback_label.text = "%s: %s" % [value.denial_code.to_upper(), value.denial_message]


func show_feedback(message: String) -> void:
	feedback_label.text = message


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


func hide_reaction() -> void:
	reaction_panel.visible = false


func selected_context() -> Dictionary:
	return {
		"target_sector": selected_sector,
		"target_actor_id": _occupant_at(selected_sector),
		"item_instance_id": selected_item_id,
		"wound_id": selected_wound_id,
		"facing": "",
	}


func _render_top() -> void:
	var active := _actor(str(snapshot.get("active_actor_id", "")))
	var active_name := str(active.get("name", snapshot.get("active_actor_id", "")))
	var reserved: Dictionary = snapshot.get("reserved_ap", {})
	top_label.text = "ROUND %02d   ACTIVE: %s   AP %02d/12   RESERVED %02d" % [
		int(snapshot.get("round", 0)),
		active_name.to_upper(),
		int(snapshot.get("ap", 0)),
		int(reserved.get(snapshot.get("active_actor_id", ""), 0)),
	]


func _render_actor_context() -> void:
	var actor := _actor(selected_actor_id)
	if actor.is_empty():
		actor_label.text = "[b]NO ACTOR SELECTED[/b]"
		return
	actor_label.text = (
		"[b]%s[/b]\nPOSTURE %s  FACING %s\nBLOOD %.1f  PAIN %.1f\nSHOCK %.1f  CONSCIOUS %.1f\nCONTROL %s\n\n[b]REGION FUNCTION[/b]\n%s"
		% [
			str(actor.get("name", selected_actor_id)).to_upper(),
			str(actor.get("posture", "standing")).to_upper(),
			str(actor.get("facing", "east")).to_upper(),
			float(actor.get("blood", 0.0)),
			float(actor.get("pain", 0.0)),
			float(actor.get("shock", 0.0)),
			float(actor.get("consciousness", 0.0)),
			str(actor.get("control_role", "none")).to_upper(),
			_region_lines(actor.get("region_function", {})),
		]
	)
	_render_wounds(actor.get("wounds", []))
	_render_items(actor.get("items", []))


func _render_target_context(data: Dictionary = {}) -> void:
	var sector := data if not data.is_empty() else _sector(selected_sector)
	if sector.is_empty():
		target_label.text = "[b]SECTOR CONTEXT[/b]\nSelect or hover a sector."
		return
	var coords: Vector2i = sector.get("coords", Vector2i(-1, -1))
	var occupant := str(sector.get("occupant_id", ""))
	var object_state: Dictionary = sector.get("object", {})
	target_label.text = (
		"[b]SECTOR %d,%d[/b]\n%s  ELEV %+d\nMOVE %+d  CONCEAL %.0f%%\nCOVER %s\nHAZARDS %s\nOBJECT %s\nOCCUPANT %s"
		% [
			coords.x,
			coords.y,
			str(sector.get("surface_label", "UNRESOLVED")),
			int(sector.get("elevation", 0)),
			int(sector.get("movement_modifier", 0)),
			float(sector.get("concealment", 0.0)) * 100.0,
			str(sector.get("cover_edges", {})),
			str(sector.get("hazards", {}).keys()),
			str(object_state.get("label", "NONE")),
			occupant if not occupant.is_empty() else "NONE",
		]
	)


func _render_actions() -> void:
	_clear_children(actions)
	var ordered := quotes.duplicate()
	ordered.sort_custom(func(a: CombatActionQuote, b: CombatActionQuote) -> bool:
		if a.legal != b.legal:
			return a.legal
		return a.action_id < b.action_id
	)
	for action_quote in ordered:
		var button := Button.new()
		button.custom_minimum_size = Vector2(140.0, 32.0)
		button.clip_text = true
		button.text = "%s  %s" % [
			action_quote.action_id.replace("_", " ").to_upper(),
			("%d AP" % action_quote.ap_cost) if action_quote.legal else action_quote.denial_code.replace("_", " ").to_upper(),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.mouse_entered.connect(show_quote.bind(action_quote))
		button.focus_entered.connect(show_quote.bind(action_quote))
		button.pressed.connect(func() -> void:
			show_quote(action_quote)
			if action_quote.legal:
				action_selected.emit(action_quote.action_id)
		)
		actions.add_child(button)


func _render_items(actor_items: Array) -> void:
	_clear_children(items)
	for item in actor_items:
		var button := Button.new()
		button.text = "%s • %s" % [str(item.get("name", "ITEM")), str(item.get("access", "unknown")).to_upper()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var instance_id := str(item.get("instance_id", ""))
		button.button_pressed = instance_id == selected_item_id
		button.pressed.connect(func() -> void:
			selected_item_id = instance_id
			item_selected.emit(instance_id)
		)
		items.add_child(button)


func _render_wounds(actor_wounds: Array) -> void:
	_clear_children(wounds)
	for wound in actor_wounds:
		var button := Button.new()
		button.text = "%s • SEV %.1f • BLEED %.1f" % [
			str(wound.get("wound_type", "WOUND")),
			float(wound.get("severity", 0.0)),
			float(wound.get("bleeding_rate", 0.0)),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var wound_id := str(wound.get("wound_id", ""))
		button.pressed.connect(func() -> void:
			selected_wound_id = wound_id
			wound_selected.emit(wound_id)
		)
		wounds.add_child(button)


func _on_sector_selected(coords: Vector2i) -> void:
	selected_sector = coords
	sector_selected.emit(coords)
	_render_target_context()


func _on_sector_hovered(coords: Vector2i) -> void:
	_render_target_context(_sector(coords))


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


func _region_lines(functions: Dictionary) -> String:
	var lines: Array[String] = []
	for region in functions:
		lines.append("%s %.1f/12" % [str(region).replace("_", " ").to_upper(), float(functions[region])])
	return "\n".join(lines)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()
