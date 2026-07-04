extends Control
class_name PocketClockDisplay

var _frame: TextureRect
var _digits: HBoxContainer
var _digit_nodes: Array[TextureRect] = []


func _ready() -> void:
	_frame = TextureRect.new()
	_frame.custom_minimum_size = Vector2(96, 48)
	_frame.texture = RevampedHUDAtlas.clock_frame_texture()
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_frame)

	_digits = HBoxContainer.new()
	_digits.position = Vector2(18, 10)
	add_child(_digits)
	for i in 4:
		var digit := TextureRect.new()
		digit.custom_minimum_size = Vector2(16, 16)
		digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		digit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		digit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_digits.add_child(digit)
		_digit_nodes.append(digit)


func set_time(hour: int, minute: int) -> void:
	var hh := "%02d" % clampi(hour, 0, 23)
	var mm := "%02d" % clampi(minute, 0, 59)
	var text := hh + mm
	for i in text.length():
		var digit_value := int(text[i])
		_digit_nodes[i].texture = RevampedHUDAtlas.clock_digit(i, digit_value)
