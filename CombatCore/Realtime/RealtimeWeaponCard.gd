extends PanelContainer
class_name RealtimeWeaponCard

const GUN_CATALOG := preload("res://CombatCore/DuelUI/GunAnimationCatalog.gd")

@onready var weapon_name: Label = %WeaponName
@onready var ammo_label: Label = %AmmoLabel
@onready var state_label: Label = %StateLabel
@onready var weapon_image: TextureRect = %WeaponImage
@onready var effect_image: TextureRect = %EffectImage
@onready var grade_label: Label = get_node_or_null("%GradeLabel") as Label
@onready var condition_bar: ProgressBar = get_node_or_null("%ConditionBar") as ProgressBar
@onready var detail_label: Label = get_node_or_null("%DetailLabel") as Label

var _weapon: Dictionary = {}
var _base_atlas: AtlasTexture
var _effect_atlas: AtlasTexture
var _base_columns := 1
var _effect_columns := 1
var _frame_count := 1
var _effect_frame_count := 1
var _frame_size := Vector2i.ONE
var _effect_frame_size := Vector2i.ONE
var _animation_elapsed := 0.0
var _animation_duration := 0.0
var _visual_signature := ""
var _current_base_frame := 0
var _current_effect_frame := 0

func _ready() -> void:
	HUDAssetLibrary.connect_scheme_changed(_apply_standard_theme)
	_apply_standard_theme()
	set_process(false)
	effect_image.visible = false

func _exit_tree() -> void:
	HUDAssetLibrary.disconnect_scheme_changed(_apply_standard_theme)

func _apply_standard_theme(_scheme_id: String = "") -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_label(weapon_name, "title")
	HUDAssetLibrary.apply_label(ammo_label, "warning")
	HUDAssetLibrary.apply_label(state_label, "info")
	weapon_name.add_theme_font_size_override("font_size", 17)
	ammo_label.add_theme_font_size_override("font_size", 22)
	state_label.add_theme_font_size_override("font_size", 15)
	if grade_label:
		HUDAssetLibrary.apply_label(grade_label, "muted")
	if detail_label:
		HUDAssetLibrary.apply_label(detail_label, "body")
	if condition_bar:
		HUDAssetLibrary.apply_progress_bar(condition_bar, "health")

func show_actor_weapon(actor: Dictionary) -> void:
	var ranged: Dictionary = actor.get("ranged_weapon", {})
	var melee: Dictionary = actor.get("melee_weapon", {})
	var next_weapon: Dictionary = ranged if not ranged.is_empty() else melee
	show_descriptor(next_weapon, not ranged.is_empty())

func show_descriptor(next_weapon: Dictionary, is_ranged_weapon: bool = false) -> void:
	var next_signature := "%s|%s" % [
		str(next_weapon.get("id", "")),
		str(next_weapon.get("sprite_path", "")),
	]
	var visual_changed := next_signature != _visual_signature
	_visual_signature = next_signature
	_weapon = next_weapon
	if _weapon.is_empty():
		_animation_duration = 0.0
		_animation_elapsed = 0.0
		_base_atlas = null
		_effect_atlas = null
		effect_image.visible = false
		set_process(false)
		weapon_name.text = "UNARMED"
		ammo_label.text = ""
		state_label.text = "READY"
		weapon_image.texture = null
		if grade_label:
			grade_label.text = "NO ITEM"
		if condition_bar:
			condition_bar.value = 0.0
		if detail_label:
			detail_label.text = ""
		return
	weapon_name.text = str(_weapon.get("display_name", _weapon.get("id", "WEAPON"))).to_upper()
	var grade := int(_weapon.get("item_grade", GameEnums.ItemGrade.CIVILIAN))
	var grade_name := (
		str(GameEnums.ItemGrade.keys()[grade])
		if grade >= 0 and grade < GameEnums.ItemGrade.keys().size()
		else "CIVILIAN"
	)
	var condition := float(_weapon.get("current_condition", 12.0))
	if grade_label:
		grade_label.text = "%s // %s" % [
			grade_name,
			str(_weapon.get("condition_band", ItemConditionRules.condition_band(condition))).to_upper(),
		]
	if condition_bar:
		condition_bar.value = condition
	if detail_label:
		detail_label.text = "RANGE %d // FAULT %.2f%%" % [
			int(_weapon.get("effective_range", 0)),
			float(_weapon.get("fault_chance", ItemConditionRules.fault_chance(condition))) * 100.0,
		]
	if is_ranged_weapon:
		ammo_label.text = "%02d / %02d" % [
			int(_weapon.get("current_magazine", 0)),
			int(_weapon.get("max_magazine", 0)),
		]
		var readiness: Dictionary = _weapon.get("readiness", {})
		state_label.text = str(readiness.get("reason", "ready")).to_upper()
	else:
		ammo_label.text = "MELEE"
		state_label.text = "READY"
	if visual_changed and _animation_duration <= 0.0:
		_show_static_weapon()

