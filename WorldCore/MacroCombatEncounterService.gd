extends RefCounted
class_name MacroCombatEncounterService

## Builds the neutral macro-to-tactical encounter handoff. The participant
## roster is assembled once here; TacticalCombatScene never discovers late
## reinforcements from the macro world.

const ASSEMBLY_PROFILE := preload("res://SystemCore/default_combat_encounter_assembly_profile.tres")
const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var map_visualizer: HexMapVisualizer


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	visualizer: HexMapVisualizer
) -> void:
	world_state = state
	world_generator = generator
	map_visualizer = visualizer


func build(request: Dictionary) -> CombatEncounterRecord:
	if world_state == null or world_generator == null:
		return null
	var coords: Vector2i = request.get("coords", Vector2i.ZERO)
	if not world_generator.is_in_zone_bounds(coords):
		return null
	var center := world_generator.get_hex_at(coords)
	if center == null:
		return null
	var encounter := CombatEncounterRecord.new()
	encounter.encounter_id = "%s:%s:%d" % [str(world_state.world_seed), str(coords), int(world_state.world_time_minutes)]
	encounter.source_coords = coords
	encounter.approach_from = request.get("approach_from", coords)
	encounter.initiator_id = str(request.get("initiator_id", "player"))
	encounter.context = int(request.get("context", GameEnums.EncounterContext.NEUTRAL_MEET))
	encounter.ambush_position = int(request.get("ambush_position", GameEnums.AmbushPosition.STANDARD))
	encounter.world_seed = str(world_state.world_seed)
	encounter.world_time = world_state.get_world_time_snapshot()
	encounter.center_hex = center.to_state()
	for direction in HexCoordUtils.AXIAL_DIRECTIONS:
		var neighbor_coords: Vector2i = coords + direction
		var neighbor_record: HexRecord = null
		if world_generator.is_in_zone_bounds(neighbor_coords):
			neighbor_record = world_generator.get_hex_at(neighbor_coords).to_state()
		encounter.neighbor_hexes.append(neighbor_record)
	var combat_topology := CombatTopologyCatalog.load_profile(encounter.topology_id)
	for trap in center.camp_traps:
		if not trap is Dictionary:
			continue
		var trap_record: Dictionary = trap.duplicate(true)
		trap_record["id"] = str(trap.get("item_id", "trap_makeshift"))
		trap_record["instance_id"] = str(trap.get("instance_id", ""))
		trap_record["armed"] = true
		trap_record["damage"] = float(trap.get("trap_damage", 2.5))
		trap_record["owner_side"] = "player"
		trap_record["sector"] = Vector2i(clampi(int(trap.get("sector_x", 1)), 0, combat_topology.columns - 1), clampi(int(trap.get("sector_y", 0)), 0, combat_topology.rows - 1))
		encounter.traps.append(trap_record)
	var encounter_ground_items: Array[Dictionary] = []
	for ground_item in world_state.get_ground_items(coords):
		if ground_item is Dictionary:
			encounter_ground_items.append(ground_item.duplicate(true))
	encounter.ground_items = encounter_ground_items
	var decorations: Array = []
	if world_generator.has_method("get_decorations_at"):
		decorations = world_generator.get_decorations_at(coords)
	var catalog: MacroTileCatalog = map_visualizer.tile_catalog if map_visualizer else null
	encounter.presentation = HexPresentationDescriptor.build(center, catalog, decorations, encounter.world_seed, coords, {}, encounter.ground_items)
	_assemble_participants(encounter, request)
	return encounter


