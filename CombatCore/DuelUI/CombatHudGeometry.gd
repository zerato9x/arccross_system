extends RefCounted
class_name CombatHudGeometry

static func compact_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

static func set_box(polygon: Polygon2D, box_size: Vector2) -> void:
	polygon.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(box_size.x, 0.0),
		box_size,
		Vector2(0.0, box_size.y),
	])

static func set_outline(line: Line2D, box_size: Vector2) -> void:
	line.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(box_size.x, 0.0),
		box_size,
		Vector2(0.0, box_size.y),
		Vector2.ZERO,
	])

static func camera_zoom_value(camera: Camera2D) -> float:
	if camera == null:
		return 1.0
	return maxf(0.01, camera.zoom.x)

static func screen_to_world(camera: Camera2D, screen_pos: Vector2, viewport_size: Vector2) -> Vector2:
	if camera == null:
		return screen_pos
	return (
		camera.global_position
		+ (screen_pos - viewport_size * 0.5) / camera_zoom_value(camera)
	)

static func layout_meter_frame(sprite: Sprite2D, size: Vector2, tint: Color) -> void:
	if sprite == null:
		return
	if sprite.texture == null:
		sprite.texture = HUDAssetLibrary.meter_frame_texture("segmented")
	sprite.visible = sprite.texture != null
	if not sprite.visible:
		return
	var texture_size := Vector2(
		float(sprite.texture.get_width()),
		float(sprite.texture.get_height())
	)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(
		size.x / maxf(1.0, texture_size.x),
		size.y / maxf(1.0, texture_size.y)
	)
	sprite.modulate = tint
