extends RefCounted
class_name MacroCampaignProgressionService

## Application adapter for campaign traversal. MacroGameManager owns surface
## and token side effects; this service exposes only campaign intent outcomes.

var campaign: MacroProgressController
var callbacks: Dictionary = {}


func configure(
	value: MacroProgressController,
	configured_callbacks: Dictionary = {}
) -> void:
	campaign = value
	callbacks = configured_callbacks.duplicate()


func available_nodes() -> Array[String]:
	return campaign.get_available_nodes() if campaign != null else []


func can_enter(node_id: String, exit_direction: int) -> bool:
	return campaign != null and campaign.can_enter_node(node_id, exit_direction)


func enter(node_id: String, exit_direction: int) -> bool:
	return campaign != null and campaign.enter_node(node_id, exit_direction)


func mark_completed(node_id: String) -> void:
	if campaign != null:
		campaign.mark_node_completed(node_id)


func evaluate_unlocks(player_progress: Dictionary) -> Array[String]:
	return campaign.evaluate_unlocks(player_progress) if campaign != null else []


func apply_discovery_trigger(trigger_id: String) -> PackedStringArray:
	return campaign.apply_discovery_trigger(trigger_id) if campaign != null else []


func debug_map() -> String:
	return campaign.debug_print_map() if campaign != null else "(no campaign graph)"


func resolve_central_core_activation(
	coords: Vector2i,
	hex_data: MacroHexData,
	meta_progress: Node
) -> void:
	if hex_data == null or hex_data.poi_id != MacroGraphGenerator.CENTRAL_ID:
		_show_result(
			"ACTIVATION BLOCKED",
			"This location cannot bring the Alpha Core online."
		)
		return
	var core_state: Dictionary = (
		meta_progress.get_core_state(MacroGraphGenerator.CENTRAL_ID)
		if meta_progress != null and meta_progress.has_method("get_core_state")
		else {}
	)
	if bool(core_state.get("activated", false)):
		_show_result(
			"CORE ONLINE",
			"The Alpha Core is already active. The wasteland remembers."
		)
		return

	_advance_time(_search_minutes(), 1.5, coords)
	if meta_progress != null:
		meta_progress.complete_event(
			"central_core_activated",
			[
				{
					"type": "set_core_state",
					"core_id": MacroGraphGenerator.CENTRAL_ID,
					"state": {"activated": true},
				}
			]
		)
	_close_interaction()
	_set_event("Alpha Core activated at %s." % str(coords))
	_refresh()
	_emit_core_activated()


func resolve_regional_core_restoration(
	coords: Vector2i,
	hex_data: MacroHexData,
	meta_progress: Node
) -> void:
	var active_node := campaign.get_active_node() if campaign != null else null
	if (
		active_node == null
		or active_node.role != GameEnums.MacroNodeRole.ARM_CORE
		or hex_data == null
		or hex_data.poi_id != "arm_core"
	):
		_show_result(
			"RESTORATION BLOCKED",
			"No regional Core is connected here."
		)
		return
	var core_id := active_node.id
	var state: Dictionary = (
		meta_progress.get_core_state(core_id)
		if meta_progress != null and meta_progress.has_method("get_core_state")
		else {}
	)
	if bool(state.get("restored", false)):
		_show_result("CORE STABLE", "This regional Core is already restored.")
		return

	_advance_time(_search_minutes(), 1.5, coords)
	state["restored"] = true
	if meta_progress != null and meta_progress.has_method("set_core_state"):
		meta_progress.set_core_state(core_id, state)
	if not hex_data.searched_targets.has("restore_regional_core"):
		hex_data.searched_targets.append("restore_regional_core")
		_persist_hex(coords, hex_data.to_state())
	if campaign != null:
		campaign.refresh_meta_unlocks()
	_apply_trigger("core_restored:%s" % core_id)
	_close_interaction()
	_set_event("%s restored." % active_node.display_name)
	_refresh()
	_show_result(
		"REGIONAL CORE RESTORED",
		"%s is back in the infrastructure network." % active_node.display_name
	)


func _search_minutes() -> int:
	var value: Variant = _call("search_minutes")
	return int(value) if value != null else 15


func _advance_time(minutes: int, exertion: float, coords: Vector2i) -> void:
	_call("advance_time", [minutes, exertion, coords])


func _persist_hex(coords: Vector2i, state: Variant) -> void:
	_call("persist_hex", [coords, state])


func _apply_trigger(trigger_id: String) -> void:
	_call("apply_trigger", [trigger_id])


func _close_interaction() -> void:
	_call("close_interaction")


func _set_event(message: String) -> void:
	_call("set_event", [message])


func _refresh() -> void:
	_call("refresh_hud")


func _emit_core_activated() -> void:
	_call("emit_core_activated")


func _show_result(title: String, message: String) -> void:
	_call("show_result", [title, message])


func _call(key: String, args: Array = []) -> Variant:
	var value: Variant = callbacks.get(key, Callable())
	if value is Callable and value.is_valid():
		return value.callv(args)
	return null
