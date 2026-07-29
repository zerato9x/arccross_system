extends RefCounted
class_name MacroCollisionCoordinator

## Entity-collision UI dispatch extracted from MacroGameManager.
## Holds trade/ask/leave/back/session-open bodies; talk and ambush combat
## resolution stay on the host. Shares MacroInteractionState with the host.
## WorldCore may use ItemCore/SystemCore; must not import duel or menu domains.

var host: MacroGameManager
var interaction_state: MacroInteractionState


func _init(
	host_manager: MacroGameManager = null,
	shared_interaction: MacroInteractionState = null
) -> void:
	host = host_manager
	interaction_state = shared_interaction


func resolve_choice(choice_id: String) -> void:
	if (
		interaction_state.get_type()
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		return
	match choice_id:
		MacroEntityCollisionResolver.CHOICE_TALK:
			open_session(MacroEntityCollisionResolver.MODE_TALK)
		MacroEntityCollisionResolver.CHOICE_AMBUSH:
			var ambush_enemy_id: String = str(
				interaction_state.get_value("enemy_id", "")
			)
			var ambush_record := host._world_state.get_entity(ambush_enemy_id)
			var ambush_opponent := MacroEntityCollisionResolver.build_opponent_summary(
				ambush_record
			)
			if bool(ambush_opponent.get("blocks_ambush", false)):
				var deny := MacroEntityCollisionResolver.ambush_denied_result(
					ambush_record
				)
				host._last_macro_event = str(deny.get("body", "Ambush denied."))
				host._macro_log(host._last_macro_event)
				interaction_state.set_value(
					"resume_after_result",
					str(deny.get("resume", MacroEntityCollisionResolver.MODE_ROOT))
				)
				if host.macro_hud:
					host.macro_hud.show_event_result(deny)
				return
			open_session(MacroEntityCollisionResolver.MODE_AMBUSH)
		MacroEntityCollisionResolver.CHOICE_BACK:
			resolve_back()
		MacroEntityCollisionResolver.CHOICE_THREAT:
			host.resolve_talk_action(GameEnums.TalkAction.THREAT)
		MacroEntityCollisionResolver.CHOICE_CEASEFIRE:
			host.resolve_talk_action(GameEnums.TalkAction.CEASEFIRE)
		MacroEntityCollisionResolver.CHOICE_AMBUSH_FAR:
			host.resolve_entity_ambush(GameEnums.AmbushPosition.FAR)
		MacroEntityCollisionResolver.CHOICE_AMBUSH_STANDARD:
			host.resolve_entity_ambush(GameEnums.AmbushPosition.STANDARD)
		MacroEntityCollisionResolver.CHOICE_AMBUSH_CLOSE:
			host.resolve_entity_ambush(GameEnums.AmbushPosition.CLOSE)
		MacroEntityCollisionResolver.CHOICE_ASK:
			open_session(MacroEntityCollisionResolver.MODE_ASK)
		MacroEntityCollisionResolver.CHOICE_TRADE:
			resolve_trade()
		MacroEntityCollisionResolver.CHOICE_LEAVE:
			resolve_leave()
		_:
			if str(choice_id).begins_with("ask_"):
				resolve_ask(choice_id)


func resolve_back() -> void:
	var mode := str(
		interaction_state.get_value(
			"collision_mode",
			MacroEntityCollisionResolver.MODE_ROOT
		)
	)
	if mode == MacroEntityCollisionResolver.MODE_ASK:
		open_session(MacroEntityCollisionResolver.MODE_PEACEFUL)
		return
	open_session(MacroEntityCollisionResolver.MODE_ROOT)


func resolve_trade() -> void:
	var enemy_id: String = str(interaction_state.get_value("enemy_id", ""))
	var enemy_record := host._world_state.get_entity(enemy_id)
	if enemy_record == null:
		return
	var opponent := MacroEntityCollisionResolver.build_opponent_summary(
		enemy_record
	)
	if not bool(opponent.get("allows_trade", true)):
		return
	var player_core := host.player_token.get_humanoid_core()
	var result := MacroEntityCollisionResolver.resolve_trade(
		player_core,
		enemy_record,
		host._loot_catalog
	)
	var remove_id := str(result.get("remove_player_instance_id", ""))
	if not remove_id.is_empty() and player_core != null:
		player_core.inventory.remove_item_by_instance_id(remove_id)
	var received_state: Dictionary = result.get("received_item_state", {})
	if not received_state.is_empty():
		var received := ItemData.from_runtime_state(received_state)
		if player_core == null or not player_core.inventory.add_to_backpack(received):
			host._world_state.add_ground_items(
				host.player_token.current_hex_coords,
				[received_state]
			)
	if result.has("kept_loadout"):
		var definition: Dictionary = enemy_record.definition.duplicate(true)
		definition["loadout"] = result.get("kept_loadout", {})
		host._world_state.patch_entity_record(enemy_id, {"definition": definition})
	interaction_state.set_value(
		"resume_after_result",
		str(result.get("resume", MacroEntityCollisionResolver.MODE_PEACEFUL))
	)
	host._refresh_world_hud()
	if host.macro_hud:
		host.macro_hud.show_event_result(result)


func resolve_ask(choice_id: String) -> void:
	var enemy_id: String = str(interaction_state.get_value("enemy_id", ""))
	var enemy_record := host._world_state.get_entity(enemy_id)
	if enemy_record == null:
		return
	host.player_token.play_interaction()
	var result := MacroEntityCollisionResolver.resolve_ask_choice(
		enemy_record,
		choice_id
	)
	host._apply_macro_event_effects(result.get("effects", {}))
	interaction_state.set_value(
		"resume_after_result",
		str(result.get("resume", MacroEntityCollisionResolver.MODE_ASK))
	)
	host._refresh_world_hud()
	if host.macro_hud:
		host.macro_hud.show_event_result(result)


func resolve_leave() -> void:
	var enemy_id: String = str(interaction_state.get_value("enemy_id", ""))
	if not enemy_id.is_empty():
		host._world_state.set_entity_world_status(
			enemy_id,
			GameEnums.EntityWorldStatus.CEASEFIRE
		)
	host.close_macro_interaction()


func open_session(mode: String) -> void:
	var enemy_id: String = str(interaction_state.get_value("enemy_id", ""))
	var enemy_record := host._world_state.get_entity(enemy_id)
	if enemy_record == null or host.macro_hud == null:
		host.close_macro_interaction()
		return
	var session: Dictionary
	match mode:
		MacroEntityCollisionResolver.MODE_TALK:
			session = MacroEntityCollisionResolver.build_talk_session(
				enemy_record
			)
		MacroEntityCollisionResolver.MODE_AMBUSH:
			session = MacroEntityCollisionResolver.build_ambush_session(
				enemy_record
			)
		MacroEntityCollisionResolver.MODE_PEACEFUL:
			session = MacroEntityCollisionResolver.build_peaceful_session(
				enemy_record
			)
		MacroEntityCollisionResolver.MODE_ASK:
			session = MacroEntityCollisionResolver.build_ask_session(
				enemy_record
			)
		_:
			session = MacroEntityCollisionResolver.build_root_session(
				enemy_record
			)
	interaction_state.set_value("collision_mode", mode)
	interaction_state.erase("resume_after_result")
	session["player"] = _player_presentation()
	session["image_path"] = _collision_background_path(enemy_record)
	if host.macro_hud.has_method("hide_entity_inspect"):
		host.macro_hud.hide_entity_inspect()
	host.macro_hud.open_event(session)


func _collision_background_path(enemy_record: EntityRecord) -> String:
	var coords: Vector2i = Vector2i.ZERO
	if interaction_state != null and interaction_state.has_key("coords"):
		coords = interaction_state.get_value("coords", Vector2i.ZERO)
	elif enemy_record != null:
		coords = enemy_record.coords
	elif host.player_token != null:
		coords = host.player_token.current_hex_coords
	if host.world_generator == null:
		return EventBgCatalog.PLAINS_BG
	var hex_data := host.world_generator.get_hex_at(coords)
	var dialogue_id := ""
	if enemy_record != null:
		dialogue_id = str(enemy_record.definition.get("dialogue_id", ""))
	var path := EventBgCatalog.resolve_dialogue_background(dialogue_id, hex_data)
	if path.is_empty():
		return EventBgCatalog.PLAINS_BG
	return path


func _player_presentation() -> Dictionary:
	var player_token = host.player_token
	if player_token == null:
		return {}
	var core = player_token.get_humanoid_core()
	if core == null or core.inventory == null:
		return {}
	var equipment: Array = []
	for slot_key in core.inventory.paper_doll.keys():
		var item: ItemData = core.inventory.paper_doll[slot_key]
		if item == null:
			continue
		equipment.append({
			"instance_id": item.instance_id,
			"id": item.id,
			"item_id": item.id,
			"name": item.display_name,
			"item_type": item.item_type,
			"weapon_type": item.weapon_type,
			"condition_enabled": item.condition_enabled,
			"current_condition": item.current_condition,
			"condition_band": ItemConditionRules.condition_band(item.current_condition),
			"equipment_slot": int(slot_key),
			"sprite_path": item.get_inventory_sprite_path(),
			"equipped_sprite_paths": item.get_equipped_sprite_paths(),
			"requires_two_hands": item.requires_two_hands,
		})
	var record: Dictionary = {}
	if player_token.has_method("capture_runtime_record"):
		record = player_token.capture_runtime_record()
	var appearance := (
		HumanoidVisualCatalog.appearance_from_record(record)
		if not record.is_empty()
		else HumanoidVisualCatalog.appearance_from_equipment_snapshot(equipment)
	)
	return {
		"name": "YOU",
		"equipment": equipment,
		"appearance": appearance,
		"record": record,
	}
