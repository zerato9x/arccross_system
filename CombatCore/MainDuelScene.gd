extends Node2D

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

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var enemy_entity_id: String = ""

var dropped_combat_loot: Array[ItemData] = []

func _ready() -> void:
	lane_hud.action_requested.connect(command_adapter.request_player_action)
	lane_hud.pass_requested.connect(command_adapter.pass_player_turn)
	lane_hud.reaction_selected.connect(
		command_adapter.resolve_player_reaction
	)
	command_adapter.snapshot_changed.connect(lane_hud.show_snapshot)
	command_adapter.presentation_event.connect(
		lane_hud.show_presentation_event
	)
	command_adapter.reaction_requested.connect(lane_hud.show_reaction)
	command_adapter.command_feedback.connect(lane_hud.show_feedback)
	lane_hud.open_hud()

	# AUTO-TEST BOOTSTRAP: Only run if we are testing the scene directly!
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		print("\n>>> INITIALIZING ARCCROSS COMBAT SIMULATION (STANDALONE) <<<")
		var p_def = preload("res://BiologicalCore/player_def.tres")
		var e_def = preload("res://BiologicalCore/scavenger_def.tres")
		if p_def and e_def:
			setup_duel_from_records(
				{
					"entity_id": "standalone_player",
					"definition": p_def.to_state(),
					"runtime": {},
				},
				{
					"entity_id": "standalone_enemy",
					"definition": e_def.to_state(),
					"runtime": {},
				}
			)
		else:
			print("Failed to load entity definitions for test.")

func setup_duel_from_records(
	player_record: Dictionary,
	enemy_record: Dictionary,
	encounter_setup: Dictionary = {}
) -> void:
	_clear_humanoid_cores()

	enemy_entity_id = enemy_record.get("entity_id", "")
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
	if enemy_core and enemy_core.inventory:
		enemy_core.inventory.items_spilled.connect(
			_on_items_spilled.bind(enemy_core)
		)
	_begin_duel(encounter_setup)


## Legacy test entry: reuses an existing player core node.
func setup_duel(
	existing_player_core: HumanoidCore,
	enemy_record: Dictionary,
	encounter_setup: Dictionary = {}
) -> void:
	if not existing_player_core:
		push_error("Cannot start duel without an authoritative player core.")
		return

	for child in get_children():
		if child is HumanoidCore and child != existing_player_core:
			child.queue_free()

	if lane_manager:
		for slot in lane_manager.lane_slots:
			slot.occupants.clear()
			slot.is_melee_locked = false
			slot.grapple_stance_scale = 12

	player_core = existing_player_core
	enemy_entity_id = enemy_record.get("entity_id", "")
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
	if enemy_core and enemy_core.inventory:
		enemy_core.inventory.items_spilled.connect(
			_on_items_spilled.bind(enemy_core)
		)
	_begin_duel(encounter_setup)


func _clear_humanoid_cores() -> void:
	for child in get_children():
		if child is HumanoidCore:
			child.queue_free()
	player_core = null
	enemy_core = null

	if lane_manager:
		for slot in lane_manager.lane_slots:
			slot.occupants.clear()
			slot.is_melee_locked = false
			slot.grapple_stance_scale = 12


func _begin_duel(encounter_setup: Dictionary = {}) -> void:
	if player_core == null or enemy_core == null:
		push_error("Cannot begin duel without player and enemy cores.")
		return

	player_core.reset_combat_transients()
	enemy_core.reset_combat_transients()

	if not player_core.inventory.items_spilled.is_connected(_on_player_items_spilled):
		player_core.inventory.items_spilled.connect(_on_player_items_spilled)

	if not turn_manager.entity_escaped.is_connected(_on_entity_escaped):
		turn_manager.entity_escaped.connect(_on_entity_escaped)

	player_core.died.connect(_on_combatant_died.bind(player_core))
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))

	command_adapter.configure(
		player_core,
		enemy_core,
		lane_manager,
		turn_manager,
		resolution_engine
	)

	_wire_combat_audio(player_core)

	encounter_builder.build_encounter(
		player_core,
		enemy_core,
		encounter_setup
	)
	command_adapter.refresh_snapshot()


