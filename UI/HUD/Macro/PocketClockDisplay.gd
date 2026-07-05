extends Control
class_name PocketClockDisplay

const DIGIT_SIZE := Vector2(22.0, 28.0)

@onready var _frame: TextureRect = %Frame
@onready var _digit0: TextureRect = %Digit0
@onready var _digit1: TextureRect = %Digit1
@onready var _digit2: TextureRect = %Digit2
@onready var _digit3: TextureRect = %Digit3

var _digit_nodes: Array[TextureRect] = []
var _last_digits := ""


func _ready() -> void:
	_digit_nodes = [_digit0, _digit1, _digit2, _digit3]
	if _frame:
		_frame.texture = RevampedHUDAtlas.clock_frame_texture()
	for digit in _digit_nodes:
		digit.custom_minimum_size = DIGIT_SIZE
		digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		digit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		digit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_time(hour: int, minute: int) -> void:
	var hh := "%02d" % clampi(hour, 0, 23)
	var mm := "%02d" % clampi(minute, 0, 59)
	var text := hh + mm
	for i in text.length():
		if i >= _digit_nodes.size():
			break
		var digit_value := int(text[i])
		var digit_tex := RevampedHUDAtlas.clock_digit(i, digit_value)
		var changed := i >= _last_digits.length() or text[i] != _last_digits[i]
		if changed:
			_animate_digit_swap(_digit_nodes[i], digit_tex)
		else:
			_digit_nodes[i].texture = digit_tex
	_last_digits = text


func _animate_digit_swap(digit: TextureRect, texture: Texture2D) -> void:
	if digit.texture == texture:
		return
	var tween := create_tween()
	tween.tween_property(digit, "scale", Vector2(1.0, 0.05), 0.06)
	tween.tween_callback(func(): digit.texture = texture)
	tween.tween_property(digit, "scale", Vector2.ONE, 0.08)
