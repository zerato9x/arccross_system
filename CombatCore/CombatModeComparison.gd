extends Node2D

@onready var mode_menu: Control = %ModeMenu
@onready var result_label: Label = %ResultLabel
@onready var mode_badge: Label = %ModeBadge

var _active_combat: TacticalCombatScene


func _ready() -> void:
	mode_menu.visible = true
	mode_badge.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _active_combat != null:
		_return_to_lab(null)
		get_viewport().set_input_as_handled()
	elif mode_menu.visible and event.keycode == KEY_F1:
		launch_topology("duel_12x1")
		get_viewport().set_input_as_handled()
	elif mode_menu.visible and event.keycode == KEY_F2:
		launch_topology("squad_7x5")
		get_viewport().set_input_as_handled()


func launch_topology(topology_id: String) -> void:
	if _active_combat != null:
		_active_combat.queue_free()
		_active_combat = null
	var packed := load(PresentationSceneRegistry.TACTICAL_COMBAT_SCENE) as PackedScene
	if packed == null:
		push_error("Combat Lab could not load the tactical combat scene.")
		return
	_active_combat = packed.instantiate() as TacticalCombatScene
	add_child(_active_combat)
	var encounter := (
		load("res://CombatCore/Tactical/combat_lab_encounter.tres")
		as CombatEncounterRecord
	).duplicate(true)
	encounter.topology_id = topology_id
	var player_definition := preload("res://BiologicalCore/player_def.tres")
	var enemy_definition := preload("res://BiologicalCore/scavenger_def.tres")
	encounter.actors = [
		{"actor_id": "player", "team_id": "player", "runtime_record": {"entity_id": "player", "definition": player_definition.to_state(), "runtime": {}}},
		{"actor_id": "combat_lab_enemy", "team_id": "enemy", "runtime_record": {"entity_id": "combat_lab_enemy", "definition": enemy_definition.to_state(), "runtime": {}}},
	]
	_active_combat.combat_finished.connect(_return_to_lab)
	_active_combat.setup_encounter(encounter)
	mode_menu.visible = false
	mode_badge.text = "%s  |  ESC: RETURN TO TOPOLOGY LAB" % topology_id.to_upper()
	mode_badge.visible = true


func _on_realtime_pressed() -> void:
	launch_topology("duel_12x1")


func _on_turn_based_pressed() -> void:
	launch_topology("squad_7x5")


func _return_to_lab(result: CombatResultRecord) -> void:
	if result != null:
		result_label.text = "LAST RESULT: %s // %s" % [GameEnums.CombatOutcome.keys()[result.outcome], result.reason.to_upper()]
	if _active_combat != null:
		_active_combat.queue_free()
		_active_combat = null
	mode_menu.visible = true
	mode_badge.visible = false
