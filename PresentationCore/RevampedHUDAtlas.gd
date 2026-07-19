extends "res://PresentationCore/HUDAssetLibrary.gd"
class_name RevampedHUDAtlas

# Widget-only helper for the revamped art pack. Corner panel chrome belongs to
# HUDAssetLibrary; do not apply these atlas panels to resizable HUD shells.
const UI_ATLAS := REVAMPED_ROOT + "UI Assets pack_v.1_st/UI.png"
const CONDITION_ROOT := REVAMPED_ROOT + "Condition/"

const UI_PANEL_CORNER := Rect2(16.0, 16.0, 32.0, 32.0)
const UI_PANEL_EDGE_H := Rect2(48.0, 16.0, 32.0, 32.0)
const UI_PANEL_EDGE_V := Rect2(16.0, 48.0, 32.0, 32.0)
const UI_PANEL_FILL := Rect2(48.0, 48.0, 32.0, 32.0)
const UI_BAR_SEGMENTED := Rect2(769.0, 18.0, 46.0, 12.0)
const UI_BAR_PLAIN := Rect2(866.0, 19.0, 44.0, 10.0)
const UI_ICON_HEART := Rect2(145.0, 17.0, 14.0, 14.0)
const UI_ICON_SHIELD := Rect2(193.0, 17.0, 14.0, 14.0)
const UI_ICON_LIGHTNING := Rect2(257.0, 18.0, 14.0, 14.0)
const UI_ICON_DROPLET := Rect2(209.0, 18.0, 14.0, 14.0)
const UI_INVENTORY_SLOT := Rect2(1056.0, 16.0, 32.0, 32.0)
const UI_BUTTON_IDLE := Rect2(288.0, 16.0, 48.0, 24.0)
const UI_BUTTON_HOVER := Rect2(352.0, 17.0, 48.0, 24.0)

const CONDITION_FILES := {
	"fine": "ConditionFine.png",
	"danger": "ConditionDanger.png",
	"healing": "ConditionHealing.png",
	"infected": "ConditionInfected.png",
	"precaution_o": "ConditionPrecautionO.png",
	"precaution_y": "ConditionPrecautionY.png",
}

static var _texture_cache: Dictionary = {}


static func atlas_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex := official_texture(path)
	if tex != null:
		_texture_cache[path] = tex
	return tex


static func atlas_region(path: String, region: Rect2) -> Texture2D:
	var source := atlas_texture(path)
	if source == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	return atlas


static func panel_stylebox(kind: String = "neutral") -> StyleBox:
	var tex := atlas_texture(UI_ATLAS)
	if tex == null:
		return panel_style(kind)
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.set_texture_margin_all(16)
	style.region_rect = Rect2(16.0, 16.0, 128.0, 128.0)
	style.modulate_color = Color(1, 1, 1, 0.96)
	match kind:
		"warning":
			style.modulate_color = Color(1.08, 0.95, 0.82, 0.98)
		"critical":
			style.modulate_color = Color(1.15, 0.82, 0.78, 0.98)
		"anomaly":
			style.modulate_color = Color(0.92, 0.86, 0.95, 0.98)
	return style


static func apply_revamped_panel(panel: PanelContainer, kind: String = "neutral") -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", panel_stylebox(kind))


static func segmented_bar_texture() -> Texture2D:
	return atlas_region(UI_ATLAS, UI_BAR_SEGMENTED)


static func plain_bar_texture() -> Texture2D:
	return atlas_region(UI_ATLAS, UI_BAR_PLAIN)


static func inventory_slot_style(active: bool = false) -> StyleBox:
	var tex := atlas_region(UI_ATLAS, UI_INVENTORY_SLOT)
	if tex == null:
		return pocket_slot_style(active)
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.set_texture_margin_all(4)
	style.modulate_color = Color(1.1, 1.02, 0.9, 1.0) if active else Color.WHITE
	return style


static func apply_revamped_button(button: Button) -> void:
	if button == null:
		return
	var idle := atlas_region(UI_ATLAS, UI_BUTTON_IDLE)
	var hover := atlas_region(UI_ATLAS, UI_BUTTON_HOVER)
	if idle == null:
		apply_button(button)
		return
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = hover if state in ["hover", "pressed"] else idle
		style.set_texture_margin_all(8)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_font_size_override("font_size", 11)


static func apply_revamped_progress_bar(
	bar: ProgressBar,
	fill_kind: String = "health"
) -> void:
	if bar == null:
		return
	bar.show_percentage = false
	var frame := segmented_bar_texture()
	if frame == null:
		apply_progress_bar(bar, fill_kind)
		return
	var bg := StyleBoxTexture.new()
	bg.texture = frame
	bg.modulate_color = Color(0.35, 0.35, 0.35, 1.0)
	var fill := StyleBoxTexture.new()
	fill.texture = frame
	fill.modulate_color = bar_fill_style(fill_kind).bg_color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


static func stat_icon(name: String) -> Texture2D:
	match name:
		"blood", "heart":
			return atlas_region(UI_ATLAS, UI_ICON_HEART)
		"stance", "shield":
			return atlas_region(UI_ATLAS, UI_ICON_SHIELD)
		"hunger", "warning":
			return atlas_region(UI_ATLAS, UI_ICON_LIGHTNING)
		"thirst", "health":
			return atlas_region(UI_ATLAS, UI_ICON_DROPLET)
	return status_icon(name)


static func condition_icon(condition: String) -> Texture2D:
	var key := condition.to_lower()
	if not CONDITION_FILES.has(key):
		key = "fine"
	var path: String = CONDITION_ROOT + CONDITION_FILES[key]
	return atlas_texture(path)


static func emergency_condition_icon(emergency: String) -> Texture2D:
	match emergency:
		"LOW_BLOOD", "EXSANGUINATION", "BLEEDING":
			return condition_icon("danger")
		"STARVING", "DEHYDRATED":
			return condition_icon("precaution_o")
		"EXHAUSTED", "STANCE_BREAK":
			return condition_icon("precaution_y")
		"INFECTION", "ORGAN_FAILURE":
			return condition_icon("infected")
		"HEALING":
			return condition_icon("healing")
	return condition_icon("fine")


static func apply_revamped_label(label: Label, role: String = "body") -> void:
	apply_label(label, role)
