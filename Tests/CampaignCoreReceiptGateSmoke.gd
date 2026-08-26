extends SceneTree


class FakeMetaProgress:
	extends Node
	var core_states: Dictionary = {}
	var completed_events: Dictionary = {}

	func get_core_state(core_id: String) -> Dictionary:
		return core_states.get(core_id, {}).duplicate(true)

	func complete_event(event_id: String, effects: Array = []) -> bool:
		completed_events[event_id] = true
		for effect_value in effects:
			if not effect_value is Dictionary:
				continue
			var effect: Dictionary = effect_value
			if str(effect.get("type", "")) == "set_core_state":
				core_states[str(effect.get("core_id", ""))] = effect.get(
					"state", {}
				).duplicate(true)
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	if not _verify_rejected_activation_stops_side_effects():
		return false
	if not _verify_accepted_activation_orders_side_effects():
		return false
	print("CAMPAIGN_CORE_RECEIPT_GATE_SMOKE: PASS")
	quit(0)
	return true


func _verify_rejected_activation_stops_side_effects() -> bool:
	var meta := FakeMetaProgress.new()
	root.add_child(meta)
	var calls := _call_state()
	var rejected := WorldActionApplicationReceipt.new()
	rejected.error = "Injected activation receipt rejection."
	var service := MacroCampaignProgressionService.new()
	service.configure(null, _callbacks(calls, rejected))
	service.resolve_central_core_activation(Vector2i.ZERO, _central_hex(), meta)
	if int(calls.get("advance", 0)) != 1:
		return _fail(meta, "Rejected activation did not attempt exactly one receipt.")
	if not meta.get_core_state(MacroGraphGenerator.CENTRAL_ID).is_empty():
		return _fail(meta, "Rejected activation mutated meta core state.")
	if bool(meta.completed_events.get("central_core_activated", false)):
		return _fail(meta, "Rejected activation completed the meta event.")
	for key in ["close", "event", "refresh", "emit"]:
		if int(calls.get(key, 0)) != 0:
			return _fail(meta, "Rejected activation emitted post-commit callback: " + key)
	if str(calls.get("result_title", "")) != "ACTIVATION INTERRUPTED":
		return _fail(meta, "Rejected activation did not expose interruption state.")
	meta.queue_free()
	return true


func _verify_accepted_activation_orders_side_effects() -> bool:
	var meta := FakeMetaProgress.new()
	root.add_child(meta)
	var calls := _call_state()
	var accepted := WorldActionApplicationReceipt.new()
	accepted.applied = true
	var service := MacroCampaignProgressionService.new()
	service.configure(null, _callbacks(calls, accepted))
	service.resolve_central_core_activation(Vector2i(1, 2), _central_hex(), meta)
	if not bool(meta.get_core_state(
		MacroGraphGenerator.CENTRAL_ID
	).get("activated", false)):
		return _fail(meta, "Accepted activation did not update meta core state.")
	if not bool(meta.completed_events.get("central_core_activated", false)):
		return _fail(meta, "Accepted activation did not complete its meta event.")
	for key in ["advance", "close", "event", "refresh", "emit"]:
		if int(calls.get(key, 0)) != 1:
			return _fail(meta, "Accepted activation callback count drifted: " + key)
	meta.queue_free()
	return true


func _callbacks(
	calls: Dictionary,
	application: WorldActionApplicationReceipt
) -> Dictionary:
	return {
		"search_minutes": func(): return 15,
		"advance_time": func(
			_minutes: int, _exertion: float, _coords: Vector2i
		):
			calls["advance"] = int(calls.get("advance", 0)) + 1
			return application,
		"close_interaction": func():
			calls["close"] = int(calls.get("close", 0)) + 1,
		"set_event": func(_message: String):
			calls["event"] = int(calls.get("event", 0)) + 1,
		"refresh_hud": func():
			calls["refresh"] = int(calls.get("refresh", 0)) + 1,
		"emit_core_activated": func():
			calls["emit"] = int(calls.get("emit", 0)) + 1,
		"show_result": func(title: String, message: String):
			calls["result_title"] = title
			calls["result_message"] = message,
	}


func _call_state() -> Dictionary:
	return {
		"advance": 0,
		"close": 0,
		"event": 0,
		"refresh": 0,
		"emit": 0,
		"result_title": "",
		"result_message": "",
	}


func _central_hex() -> MacroHexData:
	var hex := MacroHexData.new()
	hex.poi_id = MacroGraphGenerator.CENTRAL_ID
	return hex


func _fail(meta: Node, message: String) -> bool:
	if meta != null:
		meta.queue_free()
	push_error("[CAMPAIGN CORE RECEIPT GATE] " + message)
	quit(1)
	return false
