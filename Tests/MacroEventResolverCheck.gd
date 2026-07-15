extends SceneTree


func _initialize() -> void:
	var base_context := {
		"item_ids": [],
		"item_tags": [],
		"item_roles": [],
		"item_names": {},
		"occupations": [],
		"traits": [],
		"flaws": [],
		"stats": {"brawn": 1, "finesse": 1, "fortitude": 1, "will": 1},
	}
	var session: Dictionary = MacroEventResolver.build_event_session(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		base_context
	)
	if session.is_empty() or session.get("choices", []).size() != 5:
		_fail("Locked treatment room session did not expose all choices.")
		return
	if not _choice_enabled(session, "listen_first"):
		_fail("Always-available observation choice was locked.")
		return
	if _choice_enabled(session, "cut_alarm"):
		_fail("Contextual alarm choice was enabled without its requirement.")
		return

	var blocked: Dictionary = MacroEventResolver.resolve_choice(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		"cut_alarm",
		base_context
	)
	if not blocked.get("effects", {}).is_empty() or blocked.has("choice_id"):
		_fail("Blocked choices produced a successful event result.")
		return

	var equipped_context: Dictionary = base_context.duplicate(true)
	equipped_context["item_ids"] = ["wire_cutter"]
	equipped_context["item_names"] = {"wire_cutter": "Wire Cutter"}
	var equipped_session: Dictionary = MacroEventResolver.build_event_session(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		equipped_context
	)
	if not _choice_enabled(equipped_session, "cut_alarm"):
		_fail("Wire cutter did not unlock the alarm choice.")
		return

	var resolved: Dictionary = MacroEventResolver.resolve_choice(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		"listen_first",
		base_context
	)
	if (
		resolved.get("choice_id", "") != "listen_first"
		or int(resolved.get("effects", {}).get("elapsed_minutes", 0)) != 5
	):
		_fail("Valid choice did not return its expected result and effects.")
		return

	print("[TEST PASS] Macro event resolver requirements and outcomes.")
	quit(0)


func _choice_enabled(session: Dictionary, choice_id: String) -> bool:
	for choice in session.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			return bool(choice.get("enabled", false))
	return false


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
