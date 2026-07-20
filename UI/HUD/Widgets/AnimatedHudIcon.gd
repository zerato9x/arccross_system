extends TextureRect
class_name AnimatedHudIcon

@export var animation_name: String = "heartbeat"
@export var fps: float = 6.0
@export var autoplay: bool = true

var _frames: Array[Texture2D] = []
var _frame_index := 0
var _elapsed := 0.0
var _playing := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_animation(animation_name)
	if autoplay:
		play()


func _process(delta: float) -> void:
	if not _playing or _frames.size() <= 1 or fps <= 0.0:
		return
	_elapsed += delta
	var frame_time := 1.0 / fps
	while _elapsed >= frame_time:
		_elapsed -= frame_time
		_frame_index = (_frame_index + 1) % _frames.size()
		texture = _frames[_frame_index]


func set_animation(name: String) -> void:
	animation_name = name
	_frames = HUDAssetLibrary.anim_icon_frames(name)
	_frame_index = 0
	_elapsed = 0.0
	if _frames.is_empty():
		var fallback := HUDAssetLibrary.status_icon(name)
		texture = fallback
		_playing = false
		return
	texture = _frames[0]


func play() -> void:
	_playing = _frames.size() > 1


func stop() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func set_static_texture(tex: Texture2D) -> void:
	stop()
	_frames.clear()
	texture = tex
