extends CanvasLayer
class_name WorldHUD

signal inventory_requested
signal save_requested
signal load_requested

const MAX_SCALE := 12.0

## Pixel‑scale multiplier – the source sprites are tiny pixel art so we blow
## them up to a comfortable on‑screen size.  Adjust this single value and the
## entire HUD scales uniformly.
const PIX := 3.0

## Which side‑tab indices map to which page.
## The sprite pack provides Side Tabs 0‑8; we use pairs (normal, active).
## Tab indices: 0/1 = Profile, 2/3 = Inventory, 4/5 = Map, 6/7 = Save, 8 = Options
enum Page { PROFILE, INVENTORY, MAP, SAVE, OPTIONS }
const TAB_SPRITE_NORMAL := [0, 2, 4, 6, 8]
const TAB_SPRITE_ACTIVE := [1, 3, 5, 7, 8]  # 8 has no active variant

var _snapshot: Dictionary = {}
var _vital_rows: Dictionary = {}
var _current_page: int = Page.PROFILE
var _page_containers: Dictionary = {}  # Page enum -> Control

# ── Core nodes ──
var _root: Control
var _device_frame: TextureRect
var _content_area: Control
var _flicker_sprite: TextureRect
var _flicker_frames: Array[Texture2D] = []
var _flicker_index: int = 0
var _flicker_timer: Timer
var _page_flip_rect: TextureRect

# ── Side tab buttons ──
var _tab_buttons: Array[TextureButton] = []

# ── Profile page nodes ──
var _location_label: Label
var _time_label: Label
var _warning_label: Label
var _clock_frame: TextureRect
var _compass_frame: TextureRect

# ── Settings sub‑nodes ──
var _screen_noise_toggle: CheckButton
var _hud_scale_slider: HSlider
var _hud_scale_label: Label
var _screen_overlay: TextureRect

# ── Medical monitor ──
var _medical_monitor: MedicalMonitor

func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_flicker_frames = HUDAssetLibrary.light_flicker_frames()
	_build_interface()
	_switch_page(Page.PROFILE)

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_render()
	if _medical_monitor:
		_medical_monitor.show_snapshot(_snapshot)

func set_inventory_open(open: bool) -> void:
	visible = not open
	if not visible:
		if _medical_monitor:
			_medical_monitor.close_monitor()

# ──────────────────────────────────────────────
# BUILD
# ──────────────────────────────────────────────

func _build_interface() -> void:
	# Root control – full rect, ignores mouse so clicks pass through to game
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Screen overlay (scanline texture, initially hidden)
	_screen_overlay = TextureRect.new()
	_screen_overlay.name = "ScreenOverlay"
	_screen_overlay.visible = false
	_screen_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_overlay.stretch_mode = TextureRect.STRETCH_TILE
	_screen_overlay.texture = HUDAssetLibrary.background_texture()
	_screen_overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_root.add_child(_screen_overlay)

	# ── Device container (anchored bottom‑left) ──
	var device_container := Control.new()
	device_container.name = "DeviceContainer"
	# The Pixel Map/0.png is the full device frame.  At native resolution it's
	# roughly 192×160.  We scale by PIX.
	var frame_tex := HUDAssetLibrary.pixel_map_frame_texture()
	var frame_size := frame_tex.get_size() * PIX if frame_tex else Vector2(576.0, 480.0)
	device_container.custom_minimum_size = frame_size
	device_container.size = frame_size
	# Anchor to bottom‑left with some padding
	device_container.anchor_left = 0.0
	device_container.anchor_top = 1.0
	device_container.anchor_right = 0.0
	device_container.anchor_bottom = 1.0
	device_container.offset_left = 8.0
	device_container.offset_top = -frame_size.y - 8.0
	device_container.offset_right = 8.0 + frame_size.x
	device_container.offset_bottom = -8.0
	device_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(device_container)

	# Device frame texture
	_device_frame = TextureRect.new()
	_device_frame.name = "DeviceFrame"
	_device_frame.texture = frame_tex
	_device_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_device_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_device_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_device_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	device_container.add_child(_device_frame)

	# Light flicker overlay – same size, layered on top
	_flicker_sprite = TextureRect.new()
	_flicker_sprite.name = "LightFlicker"
	_flicker_sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flicker_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flicker_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_flicker_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flicker_sprite.modulate = Color(1.0, 1.0, 1.0, 0.12)
	device_container.add_child(_flicker_sprite)
	_start_flicker_animation()

	# ── Content area (the parchment/paper region inside the device) ──
	# Based on the design, the content area sits inside the device roughly at:
	# Left: ~35% of width, Top: ~10%, Right: ~92%, Bottom: ~88%
	_content_area = Control.new()
	_content_area.name = "ContentArea"
	_content_area.anchor_left = 0.33
	_content_area.anchor_top = 0.09
	_content_area.anchor_right = 0.90
	_content_area.anchor_bottom = 0.88
	_content_area.offset_left = 0.0
	_content_area.offset_top = 0.0
	_content_area.offset_right = 0.0
	_content_area.offset_bottom = 0.0
	_content_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_area.clip_contents = true
	device_container.add_child(_content_area)

	# Page flip overlay (for transitions)
	_page_flip_rect = TextureRect.new()
	_page_flip_rect.name = "PageFlip"
	_page_flip_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_flip_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_flip_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_page_flip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_flip_rect.visible = false
	_content_area.add_child(_page_flip_rect)

	# Build each page
	_page_containers[Page.PROFILE] = _build_profile_page()
	_page_containers[Page.INVENTORY] = _build_inventory_page()
	_page_containers[Page.MAP] = _build_map_page()
	_page_containers[Page.SAVE] = _build_save_page()
	_page_containers[Page.OPTIONS] = _build_options_page()

	for page_key: int in _page_containers:
		var page_ctrl: Control = _page_containers[page_key]
		page_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content_area.add_child(page_ctrl)

	# Side tabs strip (in the left gadget area of the device)
	_build_side_tabs(device_container)

	# Build clock / compass widgets in the left gadget area
	_build_gadget_widgets(device_container)

	# Bottom bar buttons (Menu / Default / Route)
	_build_bottom_bar(device_container)

	# Medical monitor (reuse the existing scene if available)
	var med_scene_path := "res://UI/HUD/MedicalMonitor.tscn"
	if ResourceLoader.exists(med_scene_path):
		var med_scene := load(med_scene_path) as PackedScene
		if med_scene:
			_medical_monitor = med_scene.instantiate() as MedicalMonitor
			_medical_monitor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_root.add_child(_medical_monitor)
			_medical_monitor.closed.connect(_on_medical_monitor_closed)

