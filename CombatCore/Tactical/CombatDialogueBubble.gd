extends Node2D
class_name CombatDialogueBubble

var payload: Dictionary = {}
var max_width := 220.0


func configure(value: Dictionary) -> void:
	payload = value.duplicate(true)
	queue_redraw()


func _draw() -> void:
	if payload.is_empty():
		return
	var text := str(payload.get("text", ""))
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var lines := _wrap(text, 34)
	var height := float(lines.size()) * 13.0 + 14.0
	var rect := Rect2(-max_width * 0.5, -height - 74.0, max_width, height)
	draw_rect(rect, Color(0.04, 0.05, 0.05, 0.96), true)
	draw_rect(rect, Color("d4ba7e"), false, 1.0)
	for index in range(lines.size()):
		draw_string(font, Vector2(rect.position.x + 8.0, rect.position.y + 13.0 + index * 13.0), lines[index], HORIZONTAL_ALIGNMENT_LEFT, max_width - 16.0, 10, Color("e7e5db"))


func _wrap(value: String, width: int) -> Array[String]:
	var result: Array[String] = []
	var current := ""
	for word in value.split(" "):
		var next := word if current.is_empty() else "%s %s" % [current, word]
		if next.length() > width and not current.is_empty():
			result.append(current)
			current = word
		else:
			current = next
	if not current.is_empty():
		result.append(current)
	return result
