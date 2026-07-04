extends MacroCornerPanel
class_name MacroHexCornerPanel

signal expand_requested_hex(coords: Vector2i)
signal travel_requested_hex(coords: Vector2i)

@export var exploration_window: MacroExplorationWindow

var _hex: Dictionary = {}
var _title_label: Label
var _details_label: Label
var _hint_label: Label
var _thumb: TextureRect
var _action_button: Button


func _ready() -> void:
	panel_id = "hex"
	panel_corner = PanelCorner.TOP_RIGHT
	preview_size = Vector2(326.0, 360.0)
	super._ready()
	_build_preview_ui()


func _build_preview_ui() -> void:
	var root := %PreviewRoot
	if root == null:
		return
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)

	_title_label = Label.new()
	HUDAssetLibrary.apply_label(_title_label, "title")
	column.add_child(_title_label)

	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(0, 120)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_thumb)

	_details_label = Label.new()
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_details_label, "body")
	column.add_child(_details_label)

	_hint_label = Label.new()
	HUDAssetLibrary.apply_label(_hint_label, "muted")
	column.add_child(_hint_label)

	_action_button = Button.new()
	HUDAssetLibrary.apply_button(_action_button, "warning")
	_action_button.pressed.connect(_on_action_pressed)
	column.add_child(_action_button)


func apply_snapshot(snapshot: Dictionary) -> void:
	super.apply_snapshot(snapshot)
	var selected_hex: Dictionary = snapshot.get("selected_hex", {})
	visible = not selected_hex.is_empty()


func _render_preview() -> void:
	_hex = _snapshot.get("selected_hex", {}).duplicate(true)
	if _hex.is_empty():
		visible = false
		return
	visible = true
	var scene_descriptor: Dictionary = _snapshot.get("selected_scene_descriptor", {})
	_title_label.text = str(_hex.get("label", "HEX --"))
	_details_label.text = "%s // %s // HAZ %.1f" % [
		str(_hex.get("terrain", "TERRAIN")),
		str(_hex.get("structure", "NONE")),
		float(_hex.get("hazard", 0.0)),
	]
	var bg_path := str(scene_descriptor.get("background_path", ""))
	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		_thumb.texture = load(bg_path) as Texture2D
		_thumb.visible = true
	else:
		_thumb.texture = null
		_thumb.visible = false
	if bool(_hex.get("can_interact", false)):
		_hint_label.text = "CLICK TO EXPLORE"
		_action_button.text = "EXPLORE"
		_action_button.disabled = false
	elif bool(_hex.get("can_travel", false)):
		_hint_label.text = "CLICK TO TRAVEL"
		_action_button.text = "TRAVEL"
		_action_button.disabled = false
	else:
		_hint_label.text = "HEX SELECTED"
		_action_button.text = "SELECTED"
		_action_button.disabled = true


func _render_expanded() -> void:
	if exploration_window == null:
		return
	var host := %ExpandedRoot
	if host:
		exploration_window.dock_into(host)


func dock_session(session: Dictionary) -> void:
	expand()
	_render_expanded()
	if exploration_window:
		exploration_window.open_landmark(session)


func _set_state(state: PanelState) -> void:
	super._set_state(state)
	if state == PanelState.PREVIEW and exploration_window:
		exploration_window.undock()
	elif state == PanelState.EXPANDED:
		_render_expanded()


func _on_action_pressed() -> void:
	var coords: Vector2i = _hex.get("coords", Vector2i.ZERO)
	if bool(_hex.get("can_interact", false)):
		expand_requested_hex.emit(coords)
	elif bool(_hex.get("can_travel", false)):
		travel_requested_hex.emit(coords)


func _is_primary_action_click(global_pos: Vector2) -> bool:
	if _action_button and _action_button.get_global_rect().has_point(global_pos):
		return true
	return false