func play_action(action: int, duration: float) -> void:
	if _weapon.is_empty() or not GUN_CATALOG.has_weapon(str(_weapon.get("id", ""))):
		return
	var effect := ""
	match action:
		GameEnums.DuelActionType.BLIND_FIRE, GameEnums.DuelActionType.AIMED_FIRE:
			effect = GUN_CATALOG.EFFECT_SHOOT
		GameEnums.DuelActionType.RELOAD:
			effect = GUN_CATALOG.EFFECT_RELOAD
		GameEnums.DuelActionType.CYCLE:
			effect = GUN_CATALOG.EFFECT_CYCLE
		GameEnums.DuelActionType.CLEAR_MALFUNCTION:
			effect = GUN_CATALOG.EFFECT_RELOAD
		GameEnums.DuelActionType.MALFUNCTION:
			effect = GUN_CATALOG.EFFECT_SHOOT
	if effect.is_empty():
		return
	_play_effect(effect, maxf(0.4, duration))


func play_turn_action(action: int, duration: float) -> void:
	if _weapon.is_empty() or not GUN_CATALOG.has_weapon(str(_weapon.get("id", ""))):
		return
	var effect := ""
	match action:
		GameEnums.ActionType.SHOOT:
			effect = GUN_CATALOG.EFFECT_SHOOT
		GameEnums.ActionType.AIMED_SHOT:
			effect = GUN_CATALOG.EFFECT_AIM
		GameEnums.ActionType.RELOAD, GameEnums.ActionType.CLEAR_MALFUNCTION:
			effect = GUN_CATALOG.EFFECT_RELOAD
		GameEnums.ActionType.CYCLE:
			effect = GUN_CATALOG.EFFECT_CYCLE
	if not effect.is_empty():
		_play_effect(effect, maxf(0.4, duration))


func get_animation_debug_state() -> Dictionary:
	return {
		"weapon_id": str(_weapon.get("id", "")),
		"playing": _animation_duration > 0.0,
		"duration": _animation_duration,
		"elapsed": _animation_elapsed,
		"base_frames": _frame_count,
		"effect_frames": _effect_frame_count if _effect_atlas != null else 0,
		"base_frame": _current_base_frame,
		"effect_frame": _current_effect_frame if _effect_atlas != null else -1,
		"base_columns": _base_columns,
		"effect_columns": _effect_columns if _effect_atlas != null else 0,
		"base_texture_path": (
			_base_atlas.atlas.resource_path
			if _base_atlas != null and _base_atlas.atlas != null
			else ""
		),
		"ammo_text": ammo_label.text if ammo_label != null else "",
		"state_text": state_label.text if state_label != null else "",
	}

func _show_static_weapon() -> void:
	var weapon_id := str(_weapon.get("id", ""))
	if GUN_CATALOG.has_weapon(weapon_id):
		_configure_base(GUN_CATALOG.texture(weapon_id, GUN_CATALOG.EFFECT_SHOOT), GUN_CATALOG.frame_spec(weapon_id, GUN_CATALOG.EFFECT_SHOOT))
		_apply_base_frame(0)
		return
	var sprite_path := str(_weapon.get("sprite_path", ""))
	weapon_image.texture = load(sprite_path) as Texture2D if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path) else null

