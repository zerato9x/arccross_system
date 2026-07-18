extends RefCounted
class_name MacroEntityCollisionResolver

const MODE_ROOT := "collision_root"
const MODE_TALK := "talk"
const MODE_AMBUSH := "ambush"
const MODE_PEACEFUL := "peaceful"
const MODE_ASK := "ask"

const CHOICE_TALK := "talk"
const CHOICE_AMBUSH := "ambush"
const CHOICE_THREAT := "threat"
const CHOICE_CEASEFIRE := "ceasefire"
const CHOICE_BACK := "back"
const CHOICE_AMBUSH_FAR := "ambush_far"
const CHOICE_AMBUSH_STANDARD := "ambush_standard"
const CHOICE_AMBUSH_CLOSE := "ambush_close"
const CHOICE_ASK := "ask"
const CHOICE_TRADE := "trade"
const CHOICE_LEAVE := "leave"

const LANE_COUNT := 12
const ENEMY_AMBUSH_LANE := 7
const ORDINARY_PLAYER_LANE := 2
const ORDINARY_ENEMY_LANE := 9

const DEFAULT_IMAGE := (
	"res://Asset/UI/Event_bg/apocalyptic_bg/PNG/Postapocalypce1/"
	+ "Bright/ground&houses.png"
)

const SAMPLE_UNIQUE_DIALOGUE_ID := "sample_wasteland_broker"


static func build_root_session(enemy_record: EntityRecord) -> Dictionary:
	var opponent := build_opponent_summary(enemy_record)
	return _session(
		"entity_collision",
		"ENTITY COLLISION",
		_root_body(opponent),
		opponent.get("tags", []),
		[
			_choice(
				CHOICE_TALK,
				"TALK",
				"talk",
				"Attempt Threat or Ceasefire. Failure starts ordinary combat.",
				true,
				"Negotiate under pressure."
			),
			_choice(
				CHOICE_AMBUSH,
				"AMBUSH",
				"ambush",
				"Choose opening lane. You act first.",
				true,
				"Commit to a fight on your terms."
			),
		],
		MODE_ROOT,
		opponent,
		_grid_preview(ORDINARY_PLAYER_LANE, ORDINARY_ENEMY_LANE, "Ordinary meet"),
		false
	)


static func build_talk_session(enemy_record: EntityRecord) -> Dictionary:
	var opponent := build_opponent_summary(enemy_record)
	return _session(
		"entity_collision_talk",
		"TALK",
		(
			"THREAT forces a gear dump and flight if it lands. "
			+ "CEASEFIRE opens conversation and trade if they stand down. "
			+ "Failure starts ordinary-position combat."
		),
		opponent.get("tags", []),
		[
			_choice(
				CHOICE_THREAT,
				"THREAT",
				"threat",
				"Success: they drop gear (except clothes) and flee.",
				true,
				"Lean on threat and will."
			),
			_choice(
				CHOICE_CEASEFIRE,
				"CEASEFIRE",
				"ceasefire",
				"Success: unlock Ask and Trade without combat.",
				true,
				"Offer a pause under tension."
			),
			_choice(
				CHOICE_BACK,
				"BACK",
				"pass",
				"Return to the collision choices.",
				true,
				""
			),
		],
		MODE_TALK,
		opponent,
		_grid_preview(ORDINARY_PLAYER_LANE, ORDINARY_ENEMY_LANE, "If talks fail"),
		false
	)


static func build_ambush_session(enemy_record: EntityRecord) -> Dictionary:
	var opponent := build_opponent_summary(enemy_record)
	return _session(
		"entity_collision_ambush",
		"AMBUSH",
		(
			"Preview the combat grid, then pick approach distance. "
			+ "As the colliding entity, you act first.\n\n"
			+ _opponent_detail_block(opponent)
		),
		opponent.get("tags", []),
		[
			_choice(
				CHOICE_AMBUSH_FAR,
				"FAR APPROACH",
				"ambush",
				"Player lane 1 vs enemy lane 7.",
				true,
				"Maximum standoff."
			),
			_choice(
				CHOICE_AMBUSH_STANDARD,
				"STANDARD APPROACH",
				"ambush",
				"Player lane 3 vs enemy lane 7.",
				true,
				"Balanced opening."
			),
			_choice(
				CHOICE_AMBUSH_CLOSE,
				"CLOSE APPROACH",
				"ambush",
				"Player lane 4 vs enemy lane 7.",
				true,
				"Knife-range pressure."
			),
			_choice(
				CHOICE_BACK,
				"BACK",
				"pass",
				"Return to the collision choices.",
				true,
				""
			),
		],
		MODE_AMBUSH,
		opponent,
		_grid_preview(
			ambush_player_lane(GameEnums.AmbushPosition.STANDARD),
			ENEMY_AMBUSH_LANE,
			"Standard ambush"
		),
		false
	)


