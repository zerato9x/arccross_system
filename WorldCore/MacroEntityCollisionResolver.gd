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

const ARENA_SIZE := Vector2i(7, 5)
const ENEMY_AMBUSH_SECTOR := Vector2i(6, 2)
const ORDINARY_PLAYER_SECTOR := Vector2i(0, 2)
const ORDINARY_ENEMY_SECTOR := Vector2i(6, 2)

const DEFAULT_IMAGE := EventBgCatalog.PLAINS_BG

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
				"Choose an opening sector. You act first.",
				true,
				"Commit to a fight on your terms."
			),
		],
		MODE_ROOT,
		opponent,
		_grid_preview(ORDINARY_PLAYER_SECTOR, ORDINARY_ENEMY_SECTOR, "Ordinary meet"),
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
		_grid_preview(ORDINARY_PLAYER_SECTOR, ORDINARY_ENEMY_SECTOR, "If talks fail"),
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
				"Player sector (0,2) vs enemy sector (6,2).",
				true,
				"Maximum standoff."
			),
			_choice(
				CHOICE_AMBUSH_STANDARD,
				"STANDARD APPROACH",
				"ambush",
				"Player sector (3,2) vs enemy sector (6,2).",
				true,
				"Balanced opening."
			),
			_choice(
				CHOICE_AMBUSH_CLOSE,
				"CLOSE APPROACH",
				"ambush",
				"Player sector (4,2) vs enemy sector (6,2).",
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
			ambush_player_sector(GameEnums.AmbushPosition.STANDARD),
			ENEMY_AMBUSH_SECTOR,
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
	## Kept for smoke compatibility name; resolves to the structured empty-trade result.
	return {
		"title": "NO DEAL",
		"body": "Neither side has anything worth exchanging right now.",
		"effects": {},
		"resume": MODE_PEACEFUL,
	}


## Auto-barter one backpack offer for one enemy pack item using barter value.
## Returns a result dictionary plus optional mutation payloads for MacroGameManager.
static func resolve_trade(
	player_core: HumanoidCore,
	enemy_record: EntityRecord,
	loot_catalog: Node
) -> Dictionary:
	if player_core == null or enemy_record == null or loot_catalog == null:
		return trade_placeholder_result()
	if not bool(enemy_record.definition.get("allows_trade", true)):
		return {
			"title": "NO DEAL",
			"body": "They refuse to barter.",
			"effects": {},
			"resume": MODE_PEACEFUL,
		}

	var offer := _pick_player_trade_offer(player_core)
	if offer == null:
		return {
			"title": "NO DEAL",
			"body": "You have nothing portable to offer from your pack.",
			"effects": {},
			"resume": MODE_PEACEFUL,
		}

	var loadout: Dictionary = enemy_record.definition.get("loadout", {}).duplicate(true)
	var starting_items: Array = loadout.get("starting_items", []).duplicate()
	var trade_index := -1
	var trade_path := ""
	for index in range(starting_items.size()):
		var path := str(starting_items[index])
		if path.is_empty():
			continue
		trade_index = index
		trade_path = path
		break
	if trade_index < 0 or trade_path.is_empty():
		return {
			"title": "NO DEAL",
			"body": "Their pack is empty. Nothing changes hands.",
			"effects": {},
			"resume": MODE_PEACEFUL,
		}

	var received_state: Dictionary = loot_catalog.create_runtime_item_from_template_path(
		trade_path
	)
	if received_state.is_empty():
		return {
			"title": "NO DEAL",
			"body": "The offered goods fall apart before the swap completes.",
			"effects": {},
			"resume": MODE_PEACEFUL,
		}
	var received := ItemData.from_runtime_state(received_state)
	var offer_value := offer.get_barter_value()
	var received_value := received.get_barter_value()
	if received_value > offer_value * 1.75:
		return {
			"title": "NO DEAL",
			"body": (
				"They eye your %s and shake their head. "
				+ "Your offer is too thin for what they carry."
			) % offer.display_name,
			"effects": {},
			"resume": MODE_PEACEFUL,
		}

	starting_items.remove_at(trade_index)
	var offer_template := offer.template_path
	if not offer_template.is_empty():
		starting_items.append(offer_template)
	loadout["starting_items"] = starting_items

	return {
		"title": "TRADE COMPLETE",
		"body": (
			"You hand over %s and take %s."
			% [offer.display_name, received.display_name]
		),
		"effects": {},
		"resume": MODE_PEACEFUL,
		"remove_player_instance_id": offer.instance_id,
		"received_item_state": received_state,
		"kept_loadout": loadout,
	}


static func _pick_player_trade_offer(player_core: HumanoidCore) -> ItemData:
	var best: ItemData = null
	var best_value := INF
	for item in player_core.inventory.backpack_array:
		if item == null:
			continue
		if item.item_type == GameEnums.ItemType.WEAPON:
			continue
		if str(item.id).begins_with("tent") or item.item_type == GameEnums.ItemType.ARMOR:
			continue
		var value := item.get_barter_value()
		if value < best_value:
			best_value = value
			best = item
	return best


static func build_opponent_summary(enemy_record: EntityRecord) -> Dictionary:
	var definition: Dictionary = {}
	if enemy_record != null:
		definition = enemy_record.definition
	var archetype := str(definition.get("archetype_name", "Unknown"))
	var dialogue_id := str(definition.get("dialogue_id", ""))
	var allows_trade := bool(definition.get("allows_trade", true))
	var blocks_ambush := bool(definition.get("blocks_ambush", false))
	var blocks_central_reentry := bool(
		definition.get("blocks_central_reentry", false)
	)
	var template_id := str(definition.get("template_id", ""))
	if template_id.is_empty() and enemy_record != null:
		template_id = str(enemy_record.runtime.get("template_id", ""))
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
	var npc_role_id := ""
	var npc_goal_id := ""
	if enemy_record != null:
		npc_role_id = str(enemy_record.runtime.get(
			"npc_role_id", definition.get("npc_role_id", "")
		))
		var macro_ai: Dictionary = enemy_record.runtime.get("macro_ai", {})
		npc_goal_id = str(macro_ai.get("goal_id", ""))
	if not npc_role_id.is_empty():
		tags.append("ROLE: " + npc_role_id.to_upper())
	if not npc_goal_id.is_empty():
		tags.append("GOAL: " + npc_goal_id.to_upper())
	if not dialogue_id.is_empty():
		tags.append("UNIQUE")
	if not allows_trade:
		tags.append("NO TRADE")
	if blocks_ambush:
		tags.append("NO AMBUSH")
	if blocks_central_reentry:
		tags.append("CENTRAL LOCK")
	var record_dict := {}
	if enemy_record != null:
		record_dict = enemy_record.to_dict()
	var equipment: Array = PaperDollPresenter.equipment_from_entity_record(enemy_record)
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
		"blocks_ambush": blocks_ambush,
		"blocks_central_reentry": blocks_central_reentry,
		"template_id": template_id,
		"npc_role_id": npc_role_id,
		"npc_goal_id": npc_goal_id,
		"tags": tags,
		"entity_id": str(record_dict.get("entity_id", "")),
		"world_status": int(record_dict.get("world_status", GameEnums.EntityWorldStatus.HOSTILE)),
		"equipment": equipment,
		"appearance": HumanoidVisualCatalog.appearance_from_record(record_dict),
		"record": record_dict,
	}