func _wire_combat_audio(core: HumanoidCore) -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus == null or core == null:
		return
	if not core.kinetic_burden_calculated.is_connected(_on_kinetic_burden_changed):
		core.kinetic_burden_calculated.connect(_on_kinetic_burden_changed)
	if not core.stance_changed.is_connected(_on_stance_changed):
		core.stance_changed.connect(_on_stance_changed)
	if not core.morale_broken.is_connected(_on_morale_broken):
		core.morale_broken.connect(_on_morale_broken)
	if not core.died.is_connected(_on_player_died_audio):
		core.died.connect(_on_player_died_audio)
	if not resolution_engine.first_combat_action.is_connected(_on_first_strike_audio):
		resolution_engine.first_combat_action.connect(_on_first_strike_audio)
	resolution_engine.reset_first_strike()


func _on_kinetic_burden_changed(tier: GameEnums.KineticTier, burden: int) -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_player_vitals({
			"type": "kinetic_tier",
			"tier": tier,
			"burden": burden,
		})


func _on_stance_changed(new_state: GameEnums.StanceState, points: int) -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_player_vitals({
			"type": "stance",
			"stance": new_state,
			"points": points,
		})


func _on_morale_broken() -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_player_vitals({"type": "morale_broken"})


func _on_player_died_audio(cause: String) -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_player_vitals({"type": "player_died", "cause": cause})


func _on_first_strike_audio(action_type: int) -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_scene_audio("first_strike", {"action_type": action_type})

## Alternative entry: spawn a procedural enemy from MobSpawner records.
func setup_duel_procedural(
	player_record: Dictionary,
	enemy_faction: GameEnums.Faction,
	difficulty: int = 0
) -> void:
	var mob_spawner := get_node_or_null("/root/MobSpawner") as MobSpawner
	if mob_spawner == null:
		push_error("MobSpawner unavailable for procedural duel setup.")
		return
	var enemy_record := mob_spawner.generate_mob_record(
		Vector2i.ZERO,
		enemy_faction,
		difficulty
	)
	setup_duel_from_records(player_record, enemy_record.to_dict())


## Test-only helper. Production handoffs use setup_duel_from_records().
func _fabricate_humanoid(
	unit_name: String,
	definition: EntityDefinition,
	attach_ai: bool,
	runtime_state: Dictionary = {}
) -> HumanoidCore:
	var core := EntityFactory.record_to_humanoid_core(
		{
			"definition": definition.to_state(),
			"runtime": runtime_state,
		},
		self,
		unit_name,
		attach_ai,
		lane_manager,
		turn_manager,
		resolution_engine,
		Callable()
	)
	return core


func _on_items_spilled(spilled_items: Array[ItemData], entity: HumanoidCore) -> void:
	print("[COMBAT DROPS] ", entity.name, " spilled ", spilled_items.size(), " items into the dirt!")
	_append_dropped_items(spilled_items)

func _on_player_items_spilled(spilled_items: Array[ItemData]) -> void:
	_on_items_spilled(spilled_items, player_core)