# ── SIDE TABS ──

func _build_side_tabs(parent: Control) -> void:
	var tab_strip := VBoxContainer.new()
	tab_strip.name = "SideTabStrip"
	# Position along the right edge of the device (where the tab notches are)
	tab_strip.anchor_left = 0.91
	tab_strip.anchor_top = 0.15
	tab_strip.anchor_right = 1.0
	tab_strip.anchor_bottom = 0.85
	tab_strip.offset_left = 0.0
	tab_strip.offset_top = 0.0
	tab_strip.offset_right = 0.0
	tab_strip.offset_bottom = 0.0
	tab_strip.add_theme_constant_override("separation", 2)
	tab_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(tab_strip)

	var page_names := ["PROFILE", "INV", "MAP", "SAVE", "OPT"]
	for i in range(5):
		var btn := TextureButton.new()
		btn.name = "Tab_%s" % page_names[i]
		btn.texture_normal = HUDAssetLibrary.side_tab_texture(TAB_SPRITE_NORMAL[i])
		btn.texture_pressed = HUDAssetLibrary.side_tab_texture(TAB_SPRITE_ACTIVE[i])
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(28.0 * PIX, 28.0 * PIX)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		tab_strip.add_child(btn)
		_tab_buttons.append(btn)

# ── GADGET WIDGETS (clock, compass, etc.) ──

func _build_gadget_widgets(parent: Control) -> void:
	# Clock widget – top of left gadget strip
	_clock_frame = TextureRect.new()
	_clock_frame.name = "ClockWidget"
	_clock_frame.texture = HUDAssetLibrary.clock_texture(0)
	_clock_frame.anchor_left = 0.04
	_clock_frame.anchor_top = 0.06
	_clock_frame.anchor_right = 0.30
	_clock_frame.anchor_bottom = 0.22
	_clock_frame.offset_left = 0.0
	_clock_frame.offset_top = 0.0
	_clock_frame.offset_right = 0.0
	_clock_frame.offset_bottom = 0.0
	_clock_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_clock_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_clock_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_clock_frame)

	# Time label overlaid on the clock
	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.text = "DAY -- // --:--"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_time_label.add_theme_font_size_override("font_size", 9)
	_time_label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_TEXT)
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_frame.add_child(_time_label)

	# Compass widget – below the clock
	_compass_frame = TextureRect.new()
	_compass_frame.name = "CompassWidget"
	_compass_frame.texture = HUDAssetLibrary.compass_texture(0)
	_compass_frame.anchor_left = 0.04
	_compass_frame.anchor_top = 0.62
	_compass_frame.anchor_right = 0.30
	_compass_frame.anchor_bottom = 0.88
	_compass_frame.offset_left = 0.0
	_compass_frame.offset_top = 0.0
	_compass_frame.offset_right = 0.0
	_compass_frame.offset_bottom = 0.0
	_compass_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_compass_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_compass_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_compass_frame)

	# Location label overlaid on the compass
	_location_label = Label.new()
	_location_label.name = "LocationLabel"
	_location_label.text = "HEX --, --"
	_location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_location_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_location_label.add_theme_font_size_override("font_size", 8)
	_location_label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_TEXT)
	_location_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_frame.add_child(_location_label)

