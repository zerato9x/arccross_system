extends SceneTree

const CATALOG_PATH := "res://CombatCore/Tactical/default_combat_action_catalog.tres"
const RETIRED := [
	"stand",
	"crouch",
	"disengage",
	"aimed_strike",
	"aimed_fire",
	"block",
	"dodge",
	"opportunity_strike",
	"brace",
	"recover",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := load(CATALOG_PATH) as CombatActionCatalog
	if catalog == null:
		_fail("The authored combat action catalog failed to load.")
		return
	var canonical := catalog.canonical_definitions()
	if canonical.is_empty():
		_fail("The canonical action projection is empty.")
		return
	for action_id in RETIRED:
		if catalog.is_player_visible(action_id) or catalog.is_ai_visible(action_id):
			_fail("Retired action remains visible to a player or AI: %s" % action_id)
			return
	var end_turn := catalog.definition("end_turn")
	if end_turn == null or end_turn.visibility_tier != "global" or end_turn.surface_id != "top_strip":
		_fail("End Turn is not authored as the sole top-strip global verb.")
		return
	for action_id in ["reload", "cycle", "ready"]:
		var maintenance := catalog.definition(action_id)
		if maintenance == null:
			_fail("Missing maintenance action: %s" % action_id)
			return
		if maintenance.visibility_tier != "maintenance" or maintenance.surface_id != "weapon_card":
			_fail("Maintenance action is not scoped to the weapon card: %s" % action_id)
			return
	var retired_malfunction := catalog.definition("clear_malfunction")
	if retired_malfunction == null or retired_malfunction.visibility_tier != "compatibility" or catalog.is_player_visible("clear_malfunction") or catalog.is_ai_visible("clear_malfunction"):
		_fail("clear_malfunction was not compatibility-remapped to jam-only Cycle.")
		return
	var seen := {}
	for definition in canonical:
		if seen.has(definition.action_id):
			_fail("Canonical action IDs are not unique: %s" % definition.action_id)
			return
		seen[definition.action_id] = true
	print("COMBAT_ACTION_CATALOG_SMOKE: PASS // canonical=%d" % canonical.size())
	quit(0)


func _fail(message: String) -> void:
	push_error("COMBAT_ACTION_CATALOG_SMOKE: " + message)
	quit(1)