func _on_combatant_died(cause: String, dead_entity: HumanoidCore) -> void:
	turn_manager.halt_loop()
	if dead_entity == enemy_core:
		_append_dropped_items(enemy_core.inventory.drain_all_items())
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_DEFEAT
		if dead_entity == player_core
		else GameEnums.CombatOutcome.PLAYER_VICTORY
	)
	var winner := enemy_core if dead_entity == player_core else player_core

	print("\n[DUEL RESOLVED] ", winner.name, " stands victorious. Cause of death: ", cause)
	if lane_hud and dead_entity == enemy_core:
		await lane_hud.show_resolve_screen({
			"title": "Combat Resolved",
			"focus_side": "enemy",
			"dead_side": "enemy",
			"dead_name": dead_entity.name,
			"cause": cause,
			"loot_names": _dropped_item_names(),
		})
	lane_hud.close_hud()
	_clear_encounter_transients()
	duel_finished.emit(
		outcome,
		enemy_entity_id,
		capture_enemy_runtime_state(),
		capture_player_runtime_state(),
		_capture_dropped_item_states()
	)
	
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		if winner == player_core:
			print("\n[SYSTEM] Standalone Test: Player won! Spawning next mob in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(_spawn_next_mob)
		else:
			print("\n[SYSTEM] Standalone Test: Player died! Reloading scene in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(func(): get_tree().reload_current_scene())

func _on_entity_escaped(escaper: HumanoidCore) -> void:
	turn_manager.halt_loop()
	lane_hud.close_hud()
	print("\n[DUEL ESCAPED] ", escaper.name, " has successfully fled the battlefield!")
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_ESCAPED
		if escaper == player_core
		else GameEnums.CombatOutcome.ENEMY_ESCAPED
	)
	_clear_encounter_transients()
	duel_finished.emit(
		outcome,
		enemy_entity_id,
		capture_enemy_runtime_state(),
		capture_player_runtime_state(),
		_capture_dropped_item_states()
	)
	
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		print("\n[SYSTEM] Standalone Test: Entity escaped! Spawning next mob in 2 seconds...")
		get_tree().create_timer(2.0).timeout.connect(_spawn_next_mob)

func _spawn_next_mob() -> void:
	if is_instance_valid(enemy_core):
		turn_manager.combatants.erase(enemy_core)
		lane_manager.remove_entity(enemy_core)
		enemy_core.queue_free()
		
	# Generate new enemy from MobSpawner record
	var mob_spawner := get_node_or_null("/root/MobSpawner") as MobSpawner
	if mob_spawner == null:
		return
	var factions := [
		GameEnums.Faction.CRAVEN_HIVE,
		GameEnums.Faction.SCAVENGER_CELL,
	]
	var enemy_record := mob_spawner.generate_mob_record(
		Vector2i.ZERO,
		factions.pick_random(),
		randi() % 3
	)
	enemy_core = EntityFactory.record_to_humanoid_core(
		enemy_record.to_dict(),
		self,
		"Endless_Mob",
		true,
		lane_manager,
		turn_manager,
		resolution_engine,
		Callable()
	)
	if enemy_core and enemy_core.inventory:
		enemy_core.inventory.items_spilled.connect(
			_on_items_spilled.bind(enemy_core)
		)
	
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	lane_manager.force_spawn_entity(enemy_core, 9)
	
	turn_manager.combatants.append(enemy_core)
	turn_manager.reserved_ap[enemy_core] = 0
	command_adapter.configure(
		player_core,
		enemy_core,
		lane_manager,
		turn_manager,
		resolution_engine
	)
	lane_hud.open_hud()
	command_adapter.refresh_snapshot()
	print("\n>>> NEW CHALLENGER APPROACHES <<<")
	turn_manager.resume_loop()

func capture_enemy_runtime_state() -> Dictionary:
	if not enemy_core:
		return {}
	return enemy_core.capture_runtime_state().to_dict()


func capture_player_runtime_state() -> Dictionary:
	if not player_core:
		return {}
	return player_core.capture_runtime_state().to_dict()

func _clear_encounter_transients() -> void:
	if player_core:
		player_core.reset_combat_transients()
	if enemy_core:
		enemy_core.reset_combat_transients()

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
		var label := item.display_name
		if label.is_empty():
			label = item.id
		if not label.is_empty():
			names.append(label)
	return names

func _append_dropped_items(items: Array[ItemData]) -> void:
	var known_ids: Dictionary = {}
	for existing in dropped_combat_loot:
		known_ids[existing.instance_id] = true

	for item in items:
		if item == null or known_ids.has(item.instance_id):
			continue
		dropped_combat_loot.append(item)
		known_ids[item.instance_id] = true
