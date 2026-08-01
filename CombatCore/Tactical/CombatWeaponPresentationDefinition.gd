extends Resource
class_name CombatWeaponPresentationDefinition

## Weapon-specific presentation data recovered from the former duel HUD.
## These sheets decorate an already-committed action; they never resolve combat.

@export var weapon_id: String = ""
@export var shoot_sheet: Texture2D
@export var shoot_frame_size := Vector2i.ZERO
@export var shoot_fps: float = 14.0
@export var reload_sheet: Texture2D
@export var reload_frame_size := Vector2i.ZERO
@export var reload_fps: float = 14.0
@export var cycle_sheet: Texture2D
@export var cycle_frame_size := Vector2i.ZERO
@export var cycle_fps: float = 14.0


func sheet_for_action(action_id: String) -> Texture2D:
	if action_id in ["fire", "aimed_fire"]:
		return shoot_sheet
	if action_id == "reload":
		return reload_sheet
	if action_id in ["cycle", "clear_malfunction"]:
		return cycle_sheet
	return null


func frame_size_for_action(action_id: String) -> Vector2i:
	if action_id in ["fire", "aimed_fire"]:
		return shoot_frame_size
	if action_id == "reload":
		return reload_frame_size
	if action_id in ["cycle", "clear_malfunction"]:
		return cycle_frame_size
	return Vector2i.ZERO


func fps_for_action(action_id: String) -> float:
	if action_id in ["fire", "aimed_fire"]:
		return shoot_fps
	if action_id == "reload":
		return reload_fps
	if action_id in ["cycle", "clear_malfunction"]:
		return cycle_fps
	return 0.0


func duration_for_action(action_id: String) -> float:
	var sheet := sheet_for_action(action_id)
	var frame_size := frame_size_for_action(action_id)
	var fps := fps_for_action(action_id)
	if sheet == null or frame_size.x <= 0 or frame_size.y <= 0 or fps <= 0.0:
		return 0.0
	var columns := maxi(1, sheet.get_width() / frame_size.x)
	var rows := maxi(1, sheet.get_height() / frame_size.y)
	return float(columns * rows) / fps

