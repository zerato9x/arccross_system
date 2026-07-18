extends Control
class_name MedicalMonitor

signal closed
signal limb_treatment_requested(instance_id: String, limb_region: int)

const MAX_SCALE := 12.0
const LIMB_ORDER: Array[int] = [
	GameEnums.LimbRegion.HEAD,
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.LOWER_TORSO,
	GameEnums.LimbRegion.LEFT_ARM,
	GameEnums.LimbRegion.RIGHT_ARM,
	GameEnums.LimbRegion.LEFT_LEG,
	GameEnums.LimbRegion.RIGHT_LEG,
]
const LIMB_CONFIG := {
	"HEAD": {
		"asset": "head",
		"short": "HD",
		"stage_position": Vector2(118.0, 8.0),
	},
	"UPPER_TORSO": {
		"asset": "upper_torso",
		"short": "UT",
		"stage_position": Vector2(114.0, 70.0),
	},
	"LOWER_TORSO": {
		"asset": "lower_torso",
		"short": "LT",
		"stage_position": Vector2(114.0, 135.0),
	},
	"LEFT_ARM": {
		"asset": "left_arm",
		"short": "LA",
		"stage_position": Vector2(42.0, 76.0),
	},
	"RIGHT_ARM": {
		"asset": "right_arm",
		"short": "RA",
		"stage_position": Vector2(190.0, 76.0),
	},
	"LEFT_LEG": {
		"asset": "left_leg",
		"short": "LL",
		"stage_position": Vector2(88.0, 198.0),
	},
	"RIGHT_LEG": {
		"asset": "right_leg",
		"short": "RL",
		"stage_position": Vector2(145.0, 198.0),
	},
}
const METRIC_CONFIG := [
	{"key": "blood", "label": "BLOOD", "icon": "blood", "fill": "blood"},
	{"key": "hunger", "label": "HUNGER", "icon": "hunger", "fill": "warning"},
	{"key": "thirst", "label": "THIRST", "icon": "thirst", "fill": "health"},
	{"key": "fatigue", "label": "FATIGUE", "icon": "fatigue", "fill": "stance"},
	{"key": "pain", "label": "PAIN", "icon": "stance", "fill": "stance"},
	{"key": "morale", "label": "MORALE", "icon": "morale", "fill": "health"},
	{"key": "red_mist", "label": "RED MIST", "icon": "anomaly", "fill": "anomaly"},
]

var _snapshot: Dictionary = {}
var _metric_rows: Dictionary = {}
var _limb_rows: Dictionary = {}
var _stage_regions: Dictionary = {}
var _stage_badges: Dictionary = {}
var _temperature_label: Label
var _temperature_bar: ProgressBar
var _system_summary: Label
var _structure_status: Label

@onready var _monitor_panel: PanelContainer = %MonitorPanel
@onready var _content: VBoxContainer = %Content

var _panel_scale := 1.0
var _embedded_fit := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	visible = false
	_apply_embedded_fit()

func set_embedded_fit(enabled: bool) -> void:
	_embedded_fit = enabled
	_apply_embedded_fit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_embedded_fit()

func _apply_embedded_fit() -> void:
	if _monitor_panel == null:
		return
	if not _embedded_fit:
		_monitor_panel.scale = Vector2.ONE
		_monitor_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var host_size := size
	if host_size.x <= 0.0 or host_size.y <= 0.0:
		return
	var panel_size := _monitor_panel.get_combined_minimum_size()
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	var fit_scale := minf(host_size.x / panel_size.x, host_size.y / panel_size.y)
	fit_scale = clampf(fit_scale, 0.25, 1.0)
	_monitor_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# The authored scene grows from both directions when full-rect. Keeping that
	# mode while assigning an oversized unscaled minimum shifts the fitted panel
	# off the left edge before scaling it back down.
	_monitor_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_monitor_panel.grow_vertical = Control.GROW_DIRECTION_END
	_monitor_panel.position = Vector2.ZERO
	_monitor_panel.size = panel_size
	_monitor_panel.scale = Vector2.ONE * fit_scale

func set_panel_scale(scale_value: float) -> void:
	_panel_scale = scale_value
	scale = Vector2.ONE * scale_value