# ── BOTTOM BAR ──

func _build_bottom_bar(parent: Control) -> void:
	var bar := HBoxContainer.new()
	bar.name = "BottomBar"
	bar.anchor_left = 0.33
	bar.anchor_top = 0.90
	bar.anchor_right = 0.90
	bar.anchor_bottom = 0.98
	bar.offset_left = 0.0
	bar.offset_top = 0.0
	bar.offset_right = 0.0
	bar.offset_bottom = 0.0
	bar.add_theme_constant_override("separation", 4)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(bar)

	# Bottom buttons: Menu, Default (center), Route
	var btn_names := ["Menu", "Default", "Route"]
	var btn_indices := [0, 1, 2]  # UI Buttons 0, 1, 2
	for i in range(3):
		var btn := TextureButton.new()
		btn.name = "Bottom_%s" % btn_names[i]
		btn.texture_normal = HUDAssetLibrary.ui_button_sprite(btn_indices[i])
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(40.0 * PIX, 12.0 * PIX)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		bar.add_child(btn)

# ──────────────────────────────────────────────
# PAGE BUILDERS
# ──────────────────────────────────────────────

func _build_profile_page() -> Control:
	var page := Control.new()
	page.name = "ProfilePage"

	var margin := MarginContainer.new()
	margin.name = "ProfileMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "– profile –"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#3e3025"))
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = ">> M_PIXEL <<"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", Color("#6d5941"))
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.modulate = Color("#b98f5e")
	vbox.add_child(sep)

	# Vital bars
	for key in ["blood", "stance", "hunger", "thirst", "fatigue", "temperature"]:
		vbox.add_child(_build_vital_row(key))

	var sep2 := HSeparator.new()
	sep2.modulate = Color("#b98f5e")
	vbox.add_child(sep2)

	# Warning label
	_warning_label = Label.new()
	_warning_label.text = "BODY SIGNAL STABLE"
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 9)
	_warning_label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_CAUTION)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_warning_label)

	# Action row with quick buttons
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(action_row)

	# Inventory quick button
	var inv_btn := Button.new()
	inv_btn.text = "INV"
	inv_btn.custom_minimum_size = Vector2(60, 22)
	HUDAssetLibrary.apply_button(inv_btn, "inventory")
	inv_btn.add_theme_font_size_override("font_size", 9)
	inv_btn.pressed.connect(inventory_requested.emit)
	action_row.add_child(inv_btn)

	# Medical button
	var med_btn := Button.new()
	med_btn.text = "MED"
	med_btn.custom_minimum_size = Vector2(60, 22)
	HUDAssetLibrary.apply_button(med_btn, "blood")
	med_btn.add_theme_font_size_override("font_size", 9)
	med_btn.pressed.connect(_toggle_medical_monitor)
	action_row.add_child(med_btn)

	return page

func _build_vital_row(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.texture = HUDAssetLibrary.status_icon(key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)

	var label := Label.new()
	label.text = "%s  --/12" % key.to_upper()
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("#3e3025"))
	col.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 8.0
	bar.max_value = MAX_SCALE
	bar.show_percentage = false
	var fill_kind := "health"
	match key:
		"blood": fill_kind = "blood"
		"stance": fill_kind = "stance"
		"hunger": fill_kind = "warning"
		"thirst": fill_kind = "health"
		"fatigue": fill_kind = "stance"
		"temperature": fill_kind = "anomaly"
	HUDAssetLibrary.apply_progress_bar(bar, fill_kind)
	col.add_child(bar)

	_vital_rows[key] = {"label": label, "bar": bar}
	return row

