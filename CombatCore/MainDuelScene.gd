extends Node2D

signal duel_finished(
	outcome: GameEnums.CombatOutcome,
	enemy_id: String,
	enemy_runtime: Dictionary,
	player_runtime: Dictionary,
	dropped_items: Array
)

@onready var lane_manager: CombatLaneManager = $CombatLaneManager
@onready var damage_resolver: RealtimeDamageResolver = $RealtimeDamageResolver
@onready var duel_runtime: RealtimeDuelRuntime = $RealtimeDuelRuntime
@onready var encounter_builder: RealtimeEncounterBuilder = $RealtimeEncounterBuilder
@onready var lane_hud: RealtimeDuelHUD = $RealtimeDuelHUD
@onready var combat_briefing: CombatBriefingOverlay = %CombatBriefingOverlay

## Transitional aliases for integrations that only need to halt/escape or read
## a snapshot. They now point at the real-time authority, not a secret turn loop.
@onready var turn_manager: RealtimeDuelRuntime = $RealtimeDuelRuntime
@onready var command_adapter: RealtimeDuelRuntime = $RealtimeDuelRuntime

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var enemy_entity_id := ""
var dropped_combat_loot: Array[ItemData] = []
var _enemy_ai: RealtimeDuelAI
var _resolving := false

func _ready() -> void:
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		var player_definition := preload("res://BiologicalCore/player_def.tres")
		var enemy_definition := preload("res://BiologicalCore/scavenger_def.tres")
		setup_duel_from_records(
			{
				"entity_id": "standalone_player",
				"definition": player_definition.to_state(),
				"runtime": {},
			},
			{
				"entity_id": "standalone_enemy",
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
		false
	)
	enemy_core = EntityFactory.record_to_humanoid_core(
		enemy_record,
		self,
		"Enemy_Scavenger",
		false
	)
	_begin_duel(encounter_setup)

func setup_duel(
	existing_player_core: HumanoidCore,
	enemy_record: Dictionary,
	encounter_setup: Dictionary = {}
) -> void:
	if existing_player_core == null:
		push_error("Cannot start real-time duel without a player core.")
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
		false
	)
	_begin_duel(encounter_setup)

func setup_duel_procedural(
	player_record: Dictionary,
	enemy_faction: GameEnums.Faction,
	difficulty: int = 0
) -> void:
	var mob_spawner := get_node_or_null("/root/MobSpawner") as MobSpawner
	if mob_spawner == null:
		push_error("MobSpawner unavailable for procedural duel setup.")
		return
	var record := mob_spawner.generate_mob_record(
		Vector2i.ZERO,
		enemy_faction,
		difficulty
	)
	setup_duel_from_records(player_record, record.to_dict())

func _fabricate_humanoid(
	unit_name: String,
	definition: EntityDefinition,
	_attach_ai: bool,
	runtime_state: Dictionary = {}
) -> HumanoidCore:
	return EntityFactory.record_to_humanoid_core(
		{
			"definition": definition.to_state(),
			"runtime": runtime_state,
		},
		self,
		unit_name,
		false
	)

func _begin_duel(encounter_setup: Dictionary) -> void:
	if player_core == null or enemy_core == null:
		push_error("Cannot begin duel without both combatants.")
		return
	_resolving = false
	dropped_combat_loot.clear()
	player_core.reset_combat_transients()
	enemy_core.reset_combat_transients()
	if not player_core.inventory.items_spilled.is_connected(_on_player_items_spilled):
		player_core.inventory.items_spilled.connect(_on_player_items_spilled)
	if not enemy_core.inventory.items_spilled.is_connected(_on_enemy_items_spilled):
		enemy_core.inventory.items_spilled.connect(_on_enemy_items_spilled)
	player_core.died.connect(_on_combatant_died.bind(player_core))
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	if not duel_runtime.entity_escaped.is_connected(_on_entity_escaped):
		duel_runtime.entity_escaped.connect(_on_entity_escaped)

	encounter_builder.build_encounter(
		player_core,
		enemy_core,
		encounter_setup
	)
	duel_runtime.configure(player_core, enemy_core)
	lane_hud.configure(duel_runtime, player_core)
	lane_hud.open_hud()

	_enemy_ai = RealtimeDuelAI.new()
	_enemy_ai.name = "RealtimeDuelAI"
	enemy_core.add_child(_enemy_ai)
	_enemy_ai.configure(enemy_core, player_core, duel_runtime, lane_manager)
	_wire_combat_audio(player_core)
	await combat_briefing.open_briefing({
		"mode": "REAL-TIME DUEL",
		"opponent": enemy_core.definition.archetype_name,
		"context": "Both combatants are loaded. AP, bleeding, AI, and action timelines remain frozen until READY clears.",
		"controls": "A / D MOVE   //   LMB STRIKE OR FIRE   //   RMB HEAVY OR AIM   //   SPACE BLOCK / PARRY   //   R SERVICE WEAPON",
	})
	if not _resolving and is_instance_valid(duel_runtime):
		duel_runtime.begin_duel()

