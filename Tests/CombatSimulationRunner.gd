extends SceneTree

const PLAYER_DEF := "res://BiologicalCore/player_def.tres"
const SCAVENGER_DEF := "res://BiologicalCore/scavenger_def.tres"

const WEAPONS := [
	"res://ItemCore/Items/makeshift_sidearm.tres",
	"res://ItemCore/Items/rusty_pipe.tres",
	"res://ItemCore/Items/scrap_pipe.tres",
	"" # Unarmed
]

func _initialize() -> void:
	call_deferred("_run_simulation")

func _run_simulation() -> void:
	print("--- STARTING COMBAT SIMULATION SYSTEM ---")
	
	var duel_scene_prefab := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	if not duel_scene_prefab:
		_fail("Could not load res://CombatCore/MainDuelScene.tscn")
		return
		
	var player_definition := load(PLAYER_DEF) as EntityDefinition
	var scavenger_definition := load(SCAVENGER_DEF) as EntityDefinition
	if not player_definition or not scavenger_definition:
		_fail("Could not load entity definitions.")
		return
		
	var total_battles := 5
	var success_count := 0
	
	for i in range(total_battles):
		print("\n==================================================")
		print("SIMULATING BATTLE ", i + 1, " OF ", total_battles)
		print("==================================================")
		
		# 1. Instantiate the arena
		var arena = duel_scene_prefab.instantiate()
		root.add_child(arena)
		await process_frame
		
		# 2. Fabricate the player with AI attached so it fights automatically
		var battle_player: HumanoidCore = arena._fabricate_humanoid(
			"Sim_Player",
			player_definition,
			true # attach_ai
		)
		
		# Randomize brawn / finesse
		battle_player.definition.brawn = randi_range(3, 12)
		battle_player.definition.finesse = randi_range(3, 12)
		battle_player.definition.fortitude = randi_range(3, 12)
		battle_player.definition.will = randi_range(3, 12)
		
		# Clear inventory and give backpack + random weapon
		battle_player.inventory.backpack_array.clear()
		for slot in battle_player.inventory.paper_doll.keys():
			battle_player.inventory.paper_doll[slot] = null
		
		var backpack_res = load("res://ItemCore/Items/military_backpack.tres")
		if backpack_res:
			battle_player.inventory.equip_item(backpack_res.create_runtime_instance(), GameEnums.EquipmentSlot.BACKPACK)
			
		var player_weapon_path = WEAPONS[randi() % WEAPONS.size()]
		if not player_weapon_path.is_empty():
			var weapon_res = load(player_weapon_path)
			if weapon_res:
				var weapon_instance = weapon_res.create_runtime_instance()
				battle_player.inventory.equip_item(weapon_instance, GameEnums.EquipmentSlot.HANDS)
				if weapon_instance.is_ranged():
					_supply_ammunition(
						battle_player.inventory,
						weapon_instance,
						18
					)
		
		# 3. Setup the duel. MainDuelScene will fabricate the enemy scavenger using setup_duel.
		var enemy_definition_copy = scavenger_definition.duplicate() as EntityDefinition
		enemy_definition_copy.brawn = randi_range(3, 12)
		enemy_definition_copy.finesse = randi_range(3, 12)
		enemy_definition_copy.fortitude = randi_range(3, 12)
		enemy_definition_copy.will = randi_range(3, 12)
		
		var tactics = [
			GameEnums.CombatTactic.MARKSMAN,
			GameEnums.CombatTactic.BRUTE,
			GameEnums.CombatTactic.OPPORTUNIST,
			GameEnums.CombatTactic.DEFENDER
		]
		enemy_definition_copy.combat_tactic = tactics[randi() % tactics.size()]
		
		var contexts = [
			GameEnums.EncounterContext.NEUTRAL_MEET,
			GameEnums.EncounterContext.PLAYER_AMBUSH,
			GameEnums.EncounterContext.ENEMY_AMBUSH,
			GameEnums.EncounterContext.DIALOGUE_BREAKDOWN
		]
		var encounter_context = contexts[randi() % contexts.size()]
		
		var positions = [
			GameEnums.AmbushPosition.FAR,
			GameEnums.AmbushPosition.STANDARD,
			GameEnums.AmbushPosition.CLOSE
		]
		var ambush_pos = positions[randi() % positions.size()]
		
		var setup_dict = {
			"context": encounter_context,
			"ambush_position": ambush_pos,
			"initiator_id": "player" if randf() > 0.5 else "enemy"
		}
		
		# Randomize tile backgrounds or covers to test cover/hazard logic
		for slot in arena.lane_manager.lane_slots:
			if randf() < 0.25:
				slot.background = CombatRules.TileBackground.MUD
			if randf() < 0.2:
				slot.current_cover = CombatRules.TileObject.COVER
				slot.object_name = "Debris Cover"
				slot.object_durability = 10.0
		
		var enemy_weapon_path = WEAPONS[randi() % WEAPONS.size()]
		var enemy_def_state = enemy_definition_copy.to_state()
		
		arena.setup_duel(
			battle_player,
			{
				"entity_id": "sim_enemy_" + str(i),
				"definition": enemy_def_state,
				"runtime": {},
			},
			setup_dict
		)
		
		# Let's equip the enemy with a specific weapon if chosen
		if not enemy_weapon_path.is_empty():
			var weapon_res = load(enemy_weapon_path)
			if weapon_res:
				var weapon_instance = weapon_res.create_runtime_instance()
				# Clear enemy's hands
				arena.enemy_core.inventory.paper_doll.erase(GameEnums.EquipmentSlot.HANDS)
				arena.enemy_core.inventory.equip_item(weapon_instance, GameEnums.EquipmentSlot.HANDS)
				if weapon_instance.is_ranged():
					_supply_ammunition(
						arena.enemy_core.inventory,
						weapon_instance,
						18
					)
		
		# Start the duel loop
		print("Duel starting: ", battle_player.name, " (", GameEnums.CombatTactic.keys()[battle_player.definition.combat_tactic], ") vs ", arena.enemy_core.name, " (", GameEnums.CombatTactic.keys()[arena.enemy_core.definition.combat_tactic], ")")
		print("Context: ", GameEnums.EncounterContext.keys()[encounter_context], " | Ambush Pos: ", GameEnums.AmbushPosition.keys()[ambush_pos])
		
		var duel_outcome_wrapper := { "outcome": null }
		var start_ticks = Time.get_ticks_msec()
		var max_simulation_ms = 15000 # 15 seconds
		
		var handle_finished = func(outcome: int, _enemy_id: String, _enemy_runtime: Dictionary, _dropped_items: Array):
			duel_outcome_wrapper.outcome = outcome
			
		arena.duel_finished.connect(handle_finished)
		
		# Kick off the turn loop
		arena.turn_manager.resume_loop()
		
		while duel_outcome_wrapper.outcome == null:
			await process_frame
			if arena.turn_manager.current_round > 50:
				print("[STALEMATE] Battle exceeded 50 rounds without casualties. Declaring a DRAW.")
				arena.turn_manager.halt_loop()
				duel_outcome_wrapper.outcome = GameEnums.CombatOutcome.DRAW
				break
				
			if Time.get_ticks_msec() - start_ticks > max_simulation_ms:
				print("[TIMEOUT WARNING] Battle exceeded ", max_simulation_ms, " ms! Aborting duel to check for deadlock.")
				arena.turn_manager.halt_loop()
				duel_outcome_wrapper.outcome = -999
				break
				
		arena.duel_finished.disconnect(handle_finished)
		
		# Clean up nodes
		arena.queue_free()
		await process_frame
		await process_frame
		
		if duel_outcome_wrapper.outcome == -999:
			_fail("Simulation deadlocked in battle " + str(i + 1))
			return
		else:
			print("Battle ", i + 1, " finished with outcome: ", GameEnums.CombatOutcome.keys()[duel_outcome_wrapper.outcome])
			success_count += 1
			
	print("\n--- ALL SIMULATIONS COMPLETE ---")
	print("Successful Battles: ", success_count, " / ", total_battles)
	quit(0)

func _fail(message: String) -> void:
	push_error("[SIMULATION FAILED] " + message)
	quit(1)

func _supply_ammunition(
	inventory: InventorySystem,
	weapon: ItemData,
	round_count: int
) -> void:
	if weapon.ammunition_id.is_empty():
		return
	var ammo_definition := load(
		"res://ItemCore/Items/%s.tres" % weapon.ammunition_id
	) as ItemData
	if ammo_definition:
		for _round_index in range(round_count):
			inventory.add_to_backpack(ammo_definition)

	for support_id in [weapon.magazine_id, weapon.reload_aid_id]:
		if support_id.is_empty():
			continue
		var support_definition := load(
			"res://ItemCore/Items/%s.tres" % support_id
		) as ItemData
		if support_definition:
			inventory.add_to_backpack(support_definition)
