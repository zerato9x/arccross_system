extends RefCounted
class_name MacroCampaignContentService

## Owns authored campaign-content seeding that must be idempotent across node
## activation and save restoration. The manager keeps only the presentation
## response so legacy event text and HUD refresh timing remain compatible.

var _world_state: RuntimeStateStore
var _loot_catalog: Node


func configure(world_state: RuntimeStateStore, loot_catalog: Node) -> void:
	_world_state = world_state
	_loot_catalog = loot_catalog


func resolve_campaign_site(
	campaign: MacroProgressController,
	coords: Vector2i,
	hex_data: MacroHexData,
	callbacks: Dictionary
) -> bool:
	if campaign == null or campaign.active_node_id.is_empty() or hex_data == null:
		return false
	var node := campaign.get_active_node()
	if node == null:
		return false
	if (
		node.role == GameEnums.MacroNodeRole.CENTRAL_CORE
		and hex_data.poi_id == MacroGraphGenerator.CENTRAL_ID
	):
		var central_callback := _callback(callbacks, "begin_central_core")
		if central_callback.is_valid():
			central_callback.call(coords)
		return true
	if str(hex_data.poi_id).begins_with("macro_event_"):
		var event_id := node.event_id
		if event_id.is_empty():
			event_id = MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM
		var event_callback := _callback(callbacks, "begin_macro_event")
		if event_callback.is_valid():
			event_callback.call(event_id, coords)
		return true
	return false


func resolve_central_meta_quest(
	campaign: MacroProgressController,
	meta_progress: Node,
	player_token: MacroPlayer
) -> Dictionary:
	if player_token != null:
		player_token.play_interaction()
	if meta_progress == null:
		return {"status": "unavailable", "message": "Meta Progress profile is unavailable."}
	if meta_progress.is_event_completed(MacroGraphGenerator.META_FETCH_EVENT_ID):
		return {
			"status": "completed",
			"message": "North Core Regulator installed. The north gateway is permanently unsealed.",
		}
	var inventory := player_token.get_humanoid_core().inventory
	var component: ItemData = null
	for item in inventory.get_all_items():
		if item != null and item.id == MacroGraphGenerator.FETCH_ITEM_ID:
			component = item
			break
	if component == null:
		campaign.reveal_fetch_branch()
		if _world_state != null:
			_world_state.campaign_graph = campaign.graph.to_dict()
		return {
			"status": "revealed",
			"message": (
				"META QUEST: Recover the North Core Regulator from the revealed east-arm branch "
				+ "and return it to the Central Core."
			),
		}
	inventory.remove_item_by_instance_id(component.instance_id)
	meta_progress.complete_event(
		MacroGraphGenerator.META_FETCH_EVENT_ID,
		[{
			"type": "set_gateway",
			"gateway_id": "north",
			"unsealed": true,
		}]
	)
	campaign.refresh_meta_unlocks()
	return {
		"status": "completed_now",
		"message": (
			"META EVENT COMPLETE: North Core Regulator installed. "
			+ "The north gateway is unsealed for every future character."
		),
		"log": true,
	}


func ensure_meta_component_source(
	campaign: MacroProgressController,
	meta_progress: Node,
	player_token: MacroPlayer
) -> Dictionary:
	if campaign == null or campaign.active_node_id != MacroGraphGenerator.FETCH_BRANCH_ID:
		return {"status": "inactive"}
	if (
		meta_progress != null
		and meta_progress.has_method("is_event_completed")
		and meta_progress.is_event_completed(MacroGraphGenerator.META_FETCH_EVENT_ID)
	):
		return {"status": "completed"}
	if _run_has_meta_component(player_token):
		return {"status": "present"}
	if _loot_catalog == null or not _loot_catalog.has_item(MacroGraphGenerator.FETCH_ITEM_ID):
		return {
			"status": "missing_catalog",
			"item_id": MacroGraphGenerator.FETCH_ITEM_ID,
		}
	var item_state: Dictionary = _loot_catalog.create_runtime_item_state(
		MacroGraphGenerator.FETCH_ITEM_ID
	)
	if item_state.is_empty():
		return {"status": "missing_item"}
	if _world_state == null:
		return {"status": "missing_world_state"}
	_world_state.add_ground_items(Vector2i.ZERO, [item_state])
	return {
		"status": "seeded",
		"item_id": MacroGraphGenerator.FETCH_ITEM_ID,
	}


func _run_has_meta_component(player_token: MacroPlayer) -> bool:
	if player_token != null and player_token.get_humanoid_core() != null:
		for item in player_token.get_humanoid_core().inventory.get_all_items():
			if item != null and item.id == MacroGraphGenerator.FETCH_ITEM_ID:
				return true
	if _world_state == null:
		return false
	for ground_stack in _world_state.ground_item_records.values():
		for item_state in ground_stack:
			if (
				item_state is Dictionary
				and _runtime_item_state_id(item_state) == MacroGraphGenerator.FETCH_ITEM_ID
			):
				return true
	for snapshot in _world_state.node_runtime_snapshots.values():
		if not snapshot is Dictionary:
			continue
		for ground_entry in snapshot.get("ground_items", []):
			if not ground_entry is Dictionary:
				continue
			for item_state in ground_entry.get("items", []):
				if (
					item_state is Dictionary
					and _runtime_item_state_id(item_state) == MacroGraphGenerator.FETCH_ITEM_ID
				):
					return true
	return false


func _runtime_item_state_id(item_state: Dictionary) -> String:
	var item_id := str(item_state.get("id", ""))
	if not item_id.is_empty():
		return item_id
	var definition: Dictionary = item_state.get("definition", {})
	return str(definition.get("id", ""))


func _callback(callbacks: Dictionary, key: String) -> Callable:
	var value: Variant = callbacks.get(key, Callable())
	if value is Callable:
		return value
	return Callable()
