extends Node2D
class_name CombatActorFloatHUD

const SIDE_PLAYER := "player"
const SIDE_ENEMY := "enemy"
const PANEL_SIZE := Vector2(250.0, 168.0)
const DETAIL_SIZE := Vector2(250.0, 104.0)
const COLOR_PANEL := Color(0.09, 0.10, 0.08, 0.92)
const COLOR_BORDER := Color(0.73, 0.62, 0.45, 0.9)
const COLOR_DANGER := Color(0.72, 0.28, 0.24, 1.0)
const COLOR_OK := Color(0.62, 0.63, 0.46, 1.0)
const COLOR_DAMAGED := Color(0.88, 0.58, 0.22, 1.0)
const LIMB_ASSET_NAMES := {
	"HD": "head",
	"UT": "upper_torso",
	"LT": "lower_torso",
	"LA": "left_arm",
	"RA": "right_arm",
	"LL": "left_leg",
	"RL": "right_leg",
}

var _actor_data: Dictionary = {}
var _side := SIDE_PLAYER
var _expanded := false
var _targeted_limb := -1
var _target_local := Vector2.ZERO
var _anchor_global := Vector2.ZERO
var _viewport_origin := Vector2.ZERO
var _viewport_size := Vector2(1280.0, 720.0)
var _camera_zoom := 1.0
var _fixed_layout := false
var _fixed_position := Vector2.ZERO
var _fixed_scale := 1.0

@onready var _panel_box: Polygon2D = %PanelBox
@onready var _border: Line2D = %Border
@onready var _pointer: Line2D = %Pointer
@onready var _pointer_triangle: Polygon2D = %PointerTriangle
@onready var _doll_plate: Polygon2D = %DollPlate
@onready var _limb_doll: Node2D = %LimbDoll
@onready var _target_reticle: Line2D = %TargetReticle
@onready var _detail_box: Polygon2D = %DetailBox
@onready var _hover_area: Area2D = %HoverArea
@onready var _collision_shape: CollisionShape2D = %CollisionShape2D
@onready var _name_label: Label = %NameLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _limb_strip_label: Label = %LimbStripLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _limb_markers: Node2D = %LimbMarkers

var _limb_sprites: Dictionary = {}

func _ready() -> void:
	_apply_geometry()
	_hover_area.input_pickable = true
	_hover_area.mouse_entered.connect(_set_expanded.bind(true))
	_hover_area.mouse_exited.connect(_set_expanded.bind(false))
	_detail_box.visible = false
	_detail_label.visible = false
	visible = false

func set_actor(
	actor_data: Dictionary,
	side: String,
	anchor_global: Vector2,
	viewport_size: Vector2,
	viewport_origin: Vector2 = Vector2.ZERO,
	camera_zoom: float = 1.0
) -> void:
	_actor_data = actor_data.duplicate(true)
	_side = side
	_anchor_global = anchor_global
	_viewport_origin = viewport_origin
	_viewport_size = viewport_size
	_camera_zoom = maxf(0.01, camera_zoom)
	_fixed_layout = false
	visible = not _actor_data.is_empty()
	if not visible:
		return

	_pointer.visible = true
	_pointer_triangle.visible = true
	_refresh_content()
	var height := PANEL_SIZE.y + (DETAIL_SIZE.y if _expanded else 0.0)
	var inverse_zoom := 1.0 / _camera_zoom
	scale = Vector2.ONE * inverse_zoom
	var world_viewport_size := viewport_size * inverse_zoom
	var is_left_side := anchor_global.x < (
		viewport_origin.x + world_viewport_size.x * 0.5
	)
	var x_offset := (
		-PANEL_SIZE.x * 0.24
		if is_left_side
		else -PANEL_SIZE.x * 0.76
	) * inverse_zoom
	# Player panel floats above the lane, enemy panel drops below it so the two
	# readouts never overlap on the same row.
	var y_offset := (
		46.0 * inverse_zoom
		if _side == SIDE_ENEMY
		else (-height - 46.0) * inverse_zoom
	)
	var target := anchor_global + Vector2(x_offset, y_offset)
	var margin := 18.0 * inverse_zoom
	target.x = clampf(
		target.x,
		viewport_origin.x + margin,
		maxf(
			viewport_origin.x + margin,
			viewport_origin.x
				+ world_viewport_size.x
				- PANEL_SIZE.x * inverse_zoom
				- margin
		)
	)
	target.y = clampf(
		target.y,
		viewport_origin.y + margin,
		maxf(
			viewport_origin.y + margin,
			viewport_origin.y
				+ world_viewport_size.y
				- height * inverse_zoom
				- margin
		)
	)
	global_position = target
	_target_local = to_local(anchor_global)
	_refresh_pointer()

