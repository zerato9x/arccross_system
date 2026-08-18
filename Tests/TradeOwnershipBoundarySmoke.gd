extends SceneTree


func _init() -> void:
	var store := RuntimeStateStore.new()
	store.begin_new_world("TRADE_OWNERSHIP_BOUNDARY")
	var offer := _item("trade-offer", "bandage")
	offer["owner_id"] = "player"
	var received := _item("trade-received", "water_bottle")
	received["owner_id"] = "trade-enemy"
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory_items": [offer]},
	}, Vector2i.ZERO)
	var enemy := EntityRecord.new()
	enemy.entity_id = "trade-enemy"
	enemy.kind = GameEnums.RuntimeEntityKind.NPC
	enemy.coords = Vector2i(1, 0)
	enemy.definition = {"loadout": {}}
	enemy.runtime = {"inventory_items": [received]}
	if store.register_entity(enemy) != enemy.entity_id:
		_fail("Could not register the trade counterparty.")
		return
	if not store.validate_integrity().is_empty():
		_fail("Trade fixture failed initial integrity.")
		return

	var player_candidate := {
		"inventory_items": [_owned_item("trade-received", "player")],
	}
	var enemy_candidate := {
		"inventory_items": [_owned_item("trade-offer", "trade-enemy")],
	}
	var player_revision := store.player_record.revision
	var enemy_revision := enemy.revision
	if not store.commit_trade(
		"trade-enemy",
		player_candidate,
		enemy_candidate,
		{"loadout": {}},
		"trade-offer",
		"trade-received",
		"inventory",
		player_revision,
		enemy_revision
	):
		_fail("Valid trade exchange did not commit.")
		return
	if store.find_item_ownership("trade-offer").get("owner_id", "") != "trade-enemy":
		_fail("Trade offer did not acquire the NPC owner.")
		return
	if store.find_item_ownership("trade-received").get("owner_id", "") != "player":
		_fail("Trade receipt did not acquire the player owner.")
		return
	if not store.validate_integrity().is_empty():
		_fail("Committed trade left invalid ownership state.")
		return
	var authored_player_revision := store.player_record.revision
	var authored_enemy_revision := enemy.revision
	if not store.commit_trade(
		"trade-enemy",
		{"inventory_items": [_owned_item("authored-received", "player")]},
		{
			"inventory_items": [
				_owned_item("trade-offer", "trade-enemy"),
				_owned_item("trade-received", "trade-enemy"),
			]
		},
		{"loadout": {}},
		"trade-received",
		"authored-received",
		"authored_loadout",
		authored_player_revision,
		authored_enemy_revision
	):
		_fail("Authored-loadout trade exchange did not commit.")
		return
	if store.find_item_ownership("authored-received").get("owner_id", "") != "player":
		_fail("Authored-loadout item did not acquire the player owner.")
		return
	if not store.validate_integrity().is_empty():
		_fail("Authored-loadout trade left invalid ownership state.")
		return
	var pickup := _item("boundary-pickup", "bandage")
	if not store.add_ground_items(Vector2i.ZERO, [pickup]):
		_fail("Could not create the player pickup fixture.")
		return
	var pickup_runtime: Dictionary = store.player_record.runtime.duplicate(true)
	pickup_runtime["inventory_items"].append(_owned_item("boundary-pickup", "player"))
	if not store.transfer_ground_item_to_entity_with_runtime(
		Vector2i.ZERO, "boundary-pickup", "player", pickup_runtime
	):
		_fail("Atomic player pickup did not commit.")
		return
	var drop_runtime: Dictionary = store.player_record.runtime.duplicate(true)
	for index in range(drop_runtime["inventory_items"].size() - 1, -1, -1):
		if str(drop_runtime["inventory_items"][index].get("instance_id", "")) == "authored-received":
			drop_runtime["inventory_items"].remove_at(index)
	if not store.commit_entity_runtime_with_ground_items(
		"player",
		drop_runtime,
		Vector2i(2, 0),
		[_owned_item("authored-received", "player")]
	):
		_fail("Atomic player drop did not commit.")
		return
	if store.find_item_ownership("authored-received").get("location", "") != "ground":
		_fail("Dropped item did not acquire the ground owner.")
		return
	if not store.validate_integrity().is_empty():
		_fail("Pickup/drop transaction left invalid ownership state.")
		return
	var before_stale := store.capture_reconciliation_snapshot()
	if store.commit_trade(
		"trade-enemy",
		player_candidate,
		enemy_candidate,
		{"loadout": {}},
		"trade-offer",
		"trade-received",
		"inventory",
		player_revision,
		enemy_revision
	):
		_fail("Stale trade revision was accepted.")
		return
	if store.capture_reconciliation_snapshot() != before_stale:
		_fail("Rejected stale trade partially mutated authoritative state.")
		return
	print("TRADE_OWNERSHIP_BOUNDARY_SMOKE: PASS")
	quit(0)


func _item(instance_id: String, item_id: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"id": item_id,
		"owner_id": "",
		"physical_location": "inventory",
		"equipped_slot": GameEnums.EquipmentSlot.NONE,
	}


func _owned_item(instance_id: String, owner_id: String) -> Dictionary:
	var item := _item(instance_id, "water_bottle")
	item["owner_id"] = owner_id
	return item


func _fail(message: String) -> void:
	push_error("[TRADE_OWNERSHIP_BOUNDARY] " + message)
	quit(1)
