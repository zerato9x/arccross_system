extends Node2D
class_name MacroEnemy

@onready var humanoid_token: HumanoidTokenView = $HumanoidTokenView

var entity_id: String = ""
var current_hex_coords: Vector2i = Vector2i(0, 0)
var _faction_color := Color(0.65, 0.68, 0.65)
var _idle_animation := "Idle2"

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
	position = pixel_position
	if humanoid_token:
		humanoid_token.play_animation(_idle_animation, false)

## Initialize presentation from a neutral persistent record.
func setup_from_record(record: Dictionary) -> void:
	entity_id = record.get("entity_id", "")
	var definition_state: Dictionary = record.get("definition", {})
	var faction: GameEnums.Faction = definition_state.get(
		"faction",
		GameEnums.Faction.UNALIGNED
	)
	var world_status: GameEnums.EntityWorldStatus = record.get(
		"world_status",
		GameEnums.EntityWorldStatus.HOSTILE
	)
	_idle_animation = (
		"Idle2"
		if world_status == GameEnums.EntityWorldStatus.HOSTILE
		else "Idle3"
	)

	if humanoid_token:
		humanoid_token.set_appearance(
			HumanoidVisualCatalog.appearance_from_record(record)
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