func _assemble_participants(encounter: CombatEncounterRecord, request: Dictionary) -> void:
	var profile: CombatEncounterAssemblyProfile = ASSEMBLY_PROFILE
	encounter.assembly_radius = profile.axial_radius
	encounter.participant_cap = profile.participant_cap
	encounter.late_reinforcements_enabled = profile.late_reinforcements_enabled
	var primary_id := str(request.get("enemy_id", ""))
	var initiator_id := encounter.initiator_id
	var candidates: Array[Dictionary] = []
	var receipt_candidates: Array[Dictionary] = []
	var primary := world_state.get_entity(primary_id)
	var primary_squad := str(primary.runtime.get("squad_id", "")) if primary != null else ""
	var player_record: EntityRecord = world_state.player_record
	if player_record != null:
		candidates.append(_candidate_for_player(player_record, encounter, primary_id, initiator_id))
	else:
		candidates.append({
			"entity_id": "player",
			"record": null,
			"origin_coords": world_state.player_coords,
			"distance": 0,
			"priority": 10000,
			"awareness": 1.0,
			"reason": "always_player",
			"direct": true,
		})
	for raw_record in world_state.get_all_entity_records():
		var record := raw_record as EntityRecord
		if record == null or record.entity_id == "player" or record.life_state != GameEnums.EntityLifeState.ALIVE:
			continue
		var distance := HexCoordUtils.distance(encounter.source_coords, record.coords)
		var is_primary := record.entity_id == primary_id
		var is_initiator := record.entity_id == initiator_id
		var runtime: Dictionary = record.runtime
		var awareness := _awareness_strength(record, encounter, primary_id, is_primary)
		var direct_threat := _is_direct_threat(record, primary_id, initiator_id)
		var committed := _is_committed(record, primary_id, initiator_id)
		var same_squad_aware := not primary_squad.is_empty() and str(runtime.get("squad_id", "")) == primary_squad and awareness >= profile.aware_same_squad_threshold
		var direct := is_primary or is_initiator or direct_threat or committed
		var eligible := direct or same_squad_aware
		var reason := ""
		if is_primary:
			reason = "initiator_contact"
		elif is_initiator:
			reason = "always_initiator"
		elif direct_threat:
			reason = "direct_threat"
		elif committed:
			reason = "committed_ally"
		elif same_squad_aware:
			reason = "aware_same_squad"
		elif distance > profile.axial_radius:
			reason = "outside_radius"
		elif record.world_status != GameEnums.EntityWorldStatus.HOSTILE:
			reason = "neutral_not_directly_involved"
		else:
			reason = "not_aware_or_committed"
		var priority := _inclusion_priority(is_primary, is_initiator, direct_threat, committed, same_squad_aware, distance)
		var candidate := {
			"entity_id": record.entity_id,
			"record": record,
			"origin_coords": record.coords,
			"distance": distance,
			"priority": priority,
			"awareness": awareness,
			"reason": reason,
			"direct": direct,
			"eligible": eligible and (distance <= profile.axial_radius or direct),
			"direct_threat": direct_threat,
			"committed": committed,
		}
		candidates.append(candidate)
	# Player and all candidates are sorted by the authored deterministic policy.
	candidates.sort_custom(func(left, right): return _candidate_before(left, right))
	var selected_ids: Dictionary = {}
	var selected: Array[Dictionary] = []
	for candidate in candidates:
		var id := str(candidate.get("entity_id", ""))
		var mandatory := id == "player" or id == initiator_id or id == primary_id
		if not mandatory and not bool(candidate.get("eligible", false)):
			continue
		if selected_ids.has(id):
			continue
		if selected.size() >= profile.participant_cap:
			break
		selected_ids[id] = true
		selected.append(candidate)
	for candidate in candidates:
		var id := str(candidate.get("entity_id", ""))
		var included := selected_ids.has(id)
		receipt_candidates.append({
			"actor_id": id,
			"origin_coords": candidate.get("origin_coords", Vector2i.ZERO),
			"distance": int(candidate.get("distance", 999)),
			"awareness_strength": float(candidate.get("awareness", 0.0)),
			"eligible": bool(candidate.get("eligible", false)),
			"included": included,
			"reason": str(candidate.get("reason", "")) if included else ("cap_exceeded" if bool(candidate.get("eligible", false)) else str(candidate.get("reason", ""))),
		})
	var ledger := _RelationshipLedger.from_dict(encounter.relationship_state)
	for candidate in selected:
		var actor_id := str(candidate.get("entity_id", ""))
		if actor_id == "player":
			continue
		var record := candidate.get("record") as EntityRecord
		if record == null:
			continue
		var context := _participant_context(record, encounter, candidate, primary_id, initiator_id, profile)
		var entry := _actor_entry(record, context)
		encounter.actors.append(entry)
		_reserve_record(record, context, encounter.encounter_id)
		encounter.actor_starting_sectors[actor_id] = context.get("starting_sector", Vector2i(-1, -1))
		encounter.relationship_state = ledger.to_dict()
	# Player is always first in the handoff, using the neutral runtime record
	# already owned by RuntimeStateStore. GameDirector may refresh its runtime
	# projection immediately before fabrication.
	var player_candidate: Dictionary = {}
	for candidate in selected:
		if str(candidate.get("entity_id", "")) == "player":
			player_candidate = candidate
			break
	var player_context := _player_context(player_candidate, encounter, profile)
	_set_participant_relations(ledger, selected, primary_id)
	encounter.relationship_state = ledger.to_dict()
	var player_entry := {
		"actor_id": "player",
		"team_id": "player",
		"direct_player": true,
		"combat_side": "player",
		"runtime_record": player_record.to_dict() if player_record != null else {"entity_id": "player", "runtime": {}},
		"participant_context": player_context,
	}
	encounter.actors.push_front(player_entry)
	encounter.assembly_receipt = {
		"profile_id": profile.profile_id,
		"center_coords": encounter.source_coords,
		"radius": profile.axial_radius,
		"participant_cap": profile.participant_cap,
		"late_reinforcements_enabled": profile.late_reinforcements_enabled,
		"initiator_id": initiator_id,
		"primary_contact_id": primary_id,
		"included_actor_ids": encounter.actors.map(func(value: Dictionary) -> String: return str(value.get("actor_id", ""))),
		"candidates": receipt_candidates,
	}


