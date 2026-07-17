extends Node2D
class_name TurnBasedDuelScene

signal duel_finished(
	outcome: GameEnums.CombatOutcome,
	enemy_id: String,
	enemy_runtime: Dictionary,
	player_runtime: Dictionary,
	dropped_items: Array
)

@onready var lane_manager: CombatLaneManager = $CombatLaneManager
@onready var turn_manager: CombatTurnManager = $CombatTurnManager
@onready var resolution_engine: CombatResolutionEngine = $CombatResolutionEngine
@onready var encounter_builder: EncounterBuilder = $EncounterBuilder
@onready var command_adapter: CombatCommandAdapter = $CombatCommandAdapter
@onready var lane_hud: CombatLaneHUD = $CombatLaneHUD
@onready var combat_briefing: CombatBriefingOverlay = %CombatBriefingOverlay

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var enemy_entity_id := ""
var dropped_combat_loot: Array[ItemData] = []
var _resolving := false

func _ready() -> void:
	lane_hud.action_requested.connect(command_adapter.request_player_action)
	lane_hud.pass_requested.connect(command_adapter.pass_player_turn)
	lane_hud.reaction_selected.connect(command_adapter.resolve_player_reaction)
	command_adapter.snapshot_changed.connect(lane_hud.show_snapshot)
	command_adapter.presentation_event.connect(lane_hud.show_presentation_event)
	command_adapter.reaction_requested.connect(lane_hud.show_reaction)
	command_adapter.command_feedback.connect(lane_hud.show_feedback)
	lane_hud.open_hud()

	if get_parent() == get_tree().root and get_tree().current_scene == self:
		var player_definition := preload("res://BiologicalCore/player_def.tres")
		var enemy_definition := preload("res://BiologicalCore/scavenger_def.tres")
		setup_duel_from_records(
			{
				"entity_id": "turn_based_player",
				"definition": player_definition.to_state(),
				"runtime": {},
			},
			{
				"entity_id": "turn_based_enemy",
				"definition": enemy_definition.to_state(),
				"runtime": {},
			}
		)

func setup_duel_from_records(
	player_record: Dictionary,
	enemy_record: Dictionary,
	encounter_setup: Dictionary = {}
) -> void:
	_clear_humanoid_cores()
	enemy_entity_id = str(enemy_record.get("entity_id", ""))
	player_core = EntityFactory.record_to_humanoid_core(
		player_record,
		self,
		"Player_Unit",
		false,
		null,
		null,
		null,
		Callable()
	)
	enemy_core = EntityFactory.record_to_humanoid_core(
		enemy_record,
		self,
		"Enemy_Scavenger",
		true,
		lane_manager,
		turn_manager,
		resolution_engine,
		Callable()
	)
	_begin_duel(encounter_setup)

func setup_duel(
	existing_player_core: HumanoidCore,
	enemy_record: Dictionary,
	encounter_setup: Dictionary = {}
) -> void:
	if existing_player_core == null:
		push_error("Cannot start turn-based duel without a player core.")
		return
	_clear_humanoid_cores(existing_player_core)
	player_core = existing_player_core
	if player_core.get_parent() != self:
		player_core.reparent(self)
	enemy_entity_id = str(enemy_record.get("entity_id", ""))
	enemy_core = EntityFactory.record_to_humanoid_core(
		enemy_record,
		self,
		"Enemy_Scavenger",
		true,
		lane_manager,
		turn_manager,
		resolution_engine,
		Callable()
	)
	_begin_duel(encounter_setup)

func setup_duel_procedural(
	player_record: Dictionary,
	enemy_faction: GameEnums.Faction,
	difficulty: int = 0
) -> void:
	var mob_spawner := get_node_or_null("/root/MobSpawner") as MobSpawner
	if mob_spawner == null:
		push_error("MobSpawner unavailable for procedural turn-based duel setup.")
		return
	var record := mob_spawner.generate_mob_record(Vector2i.ZERO, enemy_faction, difficulty)
	setup_duel_from_records(player_record, record.to_dict())