static func ambush_denied_result(enemy_record: EntityRecord = null) -> Dictionary:
	var line := ambush_denied_line(enemy_record)
	return {
		"title": "AMBUSH DENIED",
		"body": line,
		"effects": {},
		"resume": MODE_ROOT,
	}


static func ambush_denied_line(enemy_record: EntityRecord = null) -> String:
	var lines: Array[String] = [
		"Ambush a posted pair in service kit? File denied. Stamp optional.",
		"They already see you. The form for 'surprise' is out of stock.",
		"Two rifles, one idea: you first. Application rejected.",
		"Central edge security does not do 'sneaky.' Try paperwork.",
		"You want the drop on people whose whole job is watching the drop. Cute.",
	]
	var seed_key := "ambush_deny"
	if enemy_record != null:
		seed_key = enemy_record.entity_id
	var index := absi(seed_key.hash()) % lines.size()
	return lines[index]


static func central_reentry_refused_line() -> String:
	return (
		"Central Core stays sealed. The posted pair on the rim already filed "
		+ "your eviction; walking back through them is not a travel option."
	)


static func ambush_player_sector(position: GameEnums.AmbushPosition) -> Vector2i:
	match position:
		GameEnums.AmbushPosition.FAR:
			return Vector2i(0, 2)
		GameEnums.AmbushPosition.CLOSE:
			return Vector2i(4, 2)
		_:
			return Vector2i(3, 2)


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
		"place_presence": true,
		"walk_in": mode == MODE_ROOT,
		"meet_label": "You and %s share this ground." % str(
			opponent.get("name", "a stranger")
		),
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
	player_sector: Vector2i,
	enemy_sector: Vector2i,
	caption: String
) -> Dictionary:
	return {
		"width": ARENA_SIZE.x,
		"height": ARENA_SIZE.y,
		"player_sector": player_sector,
		"enemy_sector": enemy_sector,
		"caption": caption,
	}