static func build_peaceful_session(enemy_record: EntityRecord) -> Dictionary:
	var opponent := build_opponent_summary(enemy_record)
	var allows_trade := bool(opponent.get("allows_trade", true))
	return _session(
		"entity_collision_peaceful",
		"CEASEFIRE",
		(
			"Weapons stay low. You can Ask questions, attempt Trade, or Leave. "
			+ "The encounter ends peacefully if you walk away."
		),
		opponent.get("tags", []),
		[
			_choice(
				CHOICE_ASK,
				"ASK",
				"talk",
				"Open a short conversation with choices.",
				true,
				"Learn what they will say aloud."
			),
			_choice(
				CHOICE_TRADE,
				"TRADE",
				"trade",
				(
					"Trade screen placeholder."
					if allows_trade
					else "This contact refuses to barter."
				),
				allows_trade,
				"Available." if allows_trade else "Refuses to barter."
			),
			_choice(
				CHOICE_LEAVE,
				"LEAVE",
				"pass",
				"End the encounter without combat.",
				true,
				"Both sides separate."
			),
		],
		MODE_PEACEFUL,
		opponent,
		{},
		true
	)


static func build_ask_session(enemy_record: EntityRecord) -> Dictionary:
	var opponent := build_opponent_summary(enemy_record)
	var dialogue_id := str(opponent.get("dialogue_id", ""))
	var profile := _ask_profile(dialogue_id)
	var choices: Array = []
	for entry in profile.get("choices", []):
		if entry is Dictionary:
			choices.append(
				_choice(
					str(entry.get("id", "")),
					str(entry.get("label", "Ask")),
					"talk",
					str(entry.get("preview", "")),
					true,
					str(entry.get("reason", "Available."))
				)
			)
	choices.append(
		_choice(
			CHOICE_BACK,
			"BACK",
			"pass",
			"Return to Ceasefire options.",
			true,
			""
		)
	)
	return _session(
		"entity_collision_ask",
		str(profile.get("title", "ASK")),
		str(profile.get("body", "They wait for a question.")),
		opponent.get("tags", []),
		choices,
		MODE_ASK,
		opponent,
		{},
		true
	)


static func resolve_ask_choice(
	enemy_record: EntityRecord,
	choice_id: String
) -> Dictionary:
	var opponent := build_opponent_summary(enemy_record)
	var dialogue_id := str(opponent.get("dialogue_id", ""))
	var profile := _ask_profile(dialogue_id)
	for entry in profile.get("choices", []):
		if not (entry is Dictionary):
			continue
		if str(entry.get("id", "")) != choice_id:
			continue
		return {
			"title": str(entry.get("result_title", "ANSWER")),
			"body": str(entry.get("result_body", "")),
			"effects": entry.get("effects", {}).duplicate(true),
			"resume": MODE_ASK,
		}
	return {
		"title": "NO ANSWER",
		"body": "They shrug and look elsewhere.",
		"effects": {},
		"resume": MODE_ASK,
	}


static func trade_placeholder_result() -> Dictionary:
	return {
		"title": "TRADE UNAVAILABLE",
		"body": (
			"A trade screen will open here once the item value system exists. "
			+ "For now, nothing changes hands."
		),
		"effects": {},
		"resume": MODE_PEACEFUL,
	}


