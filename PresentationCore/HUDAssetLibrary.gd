extends RefCounted

## Semantic HUD palette. Active colors are mutable so settings / event overrides
## can swap schemes without rewriting every consumer.

const SCHEME_AMBER := "amber"
const SCHEME_CYAN := "cyan"
const DEFAULT_SCHEME := SCHEME_AMBER

const SCHEME_DEFS := {
	SCHEME_AMBER: {
		"label": "Amber Terminal",
		"text": "#e8dcc0",
		"muted": "#8e8b78",
		"info": "#d69a43",
		"travel": "#7a8fa8",
		"discovery": "#79b86a",
		"success": "#8bcf78",
		"caution": "#e0b24a",
		"critical": "#b9493e",
		"anomaly": "#b35bb8",
		"panel": "#0b0d0b",
		"panel_alt": "#151711",
		"panel_warm": "#201b13",
		"border": "#6f6752",
		"border_dark": "#37372f",
		"slot": "#11140f",
		"neutral_fill": Color(0.04, 0.035, 0.025, 1.0),
		"neutral_inset": Color(0.07, 0.06, 0.045, 1.0),
		"neutral_inset_border": "#5a4a32",
		"button_fill": Color(0.07, 0.06, 0.04, 1.0),
	},
	SCHEME_CYAN: {
		"label": "Cyan Link",
		"text": "#e4dfcf",
		"muted": "#7c8882",
		"info": "#39c8c6",
		"travel": "#4e91c7",
		"discovery": "#79b86a",
		"success": "#8bcf78",
		"caution": "#d3a13d",
		"critical": "#d55749",
		"anomaly": "#b35bb8",
		"panel": "#0b0d0b",
		"panel_alt": "#151711",
		"panel_warm": "#201b13",
		"border": "#6f634d",
		"border_dark": "#37372f",
		"slot": "#11140f",
		"neutral_fill": Color(0.016, 0.04, 0.047, 1.0),
		"neutral_inset": Color(0.035, 0.06, 0.065, 1.0),
		"neutral_inset_border": "#2a5a5c",
		"button_fill": Color(0.04, 0.08, 0.09, 1.0),
	},
}

static var COLOR_TEXT := Color("#e8dcc0")
static var COLOR_MUTED := Color("#8e8b78")
static var COLOR_INFO := Color("#d69a43")
static var COLOR_TRAVEL := Color("#7a8fa8")
static var COLOR_DISCOVERY := Color("#79b86a")
static var COLOR_SUCCESS := Color("#8bcf78")
static var COLOR_CAUTION := Color("#e0b24a")
static var COLOR_CRITICAL := Color("#b9493e")
static var COLOR_ANOMALY := Color("#b35bb8")
static var COLOR_NORMAL := COLOR_INFO
static var COLOR_PANEL := Color("#0b0d0b")
static var COLOR_PANEL_ALT := Color("#151711")
static var COLOR_PANEL_WARM := Color("#201b13")
static var COLOR_BORDER := Color("#6f6752")
static var COLOR_BORDER_DARK := Color("#37372f")
static var COLOR_SLOT := Color("#11140f")

static var _base_scheme_id := DEFAULT_SCHEME
static var _override_scheme_id := ""
static var _scheme_listeners: Array[Callable] = []
static var _neutral_fill := Color(0.04, 0.035, 0.025, 1.0)
static var _neutral_inset := Color(0.07, 0.06, 0.045, 1.0)
static var _neutral_inset_border := Color("#5a4a32")
static var _button_fill := Color(0.07, 0.06, 0.04, 1.0)

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
const BAR_FRAME_THIN := ROOT + "bars/bar_frame_thin_96x8.png"
const USE_HUD_TEXTURES := true
const PANEL_SLICE := 8
const BUTTON_SLICE_H := 6
const BUTTON_SLICE_V := 4


static func scheme_ids() -> PackedStringArray:
	return PackedStringArray([SCHEME_AMBER, SCHEME_CYAN])


static func scheme_label(scheme_id: String) -> String:
	var def: Dictionary = SCHEME_DEFS.get(_sanitize_scheme_id(scheme_id), {})
	return str(def.get("label", scheme_id.to_upper()))


static func get_base_scheme_id() -> String:
	return _base_scheme_id


