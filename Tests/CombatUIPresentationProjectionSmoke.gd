extends SceneTree

const PROJECTION := preload("res://CombatCore/Tactical/CombatActorPresentationProjection.gd")
const INVENTORY := preload("res://CombatCore/Tactical/CombatInventorySnapshotPresenter.gd")
const TURN_STATUS := preload("res://CombatCore/Tactical/CombatTurnStatusSnapshotPresenter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := {
		"revision": 14,
		"active_actor_id": "player",
		"ap": 7,
		"max_ap": 12,
		"actors": [
			{
				"actor_id": "player",
				"direct_player": true,
				"team_id": "player",
				"name": "Field Operator",
				"blood": 11.0,
				"pain": 4.0,
				"shock": 2.0,
				"consciousness": 10.0,
				"max_ap": 12,
				"stance": 8.0,
				"max_stance": 12.0,
				"burden": 3,
				"burden_tier": "fluid",
				"posture": "standing",
				"limbs": [{"region": GameEnums.LimbRegion.LEFT_ARM, "region_id": "left_arm", "current": 8.0, "maximum": 12.0, "function": 8.0, "bleeding_rate": 1.0}],
				"wounds": [{"wound_id": "w1", "body_region": GameEnums.LimbRegion.LEFT_ARM, "wound_type": "cut", "severity": 5.0, "bleeding_rate": 1.0}],
				"items": [{"instance_id": "bandage", "name": "Bandage", "access": "hands", "access_tier": "hands"}],
				"equipment": [],
				"ranged_weapon": {},
				"melee_weapon": {},
			},
			{
				"actor_id": "enemy",
				"team_id": "hostile",
				"name": "Unknown Raider",
				"blood": 6.0,
				"pain": 8.0,
				"consciousness": 7.0,
				"max_ap": 10,
				"stance": 3.0,
				"max_stance": 10.0,
				"burden": 9,
				"posture": "crouched",
				"limbs": [{"region": GameEnums.LimbRegion.HEAD, "region_id": "head", "current": 4.0, "maximum": 12.0, "function": 4.0, "bleeding_rate": 0.0}],
				"wounds": [{"wound_id": "hidden-wound", "body_region": GameEnums.LimbRegion.HEAD, "wound_type": "trauma", "severity": 9.0, "bleeding_rate": 0.0}],
				"items": [{"instance_id": "hidden-item", "name": "Hidden Item", "access": "carried", "access_tier": "carried", "condition": 1.0}],
				"equipment": [],
				"ranged_weapon": {"name": "Carbine", "ranged": true, "current_magazine": 2, "max_magazine": 20, "condition": 4.0},
				"melee_weapon": {},
			},
		],
		"arena": {
			"relationships": {
				"relation_by_pair": {"enemy|player": CombatRelationshipLedger.Relation.HOSTILE},
			},
			"communication_points": {"current": 2, "initial": 4, "spent": 2},
		},
	}
	var actors_by_id: Dictionary = PROJECTION.build(snapshot)
	var self_view: Dictionary = actors_by_id["player"]
	var hostile_view: Dictionary = actors_by_id["enemy"]
	_assert(self_view.get("knowledge_level", "") == "self", "Self projection did not retain self knowledge.")
	_assert(self_view.has("blood") and self_view.has("limbs") and self_view.has("items"), "Self projection dropped exact presentation fields.")
	_assert(hostile_view.get("relationship_id", "") == "hostile", "Hostile relationship was not resolved from the ledger.")
	_assert(not hostile_view.has("blood") and not hostile_view.has("pain") and (not hostile_view.has("stance") or hostile_view.get("stance") == null), "Hostile projection leaked exact hidden vital or stance state.")
	_assert((hostile_view.get("items", []) as Array).is_empty(), "Hostile projection retained carried inventory.")
	_assert(not (hostile_view.get("visible_wounds", []) as Array).is_empty(), "Observable wound evidence was redacted too aggressively.")
	var hostile_weapon: Dictionary = hostile_view.get("weapon", {})
	_assert(hostile_weapon.has("ammo_band") and not hostile_weapon.has("current_magazine"), "Hostile weapon projection leaked exact ammunition.")
	_assert(hostile_view.get("burden_tier", "") == "agonizing", "Hostile burden was not reduced to a qualitative tier.")

	var inventory_presenter := INVENTORY.new()
	var inventory_view: Dictionary = inventory_presenter.build(snapshot)
	var accessible: Array = inventory_view.get("accessible_items_by_actor", {}).get("player", [])
	_assert(accessible.size() == 1 and accessible[0].get("instance_id", "") == "bandage", "Hands/quick inventory projection did not filter by authoritative access tier.")

	var turn_presenter := TURN_STATUS.new()
	var turn_view: Dictionary = turn_presenter.build(snapshot)
	_assert(int(turn_view.get("max_ap", 0)) == 12, "Turn status projection omitted max AP.")
	_assert(int(turn_view.get("communication_points", {}).get("current", 0)) == 2, "Turn status projection omitted CP.")

	var contract_sources := {
		"controller": FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatActionController.gd"),
		"snapshot_presenter": FileAccess.get_file_as_string("res://CombatCore/Tactical/TacticalCombatSnapshotPresenter.gd"),
		"inventory_presenter": FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatInventorySnapshotPresenter.gd"),
		"hud": FileAccess.get_file_as_string("res://CombatCore/Tactical/TacticalCombatHUD.gd"),
		"body_view": FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatBodyTargetView.gd"),
		"motion": FileAccess.get_file_as_string("res://PresentationCore/HudMotion.gd"),
	}
	for token in ["\"limbs\"", "\"equipment\"", "\"access_tier\"", "\"max_ap\"", "\"burden_tier\""]:
		_assert(str(contract_sources["controller"]).find(token) >= 0, "Authoritative snapshot is missing token %s." % token)
	for token in ["actors_by_id", "turn_status"]:
		_assert(str(contract_sources["snapshot_presenter"]).find(token) >= 0, "Snapshot presenter is missing token %s." % token)
	_assert(str(contract_sources["inventory_presenter"]).find("accessible_items_by_actor") >= 0, "Inventory presenter is missing token accessible_items_by_actor.")
	for token in ["PaperDollModel", "CommandDock", "HANDS & QUICK ACCESS", "qualitative_only", "severity_breathe"]:
		var source_name := "body_view" if token == "qualitative_only" else ("motion" if token == "severity_breathe" else "hud")
		_assert(str(contract_sources[source_name]).find(token) >= 0, "Presentation contract is missing token %s." % token)

	if _failures.is_empty():
		print("COMBAT_UI_PRESENTATION_PROJECTION_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[COMBAT_UI_PRESENTATION] " + failure)
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
