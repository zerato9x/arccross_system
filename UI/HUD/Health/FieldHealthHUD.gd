extends PanelContainer
class_name FieldHealthHUD

signal details_requested
signal inventory_requested
signal settings_requested
signal limb_treatment_requested(instance_id: String, limb_region: int)

enum DisplayMode { COMPACT, DETAILED }

const METRIC_TILE_SCENE := preload("res://UI/HUD/Health/HealthMetricTile.tscn")
const REGION_HOTSPOT_SCENE := preload("res://UI/HUD/Health/WoundRegionHotspot.tscn")
const STATE_STABLE := "res://Asset/UI/HUD/medical/state_stable_32.png"
const STATE_DAMAGED := "res://Asset/UI/HUD/medical/state_damaged_32.png"
const STATE_CRITICAL := "res://Asset/UI/HUD/medical/state_critical_32.png"

@export var display_mode: DisplayMode = DisplayMode.COMPACT
@export var profile: HealthHUDProfile = preload(
	"res://PresentationCore/health_hud_profile.tres"
)

var _snapshot: Dictionary = {}
var _metric_tiles: Array[HealthMetricTile] = []
var _region_hotspots: Dictionary = {}
var _region_definitions: Dictionary = {}
var _limb_snapshots: Dictionary = {}
var _selected_region := ""
var _selected_limb_region := -1

@onready var _compact_root: VBoxContainer = %CompactRoot
@onready var _detail_root: VBoxContainer = %DetailRoot
@onready var _compact_metric_grid: GridContainer = %CompactMetricGrid
@onready var _detail_metric_list: VBoxContainer = %DetailMetricList
@onready var _paper_doll_surface: BoxContainer = %PaperDollSurface
@onready var _paper_doll_stage: PanelContainer = %PaperDollStage
@onready var _inspector_stack: VBoxContainer = %InspectorStack
@onready var _region_inspector: PanelContainer = %RegionInspector
@onready var _inspector_title: Label = %InspectorTitle
@onready var _inspector_icon: TextureRect = %InspectorIcon
@onready var _inspector_integrity: Label = %InspectorIntegrity
@onready var _inspector_integrity_bar: ProgressBar = %InspectorIntegrityBar
@onready var _inspector_trauma: Label = %InspectorTrauma
@onready var _inspector_wounds: RichTextLabel = %InspectorWounds
@onready var _inspector_treatment: Label = %InspectorTreatment
@onready var _treatment_tray: PanelContainer = %TreatmentTray
@onready var _treatment_title: Label = %TreatmentTitle
@onready var _treatment_need: Label = %TreatmentNeed
@onready var _treatment_items: VBoxContainer = %TreatmentItems
@onready var _treatment_missing: Label = %TreatmentMissing
@onready var _treatment_close: Button = %TreatmentClose
@onready var _condition_icon: TextureRect = %ConditionIcon
@onready var _condition_label: Label = %ConditionLabel
@onready var _condition_detail: Label = %ConditionDetail
@onready var _alert_label: Label = %AlertLabel
@onready var _detail_condition_icon: TextureRect = %DetailConditionIcon
@onready var _detail_condition_label: Label = %DetailConditionLabel
@onready var _blood_summary: Label = %BloodSummary
@onready var _wound_summary: Label = %WoundSummary
@onready var _bleed_summary: Label = %BleedSummary
@onready var _infection_summary: Label = %InfectionSummary
@onready var _details_button: Button = %DetailsButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _settings_button: Button = %SettingsButton


func _ready() -> void:
	HUDAssetLibrary.apply_panel(self)
	_apply_typography()
	_build_from_profile()
	_compact_root.visible = display_mode == DisplayMode.COMPACT
	_detail_root.visible = display_mode == DisplayMode.DETAILED
	_details_button.pressed.connect(details_requested.emit)
	_details_button.text = "BODY MAP [M]"
	# Pack and Settings live on inventory / world-log corners only (no duplicates).
	if _inventory_button:
		_inventory_button.visible = false
	if _settings_button:
		_settings_button.visible = false
	_treatment_close.pressed.connect(_close_treatment)
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()
	if not _snapshot.is_empty():
		_render()


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if is_node_ready():
		_render()


