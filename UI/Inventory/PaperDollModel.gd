extends Control
class_name PaperDollModel

const BACKGROUND_PATH := ""
const BODY_PATH := "res://Asset/Innawoods_Asset/Humanoid/Body/Body_Nude.png"
const HEAD_PATH := "res://Asset/Innawoods_Asset/Humanoid/Head/Male_1.png"
const ARM_REST_PATH := "res://Asset/Innawoods_Asset/Humanoid/Body/arm_rest.png"
const ARM_EQUIP_PATH := "res://Asset/Innawoods_Asset/Humanoid/Body/arm_equip.png"
const ARM_OFFHAND_2H_PATH := (
	"res://Asset/Innawoods_Asset/Humanoid/Body/arm_offhand_2hequip.png"
)
const GRIP_MASK_RECT := Rect2i(64, 62, 54, 56)
const WOUND_ROOT := "res://Asset/Innawoods_Asset/Humanoid/Wounds"
const FULL_WOUND_PATHS := [
	WOUND_ROOT + "/arm_laceration.png",
	WOUND_ROOT + "/face_craven_1.png",
	WOUND_ROOT + "/face_craven_2.png",
	WOUND_ROOT + "/face_craven_3.png",
	WOUND_ROOT + "/head_disfigured.png",
	WOUND_ROOT + "/head_disfigured_2.png",
	WOUND_ROOT + "/head_headshot.png",
	WOUND_ROOT + "/head_headshot_melee.png",
	WOUND_ROOT + "/head_scratch.png",
	WOUND_ROOT + "/head_wounded.png",
	WOUND_ROOT + "/torso_lower_laceration.png",
]
const DECAL_WOUND_PATHS := {
	"bullet": WOUND_ROOT + "/wound_bullet.png",
	"laceration": WOUND_ROOT + "/wound_laceration.png",
	"scratch": WOUND_ROOT + "/wound_scratch.png",
}
const DECAL_LAYOUT := {
	"HEAD": {"anchor": Vector2(0.47, 0.22), "size": Vector2(10.0, 12.0)},
	"UPPER_TORSO": {"anchor": Vector2(0.43, 0.39), "size": Vector2(12.0, 18.0)},
	"LOWER_TORSO": {"anchor": Vector2(0.43, 0.54), "size": Vector2(13.0, 20.0)},
	"LEFT_ARM": {"anchor": Vector2(0.34, 0.53), "size": Vector2(10.0, 18.0)},
	"RIGHT_ARM": {"anchor": Vector2(0.56, 0.45), "size": Vector2(10.0, 18.0)},
	"LEFT_LEG": {"anchor": Vector2(0.40, 0.74), "size": Vector2(10.0, 20.0)},
	"RIGHT_LEG": {"anchor": Vector2(0.53, 0.74), "size": Vector2(10.0, 20.0)},
}
const SOURCE_MODEL_SIZE := Vector2(209.0, 241.0)

const Z_BODY := 0
const Z_REST_ARM := 3
const Z_EQUIPMENT_BASE := 20
const Z_WOUND_BODY := Z_EQUIPMENT_BASE - 1
const Z_WOUND_HEAD := 35
const Z_WEAPON := 64
const Z_GRIP := 86

enum ArmPose {
	REST,
	ONE_HANDED,
	TWO_HANDED,
}

const POSE_SLOTS := [
	GameEnums.EquipmentSlot.INNER_TORSO,
	GameEnums.EquipmentSlot.OUTER_TORSO,
	GameEnums.EquipmentSlot.ARMS,
]

const WEAPON_SLOT_PRIORITY := [
	GameEnums.EquipmentSlot.HAND,
	GameEnums.EquipmentSlot.OFFHAND,
]

const BASE_SLOT_LAYERS := [
	GameEnums.EquipmentSlot.BACKPACK,
	GameEnums.EquipmentSlot.LEGS,
	GameEnums.EquipmentSlot.FEET,
	GameEnums.EquipmentSlot.INNER_TORSO,
	GameEnums.EquipmentSlot.OUTER_TORSO,
	GameEnums.EquipmentSlot.VEST,
	GameEnums.EquipmentSlot.ARMS,
	GameEnums.EquipmentSlot.NECK,
	GameEnums.EquipmentSlot.FACE,
	GameEnums.EquipmentSlot.EYES,
	GameEnums.EquipmentSlot.HEAD,
	GameEnums.EquipmentSlot.BELT,
	GameEnums.EquipmentSlot.SLING,
	GameEnums.EquipmentSlot.HAND,
	GameEnums.EquipmentSlot.OFFHAND,
]

