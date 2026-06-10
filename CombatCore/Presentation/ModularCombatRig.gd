extends Node2D
class_name ModularCombatRig

const PART_ROOT := "res://Asset/Characters/CombatSilhouetteThreeQuarter/Parts/"
const COLOR_SHADER := preload("res://CombatCore/Presentation/SilhouetteColor.gdshader")
const WEAPON_ANIMATOR := preload(
	"res://CombatCore/Presentation/CombatWeaponAnimator.gd"
)

const PLAYER_COLOR := Color(0.28, 0.95, 0.88)
const ENEMY_COLOR := Color(1.0, 0.25, 0.34)

var _body_root: Node2D
var _pelvis: Node2D
var _shoulder_near: Node2D
var _shoulder_far: Node2D
var _hip_near: Node2D
var _hip_far: Node2D
var _weapon_anchor: Node2D
var _weapon_animator: CombatWeaponAnimator
var _outline_material: ShaderMaterial
var _body_parts: Array[Sprite2D] = []
var _base_rotations: Dictionary = {}
var _pose_tween: Tween
var _stance_position := Vector2.ZERO
var _stance_rotation := 0.0

func _ready() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = COLOR_SHADER
	_build_body()
	set_side("player")

func set_side(side: String) -> void:
	var color := PLAYER_COLOR if side == "player" else ENEMY_COLOR
	_outline_material.set_shader_parameter("silhouette_color", color)

func set_facing(direction: int) -> void:
	if _body_root:
		_body_root.scale.x = 1.0 if direction >= 0 else -1.0

func show_combatant(data: Dictionary) -> void:
	if not _body_root:
		return
	_weapon_animator.set_profile(_weapon_profile(data))
	_apply_stance(str(data.get("stance_state", "PLANTED")))

func play_action(action: int) -> void:
	if not _body_root:
		return
	match action:
		GameEnums.ActionType.MOVE_FORWARD, GameEnums.ActionType.MOVE_BACKWARD:
			_play_step()
		GameEnums.ActionType.CHARGE:
			_play_lunge(32.0)
		GameEnums.ActionType.SHOOT, GameEnums.ActionType.AIMED_SHOT:
			_weapon_animator.play_event("fire")
			_play_recoil()
		GameEnums.ActionType.RELOAD:
			_weapon_animator.play_event("reload")
			_play_reload_pose()
		GameEnums.ActionType.CYCLE:
			_weapon_animator.play_event("cycle")
			_play_reload_pose()
		GameEnums.ActionType.STRIKE:
			_play_arm_action(-0.8)
		GameEnums.ActionType.GRAPPLE, GameEnums.ActionType.BREAK:
			_play_arm_action(-0.45)
		GameEnums.ActionType.PUSH_STAY, GameEnums.ActionType.PUSH_FOLLOW:
			_play_lunge(24.0)
		GameEnums.ActionType.PULL_FOLLOW:
			_play_lunge(-18.0)
		GameEnums.ActionType.DISENGAGE:
			_play_lunge(-28.0)

func get_body_part_names() -> PackedStringArray:
	var names := PackedStringArray()
	for part in _body_parts:
		names.append(part.name)
	return names

func get_weapon_profile() -> String:
	return _weapon_animator.get_profile() if _weapon_animator else "unarmed"

func get_weapon_event() -> String:
	return _weapon_animator.get_current_event() if _weapon_animator else "idle"

func has_weapon_animation(event_name: String) -> bool:
	return _weapon_animator != null and _weapon_animator.has_animation(event_name)

func has_weapon_fx(event_name: String) -> bool:
	return _weapon_animator != null and _weapon_animator.has_fx_animation(
		event_name
	)