func _set_participant_relations(ledger: CombatRelationshipLedger, selected: Array[Dictionary], primary_id: String) -> void:
	var ids: Array[String] = []
	for candidate in selected:
		var id := str(candidate.get("entity_id", ""))
		if not id.is_empty():
			ids.append(id)
	ids.sort()
	for left_index in range(ids.size()):
		for right_index in range(left_index + 1, ids.size()):
			var left_id := ids[left_index]
			var right_id := ids[right_index]
			var key := _RelationshipLedger.pair_key(left_id, right_id)
			if ledger.relation_by_pair.has(key):
				continue
			var left_candidate := _candidate_by_id(selected, left_id)
			var right_candidate := _candidate_by_id(selected, right_id)
			var relation := _explicit_relation(left_candidate, right_id)
			if relation < 0:
				relation = _explicit_relation(right_candidate, left_id)
			if relation < 0:
				if left_id == "player" or right_id == "player":
					var other_id := right_id if left_id == "player" else left_id
					var other := right_candidate if left_id == "player" else left_candidate
					relation = _RelationshipLedger.Relation.HOSTILE if other_id == primary_id or bool(other.get("direct_threat", false)) else _RelationshipLedger.Relation.NEUTRAL
				elif _same_squad(left_candidate, right_candidate):
					relation = _RelationshipLedger.Relation.FRIENDLY
				else:
					relation = _RelationshipLedger.Relation.NEUTRAL
			ledger.set_relation(left_id, right_id, relation)


func _candidate_by_id(candidates: Array[Dictionary], actor_id: String) -> Dictionary:
	for candidate in candidates:
		if str(candidate.get("entity_id", "")) == actor_id:
			return candidate
	return {}


func _same_squad(left: Dictionary, right: Dictionary) -> bool:
	var left_record := left.get("record") as EntityRecord
	var right_record := right.get("record") as EntityRecord
	if left_record == null or right_record == null:
		return false
	var left_squad := str(left_record.runtime.get("squad_id", ""))
	var right_squad := str(right_record.runtime.get("squad_id", ""))
	return not left_squad.is_empty() and left_squad == right_squad


func _explicit_relation(candidate: Dictionary, other_id: String) -> int:
	var record := candidate.get("record") as EntityRecord
	if record == null:
		return -1
	var runtime := record.runtime
	var relation_map: Dictionary = runtime.get("relationships", {})
	var raw: Variant = relation_map.get(other_id, relation_map.get(_RelationshipLedger.pair_key(str(candidate.get("entity_id", "")), other_id), null))
	if raw == null:
		raw = runtime.get("relationship_to_player", null) if other_id == "player" else null
	if raw == null:
		return -1
	if raw is String:
		return {"friendly": _RelationshipLedger.Relation.FRIENDLY, "neutral": _RelationshipLedger.Relation.NEUTRAL, "hostile": _RelationshipLedger.Relation.HOSTILE}.get(str(raw).to_lower(), -1)
	return clampi(int(raw), _RelationshipLedger.Relation.FRIENDLY, _RelationshipLedger.Relation.HOSTILE)


func _candidate_for_player(record: EntityRecord, encounter: CombatEncounterRecord, primary_id: String, initiator_id: String) -> Dictionary:
	return {
		"entity_id": "player",
		"record": record,
		"origin_coords": record.coords,
		"distance": HexCoordUtils.distance(encounter.source_coords, record.coords),
		"priority": 10000,
		"awareness": 1.0,
		"reason": "always_player",
		"direct": true,
		"eligible": true,
	}


func _awareness_strength(record: EntityRecord, encounter: CombatEncounterRecord, primary_id: String, is_primary: bool) -> float:
	if is_primary:
		return 1.0
	var runtime := record.runtime
	var authored: Variant = runtime.get("awareness_strength", runtime.get("awareness", record.knowledge.get("awareness_strength", 0.0)))
	if authored is bool:
		return 1.0 if authored else 0.0
	return clampf(float(authored), 0.0, 1.0)


func _is_direct_threat(record: EntityRecord, primary_id: String, initiator_id: String) -> bool:
	var runtime := record.runtime
	if bool(runtime.get("direct_threat", false)) or bool(runtime.get("threatened_player", false)) or bool(runtime.get("directly_threatened", false)):
		return true
	for key in ["threat_target_id", "committed_subject_id", "target_id"]:
		if str(runtime.get(key, "")) in ["player", initiator_id]:
			return true
	var ids: Array = runtime.get("threatened_subject_ids", [])
	return "player" in ids or initiator_id in ids


