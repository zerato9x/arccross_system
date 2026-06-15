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

var layer_nodes: Dictionary = {}
var secondary_layer_nodes: Dictionary = {}

var _model_frame: Control
var _base_main_arm_under: TextureRect
var _base_main_arm_over: TextureRect
var _two_handed_grip: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_model()

func update_model(equipment_data: Array) -> void:
	if not is_node_ready():
		await ready

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

func _build_model() -> void:
	for child in get_children():
		child.queue_free()
	layer_nodes.clear()
	secondary_layer_nodes.clear()

	var background := TextureRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = _load_texture(BACKGROUND_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.58, 0.62, 0.62, 0.58)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.03, 0.045, 0.052, 0.28)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	_model_frame = Control.new()
	_model_frame.name = "ModelFrame"
	_model_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_model_frame.offset_left = 35.0
	_model_frame.offset_top = 18.0
	_model_frame.offset_right = -35.0
	_model_frame.offset_bottom = -18.0
	_model_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_model_frame)

	# Back-mounted gear must stay behind the body.
	_create_slot_layers(GameEnums.EquipmentSlot.BACKPACK)

	var body := _make_layer("Layer_Body")
	body.texture = _load_texture(BODY_PATH)

	# The relaxed arm remains below torso clothing.
	_base_main_arm_under = _make_layer("Layer_Arm_Main_Rest")
	_base_main_arm_under.texture = _load_texture(ARM_REST_PATH)

	# Lower body and torso clothing sit below the head.
	_create_slot_layers(GameEnums.EquipmentSlot.LEGS)
	_create_slot_layers(GameEnums.EquipmentSlot.FEET)
	_create_slot_base(GameEnums.EquipmentSlot.INNER_TORSO)
	_create_slot_base(GameEnums.EquipmentSlot.OUTER_TORSO)
	_create_slot_base(GameEnums.EquipmentSlot.VEST)
	_create_slot_base(GameEnums.EquipmentSlot.ARMS)

	# The bare head must render over collars, coats, rigs, and torso layers.
	var head := _make_layer("Layer_Head_Base")
	head.texture = _load_texture(HEAD_PATH)

	_create_slot_layers(GameEnums.EquipmentSlot.NECK)
	_create_slot_layers(GameEnums.EquipmentSlot.FACE)
	_create_slot_layers(GameEnums.EquipmentSlot.EYES)
	_create_slot_layers(GameEnums.EquipmentSlot.HEAD)

	# Belt and sling are worn gear, not weapon hands.
	_create_slot_layers(GameEnums.EquipmentSlot.BELT)
	_create_slot_layers(GameEnums.EquipmentSlot.SLING)

	# Readied weapons sit below the gripping arm and clothing-arm artwork.
	_create_slot_layers(GameEnums.EquipmentSlot.HAND)
	_create_slot_layers(GameEnums.EquipmentSlot.OFFHAND)

	_base_main_arm_over = _make_layer("Layer_Arm_Main_Equipped")
	_create_slot_overlay(GameEnums.EquipmentSlot.INNER_TORSO)
	_create_slot_overlay(GameEnums.EquipmentSlot.OUTER_TORSO)
	_create_slot_overlay(GameEnums.EquipmentSlot.VEST)
	_create_slot_overlay(GameEnums.EquipmentSlot.ARMS)

	# The offhand only exists for the authored two-handed grip.
	_two_handed_grip = _make_layer("Layer_Arm_Offhand_2H")

func _create_slot_layers(slot: int) -> void:
	_create_slot_base(slot)
	_create_slot_overlay(slot)

func _create_slot_base(slot: int) -> void:
	layer_nodes[slot] = _make_layer("Layer_%d" % slot)

func _create_slot_overlay(slot: int) -> void:
	secondary_layer_nodes[slot] = _make_layer(
		"Layer_%d_Secondary" % slot
	)

func _make_layer(layer_name: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = layer_name
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_model_frame.add_child(layer)
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
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _load_grip_mask(path: String) -> Texture2D:
	var texture := _load_texture(path)
	if texture == null:
		return null
	var source := texture.get_image()
	var masked := Image.create(
		source.get_width(),
		source.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	masked.fill(Color.TRANSPARENT)
	masked.blit_rect(source, GRIP_MASK_RECT, GRIP_MASK_RECT.position)
	return ImageTexture.create_from_image(masked)
