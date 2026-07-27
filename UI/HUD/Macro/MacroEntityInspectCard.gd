extends PanelContainer
class_name MacroEntityInspectCard

## Floating inspect card for hovered macro entities. Presentation only.

var _payload: Dictionary = {}

@onready var _title: Label = %InspectTitle
@onready var _meta: Label = %InspectMeta
@onready var _tags: Label = %InspectTags
@onready var _paper_doll: PaperDollModel = %InspectPaperDoll


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	restyle()
	if _paper_doll:
		_paper_doll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_paper_doll.set_backdrop_visible(false)


func restyle() -> void:
	HUDAssetLibrary.apply_panel(self, "warning")
	HUDAssetLibrary.apply_label(_title, "title")
	HUDAssetLibrary.apply_label(_meta, "body")
	HUDAssetLibrary.apply_label(_tags, "muted")
	HUDAssetLibrary.apply_soft_edge(self, 0.16)


func show_entity(payload: Dictionary) -> void:
	_payload = payload.duplicate(true)
	if _payload.is_empty():
		hide_card()
		return
	visible = true
	_title.text = str(_payload.get("name", "UNKNOWN")).to_upper()
	_meta.text = "%s // %s // %s\nWPN %s // ARM %s\nB%d F%d Fo%d W%d" % [
		str(_payload.get("faction", "?")),
		str(_payload.get("agenda", "?")),
		str(_payload.get("combat_tactic", "?")),
		str(_payload.get("weapon", "NONE")).to_upper(),
		str(_payload.get("armor", "NONE")).to_upper(),
		int(_payload.get("brawn", 0)),
		int(_payload.get("finesse", 0)),
		int(_payload.get("fortitude", 0)),
		int(_payload.get("will", 0)),
	]
	var tags: Array = _payload.get("tags", [])
	var tag_parts: PackedStringArray = []
	for tag in tags:
		tag_parts.append(str(tag))
	_tags.text = " // ".join(tag_parts)
	var equipment: Array = _payload.get("equipment", [])
	if equipment.is_empty() and _payload.has("record"):
		equipment = PaperDollPresenter.equipment_from_entity_record(
			_payload.get("record", {})
		)
	PaperDollPresenter.apply_to_doll(_paper_doll, equipment)


func hide_card() -> void:
	_payload.clear()
	visible = false


func is_showing() -> bool:
	return visible and not _payload.is_empty()