func _is_committed(record: EntityRecord, primary_id: String, initiator_id: String) -> bool:
	var runtime := record.runtime
	if bool(runtime.get("committed_to_contact", false)) or bool(runtime.get("committed", false)):
		return true
	return str(runtime.get("commitment_subject_id", "")) in ["player", primary_id, initiator_id]


func _inclusion_priority(primary: bool, initiator: bool, direct_threat: bool, committed: bool, same_squad: bool, distance: int) -> int:
	if primary:
		return 9000
	if initiator:
		return 9500
	if direct_threat:
		return 8000
	if committed:
		return 7000
	if same_squad:
		return 6000
	return 1000 - distance


func _candidate_before(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", 0))
	var right_priority := int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	var left_distance := int(left.get("distance", 999))
	var right_distance := int(right.get("distance", 999))
	if left_distance != right_distance:
		return left_distance < right_distance
	var left_awareness := float(left.get("awareness", 0.0))
	var right_awareness := float(right.get("awareness", 0.0))
	if not is_equal_approx(left_awareness, right_awareness):
		return left_awareness > right_awareness
	return str(left.get("entity_id", "")) < str(right.get("entity_id", ""))


func _participant_context(record: EntityRecord, encounter: CombatEncounterRecord, candidate: Dictionary, primary_id: String, initiator_id: String, profile: CombatEncounterAssemblyProfile) -> Dictionary:
	var delta := record.coords - encounter.source_coords
	var direction := HexCoordUtils.travel_direction_for_coords(delta)
	if direction == GameEnums.MacroTravelDirection.NONE:
		direction = HexCoordUtils.travel_direction_for_step(encounter.source_coords - encounter.approach_from)
	var runtime := record.runtime.duplicate(true)
	return {
		"macro_origin_coords": record.coords,
		"origin_coords": record.coords,
		"relative_entry_direction": int(direction),
		"entry_direction": int(direction),
		"starting_sector": Vector2i(-1, -1),
		"inclusion_reason": str(candidate.get("reason", "")),
		"awareness_strength": float(candidate.get("awareness", 0.0)),
		"macro_goal": str(runtime.get("macro_goal", runtime.get("macro_purpose", ""))),
		"squad_id": str(runtime.get("squad_id", "")),
		"faction_id": int(record.definition.get("faction", GameEnums.Faction.UNALIGNED)),
		"behavior_state": runtime.get("npc_behavior", {}).duplicate(true),
		"return_policy": str(runtime.get("return_policy", profile.default_return_policy)),
		"escape_direction": int(runtime.get("escape_direction", direction)),
		"primary_contact": record.entity_id == primary_id,
		"initiator": record.entity_id == initiator_id,
	}


func _player_context(candidate: Dictionary, encounter: CombatEncounterRecord, profile: CombatEncounterAssemblyProfile) -> Dictionary:
	var origin: Vector2i = candidate.get("origin_coords", world_state.player_coords)
	var direction := HexCoordUtils.travel_direction_for_coords(origin - encounter.source_coords)
	return {
		"macro_origin_coords": origin,
		"origin_coords": origin,
		"relative_entry_direction": int(direction),
		"entry_direction": int(direction),
		"starting_sector": Vector2i(-1, -1),
		"inclusion_reason": "always_player",
		"awareness_strength": 1.0,
		"return_policy": profile.default_return_policy,
		"escape_direction": int(direction),
	}


func _actor_entry(record: EntityRecord, context: Dictionary) -> Dictionary:
	var runtime := record.runtime
	var squad_id := str(runtime.get("squad_id", ""))
	var actor := {
		"actor_id": record.entity_id,
		"team_id": squad_id if not squad_id.is_empty() else "npc",
		"combat_side": "enemy",
		"runtime_record": record.to_dict(),
		"participant_context": context.duplicate(true),
		"macro_origin_coords": context.get("macro_origin_coords", record.coords),
		"relative_entry_direction": context.get("relative_entry_direction", GameEnums.MacroTravelDirection.NONE),
		"inclusion_reason": context.get("inclusion_reason", ""),
		"awareness_strength": context.get("awareness_strength", 0.0),
		"squad_id": squad_id,
		"macro_goal": context.get("macro_goal", ""),
		"faction_id": context.get("faction_id", GameEnums.Faction.UNALIGNED),
		"return_policy": context.get("return_policy", "origin"),
	}
	return actor


func _reserve_record(record: EntityRecord, context: Dictionary, encounter_id: String) -> void:
	var runtime := record.runtime.duplicate(true)
	runtime["combat_reserved_encounter_id"] = encounter_id
	runtime["combat_origin_coords"] = context.get("macro_origin_coords", record.coords)
	runtime["combat_entry_direction"] = context.get("relative_entry_direction", GameEnums.MacroTravelDirection.NONE)
	world_state.update_entity_runtime(record.entity_id, runtime)
