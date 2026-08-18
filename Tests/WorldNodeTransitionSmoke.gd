extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var store := RuntimeStateStore.new()
	store.begin_new_world("WORLD_NODE_TRANSITION")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory_items": []},
	}, Vector2i.ZERO)
	var graph := {"seed": store.world_seed, "nodes": {"node-a": {}, "node-b": {}}}
	var baseline_a := {Vector2i.ZERO: HexRecord.new(), Vector2i(1, 0): HexRecord.new()}
	if not store.transition_active_node("node-a", 0, baseline_a, graph, Vector2i(1, 0)):
		return _fail("Initial node transition failed.")
	var node_a_zero := store.get_hex_record(Vector2i.ZERO)
	node_a_zero.search_count = 3
	if not store.replace_hex_record(Vector2i.ZERO, node_a_zero, node_a_zero.revision):
		return _fail("Could not commit node A mutation.")
	var actor := EntityRecord.new()
	actor.entity_id = "node-a-actor"
	actor.coords = Vector2i(1, 0)
	actor.runtime = {"inventory_items": []}
	store.register_entity(actor)
	store.add_ground_items(Vector2i.ZERO, [_item("node-a-item")])

	var baseline_b_hex := HexRecord.new()
	baseline_b_hex.search_count = 1
	var baseline_b := {Vector2i.ZERO: baseline_b_hex}
	if not store.transition_active_node("node-b", 1, baseline_b, graph, Vector2i.ZERO):
		return _fail("Node B transition failed.")
	if store.get_entity_snapshot("node-a-actor") != {}:
		return _fail("Node A entity leaked into node B.")
	if store.get_hex_record(Vector2i.ZERO).search_count != 1:
		return _fail("Node B coordinate-zero baseline was contaminated by node A.")
	var before_invalid := store.capture_reconciliation_snapshot()
	if store.transition_active_node("invalid", 2, {}, graph, Vector2i.ZERO):
		return _fail("Empty destination baseline was accepted.")
	if store.capture_reconciliation_snapshot() != before_invalid:
		return _fail("Rejected destination partially replaced the active node.")
	if not store.transition_active_node("node-a", 0, baseline_a, graph, Vector2i(1, 0)):
		return _fail("Could not restore node A snapshot.")
	if store.get_hex_record(Vector2i.ZERO).search_count != 3:
		return _fail("Node A runtime mutation was not restored.")
	if store.get_entity_snapshot("node-a-actor").is_empty():
		return _fail("Node A entity was not restored.")
	if store.get_ground_items(Vector2i.ZERO).size() != 1:
		return _fail("Node A item ownership was not restored.")
	if not store.validate_integrity().is_empty():
		return _fail("Restored node failed integrity validation.")
	print("WORLD_NODE_TRANSITION_SMOKE: PASS")
	quit(0)
	return true


func _item(instance_id: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"id": "scrap",
		"owner_id": "",
		"physical_location": "ground",
		"equipped_slot": GameEnums.EquipmentSlot.NONE,
	}


func _fail(message: String) -> bool:
	push_error("[WORLD_NODE_TRANSITION] " + message)
	quit(1)
	return false
