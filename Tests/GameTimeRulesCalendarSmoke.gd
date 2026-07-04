extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_calendar()
	print("[TEST PASS] GameTimeRules calendar derivation.")
	quit(0)

func _assert_calendar() -> void:
	var day1 := GameTimeRules.calendar_snapshot(8 * 60)
	if int(day1.get("day", 0)) != 1:
		_fail("Day 1 calendar snapshot failed.")
	if int(day1.get("month", 0)) != 1:
		_fail("Month should be 1 on day 1.")
	var day31 := GameTimeRules.calendar_snapshot((31 * 24 * 60) + (8 * 60))
	if int(day31.get("month", 0)) != 2:
		_fail("Day 31 should roll to month 2.")
	var day360 := GameTimeRules.calendar_snapshot((360 * 24 * 60))
	if int(day360.get("year", 0)) != 2:
		_fail("Day 360 should be year 2.")

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