func _build_body() -> void:
	_body_root = Node2D.new()
	_body_root.name = "BodyRoot"
	add_child(_body_root)

	_pelvis = _joint(_body_root, "Pelvis", Vector2(0.0, -350.0))

	_hip_far = _joint(_pelvis, "HipFar", Vector2(-42.0, -4.0), -0.10)
	_add_part(_hip_far, "thigh_far", Vector2(2.0, 102.0), -4)
	var knee_far := _joint(_hip_far, "KneeFar", Vector2(4.0, 180.0), 0.06)
	_add_part(knee_far, "shin_far", Vector2(0.0, 100.0), -4)
	var ankle_far := _joint(knee_far, "AnkleFar", Vector2(2.0, 175.0), 0.0)
	_add_part(ankle_far, "foot_far", Vector2(42.0, 34.0), -4)

	_hip_near = _joint(_pelvis, "HipNear", Vector2(45.0, -2.0), 0.08)
	_add_part(_hip_near, "thigh_near", Vector2(0.0, 104.0), 4)
	var knee_near := _joint(_hip_near, "KneeNear", Vector2(2.0, 184.0), -0.04)
	_add_part(knee_near, "shin_near", Vector2(0.0, 100.0), 4)
	var ankle_near := _joint(knee_near, "AnkleNear", Vector2(0.0, 177.0), 0.0)
	_add_part(ankle_near, "foot_near", Vector2(45.0, 34.0), 4)

	_add_part(_pelvis, "torso", Vector2(0.0, -160.0), 0)
	var neck := _joint(_pelvis, "Neck", Vector2(12.0, -318.0), 0.0)
	_add_part(neck, "head", Vector2(9.0, -80.0), 1)

	_shoulder_far = _joint(
		_pelvis, "ShoulderFar", Vector2(-58.0, -246.0), -0.92
	)
	_add_part(_shoulder_far, "upper_arm_far", Vector2(0.0, 92.0), -3)
	var elbow_far := _joint(
		_shoulder_far, "ElbowFar", Vector2(0.0, 164.0), 0.42
	)
	_add_part(elbow_far, "lower_arm_far", Vector2(0.0, 74.0), -3)
	var wrist_far := _joint(elbow_far, "WristFar", Vector2(0.0, 137.0), 0.0)
	_add_part(wrist_far, "hand_far", Vector2(0.0, 38.0), -3)

	_weapon_anchor = _joint(
		_pelvis, "WeaponAnchor", Vector2(84.0, -185.0), -0.05
	)
	_weapon_animator = WEAPON_ANIMATOR.new() as CombatWeaponAnimator
	_weapon_animator.name = "WeaponAnimator"
	_weapon_animator.scale = Vector2(2.35, 2.35)
	_weapon_anchor.add_child(_weapon_animator)
	_weapon_anchor.z_index = 2

	_shoulder_near = _joint(
		_pelvis, "ShoulderNear", Vector2(64.0, -238.0), -0.72
	)
	_add_part(_shoulder_near, "upper_arm_near", Vector2(0.0, 104.0), 3)
	var elbow_near := _joint(
		_shoulder_near, "ElbowNear", Vector2(0.0, 185.0), 0.54
	)
	_add_part(elbow_near, "lower_arm_near", Vector2(0.0, 74.0), 3)
	var wrist_near := _joint(
		elbow_near, "WristNear", Vector2(0.0, 137.0), 0.0
	)
	_add_part(wrist_near, "hand_near", Vector2(0.0, 38.0), 3)

	for joint in _all_pose_joints():
		_base_rotations[joint.name] = joint.rotation

func _joint(
	parent: Node,
	joint_name: String,
	joint_position: Vector2,
	joint_rotation: float = 0.0
) -> Node2D:
	var joint := Node2D.new()
	joint.name = joint_name
	joint.position = joint_position
	joint.rotation = joint_rotation
	parent.add_child(joint)
	return joint

func _add_part(
	joint: Node2D,
	part_name: String,
	part_offset: Vector2,
	part_z: int
) -> void:
	var texture := load(PART_ROOT + part_name + ".png") as Texture2D
	if texture == null:
		push_warning("Missing modular body part: " + part_name)
		return

	var outline := Sprite2D.new()
	outline.name = part_name + "_outline"
	outline.texture = texture
	outline.position = part_offset
	outline.scale = Vector2(1.045, 1.045)
	outline.material = _outline_material
	outline.z_index = part_z
	outline.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	joint.add_child(outline)

	var part := Sprite2D.new()
	part.name = part_name
	part.texture = texture
	part.position = part_offset
	part.z_index = part_z + 1
	part.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	part.add_to_group("combat_body_part")
	joint.add_child(part)
	_body_parts.append(part)