static func _root_body(opponent: Dictionary) -> String:
	return (
		"You step into the open and meet %s on this ground.\n\n%s\n\n"
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
	var catalog := DialogueCatalog.data()
	if catalog != null:
		var authored := catalog.resolve(dialogue_id if not dialogue_id.is_empty() else "generic")
		if not authored.is_empty():
			return authored
	if dialogue_id == SAMPLE_UNIQUE_DIALOGUE_ID:
		return _unique_sample_broker()
	if dialogue_id == "central_guard":
		return _central_guard_ask()
	if dialogue_id.begins_with("starter_wayfinder:"):
		return _starter_wayfinder_ask(dialogue_id.trim_prefix("starter_wayfinder:"))
	return _generic_ask()


static func _starter_wayfinder_ask(arm_id: String) -> Dictionary:
	var arm_label := arm_id.capitalize()
	return {
		"title": "ASK // %s WAYFINDER" % arm_label.to_upper(),
		"body": (
			"A fringe resident keeps watch beside the homesteads. They know which "
			+ "tracks still carry people, and which only carry trouble."
		),
		"choices": [
			{
				"id": "ask_wayfinder_route",
				"label": "Ask about the road ahead",
				"preview": "Get a direction beyond the settlement.",
				"reason": "Available.",
				"result_title": "%s ROUTE" % arm_label.to_upper(),
				"result_body": (
					"'Take the marked trail away from Central. The old route marker still "
					+ "points toward %s Route 2. Check it before you commit.'" % arm_label
				),
				"effects": {"elapsed_minutes": 2, "exertion": 0.05},
			},
			{
				"id": "ask_wayfinder_ring",
				"label": "Ask about the inner ring",
				"preview": "Learn how the four old approaches connect.",
				"reason": "Available.",
				"result_title": "FRINGE RING",
				"result_body": (
					"'Four old approaches still ring Central's lock, but this is the only "
					+ "settled camp. The paved bones remain even where nobody stayed.'"
				),
				"effects": {"elapsed_minutes": 2, "exertion": 0.05},
			},
		],
	}


static func _central_guard_ask() -> Dictionary:
	return {
		"title": "ASK // CENTRAL GUARD",
		"body": (
			"Service kit. Posted pair. They talk like quota clerks who were "
			+ "handed rifles and told the edge is the job."
		),
		"choices": [
			{
				"id": "ask_guard_central",
				"label": "Ask about returning to Central",
				"preview": "Probe the lock.",
				"reason": "Available.",
				"result_title": "CLOSED",
				"result_body": (
					"'Eviction stands.' One taps the helmet like a stamp. "
					+ "'Central Core is not accepting walk-backs. Not today.'"
				),
				"effects": {"elapsed_minutes": 2, "exertion": 0.1},
			},
			{
				"id": "ask_guard_orders",
				"label": "Ask who posted them",
				"preview": "Bureaucracy, not destiny.",
				"reason": "Available.",
				"result_title": "ORDERS",
				"result_body": (
					"'Logistics desk.' No names. No heroes. Just a rim shift "
					+ "and enough rounds to make the paperwork stick."
				),
				"effects": {"elapsed_minutes": 2, "exertion": 0.1},
			},
			{
				"id": "ask_guard_leave",
				"label": "Ask them to stand aside",
				"preview": "Request passage.",
				"reason": "Available.",
				"result_title": "DENIED",
				"result_body": (
					"They do not move. 'File a complaint with Central. "
					+ "Oh wait — you can't.'"
				),
				"effects": {"elapsed_minutes": 1, "exertion": 0.05},
			},
		],
	}


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
					"Their guard favors the right side. The kit is patched, "
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
