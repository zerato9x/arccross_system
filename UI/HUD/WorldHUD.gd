extends CanvasLayer
class_name WorldHUD

signal inventory_requested
signal save_requested
signal load_requested

const MAX_SCALE := 12.0

var _snapshot: Dictionary = {}
var _vital_rows: Dictionary = {}

@onready var _root: Control = %Root
@onready var _status_panel: PanelContainer = %StatusPanel
@onready var _command_panel: PanelContainer = %CommandPanel
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _location_icon: TextureRect = %LocationIcon
@onready var _time_icon: TextureRect = %TimeIcon
@onready var _location_label: Label = %LocationLabel
@onready var _time_label: Label = %TimeLabel
@onready var _warning_label: Label = %WarningLabel
@onready var _inventory_button: Button = %InventoryButton
@onready var _menu_button: Button = %MenuButton
@onready var _settings_button: Button = %SettingsButton
@onready var _menu_inventory_button: Button = %MenuInventoryButton
@onready var _menu_save_button: Button = %MenuSaveButton
@onready var _menu_load_button: Button = %MenuLoadButton
@onready var _menu_settings_button: Button = %MenuSettingsButton
@onready var _menu_close_button: Button = %MenuCloseButton
@onready var _settings_close_button: Button = %SettingsCloseButton
@onready var _screen_noise_toggle: CheckButton = %ScreenNoiseToggle
@onready var _hud_scale_slider: HSlider = %HudScaleSlider
@onready var _hud_scale_label: Label = %HudScaleLabel
@onready var _screen_overlay: TextureRect = %ScreenOverlay

func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind_vital_rows()
	_apply_assets()
	_connect_buttons()
	_menu_panel.visible = false
	_settings_panel.visible = false
	_screen_overlay.visible = false
	_update_scale_label()

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_render()

func set_inventory_open(open: bool) -> void:
	visible = not open
	if not visible:
		_menu_panel.visible = false
		_settings_panel.visible = false

func _bind_vital_rows() -> void:
	for key in [
		"blood",
		"stance",
		"hunger",
		"thirst",
		"fatigue",
		"temperature",
	]:
		var prefix: String = str(key).capitalize()
		_vital_rows[key] = {
			"icon": get_node("%" + prefix + "Icon") as TextureRect,
			"label": get_node("%" + prefix + "Label") as Label,
			"bar": get_node("%" + prefix + "Bar") as ProgressBar,
		}

func _apply_assets() -> void:
	HUDAssetLibrary.apply_panel(_status_panel, "neutral")
	HUDAssetLibrary.apply_panel(_command_panel, "neutral")
	HUDAssetLibrary.apply_panel(_menu_panel, "warning")
	HUDAssetLibrary.apply_panel(_settings_panel, "anomaly")
	_location_icon.texture = HUDAssetLibrary.status_icon("location")
	_time_icon.texture = HUDAssetLibrary.status_icon("time")
	_screen_overlay.texture = HUDAssetLibrary.texture(
		"res://Asset/UI/HUD/overlays/scanline_tile_16.png"
	)
	_screen_overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_apply_vital_icon("blood", "blood", "blood")
	_apply_vital_icon("stance", "stance", "stance")
	_apply_vital_icon("hunger", "hunger", "warning")
	_apply_vital_icon("thirst", "thirst", "health")
	_apply_vital_icon("fatigue", "fatigue", "stance")
	_apply_vital_icon("temperature", "temperature", "anomaly")
	HUDAssetLibrary.apply_button(_inventory_button, "inventory")
	HUDAssetLibrary.apply_button(_menu_button, "map")
	HUDAssetLibrary.apply_button(_settings_button, "settings")
	HUDAssetLibrary.apply_button(_menu_inventory_button, "inventory")
	HUDAssetLibrary.apply_button(_menu_save_button, "save")
	HUDAssetLibrary.apply_button(_menu_load_button, "load")
	HUDAssetLibrary.apply_button(_menu_settings_button, "settings")
	HUDAssetLibrary.apply_button(_menu_close_button)
	HUDAssetLibrary.apply_button(_settings_close_button)
	HUDAssetLibrary.apply_button(_screen_noise_toggle)
	HUDAssetLibrary.apply_label(_location_label, "body")
	HUDAssetLibrary.apply_label(_time_label, "body")
	HUDAssetLibrary.apply_label(_warning_label, "warning")
	HUDAssetLibrary.apply_label(_hud_scale_label, "muted")

func _apply_vital_icon(
	key: String,
	icon_name: String,
	fill_kind: String
) -> void:
	var row: Dictionary = _vital_rows[key]
	var icon_rect := row["icon"] as TextureRect
	var label := row["label"] as Label
	var bar := row["bar"] as ProgressBar
	icon_rect.texture = HUDAssetLibrary.status_icon(icon_name)
	HUDAssetLibrary.apply_label(label, "body")
	HUDAssetLibrary.apply_progress_bar(bar, fill_kind)
	bar.max_value = MAX_SCALE