const SECONDARY_SLOT_LAYERS := [
	GameEnums.EquipmentSlot.BACKPACK,
	GameEnums.EquipmentSlot.LEGS,
	GameEnums.EquipmentSlot.FEET,
	GameEnums.EquipmentSlot.NECK,
	GameEnums.EquipmentSlot.FACE,
	GameEnums.EquipmentSlot.EYES,
	GameEnums.EquipmentSlot.HEAD,
	GameEnums.EquipmentSlot.BELT,
	GameEnums.EquipmentSlot.SLING,
	GameEnums.EquipmentSlot.HAND,
	GameEnums.EquipmentSlot.OFFHAND,
	GameEnums.EquipmentSlot.INNER_TORSO,
	GameEnums.EquipmentSlot.OUTER_TORSO,
	GameEnums.EquipmentSlot.VEST,
	GameEnums.EquipmentSlot.ARMS,
]

var layer_nodes: Dictionary = {}
var secondary_layer_nodes: Dictionary = {}

var _background: TextureRect
var _vignette: ColorRect
var _model_frame: Control
var _body_layer: TextureRect
var _head_layer: TextureRect
var _base_main_arm_under: TextureRect
var _base_main_arm_over: TextureRect
var _two_handed_grip: TextureRect
var _full_wound_nodes: Dictionary = {}
var _decal_wound_nodes: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind_authored_model()

func update_model(equipment_data: Array) -> void:
	if not is_node_ready():
		await ready
	if _base_main_arm_under == null or _base_main_arm_over == null:
		return

	for layer: TextureRect in layer_nodes.values():
		layer.texture = null
	for layer: TextureRect in secondary_layer_nodes.values():
		layer.texture = null

	var arm_pose := _resolve_arm_pose(equipment_data)
	var has_clothing_arm := _has_authored_arm_layer(
		equipment_data,
		arm_pose
	)
	_base_main_arm_under.texture = _load_texture(
		ARM_REST_PATH if arm_pose == ArmPose.REST else ""
	)
	_base_main_arm_over.texture = _load_texture(
		ARM_EQUIP_PATH
			if arm_pose != ArmPose.REST and not has_clothing_arm
			else ""
	)
	_two_handed_grip.texture = _load_texture(
		ARM_OFFHAND_2H_PATH if arm_pose == ArmPose.TWO_HANDED else ""
	)

	for raw_descriptor in equipment_data:
		var descriptor: Dictionary = raw_descriptor
		var slot := int(descriptor.get(
			"equipment_slot",
			GameEnums.EquipmentSlot.NONE
		))
		if slot == GameEnums.EquipmentSlot.HAND or slot == GameEnums.EquipmentSlot.OFFHAND:
			continue
		if not layer_nodes.has(slot):
			continue

		var display_layers := _select_display_layers(
			descriptor,
			slot,
			arm_pose
		)
		var base_path := str(display_layers.get("base", ""))
		var overlay_path := str(display_layers.get("overlay", ""))
		var grip_mask_path := str(display_layers.get("grip_mask", ""))
		if not base_path.is_empty():
			layer_nodes[slot].texture = _load_texture(base_path)
		if (
			secondary_layer_nodes.has(slot)
			and not overlay_path.is_empty()
		):
			secondary_layer_nodes[slot].texture = _load_texture(
				overlay_path
			)
		elif (
			secondary_layer_nodes.has(slot)
			and not grip_mask_path.is_empty()
		):
			secondary_layer_nodes[slot].texture = _load_grip_mask(
				grip_mask_path
			)

func set_backdrop_visible(show_backdrop: bool) -> void:
	if not is_node_ready():
		await ready
	if _background:
		_background.visible = show_backdrop
	if _vignette:
		_vignette.visible = show_backdrop

