extends SceneTree

const _Catalog := preload("res://CombatCore/Tactical/default_combat_action_catalog.tres")
const _QuoteService := preload("res://CombatCore/Tactical/CombatActionQuoteService.gd")
const _RulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")

var _rules: CombatRulesState


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_rules = _RulesState.new()
	_rules.current_ap_pool = 99
	_rules.active_actor_id = "player"
	for definition in _Catalog.all():
		_rules.action_definitions[definition.action_id] = definition
	_rules.coordinates_by_index = {
		0: Vector2i(0, 0),
		1: Vector2i(1, 0),
		2: Vector2i(2, 0),
	}
	_rules.indices_by_coordinate = {"0,0": 0, "1,0": 1, "2,0": 2}
	_rules.neighbors = {0: [1], 1: [0, 2], 2: [1]}
	_rules.occupancy = {0: ["player"], 1: ["enemy"], 2: []}
	_rules.relationships = {
		CombatRelationshipLedger.pair_key("player", "enemy"): CombatRelationshipLedger.Relation.HOSTILE,
	}
	_rules.sector_facts = {
		0: _sector(Vector2i(0, 0), "enemy", [], {}),
		1: _sector(Vector2i(1, 0), "", ["ground-1"], {}),
		2: _sector(Vector2i(2, 0), "", [], {}),
	}
	_rules.ground_items = {"ground-1": {"instance_id": "ground-1"}}
	_rules.actor_facts = {
		"player": _actor("player", 0, "player", false),
		"enemy": _actor("enemy", 1, "enemy", false),
	}

	if not _denied(_request("escape"), "escape_edge_required"):
		return
	_rules.sector_facts[0]["escape_side"] = "player"
	if not _allowed(_request("escape")):
		return
	_rules.sector_facts[0]["escape_side"] = "enemy"

	var cover_request := _request("take_cover")
	cover_request.target_actor_id = "enemy"
	if not _denied(cover_request, "cover_edge_missing"):
		return
	_rules.sector_facts[0]["cover_edges"] = {"east": 1.0}
	if not _allowed(cover_request):
		return
	_rules.sector_facts[0]["cover_edges"] = {}

	if not _denied(_request("leave_battle"), "player_hostile_active"):
		return
	_rules.actor_facts["enemy"]["surrendered"] = true
	if not _allowed(_request("leave_battle")):
		return
	_rules.actor_facts["enemy"]["surrendered"] = false

	var terminal_request := _request("incapacitate")
	terminal_request.target_actor_id = "enemy"
	if not _denied(terminal_request, "target_not_broken"):
		return
	_rules.actor_facts["enemy"]["broken"] = true
	if not _allowed(terminal_request):
		return
	_rules.actor_facts["enemy"]["incapacitated"] = true
	if not _denied(terminal_request, "already_incapacitated"):
		return
	_rules.actor_facts["enemy"]["broken"] = false
	_rules.actor_facts["enemy"]["comatose"] = true
	_rules.actor_facts["enemy"]["sector_index"] = -1
	_rules.actor_facts["enemy"]["sector"] = Vector2i(-1, -1)
	_rules.actor_facts["enemy"]["active_on_board"] = false
	_rules.actor_facts["enemy"]["handoff_sector_index"] = 1
	_rules.actor_facts["enemy"]["handoff_sector"] = Vector2i(1, 0)
	_rules.actor_facts["enemy"]["handoff_layer"] = "incapacitated"
	var execute_request := _request("execute")
	execute_request.target_actor_id = "enemy"
	if not _allowed(execute_request):
		return
	_rules.actor_facts["enemy"]["dead"] = true
	if not _denied(execute_request, "target_already_dead"):
		return
	_rules.actor_facts["enemy"]["dead"] = false
	rules_reset_terminal_state()

	var treat_request := _request("treat")
	treat_request.target_item_instance_id = "bandage-1"
	treat_request.target_wound_id = "wound-1"
	if not _denied(treat_request, "treatment_incompatible"):
		return
	_rules.actor_facts["player"]["wounds"][0]["bleeding_rate"] = 2.0
	if not _allowed(treat_request):
		return
	_rules.actor_facts["player"]["items"][0]["consumable_effect"] = int(GameEnums.ConsumableEffect.RESTORE_BLOOD)
	if not _denied(treat_request, "treatment_incompatible"):
		return
	_rules.actor_facts["player"]["items"][0]["consumable_effect"] = int(GameEnums.ConsumableEffect.STOP_BLEEDING)
	_rules.actor_facts["player"]["items"][0]["access"] = "rummage"
	if not _denied(treat_request, "item_not_accessible"):
		return
	_rules.actor_facts["player"]["items"][0]["access"] = "quick"

	var use_request := _request("use")
	use_request.target_item_instance_id = "bandage-1"
	if not _allowed(use_request):
		return
	_rules.actor_facts["player"]["items"][0]["item_type"] = int(GameEnums.ItemType.JUNK)
	if not _denied(use_request, "consumable_required"):
		return
	_rules.actor_facts["player"]["items"][0]["item_type"] = int(GameEnums.ItemType.CONSUMABLE)
	_rules.actor_facts["player"]["items"][0]["access"] = "rummage"
	if not _denied(use_request, "item_not_accessible"):
		return
	_rules.actor_facts["player"]["items"][0]["access"] = "quick"

	var ready_request := _request("ready")
	ready_request.target_item_instance_id = "missing"
	if not _denied(ready_request, "item_not_owned"):
		return
	_rules.actor_facts["player"]["items"].append(_item("ready-1", GameEnums.ItemType.WEAPON, "quick"))
	var ready_item: Dictionary = _rules.actor_facts["player"]["items"][2]
	ready_item["ranged"] = true
	ready_item["requires_ready_action"] = true
	ready_item["is_readied"] = true
	if not _denied(_request_with_item("ready", "ready-1"), "weapon_already_ready"):
		return
	if not _denied(_request_with_item("drop", "missing"), "item_not_owned"):
		return
	if not _denied(_request_with_item("rummage", "missing"), "item_not_owned"):
		return

	var pickup_request := _request_with_item("pick_up", "ground-1")
	pickup_request.target_sector = Vector2i(2, 0)
	_rules.sector_facts[2]["ground_item_instance_ids"] = ["ground-1"]
	if not _denied(pickup_request, "adjacency_required"):
		return
	pickup_request.target_sector = Vector2i(1, 0)
	_rules.sector_facts[1]["ground_item_instance_ids"] = []
	if not _denied(pickup_request, "ground_item_sector"):
		return
	_rules.sector_facts[1]["ground_item_instance_ids"] = ["ground-1"]
	if not _allowed(pickup_request):
		return

	var strip_request := _request_with_item("strip", "enemy-item")
	strip_request.target_actor_id = "enemy"
	_rules.actor_facts["enemy"]["items"] = [_item("enemy-item", GameEnums.ItemType.WEAPON, "adjacent")]
	if not _denied(strip_request, "body_not_incapacitated"):
		return
	_rules.actor_facts["enemy"]["incapacitated"] = true
	_rules.actor_facts["enemy"]["comatose"] = true
	_rules.actor_facts["enemy"]["sector_index"] = -1
	_rules.actor_facts["enemy"]["sector"] = Vector2i(-1, -1)
	_rules.actor_facts["enemy"]["active_on_board"] = false
	_rules.actor_facts["enemy"]["handoff_sector_index"] = 1
	_rules.actor_facts["enemy"]["handoff_sector"] = Vector2i(1, 0)
	_rules.actor_facts["enemy"]["handoff_layer"] = "incapacitated"
	if not _allowed(strip_request):
		return
	rules_reset_terminal_state()

	var interact_request := _request("interact")
	interact_request.target_sector = Vector2i(1, 0)
	if not _denied(interact_request, "object_missing"):
		return
	_rules.sector_facts[1]["object"] = {"id": "door-1", "usable": true}
	if not _allowed(interact_request):
		return

	print("COMBAT_LEGALITY_REGRESSION_SMOKE: PASS")
	quit(0)


