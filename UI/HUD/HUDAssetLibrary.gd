extends RefCounted
class_name HUDAssetLibrary

const COLOR_TEXT := Color("#d6e6dc")
const COLOR_MUTED := Color("#7e9691")
const COLOR_NORMAL := Color("#48dedc")
const COLOR_CAUTION := Color("#f4b540")
const COLOR_CRITICAL := Color("#e63a46")
const COLOR_ANOMALY := Color("#d94ad6")
const COLOR_PANEL := Color("#04080a")
const COLOR_PANEL_ALT := Color("#071215")

const ROOT := "res://Asset/UI/HUD/"
const PANEL_NEUTRAL := ROOT + "frames/panel_neutral_64.png"
const PANEL_WARNING := ROOT + "frames/panel_warning_64.png"
const PANEL_CRITICAL := ROOT + "frames/panel_critical_64.png"
const PANEL_ANOMALY := ROOT + "frames/panel_anomaly_64.png"
const BUTTON_IDLE := ROOT + "frames/button_idle_64x24.png"
const BUTTON_HOVER := ROOT + "frames/button_hover_64x24.png"
const BUTTON_ACTIVE := ROOT + "frames/button_active_64x24.png"
const BUTTON_DISABLED := ROOT + "frames/button_disabled_64x24.png"
const BAR_FRAME := ROOT + "bars/bar_frame_96x12.png"

static func texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func status_icon(name: String) -> Texture2D:
	return texture(ROOT + "icons/status/%s_32.png" % name)

static func action_icon(name: String) -> Texture2D:
	return texture(ROOT + "icons/actions/%s_32.png" % name)

static func combat_icon(name: String) -> Texture2D:
	return texture(ROOT + "icons/combat/%s_32.png" % name)

static func menu_icon(name: String) -> Texture2D:
	if name in ["inventory", "settings", "save", "load", "map", "rest"]:
		return action_icon(name)
	return status_icon(name)

static func panel_style(kind: String = "neutral") -> StyleBox:
	var path := PANEL_NEUTRAL
	match kind:
		"warning":
			path = PANEL_WARNING
		"critical":
			path = PANEL_CRITICAL
		"anomaly":
			path = PANEL_ANOMALY
	return _texture_style(path, 8.0, 10.0)

static func button_style(state: String = "normal") -> StyleBox:
	var path := BUTTON_IDLE
	match state:
		"hover":
			path = BUTTON_HOVER
		"pressed":
			path = BUTTON_ACTIVE
		"disabled":
			path = BUTTON_DISABLED
	return _texture_style(path, 6.0, 8.0)

static func bar_background_style() -> StyleBox:
	return _texture_style(BAR_FRAME, 3.0, 2.0)

static func bar_fill_style(kind: String = "health") -> StyleBox:
	return _texture_style(
		ROOT + "bars/bar_fill_%s_96x8.png" % kind,
		1.0,
		1.0
	)

static func apply_panel(panel: PanelContainer, kind: String = "neutral") -> void:
	if panel == null:
		return
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
	button.add_theme_color_override("font_pressed_color", COLOR_CAUTION)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	button.add_theme_font_size_override("font_size", 12)
	if not icon_name.is_empty():
		button.icon = menu_icon(icon_name)
		button.expand_icon = false

static func apply_option_button(button: OptionButton) -> void:
	if button == null:
		return
	apply_button(button)
	button.add_theme_font_size_override("font_size", 11)

static func apply_progress_bar(
	bar: ProgressBar,
	fill_kind: String = "health"
) -> void:
	if bar == null:
		return
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", bar_background_style())
	bar.add_theme_stylebox_override("fill", bar_fill_style(fill_kind))

static func apply_label(label: Label, role: String = "body") -> void:
	if label == null:
		return
	match role:
		"title":
			label.add_theme_color_override("font_color", COLOR_NORMAL)
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

static func texture_panel_sprite(sprite: Sprite2D, kind: String, size: Vector2) -> void:
	if sprite == null:
		return
	var style_path := PANEL_NEUTRAL
	match kind:
		"warning":
			style_path = PANEL_WARNING
		"critical":
			style_path = PANEL_CRITICAL
		"anomaly":
			style_path = PANEL_ANOMALY
	var tex := texture(style_path)
	sprite.texture = tex
	sprite.centered = false
	if tex:
		sprite.scale = Vector2(
			size.x / maxf(1.0, float(tex.get_width())),
			size.y / maxf(1.0, float(tex.get_height()))
		)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func button_texture(state: String) -> Texture2D:
	match state:
		"hover":
			return texture(BUTTON_HOVER)
		"pressed":
			return texture(BUTTON_ACTIVE)
		"disabled":
			return texture(BUTTON_DISABLED)
	return texture(BUTTON_IDLE)

static func _texture_style(
	path: String,
	texture_margin: float,
	content_margin: float
) -> StyleBox:
	var tex := texture(path)
	if tex == null:
		return _flat_fallback()
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.set_texture_margin_all(texture_margin)
	style.set_content_margin_all(content_margin)
	style.draw_center = true
	return style

static func _flat_fallback() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(COLOR_PANEL, 0.94)
	style.border_color = Color(COLOR_NORMAL, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8.0)
	return style
