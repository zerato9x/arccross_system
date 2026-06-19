extends RefCounted
class_name EntityProjectionAssets

static var _texture_cache: Dictionary = {}
static var _masked_texture_cache: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _texture_cache.has(path):
		_texture_cache[path] = (
			load(path) as Texture2D
			if ResourceLoader.exists(path)
			else null
		)
	return _texture_cache[path]

static func masked_texture(path: String, mask_rect: Rect2i) -> Texture2D:
	if path.is_empty():
		return null
	var cache_key := "%s|%d,%d,%d,%d" % [
		path,
		mask_rect.position.x,
		mask_rect.position.y,
		mask_rect.size.x,
		mask_rect.size.y,
	]
	if _masked_texture_cache.has(cache_key):
		return _masked_texture_cache[cache_key]

	var source_texture := texture(path)
	if source_texture == null:
		_masked_texture_cache[cache_key] = null
		return null

	var source := source_texture.get_image()
	var masked := Image.create(
		source.get_width(),
		source.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	masked.fill(Color.TRANSPARENT)
	masked.blit_rect(source, mask_rect, mask_rect.position)

	var texture := ImageTexture.create_from_image(masked)
	texture.resource_name = "%s#mask_%s" % [
		path.get_file().get_basename(),
		str(mask_rect),
	]
	_masked_texture_cache[cache_key] = texture
	return texture
