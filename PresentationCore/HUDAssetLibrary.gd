extends RefCounted

const COLOR_TEXT := Color("#e2d6b8")
const COLOR_MUTED := Color("#8b8572")
const COLOR_NORMAL := Color("#c2aa78")
const COLOR_CAUTION := Color("#d19a3d")
const COLOR_CRITICAL := Color("#b94b3e")
const COLOR_ANOMALY := Color("#8f6958")
const COLOR_PANEL := Color("#0b0d0b")
const COLOR_PANEL_ALT := Color("#151711")
const COLOR_PANEL_WARM := Color("#201b13")
const COLOR_BORDER := Color("#6f634d")
const COLOR_BORDER_DARK := Color("#37372f")
const COLOR_SLOT := Color("#11140f")
const MACRO_PANEL_PADDING := 8.0
const MACRO_SLOT_SIZE := Vector2(78.0, 84.0)
const MACRO_BUTTON_MIN_HEIGHT := 28.0

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
const USE_HUD_TEXTURES := false
const REVAMPED_ROOT := "res://Asset/UI/revampedHUD/"
const BW_ROOT := REVAMPED_ROOT + "B&W_UI_ByAndrox_FREE/HUD/"
const BW_MENU := BW_ROOT + "menu_transparent.png"
const BW_COUNTERS := BW_ROOT + "counters_transparent.png"
const BW_CHARGE_BARS := BW_ROOT + "charge_bars_transparent.png"
const BW_INVENTORY := BW_ROOT + "inventory_transparent.png"
const BW_BUTTON_IDLE_REGION := Rect2(226.0, 13.0, 74.0, 17.0)
const BW_BUTTON_HOVER_REGION := Rect2(226.0, 39.0, 74.0, 17.0)
const BW_SEGMENTED_METER_REGION := Rect2(176.0, 55.0, 48.0, 9.0)
const BW_COMPACT_METER_REGION := Rect2(416.0, 24.0, 32.0, 8.0)
const BW_ICON_HEART_REGION := Rect2(146.0, 18.0, 12.0, 12.0)
const BW_ICON_SHIELD_REGION := Rect2(146.0, 67.0, 12.0, 14.0)
const BW_ICON_DROPLET_REGION := Rect2(18.0, 145.0, 14.0, 15.0)
const BW_ICON_SKULL_REGION := Rect2(17.0, 193.0, 14.0, 15.0)
const BW_ICON_LIGHTNING_REGION := Rect2(68.0, 193.0, 52.0, 15.0)

static func texture(path: String) -> Texture2D:
	if not USE_HUD_TEXTURES:
		return null
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func official_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func official_region(path: String, region: Rect2) -> Texture2D:
	var source := official_texture(path)
	if source == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	return atlas

static func condition_icon(condition: String) -> Texture2D:
	match condition:
		"danger":
			return official_region(BW_COUNTERS, BW_ICON_SKULL_REGION)
		"healing":
			return official_region(BW_COUNTERS, BW_ICON_LIGHTNING_REGION)
		"infected":
			return official_region(BW_COUNTERS, BW_ICON_SKULL_REGION)
		"precaution_o":
			return official_region(BW_COUNTERS, BW_ICON_DROPLET_REGION)
		"precaution_y":
			return official_region(BW_COUNTERS, BW_ICON_SHIELD_REGION)
	return official_region(BW_COUNTERS, BW_ICON_HEART_REGION)

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
	var background := COLOR_PANEL
	var border := COLOR_BORDER
	match kind:
		"warning":
			background = COLOR_PANEL_WARM
			border = COLOR_CAUTION
		"critical":
			background = Color("#211512")
			border = COLOR_CRITICAL
		"anomaly":
			background = Color("#1f1714")
			border = COLOR_ANOMALY
	return _pixel_panel_style(background, border, 1, 8.0, 0.94)

static func button_style(state: String = "normal") -> StyleBox:
	var background := Color("#171912")
	var border := COLOR_BORDER_DARK
	match state:
		"hover":
			background = Color("#242317")
			border = COLOR_CAUTION
		"pressed":
			background = Color("#2a2114")
			border = COLOR_CAUTION
		"disabled":
			background = Color("#0d0f0c")
			border = Color("#2d2d27")
	return _pixel_panel_style(background, border, 1, 7.0, 0.96)

static func bar_background_style() -> StyleBox:
	return _pixel_panel_style(Color("#080908"), Color("#2f3029"), 1, 1.0, 0.96)

static func bar_fill_style(kind: String = "health") -> StyleBox:
	var fill := COLOR_NORMAL
	match kind:
		"blood", "critical":
			fill = COLOR_CRITICAL
		"warning", "ap":
			fill = COLOR_CAUTION
		"stance":
			fill = Color("#c9c1a2")
		"anomaly":
			fill = COLOR_ANOMALY
	return _pixel_panel_style(fill, fill.darkened(0.32), 0, 0.0, 1.0)

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
	button.add_theme_constant_override("outline_size", 0)
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

static func texture_panel_sprite(sprite: Sprite2D, _kind: String, _size: Vector2) -> void:
	if sprite == null:
		return
	sprite.texture = null
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = false

static func button_texture(state: String) -> Texture2D:
	var region := BW_BUTTON_IDLE_REGION
	if state == "hover" or state == "pressed":
		region = BW_BUTTON_HOVER_REGION
	return official_region(BW_MENU, region)

static func meter_frame_texture(kind: String = "segmented") -> Texture2D:
	var region := BW_SEGMENTED_METER_REGION
	if kind == "compact":
		region = BW_COMPACT_METER_REGION
	return official_region(BW_CHARGE_BARS, region)

static func pocket_slot_style(active: bool = false) -> StyleBox:
	var background := Color("#171a14") if active else COLOR_SLOT
	var border := COLOR_CAUTION if active else COLOR_BORDER_DARK
	return _pixel_panel_style(background, border, 1, 3.0, 0.96)

static func macro_slot_style(filled: bool = false) -> StyleBox:
	var background := COLOR_PANEL_WARM if filled else COLOR_SLOT
	var border := COLOR_CAUTION if filled else COLOR_BORDER_DARK
	return _pixel_panel_style(background, border, 1, 5.0, 0.96)

static func macro_button_minimum_size(width: float = 0.0) -> Vector2:
	return Vector2(width, MACRO_BUTTON_MIN_HEIGHT)

static func pocket_grid_texture() -> Texture2D:
	return null

static func pocket_panel_texture() -> Texture2D:
	return null

static func pixel_panel_color(kind: String = "neutral") -> Color:
	match kind:
		"warning":
			return COLOR_PANEL_WARM
		"critical":
			return Color("#211512")
		"anomaly":
			return Color("#1f1714")
	return COLOR_PANEL

static func pixel_border_color(kind: String = "neutral") -> Color:
	match kind:
		"warning":
			return COLOR_CAUTION
		"critical":
			return COLOR_CRITICAL
		"anomaly":
			return COLOR_ANOMALY
	return COLOR_BORDER

static func _pixel_panel_style(
	background: Color,
	border: Color,
	border_width: int,
	content_margin: float,
	alpha: float = 0.94
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background, alpha)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(1)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style