func _build_inventory_page() -> Control:
	var page := Control.new()
	page.name = "InventoryPage"

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "– inventory –"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#3e3025"))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "OPEN YOUR FULL INVENTORY TO MANAGE GEAR, EQUIPMENT, AND FIELD ITEMS."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color("#6d5941"))
	vbox.add_child(hint)

	var open_btn := Button.new()
	open_btn.text = "OPEN INVENTORY [TAB]"
	open_btn.custom_minimum_size = Vector2(160, 28)
	HUDAssetLibrary.apply_button(open_btn, "inventory")
	open_btn.add_theme_font_size_override("font_size", 10)
	open_btn.pressed.connect(inventory_requested.emit)
	vbox.add_child(open_btn)
	# Center the button
	open_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	return page

func _build_map_page() -> Control:
	var page := Control.new()
	page.name = "MapPage"

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "– worldmap –"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#3e3025"))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = ">> SCRITE ISLAND <<"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", Color("#6d5941"))
	vbox.add_child(subtitle)

	# Map display area – uses the grid background
	var map_area := TextureRect.new()
	map_area.name = "MapDisplay"
	map_area.texture = HUDAssetLibrary.background_texture()
	map_area.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_area.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(map_area)

	return page

func _build_save_page() -> Control:
	var page := Control.new()
	page.name = "SavePage"

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "– save/load –"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#3e3025"))
	vbox.add_child(title)

	# Save button
	var save_btn := Button.new()
	save_btn.text = "FIELD SAVE"
	save_btn.custom_minimum_size = Vector2(140, 26)
	HUDAssetLibrary.apply_button(save_btn, "save")
	save_btn.add_theme_font_size_override("font_size", 10)
	save_btn.pressed.connect(save_requested.emit)
	save_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(save_btn)

	# Slot hints
	var slot_hint := Label.new()
	slot_hint.text = "Forced – 04:00 pm"
	slot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_hint.add_theme_font_size_override("font_size", 9)
	slot_hint.add_theme_color_override("font_color", Color("#d9786c"))
	vbox.add_child(slot_hint)

	for i in range(3):
		var empty := Label.new()
		empty.text = "Empty Slot"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Color("#6d5941"))
		vbox.add_child(empty)

	# Load button
	var load_btn := Button.new()
	load_btn.text = "FIELD LOAD"
	load_btn.custom_minimum_size = Vector2(140, 26)
	HUDAssetLibrary.apply_button(load_btn, "load")
	load_btn.add_theme_font_size_override("font_size", 10)
	load_btn.pressed.connect(load_requested.emit)
	load_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(load_btn)

	return page

