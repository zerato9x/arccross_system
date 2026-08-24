extends RefCounted
class_name MacroSearchActionService

## Applies a search interaction through the shared world-action and loot
## contracts. The manager remains the compatibility facade; this service owns
## the search result application sequence and its interruption policy.

const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const _InteractionResolver := preload(
	"res://WorldCore/MacroInteractionResolver.gd"
)

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var loot_catalog: Node
var callbacks: Dictionary = {}


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	catalog: Node,
	configured_callbacks: Dictionary
) -> void:
	world_state = state
	world_generator = generator
	loot_catalog = catalog
	callbacks = configured_callbacks.duplicate()


func resolve(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	selected_item_ids: Array,
	selected_search_option_id: String = "",
	preferred_target_id: String = "",
	work_hit_success_window: bool = true
) -> void:
	if world_state == null or world_generator == null or hex_data == null:
		return
	hex_data = _canonical_hex(coords)
	if hex_data == null:
		_show_result("SEARCH REJECTED", "The canonical search location is unavailable.")
		return
	var expected_search_count := hex_data.search_count
	var searched_target_id := selected_search_option_id
	var loot_profile: Dictionary = _get_loot_profile(hex_data)
	var available_guaranteed: Array = []
	for entry_value in loot_profile.get("guaranteed_entries", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var once_key := str(entry.get("once_key", ""))
		if (
			once_key.is_empty()
			or not bool(world_state.get_run_flags_snapshot().get("loot_once:" + once_key, false))
		):
			available_guaranteed.append(entry)
	loot_profile["guaranteed_entries"] = available_guaranteed

	var tool_descriptors := _PoiController.inventory_descriptors_for_ids(
		selected_item_ids,
		GameEnums.InteractionItemRole.SEARCH_TOOL,
		Callable(self, "_find_inventory_item")
	)
	var shared_receipt: WorldActionReceipt = null
	if not preferred_target_id.is_empty():
		shared_receipt = _resolve_shared_work(
			coords,
			WorldActionResolver.VERB_SEARCH,
			preferred_target_id,
			_method_id_for_item_ids(selected_item_ids),
			0.75,
			_search_minutes(),
			work_hit_success_window
		)
		if shared_receipt == null:
			_show_result("WORK BLOCKED", _last_event())
			return
		if not shared_receipt.work_completed:
			_show_result(
				"WORK CYCLE RECORDED",
				"The search is %d%% complete. The work can continue from this state; no contents were removed yet."
				% int(round(shared_receipt.work_progress * 100.0))
			)
			return
		hex_data = _canonical_hex(coords)
		if hex_data == null:
			_show_result("SEARCH REJECTED", "The canonical search location is unavailable.")
			return
		expected_search_count = hex_data.search_count

	var outcome: Dictionary = _PoiController.resolve_search_outcome(
		world_state.world_seed,
		coords,
		hex_data,
		base_metrics,
		selected_item_ids,
		selected_search_option_id,
		tool_descriptors,
		loot_profile,
		Callable(self, "_inventory_has_any_item_id"),
		Callable(self, "_inventory_has_any_tag"),
		Callable(self, "_inventory_has_any_role")
	)
	if bool(outcome.get("blocked", false)) and not preferred_target_id.is_empty():
		var physical_target := _world_object_record_at(coords, preferred_target_id)
		if physical_target != null and (
			physical_target.has_component("rubble")
			or physical_target.has_component("container")
			or physical_target.has_component("debris")
		):
			# Physical objects use the receipt as their work gate. Their finite
			# contents still resolve from the same deterministic search seed.
			var physical_metrics: Dictionary = base_metrics.duplicate(true)
			physical_metrics["safety"] = maxf(
				7.0,
				float(physical_metrics.get("safety", 0.0))
			)
			physical_metrics["sneak"] = maxf(
				6.0,
				float(physical_metrics.get("sneak", 0.0))
			)
			var physical_result := _InteractionResolver.resolve_search(
				world_state.world_seed,
				coords,
				hex_data.search_count,
				physical_metrics,
				loot_profile,
				preferred_target_id
			)
			searched_target_id = preferred_target_id
			outcome = {
				"blocked": false,
				"coords": coords,
				"search_result": physical_result,
				"loot_ids": physical_result.get("loot_ids", []),
				"search_label": physical_target.definition_id.replace("_", " ").capitalize(),
				"injured": bool(physical_result.get("injured", false)),
				"injury_limb": physical_result.get(
					"injury_limb",
					GameEnums.LimbRegion.LEFT_ARM
				),
				"injury_damage": float(physical_result.get("injury_damage", 0.0)),
				"attracted_enemy": bool(physical_result.get("attracted_enemy", false)),
			}
	if bool(outcome.get("blocked", false)):
		_show_result(
			str(outcome.get("title", "SEARCH BLOCKED")),
			str(outcome.get("message", ""))
		)
		return

	var result: Dictionary = outcome.get("search_result", {})
	var search_label := str(outcome.get("search_label", "Search"))
	var found_names: Array[String] = []
	var run_flag_patch: Dictionary = {}
	var ground_item_states: Array = []
	for entry_value in available_guaranteed:
		var entry: Dictionary = entry_value
		var once_key := str(entry.get("once_key", ""))
		if (
			not once_key.is_empty()
			and outcome.get("loot_ids", []).has(str(entry.get("item_id", "")))
		):
			run_flag_patch["loot_once:" + once_key] = true
	for loot_id_value in outcome.get("loot_ids", []):
		var loot_id := str(loot_id_value)
		var item_state := _create_runtime_item_state(loot_id)
		if item_state.is_empty():
			continue
		found_names.append(
			str(item_state.get("definition", {}).get("display_name", loot_id))
		)
		ground_item_states.append(item_state)

	var depletion: Dictionary = {}
	if shared_receipt != null and not preferred_target_id.is_empty():
		depletion = _build_depletion(coords, preferred_target_id, "player")
	if not _commit_search_transaction({
		"coords": coords,
		"expected_search_count": expected_search_count,
		"searched_target_id": searched_target_id,
		"target_state": depletion.get("target_state", {}),
		"trace": depletion.get("trace", {}),
		"ground_items": ground_item_states,
		"run_flags": run_flag_patch,
		"injury_limb": outcome.get("injury_limb", GameEnums.LimbRegion.LEFT_ARM),
		"injury_damage": float(outcome.get("injury_damage", 0.0)) if bool(outcome.get("injured", false)) else 0.0,
		"elapsed_minutes": 0 if shared_receipt != null else _search_minutes(),
		"exertion": 1.0,
		"noise_intensity": 0.75,
		"attempt_index": expected_search_count + 1,
	}):
		_show_result("SEARCH REJECTED", "The search transaction was rejected without partial state.")
		return
	if not selected_search_option_id.is_empty():
		_apply_campaign_trigger("poi_resolved:%s" % selected_search_option_id)
	if not hex_data.poi_id.is_empty():
		_apply_campaign_trigger("poi_resolved:%s" % hex_data.poi_id)
	_refresh()

	var message := "Target: %s\n" % search_label
	message += (
		"Found: " + ", ".join(found_names)
		if not found_names.is_empty()
		else "The search produced no usable supplies."
	)
	message += "\nTime: " + _format_world_time()
	if not found_names.is_empty():
		message += "\nThe recovered items are on the ground below. Take them before leaving."
	if bool(outcome.get("injured", false)):
		message += "\nUnstable debris caused an injury."

	if bool(outcome.get("attracted_enemy", false)):
		message += "\nThe noise attracted a hostile."
		_advance_world(1, true)
		_spawn_intruder(coords)
		return
	_set_event("Searched %s at HEX %d,%d." % [search_label, coords.x, coords.y])
	_advance_world(1, true)
	if _has_pending_collision():
		return

	if _is_exploration_open():
		hex_data = world_generator.get_hex_at(coords)
		_present_poi_session(coords, hex_data)
		_refresh_exploration_ground()
	_show_result("SEARCH COMPLETE", message)


func _get_loot_profile(hex_data: MacroHexData) -> Dictionary:
	var value: Variant = _call("get_loot_profile", [hex_data])
	return value if value is Dictionary else {}


func _find_inventory_item(instance_id: String) -> ItemData:
	var value: Variant = _call("find_inventory_item", [instance_id])
	return value if value is ItemData else null


func _resolve_shared_work(
	coords: Vector2i,
	verb_id: String,
	target_id: String,
	method_id: String,
	noise_intensity: float,
	elapsed_minutes: int,
	hit_success_window: bool
) -> WorldActionReceipt:
	var value: Variant = _call(
		"resolve_shared_work",
		[
			coords,
			verb_id,
			target_id,
			method_id,
			noise_intensity,
			elapsed_minutes,
			hit_success_window,
		]
	)
	return value if value is WorldActionReceipt else null


func _method_id_for_item_ids(item_ids: Array) -> String:
	var value: Variant = _call("method_id_for_item_ids", [item_ids])
	return str(value) if value != null else ""


func _search_minutes() -> int:
	var value: Variant = _call("search_minutes")
	return int(value) if value != null else 15


func _world_object_record_at(
	coords: Vector2i,
	preferred_target_id: String
) -> WorldObjectRecord:
	var value: Variant = _call(
		"world_object_record_at",
		[coords, preferred_target_id]
	)
	return value if value is WorldObjectRecord else null


func _inventory_has_any_item_id(item_ids: Array) -> bool:
	return bool(_call("inventory_has_any_item_id", [item_ids]))


func _inventory_has_any_tag(tags: Array) -> bool:
	return bool(_call("inventory_has_any_tag", [tags]))


func _inventory_has_any_role(roles: Array) -> bool:
	return bool(_call("inventory_has_any_role", [roles]))


func _create_runtime_item_state(item_id: String) -> Dictionary:
	if loot_catalog == null or not loot_catalog.has_method("create_runtime_item_state"):
		return {}
	var value: Variant = loot_catalog.call("create_runtime_item_state", item_id)
	return value if value is Dictionary else {}


func _canonical_hex(coords: Vector2i) -> MacroHexData:
	if world_state == null:
		return null
	var record := world_state.get_hex_record(coords)
	return MacroHexData.from_state(record) if record != null else null


func _build_depletion(coords: Vector2i, target_id: String, actor_id: String) -> Dictionary:
	var value: Variant = _call("build_depletion", [coords, target_id, actor_id])
	return value if value is Dictionary else {}


func _commit_search_transaction(payload: Dictionary) -> bool:
	return bool(_call("commit_search_transaction", [payload]))


func _apply_campaign_trigger(trigger_id: String) -> void:
	_call("apply_campaign_trigger", [trigger_id])


func _refresh() -> void:
	_call("refresh_hud")


func _format_world_time() -> String:
	var value: Variant = _call("format_world_time")
	return str(value) if value != null else ""


func _set_event(message: String) -> void:
	_call("set_event", [message])


func _last_event() -> String:
	var value: Variant = _call("last_event")
	return str(value) if value != null else ""


func _notify_noise(coords: Vector2i, event_id: String) -> void:
	_call("notify_noise", [coords, event_id])


func _advance_world(turns: int, bypass_interaction_check: bool) -> void:
	_call("advance_world", [turns, bypass_interaction_check])


func _has_pending_collision() -> bool:
	return bool(_call("has_pending_collision"))


func _is_exploration_open() -> bool:
	return bool(_call("is_exploration_open"))


func _present_poi_session(coords: Vector2i, hex_data: MacroHexData) -> void:
	_call("present_poi_session", [coords, hex_data])


func _refresh_exploration_ground() -> void:
	_call("refresh_exploration_ground")


func _spawn_intruder(coords: Vector2i) -> void:
	_call("spawn_intruder", [coords])


func _show_result(title: String, message: String) -> void:
	_call("show_result", [title, message])


func _call(key: String, args: Array = []) -> Variant:
	var value: Variant = callbacks.get(key, Callable())
	if value is Callable and value.is_valid():
		return value.callv(args)
	return null