func _weapon_profile(data: Dictionary) -> String:
	var weapon_id := str(data.get("weapon_id", "")).to_lower()
	var weapon_class := str(data.get("weapon_class", "NONE")).to_upper()
	if "shotgun" in weapon_id:
		return "shotgun"
	if "assault" in weapon_id or "automatic" in weapon_id:
		return "assault"
	if (
		"kar98" in weapon_id
		or "sniper" in weapon_id
		or "bolt" in weapon_id
	):
		return "kar98"
	if weapon_class == "PISTOL":
		return "pistol"
	if weapon_class == "RIFLE":
		return "kar98"
	return "unarmed"

func _apply_stance(stance_state: String) -> void:
	match stance_state:
		"FELLED":
			_stance_position = Vector2(26.0, -18.0)
			_stance_rotation = deg_to_rad(84.0)
		"STUMBLING":
			_stance_position = Vector2.ZERO
			_stance_rotation = deg_to_rad(7.0)
		_:
			_stance_position = Vector2.ZERO
			_stance_rotation = 0.0
	if not _pose_tween or not _pose_tween.is_running():
		_body_root.position = _stance_position
		_body_root.rotation = _stance_rotation

func _play_step() -> void:
	_reset_pose_tween()
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_QUAD)
	_pose_tween.tween_property(
		_hip_near, "rotation",
		float(_base_rotations["HipNear"]) - 0.32, 0.10
	)
	_pose_tween.parallel().tween_property(
		_hip_far, "rotation",
		float(_base_rotations["HipFar"]) + 0.28, 0.10
	)
	_pose_tween.tween_property(
		_hip_near, "rotation",
		float(_base_rotations["HipNear"]), 0.14
	)
	_pose_tween.parallel().tween_property(
		_hip_far, "rotation",
		float(_base_rotations["HipFar"]), 0.14
	)

func _play_recoil() -> void:
	_reset_pose_tween()
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_QUAD)
	_pose_tween.tween_property(
		_weapon_anchor, "position", Vector2(68.0, -185.0), 0.06
	)
	_pose_tween.parallel().tween_property(
		_body_root, "position", _stance_position + Vector2(-9.0, 0.0), 0.06
	)
	_pose_tween.tween_property(
		_weapon_anchor, "position", Vector2(84.0, -185.0), 0.14
	)
	_pose_tween.parallel().tween_property(
		_body_root, "position", _stance_position, 0.14
	)

func _play_reload_pose() -> void:
	_play_arm_action(0.38)

func _play_arm_action(delta_rotation: float) -> void:
	_reset_pose_tween()
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_QUAD)
	_pose_tween.tween_property(
		_shoulder_near,
		"rotation",
		float(_base_rotations["ShoulderNear"]) + delta_rotation,
		0.12
	)
	_pose_tween.parallel().tween_property(
		_shoulder_far,
		"rotation",
		float(_base_rotations["ShoulderFar"]) + delta_rotation * 0.65,
		0.12
	)
	_pose_tween.tween_property(
		_shoulder_near,
		"rotation",
		float(_base_rotations["ShoulderNear"]),
		0.22
	)
	_pose_tween.parallel().tween_property(
		_shoulder_far,
		"rotation",
		float(_base_rotations["ShoulderFar"]),
		0.22
	)

func _play_lunge(distance: float) -> void:
	_reset_pose_tween()
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_QUAD)
	_pose_tween.tween_property(
		_body_root, "position",
		_stance_position + Vector2(distance, 0.0), 0.10
	)
	_pose_tween.tween_property(
		_body_root, "position", _stance_position, 0.16
	)

func _reset_pose_tween() -> void:
	if _pose_tween and _pose_tween.is_running():
		_pose_tween.kill()
	_body_root.position = _stance_position
	_body_root.rotation = _stance_rotation
	_weapon_anchor.position = Vector2(84.0, -185.0)
	for joint in _all_pose_joints():
		joint.rotation = float(_base_rotations.get(joint.name, joint.rotation))

func _all_pose_joints() -> Array[Node2D]:
	return [_shoulder_near, _shoulder_far, _hip_near, _hip_far]
