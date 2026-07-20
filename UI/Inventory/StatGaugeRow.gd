extends HBoxContainer
class_name StatGaugeRow

const ROW_HEIGHT := 22.0
const ICON_SIZE := Vector2(16, 16)

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _value_label: Label = %ValueLabel
@onready var _bar: ProgressBar = %Bar


func _ready() -> void:
	custom_minimum_size.y = ROW_HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	HUDAssetLibrary.apply_label(_name_label, "muted")
	HUDAssetLibrary.apply_label(_value_label, "body")
	_name_label.add_theme_font_size_override("font_size", 10)
	_value_label.add_theme_font_size_override("font_size", 10)
	HUDAssetLibrary.apply_progress_bar(_bar, "health")


func configure(
	display_name: String,
	value: float,
	max_value: float = 12.0,
	value_text: String = "",
	fill_kind: String = "health",
	icon: Texture2D = null
) -> void:
	if not is_node_ready():
		await ready
	_name_label.text = display_name.to_upper()
	_bar.min_value = 0.0
	_bar.max_value = maxf(0.001, max_value)
	_bar.value = clampf(value, 0.0, _bar.max_value)
	HUDAssetLibrary.apply_progress_bar(_bar, fill_kind)
	if value_text.is_empty():
		_value_label.text = "%.1f / %.0f" % [value, max_value]
	else:
		_value_label.text = value_text
	_icon.texture = icon
	_icon.visible = icon != null