static func get_active_scheme_id() -> String:
	if not _override_scheme_id.is_empty():
		return _override_scheme_id
	return _base_scheme_id


static func connect_scheme_changed(callback: Callable) -> void:
	if callback.is_valid() and not _scheme_listeners.has(callback):
		_scheme_listeners.append(callback)


static func disconnect_scheme_changed(callback: Callable) -> void:
	_scheme_listeners.erase(callback)


static func sanitize_scheme_id(scheme_id: String) -> String:
	var key := scheme_id.to_lower().strip_edges()
	if SCHEME_DEFS.has(key):
		return key
	return DEFAULT_SCHEME


static func apply_scheme(scheme_id: String, notify: bool = true) -> void:
	_base_scheme_id = sanitize_scheme_id(scheme_id)
	_apply_active_scheme(notify)


static func push_scheme_override(scheme_id: String) -> void:
	## Temporary gameplay / event HUD look. Pop to restore the settings scheme.
	_override_scheme_id = sanitize_scheme_id(scheme_id)
	_apply_active_scheme(true)


static func pop_scheme_override() -> void:
	if _override_scheme_id.is_empty():
		return
	_override_scheme_id = ""
	_apply_active_scheme(true)


static func clear_scheme_override() -> void:
	pop_scheme_override()


static func _sanitize_scheme_id(scheme_id: String) -> String:
	return sanitize_scheme_id(scheme_id)


static func _apply_active_scheme(notify: bool) -> void:
	var def: Dictionary = SCHEME_DEFS[get_active_scheme_id()]
	COLOR_TEXT = Color(str(def["text"]))
	COLOR_MUTED = Color(str(def["muted"]))
	COLOR_INFO = Color(str(def["info"]))
	COLOR_TRAVEL = Color(str(def["travel"]))
	COLOR_DISCOVERY = Color(str(def["discovery"]))
	COLOR_SUCCESS = Color(str(def["success"]))
	COLOR_CAUTION = Color(str(def["caution"]))
	COLOR_CRITICAL = Color(str(def["critical"]))
	COLOR_ANOMALY = Color(str(def["anomaly"]))
	COLOR_NORMAL = COLOR_INFO
	COLOR_PANEL = Color(str(def["panel"]))
	COLOR_PANEL_ALT = Color(str(def["panel_alt"]))
	COLOR_PANEL_WARM = Color(str(def["panel_warm"]))
	COLOR_BORDER = Color(str(def["border"]))
	COLOR_BORDER_DARK = Color(str(def["border_dark"]))
	COLOR_SLOT = Color(str(def["slot"]))
	_neutral_fill = def["neutral_fill"]
	_neutral_inset = def["neutral_inset"]
	_neutral_inset_border = Color(str(def["neutral_inset_border"]))
	_button_fill = def["button_fill"]
	if notify:
		_notify_scheme_changed()


static func _notify_scheme_changed() -> void:
	var active := get_active_scheme_id()
	var remaining: Array[Callable] = []
	for callback in _scheme_listeners:
		if callback.is_valid():
			callback.call(active)
			remaining.append(callback)
	_scheme_listeners = remaining


static func _static_init() -> void:
	_apply_active_scheme(false)

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
			return official_texture(ROOT + "medical/state_critical_32.png")
		"healing":
			return status_icon("ap")
		"infected":
			return status_icon("infection")
		"precaution_o":
			return status_icon("blood")
		"precaution_y":
			return status_icon("warning")
		"fine", "stable":
			return official_texture(ROOT + "medical/state_stable_32.png")
		"damaged":
			return official_texture(ROOT + "medical/state_damaged_32.png")
	return official_texture(ROOT + "medical/state_stable_32.png")

static func status_icon(name: String) -> Texture2D:
	return official_texture(ROOT + "icons/status/%s_32.png" % name)

static func action_icon(name: String) -> Texture2D:
	return official_texture(ROOT + "icons/actions/%s_32.png" % name)

static func combat_icon(name: String) -> Texture2D:
	return official_texture(ROOT + "icons/combat/%s_32.png" % name)

static func menu_icon(name: String) -> Texture2D:
	if name in ["inventory", "settings", "save", "load", "map", "rest"]:
		return action_icon(name)
	if name in ["pass", "close"]:
		return combat_icon("pass")
	if name in ["warning", "caution"]:
		return status_icon("warning")
	return status_icon(name)

