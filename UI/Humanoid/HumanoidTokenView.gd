extends Node2D
class_name HumanoidTokenView

var _appearance: Dictionary = {}
var _layer_directories: Array[String] = []
var _layer_sprites: Array[Sprite2D] = []
var _layer_pool: Array[Sprite2D] = []
var _animation := "Idle"
var _direction_row := 2
var _frame_index := 0
var _frame_time := 0.0
var _display_scale := 2.4
var _bound_inventory: InventorySystem
var _return_animation := "Idle"

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

func bind_inventory(inventory: InventorySystem) -> void:
	if (
		_bound_inventory != null
		and _bound_inventory.equipment_changed.is_connected(
			_on_equipment_changed
		)
	):
		_bound_inventory.equipment_changed.disconnect(
			_on_equipment_changed
		)

	_bound_inventory = inventory
	if (
		_bound_inventory != null
		and not _bound_inventory.equipment_changed.is_connected(
			_on_equipment_changed
		)
	):
		_bound_inventory.equipment_changed.connect(
			_on_equipment_changed
		)
	refresh_from_inventory()

func refresh_from_inventory() -> void:
	if _bound_inventory == null:
		return
	set_appearance(
		HumanoidVisualCatalog.appearance_from_inventory(_bound_inventory)
	)

func set_appearance(appearance: Dictionary) -> void:
	var signature := str(appearance.get("signature", ""))
	if signature == str(_appearance.get("signature", "")):
		return
	_appearance = appearance.duplicate(true)
	_layer_directories = HumanoidVisualCatalog.layer_directories(
		_appearance
	)
	_rebuild_layers()

func set_display_scale(value: float) -> void:
	_display_scale = maxf(0.1, value)
	for sprite in _layer_pool:
		sprite.scale = Vector2.ONE * _display_scale

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
	# Sheet rows follow screen-space clockwise order starting at right.
	set_direction_row(
		HumanoidVisualCatalog.direction_row_for_vector(direction)
	)

func _process(delta: float) -> void:
	if _layer_sprites.is_empty():
		return

	_frame_time += delta
	var fps := HumanoidVisualCatalog.animation_fps(_animation)
	var next_frame := int(floor(_frame_time * fps))
	if HumanoidVisualCatalog.animation_loops(_animation):
		next_frame = posmod(
			next_frame,
			HumanoidVisualCatalog.FRAME_COLUMNS
		)
	elif next_frame >= HumanoidVisualCatalog.FRAME_COLUMNS:
		if _animation == "Die":
			next_frame = HumanoidVisualCatalog.FRAME_COLUMNS - 1
		else:
			play_animation(_return_animation)
			return

	if next_frame != _frame_index:
		_frame_index = next_frame
		_apply_frame()

func _rebuild_layers() -> void:
	_layer_sprites.clear()

	if _layer_directories.size() > _layer_pool.size():
		push_warning(
			"Humanoid Token needs %d layers but its scene pool contains %d."
			% [_layer_directories.size(), _layer_pool.size()]
		)

	for index in range(_layer_pool.size()):
		var sprite := _layer_pool[index]
		var active := index < _layer_directories.size()
		sprite.visible = active
		if active:
			_layer_sprites.append(sprite)
		else:
			sprite.texture = null
	_refresh_textures()
	_apply_layer_depth()
	_apply_frame()

func _refresh_textures() -> void:
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
	for sprite in _layer_sprites:
		sprite.frame = sheet_frame

func _apply_layer_depth() -> void:
	for index in range(_layer_sprites.size()):
		_layer_sprites[index].z_index = HumanoidVisualCatalog.layer_depth(
			_layer_directories[index],
			_direction_row
		)

func _on_equipment_changed(
	_slot: GameEnums.EquipmentSlot,
	_item: ItemData
) -> void:
	refresh_from_inventory()