func rules_reset_terminal_state() -> void:
	_rules.actor_facts["enemy"]["broken"] = false
	_rules.actor_facts["enemy"]["incapacitated"] = false
	_rules.actor_facts["enemy"]["comatose"] = false
	_rules.actor_facts["enemy"]["sector_index"] = 1
	_rules.actor_facts["enemy"]["sector"] = Vector2i(1, 0)
	_rules.actor_facts["enemy"]["active_on_board"] = true
	_rules.actor_facts["enemy"]["handoff_sector_index"] = -1
	_rules.actor_facts["enemy"]["handoff_sector"] = Vector2i(-1, -1)
	_rules.actor_facts["enemy"]["handoff_layer"] = ""


func _sector(coords: Vector2i, escape_side: String, ground_ids: Array, cover_edges: Dictionary) -> Dictionary:
	return {
		"index": _rules.indices_by_coordinate.get("%d,%d" % [coords.x, coords.y], -1),
		"coords": coords,
		"blocked": false,
		"opaque": false,
		"visibility_penalty": 0.0,
		"movement_modifier": 0,
		"cover_edges": cover_edges,
		"escape_side": escape_side,
		"ground_item_instance_ids": ground_ids,
		"hazard": {},
		"trap": {},
		"object": {},
	}


func _actor(actor_id: String, index: int, side: String, surrendered: bool) -> Dictionary:
	return {
		"actor_id": actor_id,
		"sector_index": index,
		"sector": _rules.coordinates_by_index[index],
		"active_on_board": true,
		"handoff_sector_index": -1,
		"handoff_sector": Vector2i(-1, -1),
		"handoff_layer": "",
		"combat_side": side,
		"team_id": side,
		"direct_player": actor_id == "player",
		"dead": false,
		"comatose": false,
		"surrendered": surrendered,
		"broken": false,
		"incapacitated": false,
		"engaged": false,
		"right_arm_function": GameEnums.SCALE_MAX,
		"left_arm_function": GameEnums.SCALE_MAX,
		"both_legs_disabled": false,
		"kinetic_tier": 0,
		"items": [_item("bandage-1", GameEnums.ItemType.CONSUMABLE, "quick"), _item("enemy-item", GameEnums.ItemType.WEAPON, "quick")] if actor_id == "player" else [],
		"wounds": [{"wound_id": "wound-1", "bleeding_rate": 0.0}] if actor_id == "player" else [],
	}