static func clock_digit_texture(digit: int) -> Texture2D:
	return official_texture(ROOT + "anim/clock/digit_%d.png" % clampi(digit, 0, 9))

static func clock_colon_texture() -> Texture2D:
	return official_texture(ROOT + "anim/clock/colon.png")

static func signal_texture(level: int, kind: String = "normal") -> Texture2D:
	var clamped := clampi(level, 0, 4)
	var prefix := "signal"
	match kind:
		"warning", "caution":
			prefix = "signal_warn"
		"critical", "danger":
			prefix = "signal_danger"
		"anomaly":
			prefix = "signal_anomaly"
	return official_texture(ROOT + "anim/signal/%s_%d.png" % [prefix, clamped])

static func vignette_texture(kind: String = "critical") -> Texture2D:
	match kind:
		"warning", "caution":
			return official_texture(ROOT + "overlays/warning_vignette_128x72.png")
		"anomaly":
			return official_texture(ROOT + "overlays/anomaly_vignette_128x72.png")
	return official_texture(ROOT + "overlays/critical_vignette_128x72.png")

static func anim_icon_frames(name: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var index := 0
	while true:
		var path := ROOT + "anim/icons/%s_%d.png" % [name, index]
		if not ResourceLoader.exists(path):
			break
		var tex := official_texture(path)
		if tex == null:
			break
		frames.append(tex)
		index += 1
	return frames

static func panel_texture_path(kind: String = "neutral") -> String:
	match kind:
		"warning", "caution":
			return PANEL_WARNING
		"critical", "danger":
			return PANEL_CRITICAL
		"anomaly":
			return PANEL_ANOMALY
	return PANEL_NEUTRAL

static func bar_fill_path(kind: String = "health") -> String:
	match kind:
		"blood", "critical":
			return ROOT + "bars/bar_fill_blood_96x8.png"
		"warning", "ap":
			return ROOT + "bars/bar_fill_ap_96x8.png"
		"stance":
			return ROOT + "bars/bar_fill_stance_96x8.png"
		"anomaly":
			return ROOT + "bars/bar_fill_anomaly_96x8.png"
		"travel":
			return ROOT + "bars/bar_fill_health_96x8.png"
		"discovery", "success":
			return ROOT + "bars/bar_fill_health_96x8.png"
	return ROOT + "bars/bar_fill_health_96x8.png"

static func _texture_style(
	path: String,
	margin_h: int,
	margin_v: int,
	content_margin: float,
	modulate: Color = Color.WHITE,
	draw_center: bool = true
) -> StyleBox:
	var tex := texture(path)
	if tex == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = float(margin_h)
	style.texture_margin_top = float(margin_v)
	style.texture_margin_right = float(margin_h)
	style.texture_margin_bottom = float(margin_v)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	style.modulate_color = modulate
	style.draw_center = draw_center
	return style

static func panel_style(kind: String = "neutral") -> StyleBox:
	# Solid cyber plate via StyleBoxFlat.
	# Do NOT nine-slice the 64px grid texture across large shells — it paints
	# a giant grid through inventory/HUD and reads as world bleed.
	var fill := _neutral_fill
	var border := COLOR_INFO
	var alpha := 0.96
	match kind:
		"warning", "caution":
			fill = Color(0.08, 0.06, 0.03, 1.0)
			border = COLOR_CAUTION
			alpha = 0.97
		"critical", "danger":
			fill = Color(0.09, 0.03, 0.035, 1.0)
			border = COLOR_CRITICAL
			alpha = 0.97
		"anomaly":
			fill = Color(0.07, 0.03, 0.08, 1.0)
			border = COLOR_ANOMALY
			alpha = 0.97
		"travel":
			fill = Color(0.02, 0.04, 0.08, 1.0)
			border = COLOR_TRAVEL
			alpha = 0.96
		"discovery", "success":
			fill = Color(0.03, 0.07, 0.04, 1.0)
			border = COLOR_DISCOVERY
			alpha = 0.96
	var style := _pixel_panel_style(fill, border, 2, 8.0, alpha)
	style.set_corner_radius_all(0)
	return style

static func inset_panel_style(kind: String = "neutral") -> StyleBox:
	# Nested tile: still solid, slightly lifted so hierarchy reads without going transparent.
	var fill := _neutral_inset
	var border := _neutral_inset_border
	var alpha := 0.92
	match kind:
		"warning", "caution":
			fill = Color(0.10, 0.08, 0.04, 1.0)
			border = COLOR_CAUTION.darkened(0.20)
			alpha = 0.93
		"critical", "danger":
			fill = Color(0.11, 0.04, 0.045, 1.0)
			border = COLOR_CRITICAL.darkened(0.15)
			alpha = 0.93
		"anomaly":
			fill = Color(0.09, 0.04, 0.10, 1.0)
			border = COLOR_ANOMALY.darkened(0.18)
			alpha = 0.93
		"travel":
			fill = Color(0.03, 0.05, 0.10, 1.0)
			border = COLOR_TRAVEL.darkened(0.25)
			alpha = 0.92
		"discovery", "success":
			fill = Color(0.04, 0.08, 0.05, 1.0)
			border = COLOR_DISCOVERY.darkened(0.25)
			alpha = 0.92
	return _pixel_panel_style(fill, border, 1, 5.0, alpha)

static func button_style(state: String = "normal") -> StyleBox:
	var background := _button_fill
	var border := COLOR_INFO
	var alpha := 0.96
	match state:
		"hover":
			background = Color(0.12, 0.10, 0.06, 1.0)
			border = COLOR_CAUTION
			alpha = 0.98
		"pressed":
			background = Color(0.16, 0.12, 0.06, 1.0)
			border = COLOR_CAUTION
			alpha = 1.0
		"disabled":
			background = Color(0.05, 0.06, 0.05, 1.0)
			border = Color("#2d2d27")
			alpha = 0.90
	# Cyan-baked button textures stay for the cyan scheme only.
	if get_active_scheme_id() == SCHEME_CYAN:
		var textured := _texture_style(
			BUTTON_HOVER if state == "hover" else (BUTTON_ACTIVE if state == "pressed" else (BUTTON_DISABLED if state == "disabled" else BUTTON_IDLE)),
			BUTTON_SLICE_H,
			BUTTON_SLICE_V,
			7.0
		)
		if textured != null:
			return textured
	return _pixel_panel_style(background, border, 1, 7.0, alpha)

static func bar_background_style() -> StyleBox:
	var textured := _texture_style(BAR_FRAME, 3, 2, 1.0)
	if textured != null:
		return textured
	return _pixel_panel_style(Color("#080908"), Color("#2f3029"), 1, 1.0, 0.96)

static func bar_fill_style(kind: String = "health") -> StyleBox:
	var textured := _texture_style(bar_fill_path(kind), 0, 0, 0.0)
	if textured != null:
		return textured
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
		"travel":
			fill = COLOR_TRAVEL
		"discovery", "success":
			fill = COLOR_DISCOVERY
	return _pixel_panel_style(fill, fill.darkened(0.32), 0, 0.0, 1.0)

static func apply_panel(panel: PanelContainer, kind: String = "neutral") -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", panel_style(kind))
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func apply_inset_panel(panel: PanelContainer, kind: String = "neutral") -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", inset_panel_style(kind))
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func apply_button(button: Button, icon_name: String = "") -> void:
	if button == null:
		return
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.add_theme_stylebox_override("background", bar_background_style())
	bar.add_theme_stylebox_override("fill", bar_fill_style(fill_kind))

static func color_for_role(role: String) -> Color:
	match role:
		"title", "info", "world", "normal":
			return COLOR_INFO
		"warning", "caution":
			return COLOR_CAUTION
		"critical", "danger":
			return COLOR_CRITICAL
		"travel":
			return COLOR_TRAVEL
		"discovery", "success":
			return COLOR_DISCOVERY if role == "discovery" else COLOR_SUCCESS
		"anomaly":
			return COLOR_ANOMALY
		"muted", "system":
			return COLOR_MUTED
	return COLOR_TEXT


static func color_hex(role: String) -> String:
	var color := color_for_role(role)
	return "%02x%02x%02x" % [
		clampi(int(round(color.r * 255.0)), 0, 255),
		clampi(int(round(color.g * 255.0)), 0, 255),
		clampi(int(round(color.b * 255.0)), 0, 255),
	]


static func bbcode(role: String, text: String) -> String:
	return "[color=#%s]%s[/color]" % [color_hex(role), text]


static func font_size_for_role(role: String) -> int:
	match role:
		"title":
			return 22
		"muted", "system", "warning", "caution", "critical", "danger", "travel", "discovery", "success", "anomaly", "info", "world":
			return 11
	return 12


static func apply_label(label: Label, role: String = "body") -> void:
	if label == null:
		return
	var color := COLOR_TEXT if role == "body" else color_for_role(role)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size_for_role(role))
	label.add_theme_constant_override("outline_size", 2 if role == "title" else 1)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.05, 0.85))


