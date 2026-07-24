extends PanelContainer
class_name MacroHexPreviewPanel

signal expand_requested(coords: Vector2i)
signal travel_requested(coords: Vector2i)

@onready var _title_label: Label = %PreviewTitleLabel
@onready var _details_label: RichTextLabel = %PreviewDetailsLabel
@onready var _hint_label: Label = %PreviewHintLabel
@onready var _thumb: TextureRect = %PreviewThumb
@onready var _expand_button: Button = %PreviewExpandButton

var _hex: Dictionary = {}

func _ready() -> void:
	restyle()
	_expand_button.pressed.connect(_on_expand_pressed)
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	visible = false


func restyle() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_rich_label(_details_label, "body")
	HUDAssetLibrary.apply_label(_hint_label, "muted")
	HUDAssetLibrary.apply_button(_expand_button, "warning")

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
	var hazard := float(_hex.get("hazard", 0.0))
	var blocked := not bool(_hex.get("passable", true))
	var title_role := "title"
	if blocked or hazard > 0.7:
		title_role = "critical"
	elif hazard > 0.3:
		title_role = "warning"
	HUDAssetLibrary.apply_label(_title_label, "title")
	if title_role != "title":
		_title_label.add_theme_color_override(
			"font_color",
			HUDAssetLibrary.color_for_role(title_role)
		)
	_title_label.text = "HEX %d,%d // %s" % [
		coords.x,
		coords.y,
		str(_hex.get("feature_title", "Unknown Ground")).to_upper(),
	]

	var lines := PackedStringArray()
	lines.append(HUDAssetLibrary.bbcode(
		"info",
		"%s // %s // %s"
		% [
			str(_hex.get("region", "UNKNOWN REGION")),
			str(_hex.get("terrain", "UNKNOWN TERRAIN")),
			str(_hex.get("water", "NONE")),
		]
	))
	lines.append(HUDAssetLibrary.bbcode(
		"body",
		str(_hex.get("environment_summary", "No useful survey data."))
	))
	lines.append(HUDAssetLibrary.bbcode(
		"muted",
		str(_hex.get("movement_note", "Movement conditions unknown."))
	))
	if bool(_hex.get("is_poi", false)):
		lines.append(HUDAssetLibrary.bbcode(
			_poi_role(),
			"POI " + str(_hex.get("poi_name", "Unknown"))
		))
	if int(_hex.get("travel_minutes", 0)) > 0:
		lines.append(HUDAssetLibrary.bbcode(
			"travel",
			"TRAVEL %d min // ~%.1f km // EXERT %.1f"
			% [
				int(_hex.get("travel_minutes", 0)),
				float(_hex.get("travel_km", 0.0)),
				float(_hex.get("travel_exertion", 1.0)),
			]
		))
	var haz_role := "muted"
	if hazard > 0.7:
		haz_role = "critical"
	elif hazard > 0.3:
		haz_role = "caution"
	lines.append(
		"%s // %s // %s // %s"
		% [
			HUDAssetLibrary.bbcode("muted", "VIS %s" % str(_hex.get("visibility", "UNKNOWN"))),
			HUDAssetLibrary.bbcode("muted", "COVER %s" % str(_hex.get("cover", "UNKNOWN"))),
			HUDAssetLibrary.bbcode(haz_role, "HAZ %.1f" % hazard),
			HUDAssetLibrary.bbcode("muted", "DIST %d" % int(_hex.get("distance", 0))),
		]
	)
	lines.append(HUDAssetLibrary.bbcode(
		"muted",
		str(_hex.get("resource_hint", "No obvious resources."))
	))
	if int(_hex.get("ground_item_count", 0)) > 0:
		lines.append(HUDAssetLibrary.bbcode(
			"discovery",
			"GROUND ITEMS " + str(_hex.get("ground_item_count", 0))
		))
	if not str(_hex.get("entity_name", "")).is_empty():
		lines.append(HUDAssetLibrary.bbcode(
			_entity_role(),
			"ENTITY %s // %s"
			% [
				str(_hex.get("entity_name", "")),
				str(_hex.get("entity_status", "")),
			]
		))
	if blocked:
		lines.append(HUDAssetLibrary.bbcode("critical", "BLOCKED"))
	_details_label.text = "\n".join(lines)

	var bg_path := str(scene_descriptor.get("background_path", ""))
	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		_thumb.texture = load(bg_path) as Texture2D
		_thumb.visible = true
	else:
		_thumb.texture = null
		_thumb.visible = false
	if bool(_hex.get("can_interact", false)):
		_hint_label.text = "Press E to explore"
		HUDAssetLibrary.apply_label(_hint_label, "discovery")
		_expand_button.text = "Explore [E]"
		_expand_button.disabled = false
	elif bool(_hex.get("can_travel", false)):
		_hint_label.text = "Press T to travel"
		HUDAssetLibrary.apply_label(_hint_label, "travel")
		_expand_button.text = "Travel [T]"
		_expand_button.disabled = false
	else:
		_hint_label.text = "Hex selected"
		HUDAssetLibrary.apply_label(_hint_label, "muted")
		_expand_button.text = "Selected"
		_expand_button.disabled = true

func _poi_role() -> String:
	var status := str(_hex.get("poi_status", _hex.get("entity_status", ""))).to_lower()
	if bool(_hex.get("is_anomaly", false)) or "anomaly" in status or "mist" in status:
		return "anomaly"
	if bool(_hex.get("hostile", false)) or "hostile" in status or "danger" in status:
		return "critical"
	return "discovery"

func _entity_role() -> String:
	var status := str(_hex.get("entity_status", "")).to_lower()
	if "friend" in status or "ally" in status or "clear" in status or "safe" in status:
		return "info"
	return "warning"

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
