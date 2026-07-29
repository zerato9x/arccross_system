extends Control
class_name MacroHexCompositionView

## Lightweight reusable renderer for the literal generated hex composition.

var _descriptor: Dictionary = {}
var _layer_root: Control
var _decor_root: Control


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_root = Control.new()
	_layer_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer_root)
	_decor_root = Control.new()
	_decor_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decor_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_decor_root)
	resized.connect(_layout_decorations)
	_render()


func show_composition(descriptor: Dictionary) -> void:
	_descriptor = descriptor.duplicate(true)
	if is_node_ready():
		_render()


func get_descriptor() -> Dictionary:
	return _descriptor.duplicate(true)


func _render() -> void:
	if _layer_root == null or _decor_root == null:
		return
	_clear(_layer_root)
	_clear(_decor_root)
	var layers: Array = _descriptor.get("layers", []).duplicate(true)
	layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("z_index", 0)) < int(b.get("z_index", 0))
	)
	for entry in layers:
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var layer := TextureRect.new()
		layer.name = "Layer_%s" % str(entry.get("kind", "visual"))
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.texture = load(path) as Texture2D
		_layer_root.add_child(layer)

	for entry in _descriptor.get("decorations", []):
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var decor := TextureRect.new()
		decor.name = "Decor_%s" % str(entry.get("kind", "detail"))
		decor.texture = load(path) as Texture2D
		decor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		decor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		decor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		decor.set_meta("descriptor", entry)
		_decor_root.add_child(decor)
	_layout_decorations()


func _layout_decorations() -> void:
	if _decor_root == null:
		return
	var view_scale := minf(size.x, size.y) / 512.0
	for child in _decor_root.get_children():
		if not child is TextureRect:
			continue
		var decor := child as TextureRect
		var entry: Dictionary = decor.get_meta("descriptor", {})
		var target_box: Vector2 = entry.get("target_box", Vector2(112.0, 112.0))
		var multiplier := float(entry.get("scale_multiplier", 1.0))
		var display_size := target_box * view_scale * multiplier
		var offset: Vector2 = entry.get("offset", Vector2.ZERO)
		decor.size = display_size
		decor.position = size * 0.5 + offset * view_scale - display_size * 0.5
		decor.rotation = float(entry.get("rotation", 0.0))
		decor.flip_h = bool(entry.get("flip_h", false))


func _clear(root: Node) -> void:
	for child in root.get_children():
		child.free()