func open_monitor(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	visible = true
	_render()

func close_monitor() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if visible:
		_render()

func is_open() -> bool:
	return visible

func _build_interface() -> void:
	HUDAssetLibrary.apply_panel(_monitor_panel, "neutral")

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 34.0
	header.add_theme_constant_override("separation", 10)
	_content.add_child(header)

	var title := Label.new()
	title.text = "BIOLOGICAL DIAGNOSTIC MONITOR"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HUDAssetLibrary.apply_label(title, "title")
	header.add_child(title)

	var signal_label := Label.new()
	signal_label.name = "SignalLabel"
	signal_label.text = "SYSTEM LINKED"
	HUDAssetLibrary.apply_label(signal_label, "muted")
	header.add_child(signal_label)

	var divider := HSeparator.new()
	divider.modulate = HUDAssetLibrary.COLOR_NORMAL
	_content.add_child(divider)

	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 16)
	_content.add_child(main_row)
	main_row.add_child(_build_systemic_column())
	main_row.add_child(_build_anatomy_column())
	main_row.add_child(_build_limb_column())

	var footer := Label.new()
	footer.name = "FooterLabel"
	footer.text = "LOCAL STRUCTURE AND SYSTEMIC VITALS ARE DISPLAY-ONLY SNAPSHOTS."
	HUDAssetLibrary.apply_label(footer, "muted")
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(footer)

func _build_systemic_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 244.0
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)

	var heading := Label.new()
	heading.text = "SYSTEMIC VITALS"
	HUDAssetLibrary.apply_label(heading, "warning")
	column.add_child(heading)

	for config in METRIC_CONFIG:
		column.add_child(_build_metric_row(config))

	var temperature_heading := Label.new()
	temperature_heading.text = "CORE TEMPERATURE"
	HUDAssetLibrary.apply_label(temperature_heading, "muted")
	column.add_child(temperature_heading)

	var temperature_label := Label.new()
	temperature_label.text = "TEMP --.-C"
	HUDAssetLibrary.apply_label(temperature_label, "body")
	column.add_child(temperature_label)
	_temperature_label = temperature_label

	var temperature_bar := ProgressBar.new()
	temperature_bar.custom_minimum_size.y = 12.0
	temperature_bar.max_value = MAX_SCALE
	HUDAssetLibrary.apply_progress_bar(temperature_bar, "anomaly")
	column.add_child(temperature_bar)
	_temperature_bar = temperature_bar

	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(summary, "muted")
	column.add_child(summary)
	_system_summary = summary
	return column

func _build_metric_row(config: Dictionary) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	root.add_child(header)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(18.0, 18.0)
	icon.texture = HUDAssetLibrary.status_icon(str(config.get("icon", "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HUDAssetLibrary.apply_label(label, "body")
	header.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 11.0
	bar.max_value = MAX_SCALE
	HUDAssetLibrary.apply_progress_bar(bar, str(config.get("fill", "health")))
	root.add_child(bar)

	_metric_rows[str(config.get("key", ""))] = {
		"label": label,
		"bar": bar,
		"label_text": str(config.get("label", "METER")),
	}
	return root

func _build_anatomy_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 286.0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)

	var heading := Label.new()
	heading.text = "LOCAL STRUCTURE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HUDAssetLibrary.apply_label(heading, "warning")
	column.add_child(heading)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(286.0, 344.0)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	column.add_child(stage)

	for region in LIMB_ORDER:
		var name := _region_name(region)
		var config: Dictionary = LIMB_CONFIG[name]
		var limb_texture := TextureRect.new()
		limb_texture.name = name + "Stage"
		limb_texture.position = config.get("stage_position", Vector2.ZERO)
		limb_texture.size = Vector2(64.0, 64.0)
		limb_texture.texture = HUDAssetLibrary.texture(
			"res://Asset/UI/HUD/medical/limb_%s_64.png"
			% str(config.get("asset", "head"))
		)
		limb_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		limb_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		limb_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(limb_texture)
		_stage_regions[name] = limb_texture

		var badge := TextureRect.new()
		badge.name = name + "Badge"
		badge.position = Vector2(
			float(limb_texture.position.x) + 45.0,
			float(limb_texture.position.y) + 42.0
		)
		badge.size = Vector2(22.0, 22.0)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(badge)
		_stage_badges[name] = badge

		var drop_target := LimbDropTarget.new()
		drop_target.configure(region)
		drop_target.position = config.get("stage_position", Vector2.ZERO)
		drop_target.size = Vector2(64.0, 64.0)
		drop_target.item_dropped.connect(
			func(instance_id: String, limb_region: int):
				limb_treatment_requested.emit(instance_id, limb_region)
		)
		stage.add_child(drop_target)

	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HUDAssetLibrary.apply_label(status_label, "body")
	column.add_child(status_label)
	_structure_status = status_label
	return column

func _build_limb_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 310.0
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)

	var heading := Label.new()
	heading.text = "LIMB READOUT"
	HUDAssetLibrary.apply_label(heading, "warning")
	column.add_child(heading)

	for region in LIMB_ORDER:
		var name := _region_name(region)
		var row := PanelContainer.new()
		row.custom_minimum_size.y = 52.0
		HUDAssetLibrary.apply_panel(row, "neutral")
		column.add_child(row)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 7)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_right", 7)
		margin.add_theme_constant_override("margin_bottom", 4)
		row.add_child(margin)

		var layout := HBoxContainer.new()
		layout.add_theme_constant_override("separation", 6)
		margin.add_child(layout)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(38.0, 38.0)
		icon.texture = HUDAssetLibrary.texture(
			"res://Asset/UI/HUD/medical/limb_%s_64.png"
			% str(LIMB_CONFIG[name].get("asset", "head"))
		)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(icon)

		var text_column := VBoxContainer.new()
		text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_column.add_theme_constant_override("separation", 1)
		layout.add_child(text_column)

		var label := Label.new()
		HUDAssetLibrary.apply_label(label, "body")
		text_column.add_child(label)

		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 10.0
		HUDAssetLibrary.apply_progress_bar(bar, "health")
		text_column.add_child(bar)

		var trauma := Label.new()
		HUDAssetLibrary.apply_label(trauma, "muted")
		text_column.add_child(trauma)

		var state := TextureRect.new()
		state.custom_minimum_size = Vector2(28.0, 28.0)
		state.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		state.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(state)

		_limb_rows[name] = {
			"panel": row,
			"label": label,
			"bar": bar,
			"trauma": trauma,
			"state": state,
		}
	return column

