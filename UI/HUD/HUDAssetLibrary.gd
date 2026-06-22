extends RefCounted
class_name HUDAssetLibrary

# Pocket Inventory is the visual source of truth.  The game uses native
# StyleBoxFlat frames so HUD panels can scale without stretching a texture.
const COLOR_TEXT := Color("#efe1bd")
const COLOR_MUTED := Color("#a99a82")
const COLOR_NORMAL := Color("#9ac4c4")
const COLOR_CAUTION := Color("#d8b575")
const COLOR_CRITICAL := Color("#d9786c")
const COLOR_ANOMALY := Color("#a9b8dd")
const COLOR_PANEL := Color("#101b20")
const COLOR_PANEL_ALT := Color("#162730")

const MAIN_ROOT := (
	"res://Asset/UI/revampedHUD/POCKET INVENTORY (MAIN)/Sprites/Content/"
)
const MAIN_ICON_ROOT := MAIN_ROOT + "Icons/"
const MAIN_BACKGROUND := MAIN_ROOT + "Background/0.png"
const MAIN_EQUIPMENT_HOLDER := MAIN_ROOT + "Holders/0.png"
const MAIN_INVENTORY_HOLDER := MAIN_ROOT + "Holders/1.png"
const THEME_PATH := "res://UI/HUD/PocketInventoryTheme.tres"

static func texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func background_texture() -> Texture2D:
	return texture(MAIN_BACKGROUND)

static func equipment_holder_texture() -> Texture2D:
	return texture(MAIN_EQUIPMENT_HOLDER)

static func inventory_holder_texture() -> Texture2D:
	return texture(MAIN_INVENTORY_HOLDER)

static func status_icon(name: String) -> Texture2D:
	var indices := {
		"blood": 1,
		"stance": 2,
		"hunger": 3,
		"thirst": 4,
		"fatigue": 5,
		"temperature": 6,
		"time": 7,
		"location": 8,
		"warning": 9,
	}
	return texture(MAIN_ICON_ROOT + "%d.png" % int(indices.get(name, 0)))

static func action_icon(name: String) -> Texture2D:
	var indices := {
		"inventory": 10,
		"settings": 11,
		"save": 12,
		"load": 13,
		"map": 14,
		"rest": 6,
	}
	return texture(MAIN_ICON_ROOT + "%d.png" % int(indices.get(name, 0)))

static func combat_icon(name: String) -> Texture2D:
	var indices := {
		"shoot": 1,
		"melee": 2,
		"reload": 3,
		"cycle": 4,
		"block": 5,
		"dodge": 6,
		"grapple": 7,
		"break_guard": 8,
		"cover": 9,
		"reaction": 10,
		"pass": 11,
		"execute": 12,
	}
	return texture(MAIN_ICON_ROOT + "%d.png" % int(indices.get(name, 0)))

static func menu_icon(name: String) -> Texture2D:
	if name in ["inventory", "settings", "save", "load", "map", "rest"]:
		return action_icon(name)
	return status_icon(name)

static func panel_style(kind: String = "neutral") -> StyleBoxFlat:
	match kind:
		"warning":
			return _flat_style(Color("#231d16"), COLOR_CAUTION, 2, 4, 10.0)
		"critical":
			return _flat_style(Color("#27171a"), COLOR_CRITICAL, 2, 4, 10.0)
		"anomaly":
			return _flat_style(Color("#171d2b"), COLOR_ANOMALY, 2, 4, 10.0)
		"paper":
			return _flat_style(Color("#e6d7b3"), Color("#b98f5e"), 3, 4, 12.0)
	return _flat_style(COLOR_PANEL, Color("#4b6670"), 2, 4, 10.0)

static func button_style(state: String = "normal") -> StyleBoxFlat:
	match state:
		"hover":
			return _flat_style(Color("#2d4650"), COLOR_TEXT, 2, 3, 7.0)
		"pressed":
			return _flat_style(Color("#8d6b4d"), Color("#f0d899"), 2, 3, 7.0)
		"disabled":
			return _flat_style(Color("#10191d"), Color("#314851"), 2, 3, 7.0)
	return _flat_style(Color("#1c2c33"), Color("#66848d"), 2, 3, 7.0)

static func bar_background_style() -> StyleBoxFlat:
	return _flat_style(Color("#081014"), Color("#5d7780"), 1, 2, 2.0)

static func bar_fill_style(kind: String = "health") -> StyleBoxFlat:
	var fill := Color("#b9dd69")
	match kind:
		"blood", "critical":
			fill = COLOR_CRITICAL
		"ap", "warning":
			fill = COLOR_CAUTION
		"stance":
			fill = COLOR_NORMAL
		"anomaly":
			fill = COLOR_ANOMALY
	return _flat_style(fill, fill.lightened(0.22), 1, 1, 1.0)

static func apply_panel(panel: PanelContainer, kind: String = "neutral") -> void:
	if panel:
		panel.add_theme_stylebox_override("panel", panel_style(kind))

static func apply_button(button: Button, icon_name: String = "") -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", button_style("normal"))
	button.add_theme_stylebox_override("hover", button_style("hover"))
	button.add_theme_stylebox_override("pressed", button_style("pressed"))
	button.add_theme_stylebox_override("disabled", button_style("disabled"))
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", Color("#fff2cb"))
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED.darkened(0.35))
	button.add_theme_font_size_override("font_size", 12)
	if not icon_name.is_empty():
		button.icon = menu_icon(icon_name)
		button.expand_icon = false

static func apply_option_button(button: OptionButton) -> void:
	if button:
		apply_button(button)
		button.add_theme_font_size_override("font_size", 11)

static func apply_progress_bar(
	bar: ProgressBar,
	fill_kind: String = "health"
) -> void:
	if bar:
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", bar_background_style())
		bar.add_theme_stylebox_override("fill", bar_fill_style(fill_kind))

static func apply_label(label: Label, role: String = "body") -> void:
	if label == null:
		return
	match role:
		"title":
			label.add_theme_color_override("font_color", COLOR_TEXT)
			label.add_theme_font_size_override("font_size", 22)
		"warning":
			label.add_theme_color_override("font_color", COLOR_CAUTION)
			label.add_theme_font_size_override("font_size", 11)
		"critical":
			label.add_theme_color_override("font_color", COLOR_CRITICAL)
			label.add_theme_font_size_override("font_size", 11)
		"muted":
			label.add_theme_color_override("font_color", COLOR_MUTED)
			label.add_theme_font_size_override("font_size", 11)
		_:
			label.add_theme_color_override("font_color", COLOR_TEXT)
			label.add_theme_font_size_override("font_size", 12)

# Node2D combat UI now draws its panel and borders natively.  Keeping this
# compatibility method stops stale Sprite2D frame assignments from returning.
static func texture_panel_sprite(
	sprite: Sprite2D,
	_kind: String,
	_size: Vector2
) -> void:
	if sprite:
		sprite.texture = null
		sprite.visible = false

static func button_texture(_state: String) -> Texture2D:
	return null

static func _flat_style(
	background: Color,
	border: Color,
	border_width: int,
	corner_radius: int,
	content_margin: float
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.set_content_margin_all(content_margin)
	style.shadow_color = Color("#05090d88")
	style.shadow_size = 3
	style.shadow_offset = Vector2(1.0, 2.0)
	return style
