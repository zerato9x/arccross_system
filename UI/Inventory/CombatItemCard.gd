extends PanelContainer
class_name CombatItemCard

## Data-driven item card. Tactical animation is owned by presentation profiles;
## this inventory widget only renders the item's authored sprite and state.

@onready var weapon_name: Label = %WeaponName
@onready var ammo_label: Label = %AmmoLabel
@onready var state_label: Label = %StateLabel
@onready var weapon_image: TextureRect = %WeaponImage
@onready var effect_image: TextureRect = %EffectImage
@onready var grade_label: Label = get_node_or_null("%GradeLabel") as Label
@onready var condition_bar: ProgressBar = get_node_or_null("%ConditionBar") as ProgressBar
@onready var detail_label: Label = get_node_or_null("%DetailLabel") as Label

var _weapon: Dictionary = {}
var _pulse_remaining := 0.0
var _texture_path := ""


func _ready() -> void:
	HUDAssetLibrary.connect_scheme_changed(_apply_standard_theme)
	_apply_standard_theme()
	effect_image.visible = false
	set_process(false)


func _exit_tree() -> void:
	HUDAssetLibrary.disconnect_scheme_changed(_apply_standard_theme)


func _apply_standard_theme(_scheme_id: String = "") -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(weapon_name, "title")
	HUDAssetLibrary.apply_label(ammo_label, "warning")
	HUDAssetLibrary.apply_label(state_label, "info")
	if grade_label:
		HUDAssetLibrary.apply_label(grade_label, "muted")
	if detail_label:
		HUDAssetLibrary.apply_label(detail_label, "body")
	if condition_bar:
		HUDAssetLibrary.apply_progress_bar(condition_bar, "health")


func show_actor_weapon(actor: Dictionary) -> void:
	var ranged: Dictionary = actor.get("ranged_weapon", {})
	var melee: Dictionary = actor.get("melee_weapon", {})
	show_descriptor(ranged if not ranged.is_empty() else melee, not ranged.is_empty())


func show_descriptor(descriptor: Dictionary, is_ranged_weapon: bool = false) -> void:
	_weapon = descriptor.duplicate(true)
	if _weapon.is_empty():
		weapon_name.text = "UNARMED"
		ammo_label.text = ""
		state_label.text = "READY"
		weapon_image.texture = null
		_texture_path = ""
		if grade_label:
			grade_label.text = "NO ITEM"
		if condition_bar:
			condition_bar.value = 0.0
		if detail_label:
			detail_label.text = ""
		return
	weapon_name.text = str(_weapon.get("display_name", _weapon.get("id", "ITEM"))).to_upper()
	var condition := float(_weapon.get("current_condition", 12.0))
	if condition_bar:
		condition_bar.value = condition
	if grade_label:
		var grade := int(_weapon.get("item_grade", GameEnums.ItemGrade.CIVILIAN))
		grade_label.text = "%s // %s" % [GameEnums.ItemGrade.keys()[grade], ItemConditionRules.condition_band(condition).to_upper()]
	if is_ranged_weapon:
		ammo_label.text = "%02d / %02d" % [int(_weapon.get("current_magazine", 0)), int(_weapon.get("max_magazine", 0))]
		state_label.text = str(_weapon.get("readiness", {}).get("reason", "ready")).to_upper()
	else:
		ammo_label.text = "MELEE"
		state_label.text = "READY"
	if detail_label:
		var optimal: Vector2i = _weapon.get("optimal_range_cells", Vector2i(1, 1))
		detail_label.text = "RANGE %d-%d // MAX %d // FAULT %.2f%%" % [optimal.x, optimal.y, int(_weapon.get("maximum_range_cells", 1)), ItemConditionRules.fault_chance(condition) * 100.0]
	_texture_path = str(_weapon.get("sprite_path", _weapon.get("inventory_sprite_path", "")))
	weapon_image.texture = load(_texture_path) as Texture2D if not _texture_path.is_empty() and ResourceLoader.exists(_texture_path) else null


func play_turn_action(_action_id: String, _duration: float = 0.0) -> void:
	# The card is a static equipment readout. Its action acknowledgement is a
	# fixed UI pulse, independent of combat, sprite-sheet, and body-clip clocks.
	_pulse_remaining = 0.18
	set_process(_pulse_remaining > 0.0)


func _process(delta: float) -> void:
	_pulse_remaining = maxf(0.0, _pulse_remaining - delta)
	weapon_image.modulate = Color(1.0, 0.88, 0.62).lerp(Color.WHITE, 1.0 - _pulse_remaining / maxf(0.01, _pulse_remaining + delta))
	if _pulse_remaining <= 0.0:
		weapon_image.modulate = Color.WHITE
		set_process(false)


func get_animation_debug_state() -> Dictionary:
	return {
		"weapon_id": str(_weapon.get("id", "")),
		"playing": _pulse_remaining > 0.0,
		"duration": _pulse_remaining,
		"base_texture_path": _texture_path,
		"ammo_text": ammo_label.text if ammo_label != null else "",
		"state_text": state_label.text if state_label != null else "",
	}