func _wire_combat_audio(core: HumanoidCore) -> void:
	if core == null:
		return
	if not core.kinetic_burden_calculated.is_connected(_on_kinetic_burden_changed):
		core.kinetic_burden_calculated.connect(_on_kinetic_burden_changed)

func _on_kinetic_burden_changed(tier: GameEnums.KineticTier, burden: int) -> void:
	var bus := get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_player_vitals({"type": "kinetic_tier", "tier": tier, "burden": burden})

func _on_player_items_spilled(items: Array[ItemData]) -> void:
	_append_dropped_items(items)

func _on_enemy_items_spilled(items: Array[ItemData]) -> void:
	_append_dropped_items(items)

func _on_combatant_died(cause: String, dead_entity: HumanoidCore) -> void:
	if _resolving:
		return
	_resolving = true
	duel_runtime.stop()
	duel_runtime.refresh_snapshot()
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_DEFEAT
		if dead_entity == player_core
		else GameEnums.CombatOutcome.PLAYER_VICTORY
	)
	await lane_hud.play_final_blow("player" if dead_entity == player_core else "enemy")
	# Drain after Die presentation so corpse tokens keep clothing layers.
	if dead_entity == enemy_core:
		_append_dropped_items(enemy_core.inventory.drain_all_items())
	if DisplayServer.get_name() != "headless":
		await lane_hud.show_resolve_screen({
			"title": "DEFEAT" if dead_entity == player_core else "VICTORY",
			"result": (
				"YOUR BODY CAN NO LONGER CONTINUE"
				if dead_entity == player_core
				else "OPPONENT NEUTRALIZED"
			),
			"dead_name": dead_entity.name,
			"dead_side": "player" if dead_entity == player_core else "enemy",
			"cause": cause,
			"loot_count": dropped_combat_loot.size(),
		})
	_finish_duel(outcome)

func _on_entity_escaped(entity: HumanoidCore) -> void:
	if _resolving:
		return
	_resolving = true
	duel_runtime.stop()
	duel_runtime.refresh_snapshot()
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_ESCAPED
		if entity == player_core
		else GameEnums.CombatOutcome.ENEMY_ESCAPED
	)
	if DisplayServer.get_name() != "headless":
		await lane_hud.show_resolve_screen({
			"title": "DISENGAGED",
			"result": "YOU ESCAPED THE LANE" if entity == player_core else "OPPONENT ESCAPED",
			"focus_side": "player" if entity == player_core else "enemy",
			"cause": "The duel ended by separation, not death.",
			"loot_count": dropped_combat_loot.size(),
		})
	_finish_duel(outcome)

func _finish_duel(outcome: GameEnums.CombatOutcome) -> void:
	_clear_encounter_transients()
	var enemy_runtime := capture_enemy_runtime_state()
	var player_runtime := capture_player_runtime_state()
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
	if player_core:
		player_core.reset_combat_transients()
	if enemy_core:
		enemy_core.reset_combat_transients()

func _clear_humanoid_cores(keep: HumanoidCore = null) -> void:
	duel_runtime.stop()
	for slot in lane_manager.lane_slots:
		slot.occupants.clear()
		slot.is_melee_locked = false
		slot.trap_armed = false
		slot.trap_owner_side = ""
	for child in get_children():
		if child is HumanoidCore and child != keep:
			child.queue_free()
	player_core = null
	enemy_core = null

func _capture_dropped_item_states() -> Array:
	var states: Array = []
	for item in dropped_combat_loot:
		states.append(item.to_runtime_state())
	return states

func _append_dropped_items(items: Array[ItemData]) -> void:
	var known: Dictionary = {}
	for existing in dropped_combat_loot:
		known[existing.instance_id] = true
	for item in items:
		if item == null or known.has(item.instance_id):
			continue
		dropped_combat_loot.append(item)
		known[item.instance_id] = true
