extends SceneTree


func _init() -> void:
	var store := RuntimeStateStore.new()
	store.begin_new_world("RUNTIME_AUTHORITY_ADVERSARIAL")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory_items": []},
	}, Vector2i.ZERO)
	var original_player_revision := store.player_revision
	if store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {
			"inventory_items": [
				{"instance_id": "duplicate-player-item"},
				{"instance_id": "duplicate-player-item"},
			]
		},
	}, Vector2i.ZERO):
		_fail("Player record accepted duplicate runtime item ownership.")
		return
	if store.player_revision != original_player_revision:
		_fail("Rejected player record changed the canonical revision.")
		return

	var alpha := _entity("alpha", Vector2i(1, 0))
	if store.register_entity(alpha) != "alpha":
		_fail("Could not register the canonical entity.")
		return
	var original_revision := alpha.revision
	if not store.register_entity(_entity("alpha", Vector2i(2, 0))).is_empty():
		_fail("Duplicate entity identity was accepted.")
		return
	if store.get_entity("alpha").coords != Vector2i(1, 0):
		_fail("Rejected duplicate identity changed the canonical entity.")
		return
	var malformed_registration := _entity("malformed-registration", Vector2i(2, 0))
	malformed_registration.runtime = {
		"inventory_items": [
			{"instance_id": "duplicate-registration-item"},
			{"instance_id": "duplicate-registration-item"},
		]
	}
	if not store.register_entity(malformed_registration).is_empty():
		_fail("Entity registration accepted duplicate runtime item ownership.")
		return
	if store.get_entity("malformed-registration") != null:
		_fail("Rejected entity registration left a partial record behind.")
		return
	if store.patch_entity_record("alpha", {"coords": Vector2i(3, 0)}):
		_fail("Generic patch still bypasses coordinate invariants.")
		return
	if store.patch_entity_record("alpha", {"revision": original_revision}):
		_fail("Generic patch still accepted a stale revision.")
		return
	var stable_revision := store.get_entity("alpha").revision
	if store.patch_entity_record("alpha", {"unrecognized_field": true}):
		_fail("Generic patch accepted an unrecognized authority field.")
		return
	if store.patch_entity_record("alpha", {
		"runtime": {
			"inventory_items": [
				{"instance_id": "duplicate-runtime-item"},
				{"instance_id": "duplicate-runtime-item"},
			]
		}
	}):
		_fail("Generic patch accepted duplicate runtime item ownership.")
		return
	if store.get_entity("alpha").revision != stable_revision:
		_fail("Rejected generic patches changed the canonical revision.")
		return
	var runtime_revision := store.get_entity("alpha").revision
	if store.update_entity_runtime("alpha", {
		"inventory_items": [
			{"instance_id": "duplicate-update-item"},
			{"instance_id": "duplicate-update-item"},
		]
	}):
		_fail("Runtime update accepted duplicate item ownership.")
		return
	if store.get_entity("alpha").revision != runtime_revision:
		_fail("Rejected runtime update changed the canonical revision.")
		return
	if store.get_entity("alpha").coords != Vector2i(1, 0):
		_fail("Rejected coordinate patch changed canonical state.")
		return

	var weapon := _item("authority-weapon")
	var attachment := _item("authority-attachment")
	weapon["fitted_attachment_instance_ids"] = ["authority-attachment"]
	weapon["fitted_attachment_states"] = [attachment]
	var ground_coords := Vector2i(1, 0)
	if not store.add_ground_items(ground_coords, [weapon]):
		_fail("Could not create the nested-item fixture.")
		return
	if store.find_item_ownership("authority-attachment").get("location", "") != "ground":
		_fail("Nested attachment was not indexed as an owned item.")
		return
	if not store.validate_integrity().is_empty():
		_fail("Valid nested-item state failed integrity.")
		return
	store.ground_item_records[ground_coords].append(_item("authority-attachment"))
	if store.validate_integrity().is_empty():
		_fail("Duplicate nested attachment identity was not detected.")
		return
	store.remove_item_instance("authority-attachment")
	store.remove_item_instance("authority-weapon")
	if not store.validate_integrity().is_empty():
		_fail("Nested-item cleanup left invalid ownership state.")
		return
	var detachable_weapon := _item("detachable-weapon")
	detachable_weapon["fitted_attachment_instance_ids"] = ["detachable-attachment"]
	detachable_weapon["fitted_attachment_states"] = [_item("detachable-attachment")]
	if not store.add_ground_items(Vector2i(2, 0), [detachable_weapon]):
		_fail("Could not create the nested transfer fixture.")
		return
	if not store.add_ground_items(Vector2i(3, 0), [_item("detachable-attachment")]):
		_fail("Nested attachment could not be detached through the ownership boundary.")
		return
	if store.find_item_ownership("detachable-attachment").get("coords") != Vector2i(3, 0):
		_fail("Detached attachment landed at the wrong authoritative location.")
		return
	if not store.validate_integrity().is_empty():
		_fail("Nested detach left invalid ownership state.")
		return
	store.remove_item_instance("detachable-attachment")
	store.remove_item_instance("detachable-weapon")
	if store.transfer_item_to_entity("alpha", _item("unowned-item")):
		_fail("Zero-source item was accepted as a transfer.")
		return
	print("RUNTIME_AUTHORITY_ADVERSARIAL_SMOKE: PASS")
	quit(0)


func _entity(entity_id: String, coords: Vector2i) -> EntityRecord:
	var record := EntityRecord.new()
	record.entity_id = entity_id
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.coords = coords
	record.runtime = {"inventory_items": []}
	return record


func _item(instance_id: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"id": "water_bottle",
		"owner_id": "",
		"physical_location": "ground",
		"equipped_slot": GameEnums.EquipmentSlot.NONE,
	}


func _fail(message: String) -> void:
	push_error("[RUNTIME_AUTHORITY_ADVERSARIAL] " + message)
	quit(1)