func _item(instance_id: String, item_type: int, access: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"item_type": int(item_type),
		"quantity": 1,
		"stack_count": 1,
		"access": access,
		"consumable_effect": int(GameEnums.ConsumableEffect.STOP_BLEEDING),
		"consumable_potency": 6.0,
		"ranged": false,
		"requires_ready_action": false,
		"is_readied": true,
	}


func _request(action_id: String) -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = "player"
	request.action_id = action_id
	return request


func _request_with_item(action_id: String, instance_id: String) -> CombatActionRequest:
	var request := _request(action_id)
	request.target_item_instance_id = instance_id
	return request


func _allowed(request: CombatActionRequest) -> bool:
	var quote: CombatActionQuote = _QuoteService.quote(request, _rules)
	if not quote.legal:
		return _fail("Expected %s to be legal, got %s: %s" % [request.action_id, quote.denial_code, quote.denial_message])
	return true


func _denied(request: CombatActionRequest, denial_code: String) -> bool:
	var quote: CombatActionQuote = _QuoteService.quote(request, _rules)
	if quote.legal or quote.denial_code != denial_code:
		return _fail("Expected %s to deny with %s, got legal=%s code=%s" % [request.action_id, denial_code, quote.legal, quote.denial_code])
	return true


func _fail(message: String) -> bool:
	push_error("[COMBAT_LEGALITY_REGRESSION] " + message)
	quit(1)
	return false
