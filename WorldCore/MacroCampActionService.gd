extends RefCounted
class_name MacroCampActionService

## Applies the camp/rest interaction through neutral application callbacks.
##
## MacroInteractionResolver owns the deterministic camp result. This service
## owns the repeated rest loop and delegates authoritative player/world writes
## and presentation to the macro application shell.

const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const _InteractionResolver := preload(
	"res://WorldCore/MacroInteractionResolver.gd"
)

var world_state: RuntimeStateStore
var callbacks: Dictionary = {}


func configure(state: RuntimeStateStore, configured_callbacks: Dictionary) -> void:
	world_state = state
	callbacks = configured_callbacks.duplicate()


func resolve(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	_selected_item_ids: Array
) -> void:
	if world_state == null or hex_data == null:
		return
	var descriptors: Array = _PoiController.camp_item_descriptors(
		hex_data.camp_item_states
	)
	if not hex_data.sleep_gear_instance_id.is_empty():
		var sleep_item := _find_inventory_item(hex_data.sleep_gear_instance_id)
		if sleep_item != null:
			descriptors.append(sleep_item.to_interaction_descriptor())
	var metrics := _InteractionResolver.calculate_camp_metrics(
		base_metrics,
		descriptors
	)
	var result := _resolve_camp_result(coords, hex_data, metrics)
	if hex_data.region in [
		GameEnums.MacroRegion.CENTRAL_HUB,
		GameEnums.MacroRegion.HUB_BORDER,
	]:
		result["interrupted"] = false
	hex_data.camp_rest_count += 1

	var body := _player_body()
	if body == null:
		return
	var missing_fatigue: float = body.fatigue
	var fatigue_recovery := float(result.get("fatigue_recovery", 0.0))
	var fatigue_turns: float = ceil(
		missing_fatigue / maxf(0.1, fatigue_recovery)
	)

	var total_missing_limb: float = 0.0
	for limb in body.limb_hp.keys():
		total_missing_limb += maxf(
			0.0,
			body.get_limb_max(limb) - body.limb_hp[limb]
		)
	var healing_amount := float(result.get("healing_amount", 0.0))
	var healing_turns: float = (
		ceil(total_missing_limb / maxf(0.1, healing_amount))
		if healing_amount > 0.0
		else 0
	)
	var turns_to_rest := maxi(
		1,
		mini(8, int(maxf(fatigue_turns, healing_turns)))
	)

	var turns_rested := 0
	var total_healed := 0.0
	var total_fatigue := 0.0
	for i in range(turns_to_rest):
		if i > 0:
			result = _resolve_camp_result(coords, hex_data, metrics)
			if hex_data.region in [
				GameEnums.MacroRegion.CENTRAL_HUB,
				GameEnums.MacroRegion.HUB_BORDER,
			]:
				result["interrupted"] = false

		var healed_this_turn := 0.0
		body.fatigue = maxf(
			0.0,
			body.fatigue - float(result.get("fatigue_recovery", 0.0))
		)
		total_fatigue += float(result.get("fatigue_recovery", 0.0))

		for limb in body.limb_hp.keys():
			if body.limb_hp[limb] <= 0.0:
				continue
			var to_heal := minf(
				body.get_limb_max(limb) - body.limb_hp[limb],
				healing_amount
			)
			body.limb_hp[limb] += to_heal
			healed_this_turn += to_heal
		total_healed += healed_this_turn

		_advance_survival_time(
			_time_callback_minutes(),
			0.25,
			coords,
			float(metrics.get("shelter", 0.0)),
			"sleep"
		)
		hex_data.camp_rest_count += 1
		turns_rested += 1
		_advance_world(1, true)

		if bool(result.get("interrupted", false)):
			_persist(coords, hex_data)
			_refresh()
			_spawn_intruder(coords)
			return

		if _has_pending_collision():
			_persist(coords, hex_data)
			_refresh()
			return

	_persist(coords, hex_data)
	_refresh()
	_set_event("Camp rest resolved at HEX %d,%d." % [coords.x, coords.y])
	_show_result(
		"REST COMPLETE",
		(
			"Rested for %d turn(s). Fatigue recovered by %.1f. Camp healing restored %.1f limb health."
			+ "\nTime: %s"
		) % [
			turns_rested,
			total_fatigue,
			total_healed,
			_format_world_time(),
		]
	)


func _resolve_camp_result(
	coords: Vector2i,
	hex_data: MacroHexData,
	metrics: Dictionary
) -> Dictionary:
	return _InteractionResolver.resolve_camp(
		world_state.world_seed,
		coords,
		hex_data.camp_rest_count,
		metrics
	)


func _find_inventory_item(instance_id: String) -> ItemData:
	var value: Variant = _call("find_inventory_item", [instance_id])
	return value if value is ItemData else null


func _player_body() -> HumanoidBody:
	var value: Variant = _call("player_body")
	return value if value is HumanoidBody else null


func _advance_survival_time(
	elapsed_minutes: int,
	exertion: float,
	coords: Vector2i,
	insulation_bonus: float,
	verb_id: String
) -> void:
	_call(
		"advance_survival_time",
		[
			elapsed_minutes,
			exertion,
			coords,
			insulation_bonus,
			verb_id,
		]
	)


func _time_callback_minutes() -> int:
	var value: Variant = _call("camp_minutes")
	return int(value) if value != null else 30


func _advance_world(turns: int, bypass_interaction_check: bool) -> void:
	_call("advance_world", [turns, bypass_interaction_check])


func _has_pending_collision() -> bool:
	return bool(_call("has_pending_collision"))


func _persist(coords: Vector2i, hex_data: MacroHexData) -> void:
	world_state.set_hex_record(coords, hex_data.to_state())
	var runtime: Variant = _call("capture_player_runtime")
	if runtime is Dictionary:
		world_state.update_player_runtime(runtime, coords)


func _refresh() -> void:
	_call("refresh_hud")


func _spawn_intruder(coords: Vector2i) -> void:
	_call("spawn_intruder", [coords])


func _set_event(message: String) -> void:
	_call("set_event", [message])


func _show_result(title: String, message: String) -> void:
	_call("show_result", [title, message])


func _format_world_time() -> String:
	var value: Variant = _call("format_world_time")
	return str(value) if value != null else ""


func _call(key: String, args: Array = []) -> Variant:
	var value: Variant = callbacks.get(key, Callable())
	if value is Callable and value.is_valid():
		return value.callv(args)
	return null