func _connect_buttons() -> void:
	_inventory_button.pressed.connect(inventory_requested.emit)
	_menu_button.pressed.connect(_toggle_menu)
	_settings_button.pressed.connect(_toggle_settings)
	_menu_inventory_button.pressed.connect(inventory_requested.emit)
	_menu_save_button.pressed.connect(save_requested.emit)
	_menu_load_button.pressed.connect(load_requested.emit)
	_menu_settings_button.pressed.connect(_open_settings)
	_menu_close_button.pressed.connect(_close_menu)
	_settings_close_button.pressed.connect(_close_settings)
	_screen_noise_toggle.toggled.connect(_set_screen_noise)
	_hud_scale_slider.value_changed.connect(_set_hud_scale)

func _render() -> void:
	if _snapshot.is_empty():
		_location_label.text = "HEX --, --"
		_time_label.text = "DAY -- // --:--"
		_warning_label.text = "NO BODY SIGNAL"
		return
	var coords: Vector2i = _snapshot.get("coords", Vector2i.ZERO)
	var clock: Dictionary = _snapshot.get("world_time", {})
	_location_label.text = "HEX %d, %d" % [coords.x, coords.y]
	_time_label.text = "DAY %02d // %02d:%02d" % [
		int(clock.get("day", 1)),
		int(clock.get("hour", 0)),
		int(clock.get("minute", 0)),
	]
	_update_vital("blood", float(_snapshot.get("blood", 0.0)), "BLOOD")
	_update_vital("stance", float(_snapshot.get("stance", 0.0)), "STANCE")
	_update_vital("hunger", float(_snapshot.get("hunger", 0.0)), "HUNGER")
	_update_vital("thirst", float(_snapshot.get("thirst", 0.0)), "THIRST")
	_update_vital("fatigue", float(_snapshot.get("fatigue", 0.0)), "FATIGUE", true)
	var temperature := float(_snapshot.get("core_temperature", 37.0))
	_update_vital(
		"temperature",
		clampf((temperature - 30.0) / 12.0 * MAX_SCALE, 0.0, MAX_SCALE),
		"TEMP %.1fC" % temperature
	)
	_warning_label.text = _warning_text()

func _update_vital(
	key: String,
	value: float,
	label_text: String,
	inverted: bool = false
) -> void:
	var row: Dictionary = _vital_rows[key]
	var label := row["label"] as Label
	var bar := row["bar"] as ProgressBar
	bar.value = clampf(value, 0.0, MAX_SCALE)
	var display_value := MAX_SCALE - bar.value if inverted else bar.value
	label.text = "%s  %04.1f/12" % [label_text, display_value]

func _warning_text() -> String:
	var warnings := PackedStringArray()
	if float(_snapshot.get("blood", 0.0)) <= 4.0:
		warnings.append("LOW BLOOD")
	if float(_snapshot.get("hunger", 0.0)) <= 3.0:
		warnings.append("STARVING")
	if float(_snapshot.get("thirst", 0.0)) <= 3.0:
		warnings.append("DEHYDRATED")
	if float(_snapshot.get("fatigue", 0.0)) >= 9.0:
		warnings.append("EXHAUSTED")
	if float(_snapshot.get("stance", 0.0)) <= 3.0:
		warnings.append("STANCE BREAK")
	if warnings.is_empty():
		return "BODY SIGNAL STABLE"
	return " / ".join(warnings)

func _toggle_menu() -> void:
	_menu_panel.visible = not _menu_panel.visible
	if _menu_panel.visible:
		_settings_panel.visible = false

func _close_menu() -> void:
	_menu_panel.visible = false

func _toggle_settings() -> void:
	if _settings_panel.visible:
		_close_settings()
	else:
		_open_settings()

func _open_settings() -> void:
	_settings_panel.visible = true
	_menu_panel.visible = false

func _close_settings() -> void:
	_settings_panel.visible = false

func _set_screen_noise(enabled: bool) -> void:
	_screen_overlay.visible = enabled

func _set_hud_scale(value: float) -> void:
	_status_panel.scale = Vector2.ONE * value
	_command_panel.scale = Vector2.ONE * value
	_menu_panel.scale = Vector2.ONE * value
	_settings_panel.scale = Vector2.ONE * value
	_update_scale_label()

func _update_scale_label() -> void:
	if _hud_scale_label == null or _hud_scale_slider == null:
		return
	_hud_scale_label.text = "HUD SCALE %.0f%%" % (_hud_scale_slider.value * 100.0)