func set_fixed_actor(
	actor_data: Dictionary,
	side: String,
	panel_position: Vector2,
	panel_scale: float = 1.0
) -> void:
	_actor_data = actor_data.duplicate(true)
	_side = side
	_fixed_layout = true
	_fixed_position = panel_position
	_fixed_scale = maxf(0.01, panel_scale)
	visible = not _actor_data.is_empty()
	if not visible:
		return

	_pointer.visible = false
	_pointer_triangle.visible = false
	_refresh_content()
	scale = Vector2.ONE * _fixed_scale
	global_position = _fixed_position

func set_targeted_limb(limb: int) -> void:
	_targeted_limb = limb
	_refresh_targeting()
	_refresh_limb_strip()

func clear_targeted_limb() -> void:
	if _targeted_limb < 0:
		return
	_targeted_limb = -1
	_refresh_targeting()
	_refresh_limb_strip()

func _apply_geometry() -> void:
	_set_box(_panel_box, PANEL_SIZE, Vector2.ZERO)
	_panel_box.color = COLOR_PANEL
	_set_outline(_border, PANEL_SIZE, Vector2.ZERO)
	_set_box(_doll_plate, Vector2(78.0, 118.0), Vector2(12.0, 36.0))
	_doll_plate.color = Color(0.08, 0.085, 0.07, 0.96)
	for code in LIMB_ASSET_NAMES:
		var limb_sprite := _limb_doll.get_node_or_null(code) as Sprite2D
		if limb_sprite == null:
			continue
		_limb_sprites[code] = limb_sprite
		limb_sprite.texture = HUDAssetLibrary.texture(
			"res://Asset/UI/HUD/medical/limb_%s_64.png"
			% str(LIMB_ASSET_NAMES[code])
		)
		limb_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_target_reticle.width = 1.5
	_target_reticle.default_color = HUDAssetLibrary.COLOR_CAUTION
	_target_reticle.visible = false
	_set_box(_detail_box, DETAIL_SIZE, Vector2(0.0, PANEL_SIZE.y + 8.0))
	_detail_box.color = Color(0.08, 0.075, 0.06, 0.94)
	var shape := RectangleShape2D.new()
	shape.size = PANEL_SIZE + Vector2(0.0, DETAIL_SIZE.y)
	_collision_shape.shape = shape
	_collision_shape.position = Vector2(PANEL_SIZE.x * 0.5, (PANEL_SIZE.y + DETAIL_SIZE.y) * 0.5)

func _refresh_content() -> void:
	var side_label := "YOU" if _side == SIDE_PLAYER else "HOSTILE"
	_name_label.text = "%s // %s" % [
		side_label,
		str(_actor_data.get("archetype", _actor_data.get("name", "UNKNOWN"))).to_upper(),
	]
	_name_label.modulate = COLOR_OK if _side == SIDE_PLAYER else COLOR_DANGER
	_summary_label.text = (
		"BLOOD %04.1f  STANCE %02d/12\n"
		+ "AP-R %02d  %s\n"
		+ "%s%s"
	) % [
		float(_actor_data.get("blood", 0.0)),
		int(_actor_data.get("stance", 0)),
		int(_actor_data.get("reserved_ap", 0)),
		str(_actor_data.get("stance_state", "UNKNOWN")),
		str(_actor_data.get("weapon", "UNARMED")).to_upper(),
		str(_actor_data.get("weapon_detail", "")),
	]
	var limbs: Array = _actor_data.get("limbs", [])
	_refresh_limb_strip(limbs)
	_detail_label.text = _limb_detail_text(limbs)
	_refresh_limb_markers(limbs)

func _refresh_limb_markers(limbs: Array) -> void:
	var by_code := {}
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		by_code[str(limb.get("code", ""))] = limb
	for marker in _limb_markers.get_children():
		var polygon := marker as Polygon2D
		if polygon == null:
			continue
		var limb: Dictionary = by_code.get(marker.name, {})
		var current := float(limb.get("current", 1.0))
		var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
		var trauma := str(limb.get("trauma", "NONE"))
		polygon.color = _limb_color(current, maximum, trauma)
	for code in _limb_sprites:
		var limb_sprite := _limb_sprites[code] as Sprite2D
		var limb: Dictionary = by_code.get(code, {})
		limb_sprite.modulate = _limb_color(
			float(limb.get("current", 0.0)),
			maxf(1.0, float(limb.get("maximum", 1.0))),
			str(limb.get("trauma", "NONE"))
		)
	_refresh_targeting()

func _refresh_limb_strip(limbs: Array = []) -> void:
	if _limb_strip_label == null:
		return
	var source_limbs: Array = limbs
	if source_limbs.is_empty():
		source_limbs = _actor_data.get("limbs", [])
	var warning := _limb_warning_strip(source_limbs)
	if _targeted_limb >= 0:
		_limb_strip_label.text = "AIM // %s\n%s" % [
			_limb_code(_targeted_limb),
			warning,
		]
		return
	_limb_strip_label.text = warning