func _build_options_page() -> Control:
	var page := Control.new()
	page.name = "OptionsPage"

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "– option –"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#3e3025"))
	vbox.add_child(title)

	# Resolution label
	var res_label := Label.new()
	res_label.text = "Resolution"
	res_label.add_theme_font_size_override("font_size", 10)
	res_label.add_theme_color_override("font_color", Color("#3e3025"))
	vbox.add_child(res_label)

	# Scanline toggle
	_screen_noise_toggle = CheckButton.new()
	_screen_noise_toggle.text = "SCANLINE"
	_screen_noise_toggle.add_theme_font_size_override("font_size", 9)
	_screen_noise_toggle.toggled.connect(_set_screen_noise)
	HUDAssetLibrary.apply_button(_screen_noise_toggle)
	vbox.add_child(_screen_noise_toggle)

	# HUD scale
	var scale_row := VBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 2)
	vbox.add_child(scale_row)

	_hud_scale_label = Label.new()
	_hud_scale_label.text = "HUD SCALE 100%"
	_hud_scale_label.add_theme_font_size_override("font_size", 9)
	_hud_scale_label.add_theme_color_override("font_color", Color("#6d5941"))
	scale_row.add_child(_hud_scale_label)

	_hud_scale_slider = HSlider.new()
	_hud_scale_slider.min_value = 0.85
	_hud_scale_slider.max_value = 1.25
	_hud_scale_slider.step = 0.05
	_hud_scale_slider.value = 1.0
	_hud_scale_slider.value_changed.connect(_set_hud_scale)
	scale_row.add_child(_hud_scale_slider)

	# Hint
	var hint := Label.new()
	hint.text = "Audio and control settings coming later."
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color("#6d5941"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var default_btn := Button.new()
	default_btn.text = "Default"
	default_btn.custom_minimum_size = Vector2(70, 22)
	HUDAssetLibrary.apply_button(default_btn)
	default_btn.add_theme_font_size_override("font_size", 9)
	btn_row.add_child(default_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(70, 22)
	HUDAssetLibrary.apply_button(reset_btn)
	reset_btn.add_theme_font_size_override("font_size", 9)
	btn_row.add_child(reset_btn)

	return page

# ──────────────────────────────────────────────
# TAB / PAGE SWITCHING
# ──────────────────────────────────────────────

func _on_tab_pressed(page_index: int) -> void:
	if page_index == Page.INVENTORY:
		# Inventory tab – just emit the signal to open the full inventory UI
		inventory_requested.emit()
		return
	_switch_page(page_index)

func _switch_page(new_page: int) -> void:
	if new_page == _current_page and _page_containers[new_page].visible:
		return

	var old_page := _current_page
	_current_page = new_page

	# Hide all pages, show the current one
	for page_key: int in _page_containers:
		_page_containers[page_key].visible = (page_key == new_page)

	# Update tab button visuals
	_update_tab_visuals()

	# Play page flip animation if switching between different pages
	if old_page != new_page:
		_play_page_flip(old_page < new_page)

func _update_tab_visuals() -> void:
	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		if i == _current_page:
			btn.texture_normal = HUDAssetLibrary.side_tab_texture(TAB_SPRITE_ACTIVE[i])
			btn.modulate = Color(1.2, 1.15, 1.0, 1.0)
		else:
			btn.texture_normal = HUDAssetLibrary.side_tab_texture(TAB_SPRITE_NORMAL[i])
			btn.modulate = Color.WHITE

# ──────────────────────────────────────────────
# ANIMATIONS
# ──────────────────────────────────────────────

func _start_flicker_animation() -> void:
	if _flicker_frames.is_empty():
		return
	_flicker_timer = Timer.new()
	_flicker_timer.name = "FlickerTimer"
	_flicker_timer.wait_time = 0.15
	_flicker_timer.autostart = true
	_flicker_timer.timeout.connect(_on_flicker_tick)
	add_child(_flicker_timer)
	_flicker_sprite.texture = _flicker_frames[0]

func _on_flicker_tick() -> void:
	_flicker_index = (_flicker_index + 1) % _flicker_frames.size()
	_flicker_sprite.texture = _flicker_frames[_flicker_index]

func _play_page_flip(forward: bool) -> void:
	var frames := HUDAssetLibrary.page_flip_frames("next" if forward else "prev")
	if frames.is_empty():
		return
	_page_flip_rect.visible = true
	_page_flip_rect.modulate = Color.WHITE
	var flip_tween := create_tween()
	var frame_count := frames.size()
	var frame_dur := 0.04
	for i in range(frame_count):
		flip_tween.tween_callback(_set_flip_frame.bind(frames[i])).set_delay(
			frame_dur if i > 0 else 0.0
		)
	flip_tween.tween_callback(_hide_flip).set_delay(frame_dur)

func _set_flip_frame(tex: Texture2D) -> void:
	_page_flip_rect.texture = tex

func _hide_flip() -> void:
	_page_flip_rect.visible = false

# ──────────────────────────────────────────────
# INPUT
# ──────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if (
		not visible
		or not event is InputEventKey
		or not event.pressed
		or event.echo
	):
		return
	if event.keycode == KEY_M:
		_toggle_medical_monitor()
		get_viewport().set_input_as_handled()

# ──────────────────────────────────────────────
# RENDER
# ──────────────────────────────────────────────

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
	var row: Dictionary = _vital_rows.get(key, {})
	var label := row.get("label") as Label
	var bar := row.get("bar") as ProgressBar
	if label == null or bar == null:
		return
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

# ──────────────────────────────────────────────
# MEDICAL MONITOR
# ──────────────────────────────────────────────

func _toggle_medical_monitor() -> void:
	if _snapshot.is_empty() or not _medical_monitor:
		return
	if _medical_monitor.is_open():
		_medical_monitor.close_monitor()
		return
	_medical_monitor.open_monitor(_snapshot)

func _on_medical_monitor_closed() -> void:
	pass

# ──────────────────────────────────────────────
# SETTINGS
# ──────────────────────────────────────────────

func _set_screen_noise(enabled: bool) -> void:
	_screen_overlay.visible = enabled

func _set_hud_scale(value: float) -> void:
	# Scale the device container
	if _root.get_child_count() > 1:
		var device := _root.get_child(1) as Control
		if device:
			device.scale = Vector2.ONE * value
	_update_scale_label()

func _update_scale_label() -> void:
	if _hud_scale_label == null or _hud_scale_slider == null:
		return
	_hud_scale_label.text = "HUD SCALE %.0f%%" % (_hud_scale_slider.value * 100.0)