func is_action_button_at(global_position: Vector2) -> bool:
	if _details_button != null and _details_button.visible and _details_button.get_global_rect().has_point(global_position):
		return true
	return false


func _update_responsive_layout() -> void:
	if _paper_doll_surface != null:
		_paper_doll_surface.vertical = size.x < 900.0
		if _paper_doll_surface.vertical and _treatment_tray.visible:
			_paper_doll_surface.move_child(_inspector_stack, 0)
		else:
			_paper_doll_surface.move_child(_paper_doll_stage, 0)


func _apply_typography() -> void:
	for label in [
		%CompactEyebrow,
		%ConditionDetail,
		%DetailEyebrow,
		%BloodSummary,
		%WoundSummary,
		%BleedSummary,
		%InfectionSummary,
		%SystemTitle,
		%RegionTitle,
		%InspectorIntegrity,
		%InspectorTrauma,
		%TreatmentNeed,
		%TreatmentMissing,
	]:
		HUDAssetLibrary.apply_label(label, "muted")
	HUDAssetLibrary.apply_label(_condition_label, "title")
	HUDAssetLibrary.apply_label(_detail_condition_label, "title")
	HUDAssetLibrary.apply_label(_alert_label, "warning")
	HUDAssetLibrary.apply_label(_inspector_title, "title")
	HUDAssetLibrary.apply_label(_inspector_treatment, "warning")
	HUDAssetLibrary.apply_label(_treatment_title, "title")
	_condition_label.add_theme_font_size_override("font_size", 28)
	_detail_condition_label.add_theme_font_size_override("font_size", 28)
	%CompactEyebrow.add_theme_font_size_override("font_size", 12)
	%ConditionDetail.add_theme_font_size_override("font_size", 13)
	%DetailEyebrow.add_theme_font_size_override("font_size", 12)
	_alert_label.add_theme_font_size_override("font_size", 12)
	for summary in [_blood_summary, _wound_summary, _bleed_summary, _infection_summary]:
		summary.add_theme_font_size_override("font_size", 13)
	HUDAssetLibrary.apply_button(_details_button, "search")
	HUDAssetLibrary.apply_button(_inventory_button, "inventory")
	HUDAssetLibrary.apply_button(_settings_button, "settings")
	HUDAssetLibrary.apply_button(_treatment_close)
	HUDAssetLibrary.apply_inset_panel(_paper_doll_stage)
	HUDAssetLibrary.apply_inset_panel(_region_inspector)
	HUDAssetLibrary.apply_inset_panel(_treatment_tray, "warning")
	HUDAssetLibrary.apply_progress_bar(_inspector_integrity_bar)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_condition_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_condition_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func restyle() -> void:
	HUDAssetLibrary.apply_panel(self)
	_apply_typography()
	for tile in _metric_tiles:
		if tile != null and tile.has_method("restyle"):
			tile.restyle()
		elif tile != null:
			HUDAssetLibrary.apply_inset_panel(tile)


func _build_from_profile() -> void:
	if profile == null:
		push_error("FieldHealthHUD requires a HealthHUDProfile.")
		return
	for resource in profile.metrics:
		var definition := resource as HealthMetricDefinition
		if definition == null:
			continue
		if definition.compact_visible and display_mode == DisplayMode.COMPACT:
			_add_metric_tile(_compact_metric_grid, definition)
		elif display_mode == DisplayMode.DETAILED:
			_add_metric_tile(_detail_metric_list, definition)
	if display_mode != DisplayMode.DETAILED:
		return
	for resource in profile.regions:
		var definition := resource as HealthRegionDefinition
		if definition == null:
			continue
		var region_key := str(definition.snapshot_region)
		var slot := _paper_doll_slot(region_key)
		if slot == null:
			push_error("No paper-doll slot authored for " + region_key)
			continue
		var hotspot := REGION_HOTSPOT_SCENE.instantiate() as WoundRegionHotspot
		slot.add_child(hotspot)
		hotspot.configure(definition)
		hotspot.region_hovered.connect(_show_region_details)
		hotspot.treatment_requested.connect(_open_treatment)
		hotspot.item_dropped.connect(limb_treatment_requested.emit)
		_region_hotspots[region_key] = hotspot
		_region_definitions[region_key] = definition


