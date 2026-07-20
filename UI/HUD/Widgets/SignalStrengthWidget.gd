extends TextureRect
class_name SignalStrengthWidget

@export var level: int = 4
@export var kind: String = "normal"
@export var pulse_half_duration: float = 0.9

var _pulse_tween: Tween


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = Vector2(28, 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()
	start_pulse()


func set_signal(new_level: int, new_kind: String = "normal") -> void:
	level = clampi(new_level, 0, 4)
	kind = new_kind
	refresh()
	start_pulse()


func refresh() -> void:
	texture = HUDAssetLibrary.signal_texture(level, kind)
	if kind == "travel":
		modulate = HUDAssetLibrary.COLOR_TRAVEL
	elif kind in ["warning", "caution"]:
		modulate = Color.WHITE
	elif kind in ["critical", "danger", "anomaly"]:
		modulate = Color.WHITE
	elif HUDAssetLibrary.get_active_scheme_id() != HUDAssetLibrary.SCHEME_CYAN:
		modulate = HUDAssetLibrary.COLOR_INFO
	else:
		modulate = Color.WHITE


func start_pulse() -> void:
	HudMotion.kill(_pulse_tween)
	var half := pulse_half_duration
	if kind in ["warning", "caution"]:
		half = 0.55
	elif kind == "travel":
		half = 0.75
	elif kind in ["critical", "danger", "anomaly"]:
		half = 0.35
	_pulse_tween = HudMotion.pulse_alpha(self, self, 0.4, 1.0, half)