static func build_opponent_summary(enemy_record: EntityRecord) -> Dictionary:
	var definition: Dictionary = {}
	if enemy_record != null:
		definition = enemy_record.definition
	var archetype := str(definition.get("archetype_name", "Unknown"))
	var dialogue_id := str(definition.get("dialogue_id", ""))
	var allows_trade := bool(definition.get("allows_trade", true))
	var faction_name := _enum_key(
		GameEnums.Faction.keys(),
		int(definition.get("faction", GameEnums.Faction.UNALIGNED))
	)
	var agenda_name := _enum_key(
		GameEnums.Agenda.keys(),
		int(definition.get("agenda", GameEnums.Agenda.SURVIVALIST))
	)
	var tactic_name := _enum_key(
		GameEnums.CombatTactic.keys(),
		int(definition.get("combat_tactic", GameEnums.CombatTactic.BRUTE))
	)
	var loadout: Dictionary = definition.get("loadout", {})
	var weapon_label := _loadout_item_label(loadout, "weapon")
	var armor_label := _loadout_item_label(loadout, "outer_torso")
	if armor_label.is_empty():
		armor_label = _loadout_item_label(loadout, "inner_torso")
	var tags: Array = [
		archetype,
		faction_name,
		agenda_name,
		"B%d F%d Fo%d W%d" % [
			int(definition.get("brawn", 6)),
			int(definition.get("finesse", 6)),
			int(definition.get("fortitude", 6)),
			int(definition.get("will", 6)),
		],
	]
	if not dialogue_id.is_empty():
		tags.append("UNIQUE")
	if not allows_trade:
		tags.append("NO TRADE")
	return {
		"name": archetype,
		"faction": faction_name,
		"agenda": agenda_name,
		"combat_tactic": tactic_name,
		"brawn": int(definition.get("brawn", 6)),
		"finesse": int(definition.get("finesse", 6)),
		"fortitude": int(definition.get("fortitude", 6)),
		"will": int(definition.get("will", 6)),
		"weapon": weapon_label,
		"armor": armor_label,
		"dialogue_id": dialogue_id,
		"allows_trade": allows_trade,
		"tags": tags,
	}


static func ambush_player_lane(position: GameEnums.AmbushPosition) -> int:
	match position:
		GameEnums.AmbushPosition.FAR:
			return 1
		GameEnums.AmbushPosition.CLOSE:
			return 4
		_:
			return 3


static func ambush_position_for_choice(choice_id: String) -> GameEnums.AmbushPosition:
	match choice_id:
		CHOICE_AMBUSH_FAR:
			return GameEnums.AmbushPosition.FAR
		CHOICE_AMBUSH_CLOSE:
			return GameEnums.AmbushPosition.CLOSE
		_:
			return GameEnums.AmbushPosition.STANDARD


static func _session(
	id: String,
	title: String,
	body: String,
	tags: Array,
	choices: Array,
	mode: String,
	opponent: Dictionary,
	grid_preview: Dictionary,
	can_close: bool
) -> Dictionary:
	return {
		"id": id,
		"title": title,
		"body": body,
		"image_path": DEFAULT_IMAGE,
		"tags": tags.duplicate(),
		"choices": choices,
		"can_close": can_close,
		"mode": mode,
		"opponent": opponent.duplicate(true),
		"grid_preview": grid_preview.duplicate(true),
	}


static func _choice(
	id: String,
	label: String,
	kind: String,
	preview: String,
	enabled: bool,
	reason: String
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"kind": kind,
		"preview": preview,
		"enabled": enabled,
		"reason": reason,
		"stakes": [],
	}


static func _grid_preview(
	player_lane: int,
	enemy_lane: int,
	caption: String
) -> Dictionary:
	return {
		"lane_count": LANE_COUNT,
		"player_lane": player_lane,
		"enemy_lane": enemy_lane,
		"caption": caption,
	}


static func _root_body(opponent: Dictionary) -> String:
	return (
		"You collide with %s.\n\n%s\n\n"
		+ "Talk to negotiate, or Ambush to fight with a chosen approach."
	) % [str(opponent.get("name", "Unknown")), _opponent_detail_block(opponent)]


static func _opponent_detail_block(opponent: Dictionary) -> String:
	var lines: PackedStringArray = [
		"Faction: %s" % str(opponent.get("faction", "UNALIGNED")),
		"Agenda: %s" % str(opponent.get("agenda", "SURVIVALIST")),
		"Tactic: %s" % str(opponent.get("combat_tactic", "BRUTE")),
		"Pillars: B%d / F%d / Fo%d / W%d" % [
			int(opponent.get("brawn", 6)),
			int(opponent.get("finesse", 6)),
			int(opponent.get("fortitude", 6)),
			int(opponent.get("will", 6)),
		],
	]
	var weapon := str(opponent.get("weapon", ""))
	var armor := str(opponent.get("armor", ""))
	if not weapon.is_empty():
		lines.append("Weapon: %s" % weapon)
	if not armor.is_empty():
		lines.append("Armor: %s" % armor)
	return "\n".join(lines)