func _begin_duel(encounter_setup: Dictionary) -> void:
	if player_core == null or enemy_core == null:
		push_error("Cannot begin turn-based duel without both combatants.")
		return
	_resolving = false
	dropped_combat_loot.clear()
	player_core.reset_combat_transients()
	enemy_core.reset_combat_transients()
	if not player_core.inventory.items_spilled.is_connected(_on_items_spilled):
		player_core.inventory.items_spilled.connect(_on_items_spilled)
	if not enemy_core.inventory.items_spilled.is_connected(_on_items_spilled):
		enemy_core.inventory.items_spilled.connect(_on_items_spilled)
	if not turn_manager.entity_escaped.is_connected(_on_entity_escaped):
		turn_manager.entity_escaped.connect(_on_entity_escaped)
	player_core.died.connect(_on_combatant_died.bind(player_core))
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	turn_manager.halt_loop()
	command_adapter.configure(
		player_core,
		enemy_core,
		lane_manager,
		turn_manager,
		resolution_engine
	)
	encounter_builder.build_encounter(player_core, enemy_core, encounter_setup)
	command_adapter.refresh_snapshot()
	await combat_briefing.open_briefing({
		"mode": "TURN-BASED DUEL",
		"opponent": enemy_core.definition.archetype_name,
		"context": "The turn queue is halted. Review the lane, paper doll, wounds, and equipment before initiative begins.",
		"controls": "Choose commands from the action rail. AP is committed per turn; reaction prompts pause resolution.",
	})
	if not _resolving and is_instance_valid(turn_manager):
		turn_manager.resume_loop()

func _on_combatant_died(cause: String, dead_entity: HumanoidCore) -> void:
	if _resolving:
		return
	_resolving = true
	turn_manager.halt_loop()
	if dead_entity == enemy_core:
		_append_dropped_items(enemy_core.inventory.drain_all_items())
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_DEFEAT
		if dead_entity == player_core
		else GameEnums.CombatOutcome.PLAYER_VICTORY
	)
	if DisplayServer.get_name() != "headless":
		await lane_hud.show_resolve_screen({
			"title": "TURN-BASED DUEL RESOLVED",
			"focus_side": "player" if dead_entity == player_core else "enemy",
			"dead_side": "player" if dead_entity == player_core else "enemy",
			"dead_name": dead_entity.name,
			"cause": cause,
			"loot_names": _dropped_item_names(),
		})
	_finish_duel(outcome)

func _on_entity_escaped(entity: HumanoidCore) -> void:
	if _resolving:
		return
	_resolving = true
	turn_manager.halt_loop()
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_ESCAPED
		if entity == player_core
		else GameEnums.CombatOutcome.ENEMY_ESCAPED
	)
	if DisplayServer.get_name() != "headless":
		await lane_hud.show_resolve_screen({
			"title": "TURN-BASED DUEL ENDED",
			"focus_side": "player" if entity == player_core else "enemy",
			"dead_side": "",
			"dead_name": entity.name,
			"cause": "Combatant escaped the lane.",
			"loot_names": _dropped_item_names(),
		})
	_finish_duel(outcome)

func _finish_duel(outcome: GameEnums.CombatOutcome) -> void:
	var enemy_runtime := capture_enemy_runtime_state()
	var player_runtime := capture_player_runtime_state()
	_clear_encounter_transients()
	lane_hud.close_hud()
	duel_finished.emit(
		outcome,
		enemy_entity_id,
		enemy_runtime,
		player_runtime,
		_capture_dropped_item_states()
	)

func capture_enemy_runtime_state() -> Dictionary:
	return enemy_core.capture_runtime_state().to_dict() if enemy_core != null else {}

func capture_player_runtime_state() -> Dictionary:
	return player_core.capture_runtime_state().to_dict() if player_core != null else {}

func _clear_encounter_transients() -> void:
	if player_core != null:
		player_core.reset_combat_transients()
	if enemy_core != null:
		enemy_core.reset_combat_transients()

func _clear_humanoid_cores(keep: HumanoidCore = null) -> void:
	turn_manager.halt_loop()
	for slot in lane_manager.lane_slots:
		slot.occupants.clear()
		slot.is_melee_locked = false
		slot.grapple_stance_scale = 12
	for child in get_children():
		if child is HumanoidCore and child != keep:
			child.queue_free()
	player_core = null
	enemy_core = null

func _on_items_spilled(items: Array[ItemData]) -> void:
	_append_dropped_items(items)

func _append_dropped_items(items: Array[ItemData]) -> void:
	var known: Dictionary = {}
	for existing in dropped_combat_loot:
		known[existing.instance_id] = true
	for item in items:
		if item == null or known.has(item.instance_id):
			continue
		dropped_combat_loot.append(item)
		known[item.instance_id] = true

func _capture_dropped_item_states() -> Array:
	var states: Array = []
	for item in dropped_combat_loot:
		states.append(item.to_runtime_state())
	return states

func _dropped_item_names() -> Array[String]:
	var names: Array[String] = []
	for item in dropped_combat_loot:
		if item == null:
			continue
		names.append(item.display_name if not item.display_name.is_empty() else item.id)
	return names
