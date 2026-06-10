extends Control
class_name CombatLaneView

const CYAN := Color(0.28, 0.95, 0.88)
const CYAN_DIM := Color(0.08, 0.34, 0.32)
const CRIMSON := Color(1.0, 0.25, 0.34)
const CRIMSON_DIM := Color(0.38, 0.06, 0.09)
const AMBER := Color(1.0, 0.68, 0.25)
const MUTED := Color(0.34, 0.58, 0.55)
const VOID := Color(0.006, 0.018, 0.02, 0.98)

var _snapshot: Dictionary = {}
var _font: SystemFont
var _showing_melee_lock := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(620.0, 290.0)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	resized.connect(queue_redraw)

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_showing_melee_lock = _find_lock_slot() >= 0
	queue_redraw()

func is_showing_melee_lock() -> bool:
	return _showing_melee_lock

func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, VOID, true)
	draw_rect(frame.grow(-1.0), Color(MUTED, 0.65), false, 2.0)
	_draw_scanlines(frame)

	if _snapshot.is_empty():
		_draw_centered("NO TACTICAL FEED", size.y * 0.52, 20, MUTED)
		return

	if _showing_melee_lock:
		_draw_melee_lock()
	else:
		_draw_corridor()

func _draw_corridor() -> void:
	var slots: Array = _snapshot.get("lane_slots", [])
	if slots.size() != 12:
		_draw_centered("LANE RECORD INVALID", size.y * 0.52, 20, CRIMSON)
		return

	_draw_centered("12-SLOT ENGAGEMENT CORRIDOR", 30.0, 15, MUTED)
	var left := 24.0
	var right := size.x - 24.0
	var center_y := size.y * 0.56
	var cell_width := (right - left) / 12.0

	draw_line(
		Vector2(left, center_y),
		Vector2(right, center_y),
		Color(MUTED, 0.22),
		1.0
	)

	for index in range(12):
		var descriptor: Dictionary = slots[index]
		var x0 := left + cell_width * index
		var x1 := x0 + cell_width
		var edge_factor_0: float = absf(
			(float(index) / 11.0) - 0.5
		) * 2.0
		var edge_factor_1: float = absf(
			(float(index + 1) / 11.0) - 0.5
		) * 2.0
		var half_0 := lerpf(size.y * 0.19, size.y * 0.34, edge_factor_0)
		var half_1 := lerpf(size.y * 0.19, size.y * 0.34, edge_factor_1)
		var polygon := PackedVector2Array([
			Vector2(x0, center_y - half_0),
			Vector2(x1, center_y - half_1),
			Vector2(x1, center_y + half_1),
			Vector2(x0, center_y + half_0),
		])

		var fill := _slot_fill(descriptor)
		draw_colored_polygon(polygon, fill)
		draw_polyline(
			PackedVector2Array([
				polygon[0],
				polygon[1],
				polygon[2],
				polygon[3],
				polygon[0],
			]),
			_slot_border(descriptor),
			2.0
		)

		var label_y := minf(polygon[0].y, polygon[1].y) - 9.0
		_draw_text(
			"%02d" % index,
			Vector2(x0, label_y),
			cell_width,
			13,
			MUTED,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_draw_slot_contents(descriptor, x0, x1, center_y)

func _draw_slot_contents(
	descriptor: Dictionary,
	x0: float,
	x1: float,
	center_y: float
) -> void:
	var width := x1 - x0
	if descriptor.get("is_escape", false):
		_draw_text(
			"EX",
			Vector2(x0, center_y + size.y * 0.23),
			width,
			13,
			AMBER,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	var terrain := _terrain_glyph(descriptor)
	if not terrain.is_empty():
		_draw_text(
			terrain,
			Vector2(x0, center_y + size.y * 0.12),
			width,
			16,
			AMBER,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	var occupants: Array = descriptor.get("occupants", [])
	if occupants.is_empty():
		return

	var marker_y := center_y - 23.0
	if occupants.size() == 1:
		_draw_occupant(occupants[0], x0 + width * 0.5, marker_y)
		return

	_draw_occupant(occupants[0], x0 + width * 0.32, marker_y)
	_draw_occupant(occupants[1], x0 + width * 0.68, marker_y)

func _draw_occupant(data: Dictionary, center_x: float, top: float) -> void:
	var side := str(data.get("side", "other"))
	var color := CYAN if side == "player" else CRIMSON
	var marker := "P" if side == "player" else "E"
	var rect := Rect2(Vector2(center_x - 15.0, top), Vector2(30.0, 36.0))
	draw_rect(rect, Color(color.r, color.g, color.b, 0.16), true)
	draw_rect(rect, color, false, 2.0 if data.get("is_active", false) else 1.0)
	_draw_text(
		marker,
		Vector2(rect.position.x, rect.position.y + 2.0),
		rect.size.x,
		23,
		color,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	if data.get("is_active", false):
		draw_line(
			Vector2(rect.position.x, rect.end.y + 4.0),
			Vector2(rect.end.x, rect.end.y + 4.0),
			color,
			3.0
		)

func _draw_melee_lock() -> void:
	var lock_slot := _find_lock_slot()
	var player: Dictionary = _snapshot.get("player", {})
	var enemy: Dictionary = _snapshot.get("enemy", {})

	draw_rect(
		Rect2(Vector2(28.0, 34.0), size - Vector2(56.0, 68.0)),
		Color(0.025, 0.055, 0.045, 0.88),
		true
	)
	draw_rect(
		Rect2(Vector2(28.0, 34.0), size - Vector2(56.0, 68.0)),
		AMBER,
		false,
		2.0
	)
	_draw_centered("MELEE LOCK ACTIVE", 68.0, 28, CYAN)
	_draw_centered("STANCE STRUGGLE // SLOT %02d" % lock_slot, 99.0, 17, AMBER)

	var mid_x := size.x * 0.5
	draw_line(
		Vector2(mid_x, 122.0),
		Vector2(mid_x, size.y - 54.0),
		Color(AMBER, 0.45),
		1.0
	)

	_draw_lock_combatant(
		player,
		Rect2(48.0, 126.0, mid_x - 70.0, size.y - 194.0),
		"P",
		CYAN
	)
	_draw_lock_combatant(
		enemy,
		Rect2(mid_x + 22.0, 126.0, size.x - mid_x - 70.0, size.y - 194.0),
		"E",
		CRIMSON
	)
	_draw_centered("<<  LOCK  >>", size.y - 48.0, 20, AMBER)

func _draw_lock_combatant(
	data: Dictionary,
	rect: Rect2,
	marker: String,
	color: Color
) -> void:
	draw_rect(rect, Color(color.r, color.g, color.b, 0.07), true)
	draw_rect(rect, Color(color, 0.7), false, 1.0)
	_draw_text(marker, rect.position + Vector2(0.0, 12.0), rect.size.x, 44, color)
	_draw_text(
		str(data.get("archetype", data.get("name", "UNKNOWN"))).to_upper(),
		rect.position + Vector2(0.0, 68.0),
		rect.size.x,
		15,
		color
	)
	_draw_text(
		"STANCE %02d/12  %s" % [
			int(data.get("stance", 0)),
			str(data.get("stance_state", "UNKNOWN")),
		],
		rect.position + Vector2(0.0, 98.0),
		rect.size.x,
		14,
		AMBER
	)
	_draw_text(
		"BLOOD %04.1f  AP-R %02d" % [
			float(data.get("blood", 0.0)),
			int(data.get("reserved_ap", 0)),
		],
		rect.position + Vector2(0.0, 126.0),
		rect.size.x,
		14,
		color
	)
	if data.get("is_active", false):
		_draw_text(
			"ACTIVE",
			rect.position + Vector2(0.0, rect.size.y - 30.0),
			rect.size.x,
			15,
			color
		)

func _slot_fill(descriptor: Dictionary) -> Color:
	var occupants: Array = descriptor.get("occupants", [])
	if occupants.is_empty():
		if descriptor.get("is_escape", false):
			return Color(AMBER.r, AMBER.g, AMBER.b, 0.07)
		return Color(0.02, 0.075, 0.07, 0.42)

	var has_player := false
	var has_enemy := false
	for occupant in occupants:
		has_player = has_player or occupant.get("side", "") == "player"
		has_enemy = has_enemy or occupant.get("side", "") == "enemy"
	if has_player and has_enemy:
		return Color(AMBER.r, AMBER.g, AMBER.b, 0.16)
	if has_player:
		return Color(CYAN_DIM, 0.8)
	if has_enemy:
		return Color(CRIMSON_DIM, 0.8)
	return Color(0.08, 0.08, 0.08, 0.7)

func _slot_border(descriptor: Dictionary) -> Color:
	if descriptor.get("is_melee_locked", false):
		return AMBER
	var occupants: Array = descriptor.get("occupants", [])
	for occupant in occupants:
		if occupant.get("is_active", false):
			return CYAN if occupant.get("side", "") == "player" else CRIMSON
	return Color(MUTED, 0.78)

func _terrain_glyph(descriptor: Dictionary) -> String:
	var cover := str(descriptor.get("cover", "NONE"))
	match cover:
		"COVER":
			return "#"
		"OBSTACLE":
			return "X"
		"TRAP":
			return "^"
	var background := str(descriptor.get("background", "NONE"))
	match background:
		"TREES":
			return "T"
		"MUD":
			return "~"
	return ""

func _find_lock_slot() -> int:
	for descriptor in _snapshot.get("lane_slots", []):
		if descriptor.get("is_melee_locked", false):
			return int(descriptor.get("index", -1))
	return -1

func _draw_scanlines(rect: Rect2) -> void:
	var y := rect.position.y + 3.0
	while y < rect.end.y:
		draw_line(
			Vector2(rect.position.x, y),
			Vector2(rect.end.x, y),
			Color(0.2, 0.55, 0.48, 0.025),
			1.0
		)
		y += 4.0

func _draw_centered(text: String, y: float, font_size: int, color: Color) -> void:
	_draw_text(
		text,
		Vector2(0.0, y),
		size.x,
		font_size,
		color,
		HORIZONTAL_ALIGNMENT_CENTER
	)

func _draw_text(
	text: String,
	position: Vector2,
	width: float,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
) -> void:
	draw_string(
		_font,
		position,
		text,
		alignment,
		width,
		font_size,
		color
	)
