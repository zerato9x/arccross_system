extends PanelContainer
class_name EffectChip

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	HUDAssetLibrary.apply_inset_panel(self, "neutral")
	HUDAssetLibrary.apply_label(_label, "muted")
	_label.add_theme_font_size_override("font_size", 10)


func configure(
	display_name: String,
	value_text: String = "",
	icon: Texture2D = null,
	tone: String = "neutral"
) -> void:
	if not is_node_ready():
		await ready
	HUDAssetLibrary.apply_inset_panel(self, tone if tone in ["neutral", "warning", "critical"] else "neutral")
	var text := display_name.to_upper()
	if not value_text.is_empty():
		text = "%s %s" % [text, value_text]
	_label.text = text
	_icon.texture = icon
	_icon.visible = icon != null