static func apply_rich_label(rtl: RichTextLabel, default_role: String = "body") -> void:
	if rtl == null:
		return
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var color := COLOR_TEXT if default_role == "body" else color_for_role(default_role)
	rtl.add_theme_color_override("default_color", color)
	rtl.add_theme_font_size_override("normal_font_size", font_size_for_role(default_role))
	rtl.add_theme_constant_override("outline_size", 2 if default_role == "title" else 1)
	rtl.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.05, 0.85))

static func texture_panel_sprite(sprite: Sprite2D, kind: String, size: Vector2) -> void:
	if sprite == null:
		return
	var tex := official_texture(panel_texture_path(kind))
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = tex != null
	if tex == null:
		return
	var texture_size := Vector2(float(tex.get_width()), float(tex.get_height()))
	sprite.scale = Vector2(
		size.x / maxf(1.0, texture_size.x),
		size.y / maxf(1.0, texture_size.y)
	)

static func button_texture(state: String) -> Texture2D:
	match state:
		"hover", "pressed":
			return official_texture(BUTTON_HOVER if state == "hover" else BUTTON_ACTIVE)
		"disabled":
			return official_texture(BUTTON_DISABLED)
	return official_texture(BUTTON_IDLE)

static func meter_frame_texture(kind: String = "segmented") -> Texture2D:
	if kind == "compact":
		return official_texture(BAR_FRAME_THIN)
	return official_texture(BAR_FRAME)

