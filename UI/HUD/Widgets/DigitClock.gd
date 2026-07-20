extends HBoxContainer
class_name DigitClock

signal clock_changed(text: String)

var _digits: Array[TextureRect] = []
var _colon: TextureRect
var _last_text := ""
var _flip_tween: Tween


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	alignment = BoxContainer.ALIGNMENT_END
	_build_digits()
	set_clock_text("00:00", false)


func _build_digits() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_digits.clear()
	for _i in range(2):
		_digits.append(_make_digit())
	_colon = _make_slot(Vector2(8, 22))
	_colon.texture = HUDAssetLibrary.clock_colon_texture()
	add_child(_colon)
	for _i in range(2):
		_digits.append(_make_digit())


func _make_digit() -> TextureRect:
	var slot := _make_slot(Vector2(16, 22))
	add_child(slot)
	return slot


func _make_slot(min_size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = min_size
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func set_clock_text(text: String, animate: bool = true) -> void:
	var cleaned := text.strip_edges()
	if cleaned.length() < 5:
		cleaned = "00:00"
	var digits := [
		int(cleaned.substr(0, 1)),
		int(cleaned.substr(1, 1)),
		int(cleaned.substr(3, 1)),
		int(cleaned.substr(4, 1)),
	]
	for index in range(mini(4, _digits.size())):
		_digits[index].texture = HUDAssetLibrary.clock_digit_texture(digits[index])
	if _colon:
		_colon.texture = HUDAssetLibrary.clock_colon_texture()
	if cleaned != _last_text and animate and not _last_text.is_empty():
		_play_flip()
	if cleaned != _last_text:
		_last_text = cleaned
		clock_changed.emit(cleaned)


func _play_flip() -> void:
	HudMotion.kill(_flip_tween)
	modulate = HUDAssetLibrary.COLOR_INFO.lightened(0.35)
	_flip_tween = HudMotion.flash_modulate(
		self,
		self,
		HUDAssetLibrary.COLOR_INFO.lightened(0.35),
		Color.WHITE,
		0.22
	)
