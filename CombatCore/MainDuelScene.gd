extends Node2D

@onready var lane_manager: CombatLaneManager = $CombatLaneManager
@onready var turn_manager: CombatTurnManager = $CombatTurnManager
@onready var resolution_engine: CombatResolutionEngine = $CombatResolutionEngine
@onready var encounter_builder: EncounterBuilder = $EncounterBuilder
@onready var mob_spawner: MobSpawner = $MobSpawner
@onready var debug_log: RichTextLabel = $DebugUI/DebugLog

var player_core: HumanoidCore
var enemy_core: HumanoidCore

var dropped_combat_loot: Array[ItemData] = []

func setup_duel(p_def: EntityDefinition, e_def: EntityDefinition) -> void:
	# 1. Programmatically assemble the complex entity structures from scratch
	player_core = _fabricate_humanoid("Player_Unit", p_def)
	enemy_core = _fabricate_humanoid("Enemy_Scavenger", e_def)
	
	# 2. Wire up status alerts to update our visual console readouts
	turn_manager.turn_started.connect(_on_turn_cycled)
	turn_manager.ap_spent.connect(_on_action_logged)
	
	# 3. Drop them into the mud using our tactical layout matrix
	encounter_builder.build_encounter(player_core, enemy_core, GameEnums.EncounterContext.NEUTRAL_MEET)
	_refresh_debug_hud()

## Alternative entry: spawn a procedural enemy from the MobSpawner.
func setup_duel_procedural(p_def: EntityDefinition, enemy_faction: GameEnums.Faction, difficulty: int = 0) -> void:
	var e_def: EntityDefinition = mob_spawner.generate_mob(enemy_faction, difficulty)
	setup_duel(p_def, e_def)

func _fabricate_humanoid(unit_name: String, definition: EntityDefinition) -> HumanoidCore:
	# Programmatic assembly since we are bypassing custom .tscn instantiation
	var core = HumanoidCore.new()
	core.name = unit_name
	core.definition = definition
	
	var body = HumanoidBody.new()
	body.name = "HumanoidBody"
	core.add_child(body)
	core.body = body
	
	var inv = InventorySystem.new()
	inv.name = "InventorySystem"
	core.add_child(inv)
	core.inventory = inv
	
	# Connect to the items spilled signal
	inv.items_spilled.connect(_on_items_spilled.bind(core))
	
	add_child(core)
	
	# After _ready() fires and the inventory paper_doll is built, apply the loadout
	if definition.loadout:
		definition.loadout.apply_to(inv)
		print("[FABRICATE] ", unit_name, " spawned with loadout. Weight: ", inv.get_total_weight(), " | Threat: ", inv.get_total_threat())
	else:
		print("[FABRICATE] ", unit_name, " spawned naked. No loadout assigned.")
	
	return core

func _refresh_debug_hud() -> void:
	if not player_core or not enemy_core: return
	
	var txt = ""
	txt += "[color=green]=== ARCCROSS COMBAT LANE CONSOLE ===[/color]\n"
	txt += "ROUND: %d | ACTIVE TIMEPOOL POOL: %d AP\n" % [turn_manager.current_round, turn_manager.current_ap_pool]
	txt += "---------------------------------------------------------\n\n"
	
	txt += _build_entity_readout(player_core)
	txt += "\n"
	txt += _build_entity_readout(enemy_core)
	
	debug_log.text = txt

func _build_entity_readout(entity: HumanoidCore) -> String:
	var t = ""
	var weapon_name: String = "UNARMED"
	var held = entity.inventory.paper_doll.get(GameEnums.EquipmentSlot.HANDS)
	if held: weapon_name = held.display_name
	
	t += "[b]%s[/b] (%s) | Flee: %s\n" % [entity.name, entity.definition.archetype_name, str(entity.is_fleeing)]
	t += "Vitals -> AP: %d | Blood: %.2f | Morale: %.1f\n" % [entity.current_max_ap, entity.body.blood_level, entity.current_morale]
	t += "Stance -> %s (%d/12) | Weapon: %s\n" % [GameEnums.StanceState.keys()[entity.current_stance], entity.stance_points, weapon_name]
	t += "Gear -> THREAT: %.1f | WEIGHT: %.1f | BULK: %.1f | Inventory: %d/%d\n" % [entity.get_effective_threat(), entity.inventory.get_total_weight(), entity.get_bulk_modifier(), entity.inventory.current_size, entity.inventory.current_max_capacity]
	t += "Trauma -> U-Torso: %.1f | Head: %.1f | L-Arm: %.1f\n" % [entity.body.limb_hp[GameEnums.LimbRegion.UPPER_TORSO], entity.body.limb_hp[GameEnums.LimbRegion.HEAD], entity.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM]]
	return t

func _on_turn_cycled(_active_entity: HumanoidCore) -> void:
	_refresh_debug_hud()

func _on_action_logged(_entity: HumanoidCore, _remaining_ap: int) -> void:
	_refresh_debug_hud()

func _on_items_spilled(spilled_items: Array[ItemData], entity: HumanoidCore) -> void:
	print("[COMBAT DROPS] ", entity.name, " spilled ", spilled_items.size(), " items into the dirt!")
	dropped_combat_loot.append_array(spilled_items)