func _add_metric_tile(parent: Control, definition: HealthMetricDefinition) -> void:
	var tile := METRIC_TILE_SCENE.instantiate() as HealthMetricTile
	parent.add_child(tile)
	tile.configure(definition)
	_metric_tiles.append(tile)


func _paper_doll_slot(region_key: String) -> Control:
	match region_key:
		"HEAD":
			return %HeadSlot
		"UPPER_TORSO":
			return %UpperTorsoSlot
		"LOWER_TORSO":
			return %LowerTorsoSlot
		"LEFT_ARM":
			return %LeftArmSlot
		"RIGHT_ARM":
			return %RightArmSlot
		"LEFT_LEG":
			return %LeftLegSlot
		"RIGHT_LEG":
			return %RightLegSlot
	return null


func _first_wounded_region() -> String:
	for region_key in _limb_snapshots:
		var limb: Dictionary = _limb_snapshots[region_key]
		if not (limb.get("wounds", []) as Array).is_empty():
			return str(region_key)
	return ""


func _show_region_details(region_key: String) -> void:
	var limb := _limb_snapshots.get(region_key) as Dictionary
	var definition := _region_definitions.get(region_key) as HealthRegionDefinition
	if limb == null or definition == null:
		return
	_selected_region = region_key
	_selected_limb_region = int(definition.limb_region)
	var current := float(limb.get("current", 0.0))
	var maximum := maxf(1.0, float(limb.get("maximum", 12.0)))
	var wounds: Array = limb.get("wounds", [])
	var bleeding := float(limb.get("bleeding_rate", 0.0))
	_inspector_title.text = definition.display_name
	_inspector_icon.texture = HUDAssetLibrary.official_texture(definition.icon_path)
	_inspector_integrity.text = "INTEGRITY %.1f / %.1f" % [current, maximum]
	_inspector_integrity_bar.max_value = maximum
	_inspector_integrity_bar.value = current
	_inspector_trauma.text = "%s // BLEED %.2f / TURN" % [
		str(limb.get("trauma", "NONE")).replace("_", " "),
		bleeding,
	]
	if wounds.is_empty():
		_inspector_wounds.text = "%s\nTissue integrity is the only regional concern." % [
			HUDAssetLibrary.bbcode("muted", "NO ACTIVE WOUNDS")
		]
		_inspector_treatment.text = "NO MEDICAL ITEM REQUIRED"
		return
	var lines: Array[String] = []
	for index in range(wounds.size()):
		var wound: Dictionary = wounds[index]
		lines.append(HUDAssetLibrary.bbcode(
			"caution",
			"%02d // %s" % [index + 1, str(wound.get("type", "WOUND"))]
		))
		lines.append("Severity %.1f  Pain %.1f  Bleed %.2f" % [
			float(wound.get("severity", 0.0)),
			float(wound.get("pain", 0.0)),
			float(wound.get("bleeding_rate", 0.0)),
		])
		lines.append("Contamination %.1f  %s" % [
			float(wound.get("contamination", 0.0)),
			"TREATED" if bool(wound.get("treated", false)) else "UNTREATED",
		])
	_inspector_wounds.text = "\n".join(lines)
	var target := _worst_wound(wounds)
	var treatment: Dictionary = target.get("treatment", {})
	_inspector_treatment.text = "%s // %s" % [
		str(treatment.get("care_label", "CLINICAL ASSESSMENT")),
		"RIGHT-CLICK TO OPEN TREATMENT",
	]


func _worst_wound(wounds: Array) -> Dictionary:
	var target: Dictionary = {}
	for wound in wounds:
		if not wound is Dictionary:
			continue
		if target.is_empty():
			target = wound
			continue
		var untreated_priority := int(not bool(wound.get("treated", false)))
		var target_priority := int(not bool(target.get("treated", false)))
		if untreated_priority > target_priority or (
			untreated_priority == target_priority
			and float(wound.get("severity", 0.0)) > float(target.get("severity", 0.0))
		):
			target = wound
	return target


