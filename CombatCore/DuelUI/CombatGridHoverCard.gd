extends Node2D
class_name CombatGridHoverCard

const CARD_SIZE := Vector2(380.0, 226.0)
const COLOR_PANEL := Color(0.08, 0.075, 0.06, 0.95)
const COLOR_BORDER := Color(0.72, 0.62, 0.45, 0.95)

@onready var _panel_box: Polygon2D = %PanelBox
@onready var _border: Line2D = %Border
@onready var _title_label: Label = %TitleLabel
@onready var _terrain_label: Label = %TerrainLabel
@onready var _occupants_label: Label = %OccupantsLabel
@onready var _actions_label: Label = %ActionsLabel

func _ready() -> void:
	_set_box(_panel_box, CARD_SIZE)
	_panel_box.color = COLOR_PANEL
	_set_outline(_border, CARD_SIZE)
	visible = false

func show_slot(
	slot_data: Dictionary,
	actions: Array,
	snapshot: Dictionary,
	anchor_global: Vector2,
	viewport_size: Vector2
) -> void:
	if slot_data.is_empty():
		hide_card()
		return
	visible = true
	_title_label.text = "LANE SLOT %02d" % int(slot_data.get("index", -1))
	_terrain_label.text = _terrain_text(slot_data)
	_occupants_label.text = _occupants_text(slot_data)
	_actions_label.text = _actions_text(slot_data, actions, snapshot)

	var target := anchor_global + Vector2(18.0, -CARD_SIZE.y - 24.0)
	if target.x + CARD_SIZE.x > viewport_size.x - 18.0:
		target.x = anchor_global.x - CARD_SIZE.x - 18.0
	if target.y < 18.0:
		target.y = anchor_global.y + 28.0
	target.x = clampf(target.x, 18.0, maxf(18.0, viewport_size.x - CARD_SIZE.x - 18.0))
	target.y = clampf(target.y, 18.0, maxf(18.0, viewport_size.y - CARD_SIZE.y - 18.0))
	global_position = target

func hide_card() -> void:
	visible = false

func _terrain_text(slot_data: Dictionary) -> String:
	var floor := str(slot_data.get("background_label", slot_data.get("background", "NONE")))
	var surface := str(slot_data.get("surface_label", "GRASS"))
	var object := str(slot_data.get("object_name", slot_data.get("cover", "NONE")))
	var durability := float(slot_data.get("cover_durability", 0.0))
	var spawnable := "SPAWN OK" if slot_data.get("is_spawnable", true) else "NO SPAWN"
	var escape := " EXIT" if slot_data.get("is_escape", false) else ""
	var modifiers := PackedStringArray()
	for raw_modifier in slot_data.get("terrain_modifiers", []):
		modifiers.append(str(raw_modifier))
	if modifiers.is_empty():
		modifiers.append("No terrain modifier")
	return ("FLOOR %s / %s | OBJECT %s %.0f | %s%s\nMOD %s") % [
		floor,
		surface,
		object,
		durability,
		spawnable,
		escape,
		"; ".join(modifiers),
	]

func _occupants_text(slot_data: Dictionary) -> String:
	var occupants: Array = slot_data.get("occupants", [])
	if occupants.is_empty():
		return "OCCUPANTS NONE"
	var rows := PackedStringArray()
	for raw_occupant in occupants:
		var occupant: Dictionary = raw_occupant
		rows.append("%s %s STANCE %02d %s" % [
			str(occupant.get("side", "other")).to_upper(),
			str(occupant.get("archetype", occupant.get("name", "UNKNOWN"))).to_upper(),
			int(occupant.get("stance", 0)),
			str(occupant.get("stance_state", "UNKNOWN")),
		])
	return "\n".join(rows)

func _actions_text(
	slot_data: Dictionary,
	actions: Array,
	snapshot: Dictionary
) -> String:
	var relevant := _relevant_actions(slot_data, actions, snapshot)
	var interactions := PackedStringArray()
	for raw_interaction in slot_data.get("object_interactions", []):
		interactions.append(str(raw_interaction))
	if relevant.is_empty() and interactions.is_empty():
		return "ACTIONS\n- No legal player action from here."
	var rows := PackedStringArray(["ACTIONS"])
	for interaction in interactions:
		rows.append("- CTX " + interaction)
	for descriptor in relevant:
		rows.append("- %s  AP %02d" % [
			str(descriptor.get("label", "ACTION")),
			int(descriptor.get("cost", 0)),
		])
	return "\n".join(rows)

func _relevant_actions(
	slot_data: Dictionary,
	actions: Array,
	snapshot: Dictionary
) -> Array:
	var slot_index := int(slot_data.get("index", -1))
	var player_lane := int(snapshot.get("player", {}).get("lane", -1))
	var enemy_lane := int(snapshot.get("enemy", {}).get("lane", -1))
	if slot_index < 0 or player_lane < 0:
		return []

	var distance_to_player := slot_index - player_lane
	var direction_to_enemy := signi(enemy_lane - player_lane)
	var occupants: Array = slot_data.get("occupants", [])
	var has_enemy := false
	for occupant in occupants:
		has_enemy = has_enemy or occupant.get("side", "") == "enemy"

	var relevant: Array = []
	for raw_descriptor in actions:
		var descriptor: Dictionary = raw_descriptor
		var action := int(descriptor.get("action", -1))
		if _action_matches_slot(
			action,
			slot_index,
			player_lane,
			distance_to_player,
			direction_to_enemy,
			has_enemy,
			slot_data
		):
			relevant.append(descriptor)
	return relevant

func _action_matches_slot(
	action: int,
	slot_index: int,
	player_lane: int,
	distance_to_player: int,
	direction_to_enemy: int,
	has_enemy: bool,
	slot_data: Dictionary
) -> bool:
	match action:
		GameEnums.ActionType.MOVE_FORWARD:
			return distance_to_player == direction_to_enemy
		GameEnums.ActionType.MOVE_BACKWARD:
			return (
				distance_to_player == -direction_to_enemy
				or (slot_index == player_lane and slot_data.get("is_escape", false))
			)
		GameEnums.ActionType.CHARGE:
			return signi(distance_to_player) == direction_to_enemy and absi(distance_to_player) <= 2
		GameEnums.ActionType.SHOOT, GameEnums.ActionType.AIMED_SHOT:
			return has_enemy
		GameEnums.ActionType.TAKE_COVER:
			return slot_index == player_lane and str(slot_data.get("cover", "NONE")) != "NONE"
		GameEnums.ActionType.STRIKE, GameEnums.ActionType.GRAPPLE, \
		GameEnums.ActionType.BREAK, GameEnums.ActionType.PUSH_STAY, \
		GameEnums.ActionType.PULL_FOLLOW, GameEnums.ActionType.GET_UP:
			return slot_index == player_lane or has_enemy
		GameEnums.ActionType.RELOAD, GameEnums.ActionType.CYCLE, \
		GameEnums.ActionType.USE_ITEM:
			return slot_index == player_lane
	return false

func _set_box(polygon: Polygon2D, size: Vector2) -> void:
	polygon.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
	])

func _set_outline(line: Line2D, size: Vector2) -> void:
	line.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
		Vector2.ZERO,
	])
	line.default_color = COLOR_BORDER
	line.width = 1.5