func update_wounds(limbs: Array) -> void:
	if not is_node_ready():
		await ready
	_ensure_wound_layers()
	_clear_wounds()
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		var region := _region_name(limb.get("region", ""))
		if region.is_empty():
			continue
		var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
		var current := clampf(float(limb.get("current", maximum)), 0.0, maximum)
		var trauma := str(limb.get("trauma", "NONE"))
		var damage_type := _damage_type_name(
			limb.get("damage_type", limb.get("damage_type_index", ""))
		)
		var ratio := current / maximum
		if ratio >= 0.95 and trauma == "NONE":
			continue
		_show_wound(region, ratio, trauma, damage_type)

func _bind_authored_model() -> void:
	layer_nodes.clear()
	secondary_layer_nodes.clear()

	var background := _require_texture_rect("Background")
	_background = background
	_vignette = get_node_or_null("Vignette") as ColorRect
	_model_frame = get_node_or_null("ModelFrame") as Control
	_body_layer = _require_texture_rect("ModelFrame/Layer_Body")
	_head_layer = _require_texture_rect("ModelFrame/Layer_Head_Base")
	_base_main_arm_under = _require_texture_rect(
		"ModelFrame/Layer_Arm_Main_Rest"
	)
	_base_main_arm_over = _require_texture_rect(
		"ModelFrame/Layer_Arm_Main_Equipped"
	)
	_two_handed_grip = _require_texture_rect(
		"ModelFrame/Layer_Arm_Offhand_2H"
	)

	if (
		background == null
		or _model_frame == null
		or _body_layer == null
		or _head_layer == null
		or _base_main_arm_under == null
		or _base_main_arm_over == null
		or _two_handed_grip == null
	):
		push_error("PaperDollModel requires its authored layer tree.")
		return

	background.texture = _load_texture(BACKGROUND_PATH) if not BACKGROUND_PATH.is_empty() else null
	background.visible = not BACKGROUND_PATH.is_empty()
	_body_layer.texture = _load_texture(BODY_PATH)
	_head_layer.texture = _load_texture(HEAD_PATH)
	_base_main_arm_under.texture = _load_texture(ARM_REST_PATH)
	_ensure_wound_layers()

	for slot in BASE_SLOT_LAYERS:
		var layer := _require_texture_rect("ModelFrame/Layer_%d" % slot)
		if layer != null:
			layer_nodes[slot] = layer

	for slot in SECONDARY_SLOT_LAYERS:
		var layer := _require_texture_rect(
			"ModelFrame/Layer_%d_Secondary" % slot
		)
		if layer != null:
			secondary_layer_nodes[slot] = layer

	_apply_layer_order()

func _ensure_wound_layers() -> void:
	if _model_frame == null:
		return
	if _full_wound_nodes.is_empty():
		for path in FULL_WOUND_PATHS:
			var wound := _make_full_wound_layer(str(path))
			_full_wound_nodes[path] = wound
	if _decal_wound_nodes.is_empty():
		for region in DECAL_LAYOUT.keys():
			var decal := _make_decal_wound_layer(str(region))
			_decal_wound_nodes[region] = decal

