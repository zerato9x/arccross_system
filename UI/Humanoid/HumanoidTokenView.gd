extends Node2D
class_name HumanoidTokenView

## Record-driven humanoid token presentation. Appearance comes from neutral
## entity records or pre-built appearance dictionaries only.

signal footstep_taken
signal animation_finished(animation: String)

var _appearance: Dictionary = {}
var _layer_directories: Array[String] = []
var _layer_sprites: Array[Sprite2D] = []
var _layer_pool: Array[Sprite2D] = []
var _animation := "Idle"
var _direction_row := 2
var _frame_index := 0
var _frame_time := 0.0
var _animation_speed_scale := 1.0
var _display_scale := 2.4
var _appearance_record: Dictionary = {}
var _static_sprite_sheet_path := ""
var _return_animation := "Idle"
var _return_animation_speed_scale := 1.0
var _animation_completion_emitted := false
var _suppress_equipment_layers := false

func _ready() -> void:
	for child in $Layers.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		sprite.centered = true
		sprite.hframes = HumanoidVisualCatalog.FRAME_COLUMNS
		sprite.vframes = HumanoidVisualCatalog.DIRECTION_ROWS
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * _display_scale
		sprite.visible = false
		_layer_pool.append(sprite)

	set_process(true)
	if _appearance.is_empty():
		set_appearance(
			HumanoidVisualCatalog.appearance_from_slot_item_ids({})
		)
	else:
		_rebuild_layers()

func bind_appearance_record(record: Dictionary) -> void:
	_appearance_record = record.duplicate(true)
	refresh_from_record()


func refresh_from_record(record: Dictionary = {}) -> void:
	if not record.is_empty():
		_appearance_record = record.duplicate(true)
	if _appearance_record.is_empty():
		return
	set_appearance(
		HumanoidVisualCatalog.appearance_from_record(_appearance_record)
	)


func set_slot_item_ids(slot_item_ids: Dictionary) -> void:
	set_appearance(
		HumanoidVisualCatalog.appearance_from_slot_item_ids(slot_item_ids)
	)

func set_appearance(appearance: Dictionary) -> void:
	_static_sprite_sheet_path = ""
	var signature := str(appearance.get("signature", ""))
	if signature == str(_appearance.get("signature", "")):
		return
	_appearance = appearance.duplicate(true)
	_layer_directories = HumanoidVisualCatalog.layer_directories(
		_appearance
	)
	_rebuild_layers()