func _open_treatment(region_key: String, limb_region: int) -> void:
	_show_region_details(region_key)
	_selected_limb_region = limb_region
	for child in _treatment_items.get_children():
		child.free()
	_region_inspector.visible = false
	_treatment_tray.visible = true
	if _paper_doll_surface.vertical:
		_paper_doll_surface.move_child(_inspector_stack, 0)
	var limb := _limb_snapshots.get(region_key) as Dictionary
	var definition := _region_definitions.get(region_key) as HealthRegionDefinition
	var wounds: Array = limb.get("wounds", []) if limb != null else []
	_treatment_title.text = "TREAT // %s" % (
		definition.display_name if definition != null else region_key
	)
	if wounds.is_empty():
		_treatment_need.text = "NO ACTIVE WOUND // no treatment should be wasted here."
		_treatment_missing.text = "NO MEDICAL ITEM REQUIRED"
		_treatment_missing.visible = true
		return
	var target := _worst_wound(wounds)
	var treatment: Dictionary = target.get("treatment", {})
	var recommended: Array = treatment.get("recommended_item_ids", [])
	_treatment_need.text = "%s\n%s\nRECOMMENDED // %s" % [
		str(treatment.get("care_label", "CLINICAL ASSESSMENT")),
		str(treatment.get("instructions", "No instructions authored.")),
		_format_item_ids(recommended),
	]
	if not bool(treatment.get("currently_treatable", false)):
		_treatment_missing.text = "REQUIRED TREATMENT IS NOT YET SUPPORTED BY THE CURRENT ITEM CATALOGUE"
		_treatment_missing.visible = true
		return
	var required_effect := int(treatment.get("required_effect", -1))
	var candidates: Array = []
	for item in _snapshot.get("medical_items", []):
		if item is Dictionary and int(item.get("effect", -2)) == required_effect:
			candidates.append(item)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_index := recommended.find(str(a.get("item_id", "")))
			var b_index := recommended.find(str(b.get("item_id", "")))
			a_index = a_index if a_index >= 0 else 999
			b_index = b_index if b_index >= 0 else 999
			if a_index != b_index:
				return a_index < b_index
			return float(a.get("potency", 0.0)) > float(b.get("potency", 0.0))
	)
	for item in candidates:
		_add_treatment_item_button(item)
	_treatment_missing.visible = candidates.is_empty()
	_treatment_missing.text = (
		"NO COMPATIBLE MEDICAL ITEM CARRIED // NEEDED: " + _format_item_ids(recommended)
	)


func _add_treatment_item_button(item: Dictionary) -> void:
	var button := Button.new()
	button.text = "USE %s // POTENCY %.1f%s" % [
		str(item.get("name", "MEDICAL ITEM")).to_upper(),
		float(item.get("potency", 0.0)),
		" x%d" % int(item.get("stack_count", 1)) if int(item.get("stack_count", 1)) > 1 else "",
	]
	button.custom_minimum_size = Vector2(0, 34)
	button.icon = HUDAssetLibrary.official_texture(str(item.get("sprite_path", "")))
	button.expand_icon = false
	HUDAssetLibrary.apply_button(button)
	button.pressed.connect(
		func():
			limb_treatment_requested.emit(
				str(item.get("instance_id", "")),
				_selected_limb_region
			)
			_close_treatment()
	)
	_treatment_items.add_child(button)


func _close_treatment() -> void:
	_treatment_tray.visible = false
	_region_inspector.visible = true
	if _paper_doll_surface.vertical:
		_paper_doll_surface.move_child(_paper_doll_stage, 0)


func _format_item_ids(item_ids: Array) -> String:
	if item_ids.is_empty():
		return "NONE"
	var labels := PackedStringArray()
	for item_id in item_ids:
		labels.append(str(item_id).replace("_", " ").to_upper())
	return " / ".join(labels)


func _render() -> void:
	for tile in _metric_tiles:
		tile.apply_snapshot(_snapshot)
	_limb_snapshots.clear()
	var limbs: Array = _snapshot.get("limbs", [])
	for limb in limbs:
		if not limb is Dictionary:
			continue
		var region_key := str(limb.get("region", ""))
		_limb_snapshots[region_key] = limb
		var hotspot := _region_hotspots.get(region_key) as WoundRegionHotspot
		if hotspot:
			hotspot.apply_limb_snapshot(limb)
	if display_mode == DisplayMode.DETAILED:
		var region_to_show := _selected_region
		if region_to_show.is_empty() or not _limb_snapshots.has(region_to_show):
			region_to_show = _first_wounded_region()
			if region_to_show.is_empty():
				region_to_show = "HEAD"
		_show_region_details(region_to_show)
	_render_overview()