func _refresh_targeting() -> void:
	if _target_reticle == null:
		return
	var code := _limb_code(_targeted_limb)
	var limb_sprite := _limb_sprites.get(code) as Sprite2D
	if _targeted_limb < 0 or limb_sprite == null or limb_sprite.texture == null:
		_target_reticle.visible = false
		return
	var texture_size := Vector2(
		float(limb_sprite.texture.get_width()),
		float(limb_sprite.texture.get_height())
	) * limb_sprite.scale
	var padding := Vector2(3.0, 3.0)
	var upper_left := limb_sprite.position - texture_size * 0.5 - padding
	var lower_right := limb_sprite.position + texture_size * 0.5 + padding
	_target_reticle.points = PackedVector2Array([
		upper_left,
		Vector2(lower_right.x, upper_left.y),
		lower_right,
		Vector2(upper_left.x, lower_right.y),
		upper_left,
	])
	_target_reticle.visible = true

func _limb_color(current: float, maximum: float, trauma: String) -> Color:
	var ratio := current / maxf(1.0, maximum)
	if current <= 0.0 or trauma == "SHATTERED_LIMB":
		return Color(0.78, 0.18, 0.25, 1.0)
	if trauma != "NONE" or ratio <= 0.35:
		return COLOR_DANGER
	if ratio <= 0.70:
		return COLOR_DAMAGED
	return HUDAssetLibrary.COLOR_NORMAL

func _set_expanded(value: bool) -> void:
	_expanded = value
	_detail_box.visible = _expanded
	_detail_label.visible = _expanded
	if visible:
		if _fixed_layout:
			set_fixed_actor(
				_actor_data,
				_side,
				_fixed_position,
				_fixed_scale
			)
		else:
			set_actor(
				_actor_data,
				_side,
				_anchor_global,
				_viewport_size,
				_viewport_origin,
				_camera_zoom
			)

func _refresh_pointer() -> void:
	var panel_anchor := (
		Vector2(PANEL_SIZE.x * 0.5, 2.0)
		if _side == SIDE_ENEMY
		else Vector2(PANEL_SIZE.x * 0.5, PANEL_SIZE.y - 2.0)
	)
	_pointer.points = PackedVector2Array([panel_anchor, _target_local])
	_pointer.default_color = Color(COLOR_BORDER, 0.7)
	var direction := (_target_local - panel_anchor).normalized()
	if direction.length_squared() <= 0.0:
		direction = Vector2.DOWN
	var base := _target_local - direction * 16.0
	var tangent := Vector2(-direction.y, direction.x)
	_pointer_triangle.polygon = PackedVector2Array([
		_target_local,
		base + tangent * 8.0,
		base - tangent * 8.0,
	])
	_pointer_triangle.color = Color(COLOR_BORDER, 0.72)

func _limb_warning_strip(limbs: Array) -> String:
	var warnings := PackedStringArray()
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		var current := float(limb.get("current", 0.0))
		var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
		var trauma := str(limb.get("trauma", "NONE"))
		if current / maximum <= 0.35 or trauma != "NONE":
			warnings.append("%s%s" % [str(limb.get("code", "??")), "!" if trauma != "NONE" else ""])
	if warnings.is_empty():
		return "LIMBS STABLE"
	return "DANGER " + "  ".join(warnings)

func _limb_code(limb: int) -> String:
	match limb:
		GameEnums.LimbRegion.HEAD:
			return "HD"
		GameEnums.LimbRegion.UPPER_TORSO:
			return "UT"
		GameEnums.LimbRegion.LOWER_TORSO:
			return "LT"
		GameEnums.LimbRegion.LEFT_ARM:
			return "LA"
		GameEnums.LimbRegion.RIGHT_ARM:
			return "RA"
		GameEnums.LimbRegion.LEFT_LEG:
			return "LL"
		GameEnums.LimbRegion.RIGHT_LEG:
			return "RL"
	return ""

func _limb_detail_text(limbs: Array) -> String:
	if limbs.is_empty():
		return "NO LIMB SIGNAL"
	var rows := PackedStringArray()
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		rows.append("%s  %s/%s  %s" % [
			str(limb.get("code", "??")),
			_compact_number(float(limb.get("current", 0.0))),
			_compact_number(float(limb.get("maximum", 0.0))),
			str(limb.get("trauma", "NONE")),
		])
	return "\n".join(rows)

func _compact_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _set_box(polygon: Polygon2D, box_size: Vector2, offset: Vector2) -> void:
	polygon.polygon = PackedVector2Array([
		offset,
		offset + Vector2(box_size.x, 0.0),
		offset + box_size,
		offset + Vector2(0.0, box_size.y),
	])

func _set_outline(line: Line2D, box_size: Vector2, offset: Vector2) -> void:
	line.points = PackedVector2Array([
		offset,
		offset + Vector2(box_size.x, 0.0),
		offset + box_size,
		offset + Vector2(0.0, box_size.y),
		offset,
	])
	line.default_color = COLOR_BORDER
	line.width = 1.5
