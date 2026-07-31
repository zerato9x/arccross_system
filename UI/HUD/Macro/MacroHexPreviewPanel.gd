extends PanelContainer
class_name MacroHexPreviewPanel

signal expand_requested(coords: Vector2i)
## Kept for scene/API compatibility; destination travel now belongs to the
## separate target tooltip.
signal travel_requested(coords: Vector2i)

@onready var _title_label: Label = %PreviewTitleLabel
@onready var _details_label: RichTextLabel = %PreviewDetailsLabel
@onready var _hint_label: Label = %PreviewHintLabel
@onready var _thumb: TextureRect = %PreviewThumb
@onready var _expand_button: Button = %PreviewExpandButton

var _location: Dictionary = {}
var _composition_view: MacroHexCompositionView


func _ready() -> void:
	restyle()
	_expand_button.pressed.connect(_on_expand_pressed)
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_install_composition_view()
	visible = false


func restyle() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_rich_label(_details_label, "body")
	HUDAssetLibrary.apply_label(_hint_label, "muted")
	HUDAssetLibrary.apply_button(_expand_button, "discovery")


func show_location(location: Dictionary) -> void:
	_location = location.duplicate(true)
	visible = not _location.is_empty()
	if visible:
		_render()


func show_hex(hex_descriptor: Dictionary, scene_descriptor: Dictionary = {}) -> void:
	# Compatibility for old callers during migration.
	show_location({
		"coords": hex_descriptor.get("coords", Vector2i.ZERO),
		"hex": hex_descriptor,
		"presentation": {"scene": scene_descriptor},
		"can_open": bool(hex_descriptor.get("can_interact", false)),
	})


func get_hex_coords() -> Vector2i:
	return _location.get("coords", Vector2i.ZERO)


func _install_composition_view() -> void:
	var column := _thumb.get_parent() as VBoxContainer
	if column == null:
		return
	_composition_view = MacroHexCompositionView.new()
	_composition_view.name = "HereComposition"
	_composition_view.custom_minimum_size = Vector2(0.0, 142.0)
	_composition_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_composition_view)
	column.move_child(_composition_view, _thumb.get_index())
	_thumb.visible = false
	_thumb.custom_minimum_size = Vector2.ZERO


func _render() -> void:
	var hex: Dictionary = _location.get("hex", {})
	var coords: Vector2i = _location.get("coords", Vector2i.ZERO)
	var hazard := float(hex.get("hazard", 0.0))
	HUDAssetLibrary.apply_label(_title_label, "title")
	if hazard > 0.7 or not bool(hex.get("passable", true)):
		_title_label.add_theme_color_override(
			"font_color", HUDAssetLibrary.color_for_role("critical")
		)
	elif hazard > 0.3:
		_title_label.add_theme_color_override(
			"font_color", HUDAssetLibrary.color_for_role("warning")
		)
	_title_label.text = "HERE // HEX %d,%d // %s" % [
		coords.x,
		coords.y,
		str(hex.get("feature_title", "Unknown Ground")).to_upper(),
	]

	var lines := PackedStringArray()
	lines.append(HUDAssetLibrary.bbcode(
		"info",
		"%s // %s // %s" % [
			str(hex.get("region", "UNKNOWN REGION")),
			str(hex.get("terrain", "UNKNOWN TERRAIN")),
			str(hex.get("water", "NONE")),
		]
	))
	lines.append(HUDAssetLibrary.bbcode(
		"body", str(hex.get("environment_summary", "No useful survey data."))
	))
	lines.append(
		"%s // %s // %s" % [
			HUDAssetLibrary.bbcode("muted", "VIS %s" % str(hex.get("visibility", "?"))),
			HUDAssetLibrary.bbcode("muted", "COVER %s" % str(hex.get("cover", "?"))),
			HUDAssetLibrary.bbcode(
				"critical" if hazard > 0.7 else ("caution" if hazard > 0.3 else "muted"),
				"HAZ %.1f" % hazard
			),
		]
	)
	var fixture_count := int(_location.get("fixture_count", 0))
	var ground_count := int(hex.get("ground_item_count", 0))
	var entity_name := str(hex.get("entity_name", ""))
	var presence := "%d PLACE%s" % [fixture_count, "" if fixture_count == 1 else "S"]
	if not str(hex.get("search_site_id", "")).is_empty():
		presence += (
			" // DEPLETED SALVAGE"
			if bool(hex.get("search_depleted", false))
			else (
				" // LOCKED CACHE"
				if bool(hex.get("search_requires_access", false))
				else " // OPEN SALVAGE"
			)
		)
	if ground_count > 0:
		presence += " // %d ITEM%s" % [ground_count, "" if ground_count == 1 else "S"]
	if not entity_name.is_empty():
		presence += " // " + entity_name.to_upper()
	lines.append(HUDAssetLibrary.bbcode("discovery", presence))
	_details_label.text = "\n".join(lines)

	if _composition_view:
		_composition_view.show_composition(_location.get("presentation", {}))
	_hint_label.text = "Open the location board"
	_expand_button.text = "Explore Here [E]"
	_expand_button.disabled = not bool(_location.get("can_open", true))


func _on_expand_pressed() -> void:
	if _location.is_empty() or _expand_button.disabled:
		return
	expand_requested.emit(get_hex_coords())


func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _expand_button.get_global_rect().has_point(event.global_position):
		return
	_on_expand_pressed()
	accept_event()
