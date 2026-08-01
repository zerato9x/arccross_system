extends Control
class_name MacroHexWorldMapOverlay

signal closed
signal hex_selected(coords: Vector2i)
signal travel_requested(coords: Vector2i)

var _snapshot: Dictionary = {}
var _selected_coords := Vector2i.ZERO

@onready var _map_view: MacroMinimapView = %MapView
@onready var _selection_title: Label = %SelectionTitle
@onready var _selection_details: Label = %SelectionDetails
@onready var _travel_button: Button = %TravelButton
@onready var _close_button: Button = %CloseButton
@onready var _reset_button: Button = %ResetButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map_view.navigation_enabled = true
	_map_view.hex_selected.connect(_on_hex_selected)
	_close_button.pressed.connect(close_map)
	_reset_button.pressed.connect(_map_view.reset_view)
	_travel_button.pressed.connect(_on_travel_pressed)
	HUDAssetLibrary.apply_panel(%Shell, "neutral")
	HUDAssetLibrary.apply_inset_panel(%MapFrame, "neutral")
	HUDAssetLibrary.apply_inset_panel(%InspectorPanel, "neutral")
	HUDAssetLibrary.apply_button(_close_button)
	HUDAssetLibrary.apply_button(_reset_button, "map")
	HUDAssetLibrary.apply_button(_travel_button, "discovery")
	HUDAssetLibrary.apply_label(%Title, "title")
	HUDAssetLibrary.apply_label(%Subtitle, "muted")
	HUDAssetLibrary.apply_label(_selection_title, "info")
	HUDAssetLibrary.apply_label(_selection_details, "body")


func open_map(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_selected_coords = _snapshot.get(
		"selected_coords",
		_snapshot.get("player_coords", Vector2i.ZERO)
	)
	visible = true
	move_to_front()
	_map_view.reset_view()
	_map_view.set_minimap_snapshot(_snapshot)
	_render_selection()


func refresh_map(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_selected_coords = _snapshot.get("selected_coords", _selected_coords)
	_map_view.set_minimap_snapshot(_snapshot)
	_render_selection()


func close_map(notify: bool = true) -> void:
	if not visible:
		return
	visible = false
	if notify:
		closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close_map()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F:
		_map_view.reset_view()
		get_viewport().set_input_as_handled()


func _on_hex_selected(coords: Vector2i) -> void:
	_selected_coords = coords
	_snapshot["selected_coords"] = coords
	_map_view.set_minimap_snapshot(_snapshot)
	_render_selection()
	hex_selected.emit(coords)


func _on_travel_pressed() -> void:
	if _travel_button.disabled:
		return
	travel_requested.emit(_selected_coords)


func _render_selection() -> void:
	var cell := _cell_at(_selected_coords)
	var player_coords: Vector2i = _snapshot.get("player_coords", Vector2i.ZERO)
	var distance := HexCoordUtils.distance(player_coords, _selected_coords)
	if cell.is_empty() or not bool(cell.get("explored", false)):
		_selection_title.text = "UNEXPLORED HEX"
		_selection_details.text = (
			"HEX %d, %d\nNo field intelligence is available."
			% [_selected_coords.x, _selected_coords.y]
		)
		_travel_button.text = "TRAVEL UNAVAILABLE"
		_travel_button.disabled = true
		return
	var title := str(cell.get("label", "")).strip_edges()
	if title.is_empty():
		title = _terrain_name(cell)
	_selection_title.text = title.to_upper()
	var status: Array[String] = []
	status.append("VISIBLE" if bool(cell.get("visible", false)) else "EXPLORED")
	if bool(cell.get("is_poi", false)) or bool(cell.get("has_landmark", false)):
		status.append("POINT OF INTEREST")
	if _snapshot_hostiles().has(_selected_coords):
		status.append("HOSTILE")
	if _exit_direction_at(_selected_coords) != GameEnums.MacroTravelDirection.NONE:
		status.append("ROUTE EXIT")
	var passable := bool(cell.get("passable", true))
	if not passable:
		status.append("BLOCKED")
	_selection_details.text = (
		"HEX %d, %d  //  DISTANCE %d\n%s\n%s"
		% [
			_selected_coords.x,
			_selected_coords.y,
			distance,
			_terrain_name(cell),
			"  //  ".join(status),
		]
	)
	var can_travel := distance == 1 and passable
	_travel_button.disabled = not can_travel
	_travel_button.text = (
		"TRAVEL TO HEX"
		if can_travel
		else ("CURRENT POSITION" if distance == 0 else "TRAVEL UNAVAILABLE")
	)


func _cell_at(coords: Vector2i) -> Dictionary:
	for value in _snapshot.get("cells", []):
		if value is Dictionary and value.get("coords", Vector2i(999999, 999999)) == coords:
			return value
	return {}


func _snapshot_hostiles() -> Dictionary:
	var result := {}
	for coords in _snapshot.get("visible_hostiles", []):
		if coords is Vector2i:
			result[coords] = true
	return result


func _exit_direction_at(coords: Vector2i) -> int:
	for value in _snapshot.get("exits", []):
		if value is Dictionary and value.get("coords", Vector2i(999999, 999999)) == coords:
			return int(value.get("direction", GameEnums.MacroTravelDirection.NONE))
	return GameEnums.MacroTravelDirection.NONE


func _terrain_name(cell: Dictionary) -> String:
	var water := int(cell.get("water", GameEnums.MacroWaterLayer.NONE))
	if water != GameEnums.MacroWaterLayer.NONE:
		return _enum_label(GameEnums.MacroWaterLayer.keys(), water)
	var rock := int(cell.get("rock", GameEnums.MacroRockLayer.NONE))
	if rock != GameEnums.MacroRockLayer.NONE:
		return _enum_label(GameEnums.MacroRockLayer.keys(), rock)
	return _enum_label(
		GameEnums.MacroTerrainTile.keys(),
		int(cell.get("terrain", GameEnums.MacroTerrainTile.PLAINS_GRASS))
	)


func _enum_label(keys: Array, value: int) -> String:
	if value < 0 or value >= keys.size():
		return "Unknown Terrain"
	return str(keys[value]).replace("_", " ").capitalize()
