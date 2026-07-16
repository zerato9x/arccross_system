extends PanelContainer
class_name MacroHexPreviewPanel

signal expand_requested(coords: Vector2i)
signal travel_requested(coords: Vector2i)

@onready var _title_label: Label = %PreviewTitleLabel
@onready var _details_label: Label = %PreviewDetailsLabel
@onready var _hint_label: Label = %PreviewHintLabel
@onready var _thumb: TextureRect = %PreviewThumb
@onready var _expand_button: Button = %PreviewExpandButton

var _hex: Dictionary = {}

func _ready() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_label(_details_label, "body")
	HUDAssetLibrary.apply_label(_hint_label, "muted")
	HUDAssetLibrary.apply_button(_expand_button, "warning")
	_expand_button.pressed.connect(_on_expand_pressed)
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	visible = false

func show_hex(hex_descriptor: Dictionary, scene_descriptor: Dictionary = {}) -> void:
	_hex = hex_descriptor.duplicate(true)
	if _hex.is_empty():
		visible = false
		return
	visible = true
	_render(scene_descriptor)

func get_hex_coords() -> Vector2i:
	return _hex.get("coords", Vector2i.ZERO)

func _render(scene_descriptor: Dictionary) -> void:
	var coords: Vector2i = _hex.get("coords", Vector2i.ZERO)
	_title_label.text = "HEX %d,%d // %s" % [
		coords.x,
		coords.y,
		str(_hex.get("feature_title", "Unknown Ground")).to_upper(),
	]
	var lines := PackedStringArray()
	lines.append(
		"%s // %s // %s"
		% [
			str(_hex.get("region", "UNKNOWN REGION")),
			str(_hex.get("terrain", "UNKNOWN TERRAIN")),
			str(_hex.get("water", "NONE")),
		]
	)
	lines.append(str(_hex.get("environment_summary", "No useful survey data.")))
	lines.append(str(_hex.get("movement_note", "Movement conditions unknown.")))
	if bool(_hex.get("is_poi", false)):
		lines.append("POI " + str(_hex.get("poi_name", "Unknown")))
	if int(_hex.get("travel_minutes", 0)) > 0:
		lines.append(
			"TRAVEL %d min // ~%.1f km // EXERT %.1f"
			% [
				int(_hex.get("travel_minutes", 0)),
				float(_hex.get("travel_km", 0.0)),
				float(_hex.get("travel_exertion", 1.0)),
			]
		)
	lines.append(
		"VIS %s // COVER %s // HAZ %.1f // DIST %d"
		% [
			str(_hex.get("visibility", "UNKNOWN")),
			str(_hex.get("cover", "UNKNOWN")),
			float(_hex.get("hazard", 0.0)),
			int(_hex.get("distance", 0)),
		]
	)
	lines.append(str(_hex.get("resource_hint", "No obvious resources.")))
	if int(_hex.get("ground_item_count", 0)) > 0:
		lines.append("GROUND ITEMS " + str(_hex.get("ground_item_count", 0)))
	if not str(_hex.get("entity_name", "")).is_empty():
		lines.append(
			"ENTITY %s // %s"
			% [
				str(_hex.get("entity_name", "")),
				str(_hex.get("entity_status", "")),
			]
		)
	if not bool(_hex.get("passable", true)):
		lines.append("BLOCKED")
	_details_label.text = "\n".join(lines)
	var bg_path := str(scene_descriptor.get("background_path", ""))
	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		_thumb.texture = load(bg_path) as Texture2D
		_thumb.visible = true
	else:
		_thumb.texture = null
		_thumb.visible = false
	if bool(_hex.get("can_interact", false)):
		_hint_label.text = "Click to explore"
		_expand_button.text = "Explore"
		_expand_button.disabled = false
	elif bool(_hex.get("can_travel", false)):
		_hint_label.text = "Click to travel here"
		_expand_button.text = "Travel"
		_expand_button.disabled = false
	else:
		_hint_label.text = "Hex selected"
		_expand_button.text = "Selected"
		_expand_button.disabled = true

func _on_expand_pressed() -> void:
	var coords: Vector2i = _hex.get("coords", Vector2i.ZERO)
	if bool(_hex.get("can_interact", false)):
		expand_requested.emit(coords)
	elif bool(_hex.get("can_travel", false)):
		travel_requested.emit(coords)

func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _expand_button.get_global_rect().has_point(event.global_position):
		return
	_on_expand_pressed()
	accept_event()
