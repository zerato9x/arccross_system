extends RefCounted
class_name CombatSfxEmitter

## Combat presentation sound-effect routing extracted from CombatLaneHUD.
## Forwards scene-audio requests to the GameEventBus autoload.

var _event_bus: Node

func _init(event_bus: Node = null) -> void:
	_event_bus = event_bus

func set_event_bus(event_bus: Node) -> void:
	_event_bus = event_bus

func emit_action_sfx_at_animation_start(event: Dictionary) -> void:
	var action := int(event.get("action", -1))
	if action in [GameEnums.ActionType.SHOOT, GameEnums.ActionType.AIMED_SHOT]:
		return
	match action:
		GameEnums.ActionType.STRIKE, GameEnums.ActionType.GRAPPLE, \
		GameEnums.ActionType.BREAK, GameEnums.ActionType.PUSH_STAY, \
		GameEnums.ActionType.PULL_FOLLOW, GameEnums.ActionType.BLOCK, \
		GameEnums.ActionType.RELOAD, GameEnums.ActionType.CYCLE:
			_emit_presentation_sfx("combat_action_sfx", event)

func emit_shot_sfx_at_projectile_start(event: Dictionary) -> void:
	_emit_presentation_sfx("combat_action_sfx", event)

func emit_damage_sfx_at_impact(
	event: Dictionary,
	play_impact_sound: Callable = Callable()
) -> void:
	if (
		float(event.get("flesh_damage", 0.0)) <= 0.0
		and str(event.get("result", "")) not in ["hit", "collateral_hit"]
		and str(event.get("trauma", "NONE")) == "NONE"
	):
		return
	if play_impact_sound.is_valid():
		play_impact_sound.call()
	_emit_presentation_sfx("combat_damage_sfx", event)

func _emit_presentation_sfx(scene_id: String, event: Dictionary) -> void:
	var bus := _event_bus
	if bus == null or not bus.has_method("emit_scene_audio"):
		return
	bus.emit_scene_audio(scene_id, {
		"action": int(event.get("action", -1)),
		"weapon_class": int(event.get(
			"weapon_class",
			GameEnums.WeaponClass.NONE
		)),
		"weapon_id": str(event.get("weapon_id", "")),
		"side": str(event.get("side", "")),
		"result": str(event.get("result", "")),
		"limb_index": int(event.get("limb_index", -1)),
		"damage_type": str(event.get("damage_type", "")),
		"trauma": str(event.get("trauma", "NONE")),
	})