func _make_full_wound_layer(path: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = "Wound_" + path.get_file().get_basename()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture = _load_texture(path)
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = _full_wound_z(path)
	layer.visible = false
	_model_frame.add_child(layer)
	return layer

func _make_decal_wound_layer(region: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = "Wound_Decal_" + region
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.z_index = Z_WOUND_BODY
	layer.visible = false
	_model_frame.add_child(layer)
	return layer

func _apply_layer_order() -> void:
	if _body_layer:
		_body_layer.z_index = Z_BODY
	if _head_layer:
		_head_layer.z_index = Z_EQUIPMENT_BASE + 13
	if _base_main_arm_under:
		_base_main_arm_under.z_index = Z_REST_ARM
	if _base_main_arm_over:
		_base_main_arm_over.z_index = Z_GRIP
	if _two_handed_grip:
		_two_handed_grip.z_index = Z_GRIP + 1

	for slot in layer_nodes.keys():
		var layer := layer_nodes[slot] as TextureRect
		if layer:
			layer.z_index = _slot_z_index(int(slot), false)
	for slot in secondary_layer_nodes.keys():
		var layer := secondary_layer_nodes[slot] as TextureRect
		if layer:
			layer.z_index = _slot_z_index(int(slot), true)

	for path in _full_wound_nodes.keys():
		var layer := _full_wound_nodes[path] as TextureRect
		if layer:
			layer.z_index = _full_wound_z(str(path))
	for layer: TextureRect in _decal_wound_nodes.values():
		layer.z_index = Z_WOUND_BODY

func _slot_z_index(slot: int, secondary: bool) -> int:
	if slot == GameEnums.EquipmentSlot.HAND:
		return Z_WEAPON if not secondary else Z_GRIP + 2
	if slot == GameEnums.EquipmentSlot.OFFHAND:
		return Z_WEAPON + 1 if not secondary else Z_GRIP + 3
	if secondary and (slot in POSE_SLOTS or slot == GameEnums.EquipmentSlot.VEST):
		return Z_GRIP + 4 + POSE_SLOTS.find(slot)
	var slot_index := BASE_SLOT_LAYERS.find(slot)
	if slot_index < 0:
		slot_index = 0
	return Z_EQUIPMENT_BASE + slot_index * 2 + (1 if secondary else 0)

func _clear_wounds() -> void:
	for layer: TextureRect in _full_wound_nodes.values():
		layer.visible = false
	for layer: TextureRect in _decal_wound_nodes.values():
		layer.visible = false

func _show_wound(
	region: String,
	ratio: float,
	trauma: String,
	damage_type: String
) -> void:
	var alpha := _wound_alpha(ratio, trauma)
	var full_path := _full_wound_path(region, ratio, trauma, damage_type)
	if not full_path.is_empty():
		var full_layer := _full_wound_nodes.get(full_path) as TextureRect
		if full_layer:
			full_layer.modulate = Color(1.0, 1.0, 1.0, alpha)
			full_layer.visible = true
	var decal_path := _decal_wound_path(region, ratio, trauma, damage_type)
	if not decal_path.is_empty():
		var decal := _decal_wound_nodes.get(region) as TextureRect
		if decal:
			decal.texture = _load_texture(decal_path)
			decal.modulate = Color(1.0, 1.0, 1.0, minf(alpha + 0.12, 1.0))
			_place_decal(decal, region, ratio, trauma)
			decal.visible = true

func _full_wound_path(
	region: String,
	ratio: float,
	trauma: String,
	damage_type: String
) -> String:
	match region:
		"HEAD":
			if damage_type == "BALLISTIC":
				return WOUND_ROOT + "/head_headshot.png"
			if damage_type == "SHARP":
				if trauma == "SHATTERED_LIMB" or ratio <= 0.35:
					return WOUND_ROOT + "/head_headshot_melee.png"
				if trauma != "NONE" or ratio <= 0.65:
					return WOUND_ROOT + "/head_wounded.png"
				if ratio <= 0.85:
					return WOUND_ROOT + "/head_scratch.png"
				return ""
			if trauma == "SHATTERED_LIMB" or ratio <= 0.0:
				return WOUND_ROOT + "/head_disfigured_2.png"
			if ratio <= 0.25:
				return WOUND_ROOT + "/head_disfigured.png"
			if trauma != "NONE" or ratio <= 0.55:
				return WOUND_ROOT + "/head_wounded.png"
			if ratio <= 0.85:
				return WOUND_ROOT + "/head_scratch.png"
			return ""
		"UPPER_TORSO", "LOWER_TORSO":
			if damage_type in ["BALLISTIC", "SHARP"] and (
				trauma != "NONE" or ratio <= 0.45
			):
				return WOUND_ROOT + "/torso_lower_laceration.png"
		"LEFT_ARM", "RIGHT_ARM":
			if damage_type in ["BALLISTIC", "SHARP"] and (
				trauma != "NONE" or ratio <= 0.45
			):
				return WOUND_ROOT + "/arm_laceration.png"
	return ""

func _decal_wound_path(
	region: String,
	ratio: float,
	trauma: String,
	damage_type: String
) -> String:
	if region == "HEAD":
		return ""
	match damage_type:
		"BALLISTIC":
			if trauma != "NONE" or ratio <= 0.9:
				return str(DECAL_WOUND_PATHS["bullet"])
		"SHARP":
			if trauma != "NONE" or ratio <= 0.85:
				return str(DECAL_WOUND_PATHS["laceration"])
		"BLUNT":
			if trauma != "NONE" or ratio <= 0.85:
				return str(DECAL_WOUND_PATHS["scratch"])
	if trauma == "BLEEDING" or ratio <= 0.55:
		return str(DECAL_WOUND_PATHS["laceration"])
	if ratio <= 0.85:
		return str(DECAL_WOUND_PATHS["scratch"])
	return ""

func _place_decal(
	layer: TextureRect,
	region: String,
	ratio: float,
	trauma: String
) -> void:
	var layout: Dictionary = DECAL_LAYOUT.get(region, {})
	if layout.is_empty():
		return
	var anchor: Vector2 = layout.get("anchor", Vector2(0.5, 0.5))
	var decal_size: Vector2 = layout.get("size", Vector2(18.0, 24.0))
	var content_rect := _model_content_rect()
	var content_scale := content_rect.size.x / SOURCE_MODEL_SIZE.x
	decal_size *= content_scale * lerpf(0.65, 1.0, _wound_severity(ratio, trauma))
	layer.size = decal_size
	layer.position = content_rect.position + content_rect.size * anchor - decal_size * 0.5

func _model_content_rect() -> Rect2:
	if _model_frame == null:
		return Rect2(Vector2.ZERO, SOURCE_MODEL_SIZE)
	var frame_size := _model_frame.size
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return Rect2(Vector2.ZERO, SOURCE_MODEL_SIZE)
	var scale_factor := minf(
		frame_size.x / SOURCE_MODEL_SIZE.x,
		frame_size.y / SOURCE_MODEL_SIZE.y
	)
	var content_size := SOURCE_MODEL_SIZE * scale_factor
	return Rect2((frame_size - content_size) * 0.5, content_size)

func _full_wound_z(path: String) -> int:
	return (
		Z_WOUND_HEAD
		if path.contains("/head_") or path.contains("/face_")
		else Z_WOUND_BODY
	)

func _wound_alpha(ratio: float, trauma: String) -> float:
	var severity := _wound_severity(ratio, trauma)
	return clampf(0.65 + severity * 0.35, 0.65, 1.0)

func _wound_severity(ratio: float, trauma: String) -> float:
	var severity := clampf(1.0 - ratio, 0.0, 1.0)
	match trauma:
		"BLEEDING":
			severity = maxf(severity, 0.5)
		"FRACTURED", "SHATTERED_LIMB":
			severity = maxf(severity, 0.75)
		_:
			if trauma != "NONE":
				severity = maxf(severity, 0.35)
	return severity

func _region_name(raw_region) -> String:
	if raw_region is int:
		var index := int(raw_region)
		if index >= 0 and index < GameEnums.LimbRegion.keys().size():
			return str(GameEnums.LimbRegion.keys()[index])
		return ""
	var region := str(raw_region)
	if region.is_valid_int():
		return _region_name(int(region))
	return region

func _damage_type_name(raw_damage_type) -> String:
	if raw_damage_type is int:
		var index := int(raw_damage_type)
		if index >= 0 and index < GameEnums.DamageType.keys().size():
			return str(GameEnums.DamageType.keys()[index])
		return ""
	var damage_type := str(raw_damage_type).to_upper()
	if damage_type.is_valid_int():
		return _damage_type_name(int(damage_type))
	return damage_type

func _require_texture_rect(path: String) -> TextureRect:
	var layer := get_node_or_null(path) as TextureRect
	if layer == null:
		push_error("PaperDollModel missing authored TextureRect: " + path)
	return layer

func _resolve_arm_pose(equipment_data: Array) -> ArmPose:
	return ArmPose.REST

func _is_weapon_descriptor(descriptor: Dictionary) -> bool:
	return (
		int(descriptor.get("item_type", GameEnums.ItemType.JUNK))
			== GameEnums.ItemType.WEAPON
		or int(descriptor.get(
			"weapon_type",
			GameEnums.WeaponClass.NONE
		)) != GameEnums.WeaponClass.NONE
	)

func _has_authored_arm_layer(
	equipment_data: Array,
	arm_pose: ArmPose
) -> bool:
	if arm_pose == ArmPose.REST:
		return false
	for raw_descriptor in equipment_data:
		var descriptor: Dictionary = raw_descriptor
		var slot := int(descriptor.get(
			"equipment_slot",
			GameEnums.EquipmentSlot.NONE
		))
		if slot not in POSE_SLOTS and slot != GameEnums.EquipmentSlot.VEST:
			continue
		var paths := _get_source_paths(descriptor)
		if paths.size() >= 2:
			return true
		for path in paths:
			if "arm" in path.get_file().to_lower():
				return true
	return false

func _select_display_layers(
	descriptor: Dictionary,
	slot: int,
	arm_pose: ArmPose
) -> Dictionary:
	var source_paths := _get_source_paths(descriptor)
	if source_paths.is_empty():
		return {}
	if source_paths.size() == 1:
		return {"base": source_paths[0]}

	var torso_candidates: Array[String] = []
	var arm_candidates: Array[String] = []
	var static_candidates: Array[String] = []
	for path in source_paths:
		var filename := path.get_file().to_lower()
		if "arm" in filename:
			arm_candidates.append(path)
		elif "torso" in filename:
			torso_candidates.append(path)
		else:
			static_candidates.append(path)

	# Explicit arm filenames are authoritative, including unusual rig slots.
	if not arm_candidates.is_empty():
		var result := {}
		if not torso_candidates.is_empty():
			result["base"] = _choose_torso_path(torso_candidates)
		elif not static_candidates.is_empty():
			result["base"] = static_candidates[0]
		result["overlay"] = _choose_clothing_arm_path(
			arm_candidates,
			arm_pose
		)
		return result

	if slot in POSE_SLOTS:
		# Whole-body composites remain below the weapon. A small masked copy of
		# the authored grip is placed above it so the gun stays visible.
		if arm_pose == ArmPose.REST:
			return {"base": source_paths[0]}
		return {
			"base": source_paths[1],
			"grip_mask": source_paths[1],
		}

	# Multiple paths in other slots are authored visual variants, not layers.
	return {"base": source_paths[0]}

func _get_source_paths(descriptor: Dictionary) -> Array[String]:
	var source_paths: Array[String] = []
	for raw_path in descriptor.get("equipped_sprite_paths", []):
		var path := str(raw_path)
		if not path.is_empty():
			source_paths.append(path)

	if source_paths.is_empty():
		var legacy_path := str(descriptor.get("paperdoll_texture_path", ""))
		if legacy_path.is_empty():
			legacy_path = str(descriptor.get("equipped_sprite_path", ""))
		if not legacy_path.is_empty():
			source_paths.append(legacy_path)
	return source_paths

func _choose_torso_path(candidates: Array[String]) -> String:
	for path in candidates:
		if "hood" not in path.get_file().to_lower():
			return path
	return candidates[0] if not candidates.is_empty() else ""

func _choose_clothing_arm_path(
	candidates: Array[String],
	arm_pose: ArmPose
) -> String:
	if candidates.is_empty():
		return ""

	var wants_equipped_pose := arm_pose != ArmPose.REST
	for path in candidates:
		var filename := path.get_file().to_lower()
		var is_equipped_pose := (
			"arm2" in filename
			or "arms2" in filename
			or "rolled2" in filename
		)
		var is_rolled_variant := "rolled" in filename
		if (
			is_equipped_pose == wants_equipped_pose
			and not is_rolled_variant
		):
			return path

	for path in candidates:
		var filename := path.get_file().to_lower()
		var is_equipped_pose := (
			"arm2" in filename
			or "arms2" in filename
			or "rolled2" in filename
		)
		if is_equipped_pose == wants_equipped_pose:
			return path
	return candidates[0]

func _load_texture(path: String) -> Texture2D:
	return EntityProjectionAssets.texture(path)

func _load_grip_mask(path: String) -> Texture2D:
	return EntityProjectionAssets.masked_texture(path, GRIP_MASK_RECT)