static func pocket_slot_style(active: bool = false) -> StyleBox:
	if active:
		return inset_panel_style("warning")
	return inset_panel_style("neutral")

static func macro_slot_style(filled: bool = false) -> StyleBox:
	var style := inset_panel_style("neutral") as StyleBoxFlat
	if style == null:
		return inset_panel_style("neutral")
	style.bg_color = Color(0.04, 0.07, 0.08, 0.94 if filled else 0.90)
	return style


static func macro_button_minimum_size(width: float = 0.0) -> Vector2:
	return Vector2(width, MACRO_BUTTON_MIN_HEIGHT)

static func pocket_grid_texture() -> Texture2D:
	return official_texture(PANEL_NEUTRAL)

static func pocket_panel_texture() -> Texture2D:
	return official_texture(PANEL_NEUTRAL)

static func pixel_panel_color(kind: String = "neutral") -> Color:
	match kind:
		"warning", "critical", "anomaly":
			return Color(0.04, 0.05, 0.04, 1.0)
	return Color(0.016, 0.04, 0.047, 1.0)

static func pixel_border_color(kind: String = "neutral") -> Color:
	match kind:
		"warning":
			return Color("#5a5648")
		"critical":
			return Color("#4a4a44")
		"anomaly":
			return Color("#45423c")
	return COLOR_BORDER_DARK


static func semantic_color(kind: String = "world") -> Color:
	match kind.to_lower():
		"travel":
			return COLOR_TRAVEL
		"discovery":
			return COLOR_DISCOVERY
		"success":
			return COLOR_SUCCESS
		"warning", "caution":
			return COLOR_CAUTION
		"critical", "danger":
			return COLOR_CRITICAL
		"anomaly":
			return COLOR_ANOMALY
		"system":
			return COLOR_MUTED
	return COLOR_INFO


static func log_row_style(kind: String, latest: bool = false) -> StyleBoxFlat:
	var accent := semantic_color(kind)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.07, 0.88 if latest else 0.82)
	style.border_color = accent.darkened(0.25 if latest else 0.45)
	style.border_width_left = 3
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

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