## Unique actors can use a standard 8x11 generated token sheet while systemic
## NPCs keep the composited equipment rig. Both modes share animation timing.
func set_static_sprite_sheet(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_static_sprite_sheet_path = path
	_appearance = {"signature": "static:" + path}
	_layer_directories.clear()
	_rebuild_layers()

func set_display_scale(value: float) -> void:
	_display_scale = maxf(0.1, value)
	for sprite in _layer_pool:
		sprite.scale = Vector2.ONE * _display_scale


func get_display_scale() -> float:
	return _display_scale


func combat_overhead_anchor() -> Vector2:
	# Resolve the currently rendered layers instead of assuming a particular
	# sprite height. Static sheets, equipment compositions, and display scaling
	# therefore share one stable actor-local overhead contract.
	var top := INF
	for sprite in _layer_sprites:
		if not sprite.visible or sprite.texture == null:
			continue
		var rect := sprite.get_rect()
		top = minf(top, sprite.position.y + rect.position.y * sprite.scale.y)
	if is_inf(top):
		top = -float(HumanoidVisualCatalog.FRAME_SIZE.y) * 0.5 * _display_scale
	return Vector2(0.0, top)


func combat_visual_bounds() -> Rect2:
	var result := Rect2()
	var initialized := false
	for sprite in _layer_sprites:
		if not sprite.visible or sprite.texture == null:
			continue
		var source := sprite.get_rect()
		var scaled := Rect2(
			sprite.position + source.position * sprite.scale,
			source.size * sprite.scale.abs()
		)
		result = result.merge(scaled) if initialized else scaled
		initialized = true
	if not initialized:
		var fallback := Vector2(HumanoidVisualCatalog.FRAME_SIZE) * _display_scale
		result = Rect2(-fallback * 0.5, fallback)
	return result


func combat_head_top_anchor() -> Vector2:
	return combat_overhead_anchor()


func combat_weapon_muzzle_anchor(weapon_id: String) -> Vector2:
	var normalized := HumanoidVisualCatalog.weapon_muzzle_anchor_for_item(weapon_id, _direction_row)
	if normalized.x < 0.0 or normalized.y < 0.0:
		push_warning("Missing token muzzle profile for firearm '%s'." % weapon_id)
		normalized = _fallback_weapon_muzzle_anchor()
	var frame_size := Vector2(HumanoidVisualCatalog.FRAME_SIZE)
	return (normalized * frame_size - frame_size * 0.5) * _display_scale


func combat_body_region_anchor(region: int) -> Vector2:
	var normalized := Vector2(0.5, 0.43)
	match region:
		GameEnums.LimbRegion.HEAD:
			normalized = Vector2(0.5, 0.27)
		GameEnums.LimbRegion.UPPER_TORSO:
			normalized = Vector2(0.5, 0.43)
		GameEnums.LimbRegion.LOWER_TORSO:
			normalized = Vector2(0.5, 0.56)
		GameEnums.LimbRegion.LEFT_ARM:
			normalized = Vector2(0.38, 0.45)
		GameEnums.LimbRegion.RIGHT_ARM:
			normalized = Vector2(0.62, 0.45)
		GameEnums.LimbRegion.LEFT_LEG:
			normalized = Vector2(0.43, 0.72)
		GameEnums.LimbRegion.RIGHT_LEG:
			normalized = Vector2(0.57, 0.72)
	var frame_size := Vector2(HumanoidVisualCatalog.FRAME_SIZE)
	return (normalized * frame_size - frame_size * 0.5) * _display_scale


func _fallback_weapon_muzzle_anchor() -> Vector2:
	var anchors := [
		Vector2(0.74, 0.43), Vector2(0.68, 0.59), Vector2(0.5, 0.7), Vector2(0.32, 0.59),
		Vector2(0.26, 0.43), Vector2(0.34, 0.3), Vector2(0.5, 0.24), Vector2(0.66, 0.3),
	]
	return anchors[posmod(_direction_row, anchors.size())]


func set_action_equipment_suppressed(value: bool) -> void:
	_suppress_equipment_layers = value
	_apply_frame()

func set_animation_speed(scale: float) -> void:
	_animation_speed_scale = maxf(0.1, scale)

const TIMED_ONE_SHOT_MIN_SPEED := 0.75
const TIMED_ONE_SHOT_MAX_SPEED := 1.25

func get_animation_duration(animation: String) -> float:
	if not HumanoidVisualCatalog.supports_animation(animation):
		return 0.0
	return (
		float(HumanoidVisualCatalog.animation_frames(animation))
		/ maxf(0.01, HumanoidVisualCatalog.animation_fps(animation))
	)

## Resolves the wall-clock duration a timed one-shot will actually occupy after
## stretch clamping. Prefer readable frame density over meeting an aggressive
## authored clock: speeds stay within [0.75x, 1.25x] of nominal.
func resolve_timed_one_shot_duration(
	animation: String,
	target_duration: float
) -> float:
	var nominal_duration := get_animation_duration(animation)
	if nominal_duration <= 0.0:
		return 0.0
	var safe_target := maxf(0.05, target_duration)
	var requested_speed := nominal_duration / safe_target
	var clamped_speed := clampf(
		requested_speed,
		TIMED_ONE_SHOT_MIN_SPEED,
		TIMED_ONE_SHOT_MAX_SPEED
	)
	return nominal_duration / clamped_speed

## Plays every visible frame across the resolved presentation duration. Stretch
## is clamped so short turn windows cannot crush 15-frame clips into a blur and
## long windows cannot float 5-frame attacks in slow motion.
func play_timed_one_shot(
	animation: String,
	return_animation: String,
	target_duration: float
) -> bool:
	if HumanoidVisualCatalog.animation_loops(animation):
		return false
	var nominal_duration := get_animation_duration(animation)
	if nominal_duration <= 0.0:
		return false
	var actual_duration := resolve_timed_one_shot_duration(
		animation,
		target_duration
	)
	_return_animation_speed_scale = 1.0
	set_animation_speed(nominal_duration / maxf(0.05, actual_duration))
	return play_animation(animation, true, return_animation)

func play_animation(
	animation: String,
	restart: bool = true,
	return_animation: String = ""
) -> bool:
	if not HumanoidVisualCatalog.supports_animation(animation):
		return false
	if _animation == animation and not restart:
		if not return_animation.is_empty():
			set_return_animation(return_animation)
		return true

	_animation = animation
	_animation_completion_emitted = false
	if not return_animation.is_empty():
		set_return_animation(return_animation)
	elif HumanoidVisualCatalog.animation_loops(animation):
		_return_animation = animation
	_frame_index = 0
	_frame_time = 0.0
	_refresh_textures()
	_apply_frame()
	return true

func play_one_shot(animation: String, return_animation: String) -> bool:
	if HumanoidVisualCatalog.animation_loops(animation):
		return false
	return play_animation(animation, true, return_animation)

func set_return_animation(animation: String) -> void:
	if HumanoidVisualCatalog.supports_animation(animation):
		_return_animation = animation

func is_playing_one_shot() -> bool:
	return not HumanoidVisualCatalog.animation_loops(_animation)

func get_animation() -> String:
	return _animation

func has_animation_finished(animation: String = "") -> bool:
	var requested := animation if not animation.is_empty() else _animation
	return _animation == requested and _animation_completion_emitted

func get_direction_row() -> int:
	return _direction_row

func get_frame_index() -> int:
	return _frame_index

func get_appearance_signature() -> String:
	return str(_appearance.get("signature", ""))

func set_direction_row(row: int) -> void:
	_direction_row = posmod(row, HumanoidVisualCatalog.DIRECTION_ROWS)
	_apply_layer_depth()
	_apply_frame()

func face_direction(direction: Vector2) -> void:
	if direction.length_squared() <= 0.001:
		return
	set_direction_row(
		HumanoidVisualCatalog.direction_row_for_vector(direction)
	)

func _process(delta: float) -> void:
	if _layer_sprites.is_empty():
		return

	_frame_time += delta * _animation_speed_scale
	var fps := HumanoidVisualCatalog.animation_fps(_animation)
	var max_frames := HumanoidVisualCatalog.animation_frames(_animation)
	var next_frame := int(floor(_frame_time * fps))
	if HumanoidVisualCatalog.animation_loops(_animation):
		next_frame = posmod(
			next_frame,
			max_frames
		)
	elif next_frame >= max_frames:
		if _animation == "Die":
			next_frame = max_frames - 1
			_emit_animation_finished(_animation)
		else:
			var finished_animation := _animation
			_emit_animation_finished(finished_animation)
			set_animation_speed(_return_animation_speed_scale)
			play_animation(_return_animation)
			return

	if next_frame != _frame_index:
		_frame_index = next_frame
		if _animation in ["Run", "RunBackwards", "CrouchRun", "Walk"]:
			if _frame_index == 1 or _frame_index == 7:
				footstep_taken.emit()
		_apply_frame()

func _emit_animation_finished(animation: String) -> void:
	if _animation_completion_emitted:
		return
	_animation_completion_emitted = true
	animation_finished.emit(animation)

func _rebuild_layers() -> void:
	_layer_sprites.clear()

	var requested_layer_count := 1 if not _static_sprite_sheet_path.is_empty() else _layer_directories.size()
	if requested_layer_count > _layer_pool.size():
		push_warning(
			"Humanoid Token needs %d layers but its scene pool contains %d."
			% [requested_layer_count, _layer_pool.size()]
		)

	for index in range(_layer_pool.size()):
		var sprite := _layer_pool[index]
		var active := index < requested_layer_count
		sprite.visible = active
		if active:
			_layer_sprites.append(sprite)
		else:
			sprite.texture = null
	_refresh_textures()
	_apply_layer_depth()
	_apply_frame()

func _refresh_textures() -> void:
	if not _static_sprite_sheet_path.is_empty():
		if not _layer_sprites.is_empty():
			_layer_sprites[0].texture = EntityProjectionAssets.texture(_static_sprite_sheet_path)
		return
	for index in range(_layer_sprites.size()):
		var texture_path := HumanoidVisualCatalog.texture_path(
			_layer_directories[index],
			_animation
		)
		_layer_sprites[index].texture = EntityProjectionAssets.texture(
			texture_path
		)

func _apply_frame() -> void:
	var sheet_frame := (
		_direction_row * HumanoidVisualCatalog.FRAME_COLUMNS
		+ _frame_index
	)
	for index in range(_layer_sprites.size()):
		var sprite := _layer_sprites[index]
		var directory := _layer_directories[index] if index < _layer_directories.size() else ""
		var layer_frames := HumanoidVisualCatalog.animation_frames_for_layer(_animation, directory)
		sprite.visible = not _suppress_equipment_layers or "/weapons/" not in directory
		sprite.frame = _direction_row * HumanoidVisualCatalog.FRAME_COLUMNS + mini(_frame_index, layer_frames - 1)

func _apply_layer_depth() -> void:
	for index in range(_layer_sprites.size()):
		_layer_sprites[index].z_index = HumanoidVisualCatalog.layer_depth(
			_layer_directories[index],
			_direction_row
		)
