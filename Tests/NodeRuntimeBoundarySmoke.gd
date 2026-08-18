extends SceneTree


func _init() -> void:
	var store := RuntimeStateStore.new()
	store.begin_new_world("NODE_BOUNDARY_SMOKE")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory": {"equipment": {}, "backpack": []}},
	}, Vector2i.ZERO)
	store.set_relationship(
		"player", "node-a-npc", CombatRelationshipLedger.Relation.NEUTRAL
	)

	var entity := EntityRecord.new()
	entity.entity_id = "node-a-npc"
	entity.coords = Vector2i(1, 0)
	entity.runtime = {"inventory_items": []}
	store.register_entity(entity)
	var hex := HexRecord.new()
	hex.search_count = 2
	store.set_hex_record(Vector2i(1, 0), hex)
	store.add_ground_items(Vector2i(1, 0), [_item("node-a-item")])
	store.capture_node_runtime("node-a")
	store.clear_active_node_runtime()

	if store.player_record == null or store.player_record.coords != Vector2i.ZERO:
		_fail("Node clear discarded global player state.")
		return
	if store.relationship_between("player", "node-a-npc") != CombatRelationshipLedger.Relation.NEUTRAL:
		_fail("Node clear discarded run-global relationship state.")
		return
	var entity_b := EntityRecord.new()
	entity_b.entity_id = "node-b-npc"
	entity_b.coords = Vector2i(2, 0)
	entity_b.runtime = {"inventory_items": []}
	store.register_entity(entity_b)
	store.capture_node_runtime("node-b")
	store.clear_active_node_runtime()
	if not store.restore_node_runtime("node-a"):
		_fail("Could not restore node A runtime.")
		return
	if store.get_entity("node-a-npc") == null or store.get_entity("node-b-npc") != null:
		_fail("Node restore mixed local entity ownership.")
		return
	if store.get_entity_at(Vector2i(1, 0)).entity_id != "node-a-npc":
		_fail("Node restore did not rebuild the entity coordinate index.")
		return
	if store.get_ground_items(Vector2i(1, 0)).size() != 1:
		_fail("Node restore lost local ground items.")
		return
	var errors := store.validate_integrity()
	if not errors.is_empty():
		_fail("Restored node failed integrity: " + "; ".join(errors))
		return
	var before_invalid_restore_entity := store.get_entity("node-a-npc")
	var invalid_snapshot: Dictionary = store.node_runtime_snapshots["node-a"].duplicate(true)
	var invalid_ground: Array = invalid_snapshot.get("ground_items", [])
	if invalid_ground.is_empty():
		_fail("The node fixture did not contain a ground-item boundary case.")
		return
	var first_ground_entry: Dictionary = invalid_ground[0].duplicate(true)
	var duplicate_items: Array = first_ground_entry.get("items", []).duplicate(true)
	duplicate_items.append(duplicate_items[0].duplicate(true))
	first_ground_entry["items"] = duplicate_items
	invalid_ground[0] = first_ground_entry
	invalid_snapshot["ground_items"] = invalid_ground
	store.node_runtime_snapshots["invalid-node"] = invalid_snapshot
	if store.restore_node_runtime("invalid-node"):
		_fail("Malformed node snapshot was accepted.")
		return
	if store.get_entity("node-a-npc") != before_invalid_restore_entity:
		_fail("Rejected node restore partially replaced the active entity state.")
		return
	if store.get_ground_items(Vector2i(1, 0)).size() != 1:
		_fail("Rejected node restore partially replaced active ground state.")
		return
	if not store.validate_integrity().is_empty():
		_fail("Rejected node restore left authoritative state invalid.")
		return
	print("NODE_RUNTIME_BOUNDARY_SMOKE: PASS")
	quit(0)


func _item(instance_id: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"id": "water_bottle",
		"owner_id": "",
		"physical_location": "ground",
		"equipped_slot": GameEnums.EquipmentSlot.NONE,
	}


func _fail(message: String) -> void:
	push_error("[NODE_RUNTIME_BOUNDARY] " + message)
	quit(1)
