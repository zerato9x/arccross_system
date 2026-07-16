extends PanelContainer
class_name NodeMapInspector

## Shows selected campaign node details and Enter / Advance actions.

signal enter_requested(node_id: String)
signal advance_requested

var _snapshot: Dictionary = {}
var _selected_id: String = ""

@onready var _name_label: Label = %NameLabel
@onready var _id_label: Label = %IdLabel
@onready var _type_label: Label = %TypeLabel
@onready var _status_label: Label = %StatusLabel
@onready var _zone_label: Label = %ZoneLabel
@onready var _objective_label: Label = %ObjectiveLabel
@onready var _neighbors_label: Label = %NeighborsLabel
@onready var _hint_label: Label = %HintLabel
@onready var _enter_button: Button = %EnterButton
@onready var _advance_button: Button = %AdvanceButton


func _ready() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_name_label, "title")
	HUDAssetLibrary.apply_label(_id_label, "muted")
	HUDAssetLibrary.apply_label(_type_label, "body")
	HUDAssetLibrary.apply_label(_status_label, "body")
	HUDAssetLibrary.apply_label(_zone_label, "body")
	HUDAssetLibrary.apply_label(_objective_label, "body")
	HUDAssetLibrary.apply_label(_neighbors_label, "body")
	HUDAssetLibrary.apply_label(_hint_label, "muted")
	HUDAssetLibrary.apply_button(_enter_button, "map")
	HUDAssetLibrary.apply_button(_advance_button, "pass")
	_enter_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size(120.0)
	_advance_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size(120.0)
	_enter_button.pressed.connect(_on_enter_pressed)
	_advance_button.pressed.connect(func(): advance_requested.emit())
	_clear()


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if _selected_id.is_empty():
		_selected_id = str(_snapshot.get("active_node_id", ""))
	_render()


func select_node(node_id: String) -> void:
	_selected_id = node_id
	_render()


func _render() -> void:
	var node: Variant = _find_node(_selected_id)
	if node == null:
		_clear()
		return

	_name_label.text = str(node.get("display_name", "Unknown Node"))
	_id_label.text = "ID  %s" % str(node.get("id", ""))
	_type_label.text = "Type  %s" % _enum_key(GameEnums.MacroNodeType.keys(), int(node.get("type", 0)))
	_status_label.text = "Status  %s" % _status_text(node)
	_zone_label.text = "Zone  %s · %s\n%s" % [
		_enum_key(GameEnums.MacroZoneKind.keys(), int(node.get("zone_kind", 0))),
		_enum_key(GameEnums.GridBiome.keys(), int(node.get("biome", 0))),
		str(node.get("zone_flavor", "")),
	]
	_objective_label.text = "Objective  %s\n%s" % [
		str(node.get("objective_id", "")),
		str(node.get("objective_text", "")),
	]
	_neighbors_label.text = "Neighbors\n%s" % _neighbors_text(node)

	var can_enter := bool(node.get("can_enter", false))
	var enter_reason := str(node.get("enter_reason", ""))
	_enter_button.disabled = not can_enter
	_enter_button.text = "Enter Node"
	_enter_button.tooltip_text = enter_reason if not enter_reason.is_empty() else "Enter this node's 12×12 zone."

	var can_advance := bool(_snapshot.get("can_advance", false))
	var advance_reason := str(_snapshot.get("advance_reason", ""))
	_advance_button.disabled = not can_advance
	_advance_button.text = "Advance"
	_advance_button.tooltip_text = (
		advance_reason
		if not advance_reason.is_empty()
		else str(_snapshot.get("advance_hint", "Advance to the next available node."))
	)

	var hints: PackedStringArray = []
	if not can_enter and not enter_reason.is_empty():
		hints.append(enter_reason)
	if not can_advance and not advance_reason.is_empty():
		hints.append(advance_reason)
	var advance_hint := str(_snapshot.get("advance_hint", ""))
	if not advance_hint.is_empty() and can_advance:
		hints.append(advance_hint)
	_hint_label.text = "\n".join(hints)


func _clear() -> void:
	_name_label.text = "No node selected"
	_id_label.text = ""
	_type_label.text = ""
	_status_label.text = ""
	_zone_label.text = ""
	_objective_label.text = ""
	_neighbors_label.text = ""
	_hint_label.text = ""
	_enter_button.disabled = true
	_advance_button.disabled = true


func _on_enter_pressed() -> void:
	if _selected_id.is_empty():
		return
	enter_requested.emit(_selected_id)


func _find_node(node_id: String) -> Variant:
	for entry in _snapshot.get("nodes", []):
		if entry is Dictionary and str(entry.get("id", "")) == node_id:
			return entry
	return null


func _status_text(node: Dictionary) -> String:
	var parts: PackedStringArray = []
	if bool(node.get("is_active", false)):
		parts.append("ACTIVE")
	if bool(node.get("is_next", false)):
		parts.append("NEXT")
	if bool(node.get("completed", false)):
		parts.append("COMPLETED")
	elif bool(node.get("unlocked", false)):
		parts.append("UNLOCKED")
	elif bool(node.get("discovered", false)):
		parts.append("KNOWN / LOCKED")
	else:
		parts.append("HIDDEN")
	return " · ".join(parts)


func _neighbors_text(node: Dictionary) -> String:
	var neighbors: Array = node.get("neighbors", [])
	if neighbors.is_empty():
		return "  (none)"
	var lines: PackedStringArray = []
	for neighbor_id in neighbors:
		var neighbor: Variant = _find_node(str(neighbor_id))
		var label := str(neighbor_id)
		var legality := "locked"
		if neighbor != null:
			label = str(neighbor.get("display_name", neighbor_id))
			if bool(neighbor.get("can_enter", false)):
				legality = "enterable"
			elif bool(neighbor.get("unlocked", false)):
				legality = "unlocked"
			elif bool(neighbor.get("discovered", false)):
				legality = "known"
		lines.append("  • %s (%s)" % [label, legality])
	return "\n".join(lines)


func _enum_key(keys: PackedStringArray, value: int) -> String:
	if value >= 0 and value < keys.size():
		return str(keys[value])
	return str(value)
