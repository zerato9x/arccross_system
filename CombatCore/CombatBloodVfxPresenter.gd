extends RefCounted
class_name CombatBloodVfxPresenter

## Blood impact sheet playback extracted from CombatLaneHUD.

const FRAME_COUNT := 29
const FPS := 30.0
const VARIANT_FRAME_COUNTS := {
	1: 26,
	2: 24,
	3: 29,
	4: 24,
	5: 27,
	6: 26,
	7: 27,
	8: 28,
	9: 29,
}

static func variant_for_event(event: Dictionary) -> int:
	var seed := (
		int(event.get("limb_index", 0))
		+ int(event.get("origin_lane", 0))
		+ int(event.get("target_lane", 0))
	)
	return posmod(seed, 9) + 1


static func frame_path(variant: int, frame_index: int) -> String:
	return "res://Asset/VFX/BLOOD VFX/%d/1_%03d.png" % [variant, frame_index]


static func frame_count(variant: int) -> int:
	return int(VARIANT_FRAME_COUNTS.get(variant, FRAME_COUNT))
