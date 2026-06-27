extends Node2D
class_name MacroEnemy

const WALK_DURATION_SECONDS := 2.0

@onready var humanoid_token: HumanoidTokenView = $HumanoidTokenView

var entity_id: String = ""
var current_hex_coords: Vector2i = Vector2i(0, 0)
var _faction_color := Color(0.65, 0.68, 0.65)
var _idle_animation := "Idle2"
var _movement_tween: Tween
var _movement_serial := 0
var _movement_queue: Array[Vector2] = []

func _ready() -> void:
	var placeholder := get_node_or_null("Sprite2D") as Sprite2D
	if placeholder:
		placeholder.visible = false

	if humanoid_token == null:
		push_error("MacroEnemy requires an authored HumanoidTokenView child.")
		return
	humanoid_token.set_display_scale(2.4)

func snap_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	_movement_queue.clear()
	if _movement_tween and _movement_tween.is_valid():
		_movement_tween.kill()
	position = pixel_position
	if humanoid_token:
		humanoid_token.play_animation(_idle_animation, false)

func walk_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	_movement_queue.append(pixel_position)
	if _movement_tween == null or not _movement_tween.is_valid() or not _movement_tween.is_running():
		_process_next_movement()

func _process_next_movement() -> void:
	if _movement_queue.is_empty():
		if humanoid_token:
			humanoid_token.play_animation(_idle_animation)
		return
		
	var next_pos: Vector2 = _movement_queue.pop_front()
	var movement_direction := next_pos - position
	
	if humanoid_token:
		humanoid_token.face_direction(movement_direction)
		humanoid_token.play_animation("Walk")
		
	_movement_tween = create_tween()
	_movement_tween.tween_property(
		self,
		"position",
		next_pos,
		WALK_DURATION_SECONDS
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_movement_tween.finished.connect(_process_next_movement)

## Initialize presentation from a neutral persistent record.
func setup_from_record(record) -> void:
	var definition_state: Dictionary = {}
	var faction: GameEnums.Faction = GameEnums.Faction.UNALIGNED
	var world_status: GameEnums.EntityWorldStatus = GameEnums.EntityWorldStatus.HOSTILE
	if record is EntityRecord:
		entity_id = record.entity_id
		definition_state = record.definition
		world_status = record.world_status
	elif record is Dictionary:
		entity_id = record.get("entity_id", "")
		definition_state = record.get("definition", {})
		world_status = record.get(
			"world_status",
			GameEnums.EntityWorldStatus.HOSTILE
		)
	else:
		return
	faction = definition_state.get(
		"faction",
		GameEnums.Faction.UNALIGNED
	)
	_idle_animation = (
		"Idle2"
		if world_status == GameEnums.EntityWorldStatus.HOSTILE
		else "Idle3"
	)

	if humanoid_token:
		humanoid_token.set_appearance(
			HumanoidVisualCatalog.appearance_from_record(
				record.to_dict() if record is EntityRecord else record
			)
		)
		humanoid_token.play_animation(_idle_animation, false)

	# Keep faction readability without recoloring every equipped item.
	match faction:
		GameEnums.Faction.CRAVEN_HIVE:
			_faction_color = Color(0.85, 0.18, 0.22)
		GameEnums.Faction.ARCBORN_RESISTANCE:
			_faction_color = Color(0.24, 0.55, 1.0)
		GameEnums.Faction.SCAVENGER_CELL:
			_faction_color = Color(0.9, 0.72, 0.2)
		_:
			_faction_color = Color(0.65, 0.68, 0.65)
	queue_redraw()

func play_interaction() -> void:
	if humanoid_token:
		humanoid_token.play_one_shot("Taunt", _idle_animation)

func _finish_walk(movement_id: int) -> void:
	# Retained for interface compatibility if needed, but no longer used internally
	pass

func _draw() -> void:
	draw_circle(Vector2(0.0, -5.0), 24.0, Color(_faction_color, 0.12))
	draw_arc(
		Vector2(0.0, -5.0),
		24.0,
		0.0,
		TAU,
		32,
		_faction_color,
		2.0,
		true
	)