func _render() -> void:
	if _snapshot.is_empty():
		return
	for config in METRIC_CONFIG:
		var key := str(config.get("key", ""))
		var value := float(_snapshot.get(key, 0.0))
		_render_metric(key, value)

	var temperature := float(_snapshot.get("core_temperature", 37.0))
	if _temperature_label and _temperature_bar:
		_temperature_label.text = "TEMP %.1fC // %s" % [
			temperature,
			_temperature_status(temperature),
		]
		_temperature_bar.value = clampf(temperature - 30.0, 0.0, MAX_SCALE)

	var limbs_by_region := {}
	for raw_limb in _snapshot.get("limbs", []):
		var limb: Dictionary = raw_limb
		limbs_by_region[str(limb.get("region", ""))] = limb

	var healthy_regions := 0
	var active_wounds := 0
	for region in LIMB_ORDER:
		var name := _region_name(region)
		var limb: Dictionary = limbs_by_region.get(name, {})
		var current := float(limb.get("current", 0.0))
		var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
		var trauma := str(limb.get("trauma", "NONE"))
		var wounds: Array = limb.get("wounds", [])
		var bleeding_rate := float(limb.get("bleeding_rate", 0.0))
		var state := _limb_state(current, maximum, trauma)
		if state == "stable":
			healthy_regions += 1
		active_wounds += wounds.size()
		_render_limb(name, current, maximum, trauma, state, wounds, bleeding_rate)

	if _structure_status:
		_structure_status.text = "STRUCTURE %d/7 STABLE // %d WOUNDS // BLEED %.2f" % [
			healthy_regions,
			active_wounds,
			float(_snapshot.get("bleeding_rate", 0.0)),
		]
		HUDAssetLibrary.apply_label(
			_structure_status,
			"critical" if active_wounds > 0 else "body"
		)

	if _system_summary:
		_system_summary.text = _system_summary_text()

func _render_metric(key: String, value: float) -> void:
	var row: Dictionary = _metric_rows.get(key, {})
	var label := row.get("label") as Label
	var bar := row.get("bar") as ProgressBar
	if label == null or bar == null:
		return
	bar.value = clampf(value, 0.0, MAX_SCALE)
	var suffix := "%04.1f/12" % value
	if key == "red_mist":
		suffix = "%04.1f/12 EXPOSURE" % value
	label.text = "%s  %s" % [str(row.get("label_text", key)).to_upper(), suffix]

