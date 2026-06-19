extends Control
class_name PaperDollModel

const BACKGROUND_PATH := "res://Asset/UI/paperdoll.png"
const BODY_PATH := "res://Asset/Innawoods_Asset/Humanoid/Body/Body_Nude.png"
const HEAD_PATH := "res://Asset/Innawoods_Asset/Humanoid/Head/Male_1.png"
const ARM_REST_PATH := "res://Asset/Innawoods_Asset/Humanoid/Body/arm_rest.png"
const ARM_EQUIP_PATH := "res://Asset/Innawoods_Asset/Humanoid/Body/arm_equip.png"
const ARM_OFFHAND_2H_PATH := (
	"res://Asset/Innawoods_Asset/Humanoid/Body/arm_offhand_2hequip.png"
)
const GRIP_MASK_RECT := Rect2i(64, 62, 54, 56)

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

var _model_frame: Control
var _base_main_arm_under: TextureRect
var _base_main_arm_over: TextureRect
var _two_handed_grip: TextureRect

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

func _bind_authored_model() -> void:
	layer_nodes.clear()
	secondary_layer_nodes.clear()

	var background := _require_texture_rect("Background")
	_model_frame = get_node_or_null("ModelFrame") as Control
	var body := _require_texture_rect("ModelFrame/Layer_Body")
	var head := _require_texture_rect("ModelFrame/Layer_Head_Base")
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
		or body == null
		or head == null
		or _base_main_arm_under == null
		or _base_main_arm_over == null
		or _two_handed_grip == null
	):
		push_error("PaperDollModel requires its authored layer tree.")
		return

	background.texture = _load_texture(BACKGROUND_PATH)
	body.texture = _load_texture(BODY_PATH)
	head.texture = _load_texture(HEAD_PATH)
	_base_main_arm_under.texture = _load_texture(ARM_REST_PATH)

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

func _require_texture_rect(path: String) -> TextureRect:
	var layer := get_node_or_null(path) as TextureRect
	if layer == null:
		push_error("PaperDollModel missing authored TextureRect: " + path)
	return layer

func _resolve_arm_pose(equipment_data: Array) -> ArmPose:
	var descriptors_by_slot: Dictionary = {}
	for raw_descriptor in equipment_data:
		var descriptor: Dictionary = raw_descriptor
		var slot := int(descriptor.get(
			"equipment_slot",
			GameEnums.EquipmentSlot.NONE
		))
		descriptors_by_slot[slot] = descriptor

	for slot: int in WEAPON_SLOT_PRIORITY:
		if not descriptors_by_slot.has(slot):
			continue
		var descriptor: Dictionary = descriptors_by_slot[slot]
		if not _is_weapon_descriptor(descriptor):
			continue
		if descriptor.get("requires_two_hands", false):
			return ArmPose.TWO_HANDED
		return ArmPose.ONE_HANDED
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
