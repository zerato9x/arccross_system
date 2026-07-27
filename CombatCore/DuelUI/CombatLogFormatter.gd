extends RefCounted
class_name CombatLogFormatter

static func presentation_log_line(event: Dictionary) -> String:
	var event_type := str(event.get("type", "action"))
	if event_type == "shot":
		return shot_log_line(event)
	if event_type == "damage":
		return damage_log_line(event)
	if event_type == "bleed":
		return "%s BLEEDS // -%s BLOOD (%s WOUNDS)" % [
			side_log_label(str(event.get("side", ""))),
			CombatHudGeometry.compact_number(float(event.get("blood_loss", 0.0))),
			str(event.get("active_bleeds", 0)),
		]
	if event_type == "death":
		return "%s DOWN" % side_log_label(str(event.get("side", "")))
	var action := int(event.get("action", -1))
	return "%s // %s" % [
		side_log_label(str(event.get("side", ""))),
		action_log_label(action),
	]

static func shot_log_line(event: Dictionary) -> String:
	var attacker := side_log_label(str(event.get("attacker_side", event.get("side", ""))))
	var result := str(event.get("result", "shot")).replace("_", " ").to_upper()
	return "%s SHOT // %s" % [attacker, result]

static func damage_log_line(event: Dictionary) -> String:
	var rows := PackedStringArray()
	var limb := str(event.get("limb", "BODY")).replace("_", " ")
	var flesh := float(event.get("flesh_damage", 0.0))
	var stance := float(event.get("stance_damage", 0.0))
	var trauma := str(event.get("trauma", "NONE"))
	var prefix := "%s HIT // %s" % [
		side_log_label(str(event.get("side", ""))),
		limb,
	]
	if flesh > 0.0:
		rows.append("FLESH -" + CombatHudGeometry.compact_number(flesh))
	if stance > 0.0:
		rows.append("STANCE -" + CombatHudGeometry.compact_number(stance))
	if trauma != "NONE":
		rows.append(trauma.replace("_", " "))
	if bool(event.get("was_felled", false)):
		rows.append("FELLED")
	if bool(event.get("was_killed", false)):
		rows.append("KILLED")
	if rows.is_empty():
		rows.append("DEFLECTED")
	return "%s %s" % [prefix, " / ".join(rows)]

static func side_log_label(side: String) -> String:
	match side:
		"player":
			return "YOU"
		"enemy":
			return "HOSTILE"
	return "COMBAT"

static func action_log_label(action: int) -> String:
	match action:
		GameEnums.ActionType.PUSH_STAY:
			return "PUSH"
		GameEnums.ActionType.PULL_FOLLOW:
			return "PULL"
		GameEnums.ActionType.BREAK:
			return "BREAK STANCE"
	var names := GameEnums.ActionType.keys()
	if action >= 0 and action < names.size():
		return str(names[action]).replace("_", " ")
	return "ACTION"