func _render_limb(
	name: String,
	current: float,
	maximum: float,
	trauma: String,
	state: String,
	wounds: Array,
	bleeding_rate: float
) -> void:
	var row: Dictionary = _limb_rows.get(name, {})
	var panel := row.get("panel") as PanelContainer
	var label := row.get("label") as Label
	var bar := row.get("bar") as ProgressBar
	var trauma_label := row.get("trauma") as Label
	var state_icon := row.get("state") as TextureRect
	if panel == null or label == null or bar == null or trauma_label == null or state_icon == null:
		return
	HUDAssetLibrary.apply_panel(panel, _panel_kind_for_state(state))
	label.text = "%s // %s" % [
		str(LIMB_CONFIG[name].get("short", "??")),
		name.replace("_", " "),
	]
	bar.max_value = maximum
	bar.value = current
	bar.add_theme_stylebox_override(
		"fill",
		HUDAssetLibrary.bar_fill_style(_fill_kind_for_state(state))
	)
	var wound_summary := _wound_summary(wounds)
	trauma_label.text = "%s / %s // %s%s" % [
		_compact(current),
		_compact(maximum),
		wound_summary if not wound_summary.is_empty() else trauma.replace("_", " "),
		" // BLEED %.2f" % bleeding_rate if bleeding_rate > 0.0 else "",
	]
	HUDAssetLibrary.apply_label(
		trauma_label,
		"critical" if not wounds.is_empty() or trauma != "NONE" else "muted"
	)
	state_icon.texture = HUDAssetLibrary.texture(
		"res://Asset/UI/HUD/medical/state_%s_32.png" % state
	)

	var stage_limb := _stage_regions.get(name) as TextureRect
	if stage_limb:
		stage_limb.modulate = _color_for_state(state)
		stage_limb.tooltip_text = "%s // %s" % [
			name.replace("_", " "),
			wound_summary if not wound_summary.is_empty() else trauma.replace("_", " "),
		]
	var stage_badge := _stage_badges.get(name) as TextureRect
	if stage_badge:
		stage_badge.texture = state_icon.texture

func _system_summary_text() -> String:
	var alerts := PackedStringArray()
	if float(_snapshot.get("blood", 0.0)) <= 4.0:
		alerts.append("CIRCULATORY RISK")
	if float(_snapshot.get("fatigue", 0.0)) >= 9.0:
		alerts.append("EXHAUSTION RISK")
	if float(_snapshot.get("bleeding_rate", 0.0)) > 0.0:
		alerts.append("ACTIVE HEMORRHAGE %.2f/TICK" % float(_snapshot.get("bleeding_rate", 0.0)))
	if float(_snapshot.get("pain", 0.0)) >= 8.0:
		alerts.append("SEVERE PAIN")
	if float(_snapshot.get("infection_risk", 0.0)) >= 8.0:
		alerts.append("INFECTION RISK")
	if float(_snapshot.get("red_mist", 0.0)) >= 6.0:
		alerts.append("ANOMALOUS EXPOSURE")
	var temperature := float(_snapshot.get("core_temperature", 37.0))
	if temperature < 34.0:
		alerts.append("HYPOTHERMIA RISK")
	if alerts.is_empty():
		return "SYSTEM STATUS // OPERATIONAL"
	return "SYSTEM ALERT // " + " / ".join(alerts)


func _wound_summary(wounds: Array) -> String:
	if wounds.is_empty():
		return ""
	var parts := PackedStringArray()
	for wound in wounds:
		if not wound is Dictionary:
			continue
		parts.append("%s S%.1f%s%s" % [
			str(wound.get("type", "WOUND")),
			float(wound.get("severity", 0.0)),
			" [TREATED]" if bool(wound.get("treated", false)) else "",
			" [DIRTY]" if float(wound.get("contamination", 0.0)) >= 6.0 else "",
		])
	return ", ".join(parts)

func _region_name(region: int) -> String:
	return str(GameEnums.LimbRegion.keys()[region])

func _limb_state(current: float, maximum: float, trauma: String) -> String:
	if current <= 0.0 or trauma == "SHATTERED_LIMB":
		return "destroyed"
	var ratio := current / maxf(1.0, maximum)
	if trauma != "NONE" or ratio <= 0.35:
		return "critical"
	if ratio <= 0.7:
		return "damaged"
	return "stable"

func _panel_kind_for_state(state: String) -> String:
	match state:
		"damaged":
			return "warning"
		"critical", "destroyed":
			return "critical"
	return "neutral"

func _fill_kind_for_state(state: String) -> String:
	match state:
		"damaged":
			return "warning"
		"critical", "destroyed":
			return "critical"
	return "health"

func _color_for_state(state: String) -> Color:
	match state:
		"damaged":
			return HUDAssetLibrary.COLOR_CAUTION
		"critical":
			return HUDAssetLibrary.COLOR_CRITICAL
		"destroyed":
			return HUDAssetLibrary.COLOR_ANOMALY
	return HUDAssetLibrary.COLOR_NORMAL

func _temperature_status(value: float) -> String:
	if value < 34.0:
		return "HYPOTHERMIA"
	if value > 39.0:
		return "HYPERTHERMIA"
	return "NOMINAL"

func _compact(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value
