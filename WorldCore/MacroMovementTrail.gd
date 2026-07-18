extends Node2D
class_name MacroMovementTrail

## Fading ground footprints left as the player walks hex-to-hex.

const MAX_MARKS := 24
const MARK_LIFE := 2.4

var _marks: Array[Dictionary] = []


func add_step(world_pos: Vector2, facing: Vector2 = Vector2.RIGHT) -> void:
	var mark := Polygon2D.new()
	mark.color = Color(0.72, 0.62, 0.28, 0.55)
	var dir := facing.normalized() if facing.length_squared() > 0.01 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	mark.polygon = PackedVector2Array([
		dir * 10.0,
		perp * 5.0,
		-dir * 4.0,
		-perp * 5.0,
	])
	mark.position = world_pos
	add_child(mark)
	_marks.append({"node": mark, "age": 0.0})
	while _marks.size() > MAX_MARKS:
		var old: Dictionary = _marks.pop_front()
		var old_node: Node = old.get("node")
		if is_instance_valid(old_node):
			old_node.queue_free()


func _process(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for entry in _marks:
		var node: Polygon2D = entry.get("node")
		if not is_instance_valid(node):
			continue
		var age := float(entry.get("age", 0.0)) + delta
		var t := clampf(age / MARK_LIFE, 0.0, 1.0)
		node.modulate.a = 1.0 - t
		node.scale = Vector2.ONE * (1.0 + t * 0.35)
		if t < 1.0:
			alive.append({"node": node, "age": age})
		else:
			node.queue_free()
	_marks = alive
