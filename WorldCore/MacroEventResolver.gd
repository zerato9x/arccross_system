extends RefCounted
class_name MacroEventResolver

const EVENT_LOCKED_TREATMENT_ROOM = "locked_treatment_room"
const DEFAULT_EVENT_IMAGE = (
	"res://Asset/UI/Event_bg/apocalyptic_bg/PNG/Postapocalypce1/"
	+ "Bright/ground&houses.png"
)


static func build_event_session(event_id, context):
	var definition = _event_definition(event_id)
	if definition.is_empty():
		return {}

	var choices = []
	for choice in definition.get("choices", []):
		if choice is Dictionary:
			choices.append(_evaluate_choice(choice, context))

	return {
		"id": event_id,
		"title": definition.get("title", "Event"),
		"body": definition.get("body", ""),
		"image_path": _event_image_path(definition, context),
		"tags": _build_tags(context),
		"choices": choices,
		"can_close": false,
	}


static func resolve_choice(event_id, choice_id, context):
	var definition = _event_definition(event_id)
	for choice in definition.get("choices", []):
		if str(choice.get("id", "")) != str(choice_id):
			continue
		var evaluated = _evaluate_choice(choice, context)
		if not bool(evaluated.get("enabled", false)):
			return {
				"title": "ACTION BLOCKED",
				"body": str(evaluated.get("reason", "This choice is unavailable.")),
				"effects": {},
			}
		var result = choice.get("result", {}).duplicate(true)
		result["choice_id"] = choice_id
		return result
	return {
		"title": "EVENT LOST",
		"body": "The selected choice no longer exists. Spectacular, but not useful.",
		"effects": {},
	}


static func _event_definition(event_id):
	if str(event_id) == EVENT_LOCKED_TREATMENT_ROOM:
		return _locked_treatment_room()
	return {}


static func _locked_treatment_room():
	var choices = []
	choices.append(_choice(
		"listen_first",
		"Listen before touching the door",
		"observe",
		"Takes a moment. Reveals the safer entry rhythm.",
		[],
		"A PATTERN IN THE ROOM",
		(
			"The clicking settles into a slow mechanical pulse. Whatever is "
			+ "inside is damaged, not alive. Probably. A heroic amount of "
			+ "certainty, as usual."
		),
		{"elapsed_minutes": 5, "exertion": 0.25}
	))
	choices.append(_choice(
		"pry_open",
		"Pry the frame open",
		"item",
		"Costs time. Loud enough to make stealth file a complaint.",
		[
			{"any_item_ids": ["crowbar", "multitool"]},
			{"any_item_tags": ["tools"]},
		],
		"THE FRAME GIVES",
		(
			"The frame tears loose with a dry metallic cough. The room is "
			+ "open, and subtlety has left the building."
		),
		{"elapsed_minutes": 20, "exertion": 1.0}
	))
	choices.append(_choice(
		"force_open",
		"Shoulder through",
		"force",
		"Fast, ugly, and medically optimistic.",
		[{"min_stats": {"brawn": 8}}],
		"THE DOOR BUCKLES",
		(
			"You hit the door hard enough to make old hinges remember fear. "
			+ "Your shoulder complains because apparently physics still works."
		),
		{"elapsed_minutes": 10, "exertion": 1.5}
	))
	choices.append(_choice(
		"pick_lock",
		"Work the lock",
		"item",
		"Quiet. Slower than brute force, because dignity has a cost.",
		[
			{"any_item_ids": ["multitool", "lockpick"]},
			{"any_occupations": ["Locksmith", "Mechanic"]},
		],
		"A CLEAN CLICK",
		(
			"The lock gives with a tiny click. For once, civilization's "
			+ "rotting leftovers decide to cooperate."
		),
		{"elapsed_minutes": 15, "exertion": 0.5}
	))
	choices.append(_choice(
		"cut_alarm",
		"Disable the alarm circuit",
		"item",
		"Avoids noise if you actually have the skill or tool.",
		[
			{"any_item_ids": ["wire_cutter"]},
			{"any_occupations": ["Electrician"]},
		],
		"SILENT ENTRY",
		"The alarm dies before it can embarrass everyone involved.",
		{"elapsed_minutes": 12, "exertion": 0.25}
	))
	return {
		"title": "Locked Treatment Room",
		"body": (
			"A warped steel door blocks the clinic's treatment wing. "
			+ "Something inside clicks against tile, patient as a bad idea."
		),
		"image_path": DEFAULT_EVENT_IMAGE,
		"choices": choices,
	}


static func _choice(
	id,
	label,
	kind,
	preview,
	requires_any,
	result_title,
	result_body,
	effects
):
	return {
		"id": id,
		"label": label,
		"kind": kind,
		"preview": preview,
		"requires_any": requires_any,
		"result": {
			"title": result_title,
			"body": result_body,
			"effects": effects,
		},
	}


static func _evaluate_choice(choice, context):
	var evaluated = choice.duplicate(true)
	evaluated["stakes"] = _build_choice_stakes(choice)
	var requirements = choice.get("requires_any", [])
	if requirements.is_empty():
		evaluated["enabled"] = true
		evaluated["reason"] = "Always available."
		return evaluated

	var missing = []
	for requirement in requirements:
		if not (requirement is Dictionary):
			continue
		var check = _requirement_check(requirement, context)
		if bool(check.get("met", false)):
			evaluated["enabled"] = true
			evaluated["reason"] = str(check.get("reason", "Requirement met."))
			return evaluated
		missing.append(str(check.get("missing", "missing requirement")))

	evaluated["enabled"] = false
	evaluated["reason"] = "Requires " + " or ".join(PackedStringArray(missing)) + "."
	return evaluated


