extends Node2D

@onready var lane_manager: CombatLaneManager = $CombatLaneManager
@onready var turn_manager: CombatTurnManager = $CombatTurnManager
@onready var resolution_engine: CombatResolutionEngine = $CombatResolutionEngine
@onready var encounter_builder: EncounterBuilder = $EncounterBuilder
@onready var debug_log: RichTextLabel = $DebugUI/DebugLog

var player_core: HumanoidCore
var enemy_core: HumanoidCore

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
	
	add_child(core)
	return core

func _refresh_debug_hud() -> void:
	if not player_core or not enemy_core: return
	
	var txt = ""
	txt += "[color=green]=== ARCCROSS COMBAT LANE CONSOLE ===[/color]\n"
	txt += "ROUND: %d | ACTIVE TIMEPOOL POOL: %d AP\n" % [turn_manager.current_round, turn_manager.current_ap_pool]
	txt += "---------------------------------------------------------\n\n"
	
	# Build Player Data Cluster
	txt += "[b]%s[/b] (Flee State: %s)\n" % [player_core.name, str(player_core.is_fleeing)]
	txt += "Vitals -> Max AP Limit: %d | Blood Vol: %.2f | Morale: %.1f\n" % [player_core.current_max_ap, player_core.body.blood_level, player_core.current_morale]
	txt += "Trauma Matrix -> Torso: %.1f HP | Head: %.1f HP | L-Arm: %.1f HP\n\n" % [player_core.body.limb_hp[GameEnums.Limb.TORSO], player_core.body.limb_hp[GameEnums.Limb.HEAD], player_core.body.limb_hp[GameEnums.Limb.LEFT_ARM]]
	
	# Build Enemy Data Cluster
	txt += "[b]%s[/b] (Flee State: %s)\n" % [enemy_core.name, str(enemy_core.is_fleeing)]
	txt += "Vitals -> Max AP Limit: %d | Blood Vol: %.2f | Morale: %.1f\n" % [enemy_core.current_max_ap, enemy_core.body.blood_level, enemy_core.current_morale]
	txt += "Trauma Matrix -> Torso: %.1f HP | Head: %.1f HP | L-Arm: %.1f HP\n" % [enemy_core.body.limb_hp[GameEnums.Limb.TORSO], enemy_core.body.limb_hp[GameEnums.Limb.HEAD], enemy_core.body.limb_hp[GameEnums.Limb.LEFT_ARM]]
	
	debug_log.text = txt

func _on_turn_cycled(_active_entity: HumanoidCore) -> void:
	_refresh_debug_hud()

func _on_action_logged(_entity: HumanoidCore, _remaining_ap: int) -> void:
	_refresh_debug_hud()
