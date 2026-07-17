extends Node2D
class_name CombatModeComparison

const REALTIME_SCENE := preload("res://CombatCore/MainDuelScene.tscn")
const TURN_BASED_SCENE := preload("res://CombatCore/TurnBased/TurnBasedDuelScene.tscn")

@onready var mode_menu: Control = %ModeMenu
@onready var mode_badge: Label = %ModeBadge
@onready var result_label: Label = %ResultLabel

var _active_arena: Node

func _ready() -> void:
	mode_badge.visible = false
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = int(event.physical_keycode)
	if code == 0:
		code = int(event.keycode)
	match code:
		KEY_F1:
			_start_mode(REALTIME_SCENE, "REAL-TIME DUEL")
		KEY_F2:
			_start_mode(TURN_BASED_SCENE, "TURN-BASED DUEL")
		KEY_ESCAPE:
			if _active_arena != null:
				_return_to_menu("Comparison interrupted. No combat state was persisted.")

func _on_realtime_pressed() -> void:
	_start_mode(REALTIME_SCENE, "REAL-TIME DUEL")

func _on_turn_based_pressed() -> void:
	_start_mode(TURN_BASED_SCENE, "TURN-BASED DUEL")

func _start_mode(scene: PackedScene, label: String) -> void:
	if _active_arena != null:
		_active_arena.queue_free()
	_active_arena = scene.instantiate()
	add_child(_active_arena)
	move_child(_active_arena, 0)
	_active_arena.duel_finished.connect(_on_duel_finished.bind(label))
	mode_menu.visible = false
	mode_badge.text = "%s  |  ESC: RETURN TO COMPARISON" % label
	mode_badge.visible = true
	var player_definition := preload("res://BiologicalCore/player_def.tres")
	var enemy_definition := preload("res://BiologicalCore/scavenger_def.tres")
	_active_arena.setup_duel_from_records(
		{
			"entity_id": "comparison_player",
			"definition": player_definition.to_state(),
			"runtime": {},
		},
		{
			"entity_id": "comparison_enemy",
			"definition": enemy_definition.to_state(),
			"runtime": {},
		}
	)

func _on_duel_finished(
	outcome: GameEnums.CombatOutcome,
	_enemy_id: String,
	_enemy_runtime: Dictionary,
	_player_runtime: Dictionary,
	_dropped_items: Array,
	mode_label: String
) -> void:
	_return_to_menu(
		"%s result: %s" % [mode_label, GameEnums.CombatOutcome.keys()[outcome]]
	)

func _return_to_menu(message: String) -> void:
	if _active_arena != null:
		_active_arena.queue_free()
		_active_arena = null
	result_label.text = message
	mode_badge.visible = false
	mode_menu.visible = true