static func _build_choice_stakes(choice):
	var stakes: PackedStringArray = []
	var kind := str(choice.get("kind", ""))
	match kind:
		"observe":
			stakes.append("OBSERVE")
		"force":
			stakes.append("FORCE")
		"item":
			stakes.append("TOOL")
		_:
			if not kind.is_empty():
				stakes.append(kind.to_upper())

	var result = choice.get("result", {})
	var effects = {}
	if result is Dictionary:
		effects = result.get("effects", {})
	if effects is Dictionary:
		var elapsed := int(effects.get("elapsed_minutes", 0))
		if elapsed > 0:
			stakes.append("+%d MIN" % elapsed)
		var exertion := float(effects.get("exertion", 0.0))
		if not is_zero_approx(exertion):
			stakes.append("EXERT %.2f" % exertion)
	return stakes


static func _requirement_check(requirement, context):
	var matched = []
	var missing = []
	_check_any_item_ids(requirement, context, matched, missing)
	_check_any_item_tags(requirement, context, matched, missing)
	_check_any_roles(requirement, context, matched, missing)
	_check_any_named_context(requirement, context, "any_occupations", "occupations", "occupation", matched, missing)
	_check_any_named_context(requirement, context, "any_traits", "traits", "trait", matched, missing)
	_check_any_named_context(requirement, context, "any_flaws", "flaws", "flaw", matched, missing)
	_check_min_stats(requirement, context, matched, missing)

	if not missing.is_empty():
		return {"met": false, "missing": " + ".join(PackedStringArray(missing))}
	return {
		"met": true,
		"reason": "Unlocked by " + " + ".join(PackedStringArray(matched)) + ".",
	}


static func _check_any_item_ids(requirement, context, matched, missing):
	if not requirement.has("any_item_ids"):
		return
	var item_match = _match_any(context.get("item_ids", []), requirement.get("any_item_ids", []))
	if item_match.is_empty():
		missing.append(_join_names(requirement.get("any_item_ids", [])))
	else:
		matched.append(_item_label(item_match, context))


static func _check_any_item_tags(requirement, context, matched, missing):
	if not requirement.has("any_item_tags"):
		return
	var tag_match = _match_any(context.get("item_tags", []), requirement.get("any_item_tags", []))
	if tag_match.is_empty():
		missing.append("item tag: " + _join_names(requirement.get("any_item_tags", [])))
	else:
		matched.append("item tag: " + tag_match)


static func _check_any_roles(requirement, context, matched, missing):
	if not requirement.has("any_roles"):
		return
	var role_match = _match_any(context.get("item_roles", []), requirement.get("any_roles", []))
	if role_match.is_empty():
		missing.append("item role")
	else:
		matched.append("item role")


static func _check_any_named_context(
	requirement,
	context,
	requirement_key,
	context_key,
	label,
	matched,
	missing
):
	if not requirement.has(requirement_key):
		return
	var value_match = _match_any(context.get(context_key, []), requirement.get(requirement_key, []))
	if value_match.is_empty():
		missing.append(label + ": " + _join_names(requirement.get(requirement_key, [])))
	else:
		matched.append(label + ": " + value_match)


static func _check_min_stats(requirement, context, matched, missing):
	if not requirement.has("min_stats"):
		return
	var context_stats = context.get("stats", {})
	var stats = requirement.get("min_stats", {})
	for stat in stats.keys():
		var needed = int(stats[stat])
		var actual = int(context_stats.get(stat, 0))
		if actual < needed:
			missing.append("%s %d+" % [str(stat).capitalize(), needed])
		else:
			matched.append("%s %d" % [str(stat).capitalize(), actual])


static func _match_any(owned, required):
	var owned_strings = []
	for value in owned:
		owned_strings.append(str(value))
	for value in required:
		if owned_strings.has(str(value)):
			return str(value)
	return ""


static func _join_names(values):
	var parts = []
	for value in values:
		parts.append(str(value))
	return "/".join(PackedStringArray(parts))


static func _item_label(item_id, context):
	var item_names = context.get("item_names", {})
	return str(item_names.get(item_id, str(item_id).capitalize()))


static func _build_tags(context):
	var tags = []
	var location = str(context.get("location_label", ""))
	if not location.is_empty():
		tags.append(location)
	var time_label = str(context.get("time_label", ""))
	if not time_label.is_empty():
		tags.append(time_label)
	var occupations = context.get("occupations", [])
	if not occupations.is_empty():
		tags.append("Occupation: " + str(occupations[0]))
	var item_ids = context.get("item_ids", [])
	if item_ids.has("crowbar"):
		tags.append("Crowbar")
	if item_ids.has("multitool"):
		tags.append("Multitool")
	tags.append("Macro Event")
	return tags


static func _event_image_path(definition, context):
	var explicit = str(definition.get("image_path", ""))
	if ResourceLoader.exists(explicit):
		return explicit
	var fallback = str(context.get("background_path", ""))
	if ResourceLoader.exists(fallback):
		return fallback
	return ""
