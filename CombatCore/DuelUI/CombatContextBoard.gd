extends Node2D
class_name CombatContextBoard

const BOARD_SIZE := Vector2(430.0, 132.0)
const COLOR_PANEL := Color(0.08, 0.085, 0.07, 0.88)
const COLOR_BORDER := Color(0.67, 0.58, 0.43, 0.9)

@onready var _panel_box: Polygon2D = %PanelBox
@onready var _border: Line2D = %Border
@onready var _title_label: Label = %TitleLabel
@onready var _state_label: Label = %StateLabel
@onready var _detail_label: Label = %DetailLabel

func _ready() -> void:
	_set_box(_panel_box, BOARD_SIZE)
	_panel_box.color = COLOR_PANEL
	_set_outline(_border, BOARD_SIZE)
	visible = false

func show_snapshot(snapshot: Dictionary) -> void:
	visible = not snapshot.is_empty()
	if snapshot.is_empty():
		return
	_title_label.text = "BATTLEFIELD // %s" % _battlefield_type(snapshot)
	_state_label.text = "ROUND %02d | ACTIVE %s | AP %02d" % [
		int(snapshot.get("round", 0)),
		str(snapshot.get("active_name", "UNKNOWN")).to_upper(),
		int(snapshot.get("ap", 0)),
	]
	_detail_label.text = _detail_text(snapshot)

func _battlefield_type(snapshot: Dictionary) -> String:
	var backgrounds := {}
	var objects := {}
	for raw_slot in snapshot.get("lane_slots", []):
		var slot: Dictionary = raw_slot
		var background := str(slot.get("background", "NONE"))
		var object := str(slot.get("cover", "NONE"))
		backgrounds[background] = int(backgrounds.get(background, 0)) + 1
		if object != "NONE":
			objects[object] = int(objects.get(object, 0)) + 1
	var floor := _dominant_key(backgrounds, "OPEN")
	if objects.is_empty():
		return floor
	return floor + " / " + _dominant_key(objects, "OBJECTS")

func _detail_text(snapshot: Dictionary) -> String:
	var player: Dictionary = snapshot.get("player", {})
	var enemy: Dictionary = snapshot.get("enemy", {})
	var distance := absi(int(player.get("lane", -1)) - int(enemy.get("lane", -1)))
	var actions: Array = snapshot.get("actions", [])
	var flags := PackedStringArray()
	if snapshot.get("busy", false):
		flags.append("RESOLVING")
	if snapshot.get("reaction_pending", false):
		flags.append("REACTION")
	if snapshot.get("can_pass", false):
		flags.append("PASS READY")
	if flags.is_empty():
		flags.append("NO FREE PASS")
	return (
		"DISTANCE %02d | LEGAL ACTIONS %02d | %s\n"
		+ "PLAYER %s%s\n"
		+ "ENEMY %s%s"
	) % [
		distance,
		actions.size(),
		" / ".join(flags),
		str(player.get("weapon", "UNARMED")).to_upper(),
		str(player.get("weapon_detail", "")),
		str(enemy.get("weapon", "UNARMED")).to_upper(),
		str(enemy.get("weapon_detail", "")),
	]

func _dominant_key(counts: Dictionary, fallback: String) -> String:
	var best_key := fallback
	var best_count := -1
	for key in counts.keys():
		var count := int(counts[key])
		if count > best_count and str(key) != "NONE":
			best_key = str(key)
			best_count = count
	return best_key

func _set_box(polygon: Polygon2D, size: Vector2) -> void:
	polygon.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
	])

func _set_outline(line: Line2D, size: Vector2) -> void:
	line.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
		Vector2.ZERO,
	])
	line.default_color = COLOR_BORDER
	line.width = 1.5