func _play_effect(effect: String, duration: float) -> void:
	var weapon_id := str(_weapon.get("id", ""))
	_configure_base(GUN_CATALOG.texture(weapon_id, effect), GUN_CATALOG.frame_spec(weapon_id, effect))
	_configure_effect(GUN_CATALOG.effect_texture(weapon_id, effect), GUN_CATALOG.effect_frame_spec(weapon_id, effect))
	_animation_elapsed = 0.0
	_animation_duration = duration
	_apply_base_frame(0)
	_apply_effect_frame(0)
	set_process(true)

func _process(delta: float) -> void:
	if _animation_duration <= 0.0:
		set_process(false)
		return
	_animation_elapsed += delta
	var progress := clampf(_animation_elapsed / _animation_duration, 0.0, 0.9999)
	_apply_base_frame(mini(_frame_count - 1, int(floor(progress * _frame_count))))
	_apply_effect_frame(mini(_effect_frame_count - 1, int(floor(progress * _effect_frame_count))))
	if _animation_elapsed >= _animation_duration:
		_animation_duration = 0.0
		effect_image.visible = false
		_show_static_weapon()
		set_process(false)

func _configure_base(texture: Texture2D, spec: Dictionary) -> void:
	if texture == null:
		_base_atlas = null
		_frame_count = 1
		_base_columns = 1
		weapon_image.texture = null
		return
	_frame_size = _frame_size_for(texture, spec)
	_base_columns = maxi(1, int(texture.get_width()) / _frame_size.x)
	var rows := maxi(1, int(texture.get_height()) / _frame_size.y)
	_frame_count = _base_columns * rows
	_base_atlas = AtlasTexture.new()
	_base_atlas.atlas = texture
	weapon_image.texture = _base_atlas

func _configure_effect(texture: Texture2D, spec: Dictionary) -> void:
	if texture == null:
		effect_image.visible = false
		_effect_atlas = null
		_effect_frame_count = 1
		_effect_columns = 1
		return
	_effect_frame_size = _frame_size_for(texture, spec)
	_effect_columns = maxi(1, int(texture.get_width()) / _effect_frame_size.x)
	var rows := maxi(1, int(texture.get_height()) / _effect_frame_size.y)
	_effect_frame_count = _effect_columns * rows
	_effect_atlas = AtlasTexture.new()
	_effect_atlas.atlas = texture
	effect_image.texture = _effect_atlas
	effect_image.visible = true

func _frame_size_for(texture: Texture2D, spec: Dictionary) -> Vector2i:
	return Vector2i(
		maxi(1, int(spec.get("w", texture.get_width()))),
		maxi(1, int(spec.get("h", texture.get_height())))
	)

func _apply_base_frame(frame: int) -> void:
	if _base_atlas == null:
		return
	var clamped_frame := clampi(frame, 0, maxi(0, _frame_count - 1))
	var row := int(floor(float(clamped_frame) / float(_base_columns)))
	_current_base_frame = clamped_frame
	_base_atlas.region = Rect2(
		Vector2(
			(clamped_frame % _base_columns) * _frame_size.x,
			row * _frame_size.y
		),
		Vector2(_frame_size)
	)

func _apply_effect_frame(frame: int) -> void:
	if _effect_atlas == null:
		return
	var clamped_frame := clampi(
		frame,
		0,
		maxi(0, _effect_frame_count - 1)
	)
	var row := int(floor(float(clamped_frame) / float(_effect_columns)))
	_current_effect_frame = clamped_frame
	_effect_atlas.region = Rect2(
		Vector2(
			(clamped_frame % _effect_columns) * _effect_frame_size.x,
			row * _effect_frame_size.y
		),
		Vector2(_effect_frame_size)
	)
