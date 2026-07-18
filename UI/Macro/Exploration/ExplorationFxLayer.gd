extends Control
class_name ExplorationFxLayer

## Placeholder exploration FX using basic shapes and tweens.

var _active_nodes: Array[Node] = []
var _pulse_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false


func play_fx(fx: Dictionary) -> void:
	clear_fx()
	if fx.is_empty():
		return
	var kind := str(fx.get("kind", "pulse"))
	var intensity := clampf(float(fx.get("intensity", 0.55)), 0.15, 1.0)
	var palette: Array = fx.get("palette", [])
	var primary := _palette_color(palette, 0, Color(0.85, 0.72, 0.35, 0.55))
	var secondary := _palette_color(palette, 1, Color(0.35, 0.55, 0.75, 0.4))
	match kind:
		"discover":
			_spawn_flash(primary.lightened(0.2), intensity)
			_spawn_hex_ring(primary, intensity * 1.2)
			_spawn_dust(secondary, intensity)
		"loot":
			_spawn_flash(Color(0.95, 0.8, 0.25, 0.5), intensity)
			_spawn_scan_lines(Color(0.9, 0.75, 0.2, 0.35), intensity)
		"landmark":
			_spawn_hex_ring(secondary, intensity)
			_spawn_scan_lines(primary, intensity * 0.8)
		"danger":
			_spawn_flash(Color(0.85, 0.2, 0.15, 0.45), intensity)
			_spawn_scan_lines(Color(0.7, 0.15, 0.1, 0.4), intensity)
		_:
			_spawn_hex_ring(primary, intensity)
			_spawn_dust(secondary, intensity * 0.7)


func clear_fx() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	for node in _active_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_active_nodes.clear()


func _palette_color(palette: Array, index: int, fallback: Color) -> Color:
	if index < 0 or index >= palette.size():
		return fallback
	var value = palette[index]
	if value is Color:
		return value
	if value is String:
		return Color(str(value))
	return fallback


func _spawn_flash(color: Color, intensity: float) -> void:
	var flash := ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(color.r, color.g, color.b, color.a * intensity)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	_active_nodes.append(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	tween.tween_callback(flash.queue_free)


func _spawn_hex_ring(color: Color, intensity: float) -> void:
	var poly := Polygon2D.new()
	poly.color = Color(color.r, color.g, color.b, color.a * intensity)
	var radius := 42.0 + intensity * 36.0
	var points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * float(i) / 6.0 - PI / 2.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	poly.polygon = points
	poly.position = size * 0.5 if size.x > 1.0 else Vector2(640, 360)
	add_child(poly)
	_active_nodes.append(poly)
	_pulse_tween = create_tween()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(poly, "scale", Vector2(2.4, 2.4), 0.7).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(poly, "modulate:a", 0.0, 0.7)
	_pulse_tween.chain().tween_callback(poly.queue_free)


func _spawn_dust(color: Color, intensity: float) -> void:
	var count := clampi(int(6.0 + intensity * 10.0), 6, 16)
	var origin := size * 0.5 if size.x > 1.0 else Vector2(640, 360)
	for i in range(count):
		var mote := ColorRect.new()
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mote_size := 4.0 + float(i % 3) * 2.0
		mote.custom_minimum_size = Vector2(mote_size, mote_size)
		mote.size = mote.custom_minimum_size
		mote.color = Color(color.r, color.g, color.b, color.a)
		var angle := TAU * float(i) / float(count)
		var start := origin + Vector2(cos(angle), sin(angle)) * 12.0
		mote.position = start
		add_child(mote)
		_active_nodes.append(mote)
		var end := origin + Vector2(cos(angle), sin(angle)) * (70.0 + intensity * 50.0)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(mote, "position", end, 0.55 + float(i % 4) * 0.05)
		tween.tween_property(mote, "modulate:a", 0.0, 0.55)
		tween.chain().tween_callback(mote.queue_free)


func _spawn_scan_lines(color: Color, intensity: float) -> void:
	var lines := 5
	for i in range(lines):
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = Color(color.r, color.g, color.b, color.a * intensity)
		line.anchor_left = 0.08
		line.anchor_right = 0.92
		line.offset_left = 0.0
		line.offset_right = 0.0
		line.offset_top = 120.0 + float(i) * 28.0
		line.offset_bottom = line.offset_top + 3.0
		line.modulate.a = 0.0
		add_child(line)
		_active_nodes.append(line)
		var tween := create_tween()
		tween.tween_property(line, "modulate:a", 1.0, 0.12).set_delay(float(i) * 0.05)
		tween.tween_property(line, "modulate:a", 0.0, 0.35)
		tween.tween_callback(line.queue_free)