static func _loadout_item_label(loadout: Dictionary, key: String) -> String:
	var path := str(loadout.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return ""
	var item := load(path) as ItemData
	if item == null:
		return ""
	return item.display_name


static func _enum_key(keys: Array, value: int) -> String:
	if value < 0 or value >= keys.size():
		return "UNKNOWN"
	return str(keys[value])


static func _ask_profile(dialogue_id: String) -> Dictionary:
	if dialogue_id == SAMPLE_UNIQUE_DIALOGUE_ID:
		return _unique_sample_broker()
	return _generic_ask()


static func _generic_ask() -> Dictionary:
	return {
		"title": "ASK",
		"body": "They keep a wary distance, but they will answer a few words.",
		"choices": [
			{
				"id": "ask_intent",
				"label": "Ask what they want",
				"preview": "Probe their immediate agenda.",
				"reason": "Available.",
				"result_title": "INTENT",
				"result_body": (
					"They mutter about scavenging the next ridge and staying "
					+ "alive long enough to spend whatever they find."
				),
				"effects": {"elapsed_minutes": 2, "exertion": 0.1},
			},
			{
				"id": "ask_area",
				"label": "Ask about the area",
				"preview": "Local rumors, hazards, traffic.",
				"reason": "Available.",
				"result_title": "THE AREA",
				"result_body": (
					"They point toward denser wreckage and warn that anything "
					+ "quiet out here is either bait or already dead."
				),
				"effects": {"elapsed_minutes": 3, "exertion": 0.1},
			},
			{
				"id": "ask_leave",
				"label": "Ask them to leave",
				"preview": "Request a clean separation.",
				"reason": "Available.",
				"result_title": "SPACE",
				"result_body": (
					"They nod once. Not friendship — just enough space to keep "
					+ "both of you breathing."
				),
				"effects": {"elapsed_minutes": 1, "exertion": 0.05},
			},
			{
				"id": "ask_weakness",
				"label": "Probe for a weakness",
				"preview": "Look for openings in gear or posture.",
				"reason": "Available.",
				"result_title": "TELL",
				"result_body": (
					"Their stance favors the right side. The kit is patched, "
					+ "not pristine — pressure there would hurt."
				),
				"effects": {"elapsed_minutes": 2, "exertion": 0.15},
			},
		],
	}


static func _unique_sample_broker() -> Dictionary:
	return {
		"title": "ASK // BROKER",
		"body": (
			"This one talks like someone who prices danger for a living. "
			+ "Their answers are sharper than a scavenger's shrug."
		),
		"choices": [
			{
				"id": "ask_broker_routes",
				"label": "Ask about safe routes",
				"preview": "Unique contact: route intelligence.",
				"reason": "Available.",
				"result_title": "ROUTES",
				"result_body": (
					"They sketch three ruined corridors and mark one as "
					+ "'expensive but quiet.' The other two are for people "
					+ "who enjoy dying with company."
				),
				"effects": {"elapsed_minutes": 4, "exertion": 0.1},
			},
			{
				"id": "ask_broker_prices",
				"label": "Ask what people pay for",
				"preview": "Unique contact: market gossip.",
				"reason": "Available.",
				"result_title": "MARKET",
				"result_body": (
					"Meds, batteries, and anything that still seals against "
					+ "dust. They refuse to name buyers. Professionals never do."
				),
				"effects": {"elapsed_minutes": 3, "exertion": 0.1},
			},
			{
				"id": "ask_broker_debt",
				"label": "Ask who they owe",
				"preview": "Unique contact: leverage.",
				"reason": "Available.",
				"result_title": "DEBTS",
				"result_body": (
					"A thin smile. 'Everyone owes someone. Today that someone "
					+ "is not you.' Useful, and deliberately incomplete."
				),
				"effects": {"elapsed_minutes": 2, "exertion": 0.2},
			},
		],
	}