func _render_overview() -> void:
	var emergencies: Array = _snapshot.get("emergencies", [])
	var blood := float(_snapshot.get("blood", 0.0))
	var pain := float(_snapshot.get("pain", 0.0))
	var bleeding := float(_snapshot.get("bleeding_rate", 0.0))
	var wound_count := int(_snapshot.get("wound_count", 0))
	var infection := float(_snapshot.get("infection_risk", 0.0))
	var condition := "STABLE"
	var condition_detail := "NO ACTIVE TRAUMA"
	var state_icon := STATE_STABLE
	var panel_kind := "neutral"
	if blood <= 2.0 or emergencies.has("LOW_BLOOD") or pain >= 9.0:
		condition = "CRITICAL"
		condition_detail = "IMMEDIATE TREATMENT REQUIRED"
		state_icon = STATE_CRITICAL
		panel_kind = "critical"
	elif wound_count > 0 or not emergencies.is_empty():
		condition = "WOUNDED"
		condition_detail = "%d ACTIVE WOUND%s" % [
			wound_count,
			"" if wound_count == 1 else "S",
		]
		state_icon = STATE_DAMAGED
		panel_kind = "warning"
	var previous_condition := _condition_label.text if _condition_label else ""
	_condition_icon.texture = HUDAssetLibrary.official_texture(state_icon)
	_detail_condition_icon.texture = _condition_icon.texture
	_condition_label.text = condition
	_detail_condition_label.text = condition
	_condition_detail.text = condition_detail
	_alert_label.text = (
		"BODY SIGNALS NOMINAL"
		if emergencies.is_empty()
		else " // ".join(PackedStringArray(emergencies))
	)
	_blood_summary.text = "BLOOD  %.1f / 12" % blood
	_wound_summary.text = "WOUNDS  %d" % wound_count
	_bleed_summary.text = "BLEED  %.2f / TURN" % bleeding
	_infection_summary.text = "CONTAMINATION  %.1f / 12" % infection
	HUDAssetLibrary.apply_panel(self, panel_kind)
	HUDAssetLibrary.apply_label(_condition_label, "title")
	HUDAssetLibrary.apply_label(_detail_condition_label, "title")
	_condition_label.add_theme_font_size_override("font_size", 28)
	_detail_condition_label.add_theme_font_size_override("font_size", 28)
	if panel_kind == "critical":
		_condition_label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_CRITICAL)
		_detail_condition_label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_CRITICAL)
	elif panel_kind == "warning":
		_condition_label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_CAUTION)
		_detail_condition_label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_CAUTION)
	HUDAssetLibrary.apply_label(
		_alert_label,
		"critical" if panel_kind == "critical" else (
			"warning" if panel_kind == "warning" else "muted"
		)
	)
	_alert_label.add_theme_font_size_override("font_size", 12)
	HUDAssetLibrary.apply_label(
		_blood_summary,
		"critical" if blood <= 2.0 else ("warning" if blood <= 5.0 else "muted")
	)
	HUDAssetLibrary.apply_label(
		_wound_summary,
		"critical" if wound_count >= 3 else ("warning" if wound_count > 0 else "muted")
	)
	HUDAssetLibrary.apply_label(
		_bleed_summary,
		"critical" if bleeding >= 1.0 else ("warning" if bleeding > 0.0 else "muted")
	)
	HUDAssetLibrary.apply_label(
		_infection_summary,
		"anomaly" if infection >= 6.0 else ("warning" if infection >= 3.0 else "muted")
	)
	for summary in [_blood_summary, _wound_summary, _bleed_summary, _infection_summary]:
		summary.add_theme_font_size_override("font_size", 13)
	if previous_condition != "" and previous_condition != condition and panel_kind != "neutral":
		HudMotion.severity_flash(self, _condition_icon, panel_kind)
		HudMotion.severity_flash(self, _condition_label, panel_kind)
