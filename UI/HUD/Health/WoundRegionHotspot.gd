extends PanelContainer
class_name WoundRegionHotspot

signal region_hovered(region_key: String)
signal treatment_requested(region_key: String, limb_region: int)
signal item_dropped(instance_id: String, limb_region: int)

const STATE_STABLE := "res://Asset/UI/HUD/medical/state_stable_32.png"
const STATE_DAMAGED := "res://Asset/UI/HUD/medical/state_damaged_32.png"
const STATE_CRITICAL := "res://Asset/UI/HUD/medical/state_critical_32.png"

var _definition: HealthRegionDefinition
var _region_key := ""

@onready var _limb_icon: TextureRect = %LimbIcon
@onready var _state_icon: TextureRect = %StateIcon
@onready var _region_label: Label = %RegionLabel
@onready var _integrity_bar: ProgressBar = %IntegrityBar
@onready var _wound_count: Label = %WoundCount
@onready var _drop_highlight: ColorRect = %DropHighlight


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	HUDAssetLibrary.apply_panel(self)
	HUDAssetLibrary.apply_label(_region_label, "muted")
	HUDAssetLibrary.apply_label(_wound_count, "warning")
	_region_label.add_theme_font_size_override("font_size", 11)
	_wound_count.add_theme_font_size_override("font_size", 11)
	HUDAssetLibrary.apply_progress_bar(_integrity_bar)
	mouse_entered.connect(func(): region_hovered.emit(_region_key))


func configure(definition: HealthRegionDefinition) -> void:
	_definition = definition
	_region_key = str(definition.snapshot_region)
	if not is_node_ready():
		await ready
	_region_label.text = definition.display_name
	_limb_icon.texture = HUDAssetLibrary.official_texture(definition.icon_path)
	tooltip_text = "%s // hover for details // right-click for treatment" % definition.display_name


func apply_limb_snapshot(limb: Dictionary) -> void:
	var current := float(limb.get("current", 0.0))
	var maximum := maxf(1.0, float(limb.get("maximum", 12.0)))
	var ratio := clampf(current / maximum, 0.0, 1.0)
	var wounds: Array = limb.get("wounds", [])
	_integrity_bar.max_value = maximum
	_integrity_bar.value = current
	_wound_count.visible = not wounds.is_empty()
	_wound_count.text = "%dW" % wounds.size()
	var state_path := STATE_STABLE
	var panel_kind := "neutral"
	if ratio <= 0.25:
		state_path = STATE_CRITICAL
		panel_kind = "critical"
	elif ratio < 0.75 or not wounds.is_empty():
		state_path = STATE_DAMAGED
		panel_kind = "warning"
	_state_icon.texture = HUDAssetLibrary.official_texture(state_path)
	HUDAssetLibrary.apply_panel(self, panel_kind)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT and _definition != null:
		treatment_requested.emit(_region_key, int(_definition.limb_region))
		accept_event()
	elif mouse.button_index == MOUSE_BUTTON_LEFT:
		region_hovered.emit(_region_key)
		accept_event()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var valid := not str(data.get("instance_id", "")).is_empty()
	_drop_highlight.visible = valid
	return valid


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_highlight.visible = false
	if not data is Dictionary or _definition == null:
		return
	var instance_id := str(data.get("instance_id", ""))
	if not instance_id.is_empty():
		item_dropped.emit(instance_id, int(_definition.limb_region))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_instance_valid(_drop_highlight):
		_drop_highlight.visible = false

