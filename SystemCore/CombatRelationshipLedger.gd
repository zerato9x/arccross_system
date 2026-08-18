extends Resource
class_name CombatRelationshipLedger

## Neutral encounter relationship state. Combat, macro negotiation, and AI use
## this projection; it deliberately knows nothing about HumanoidCore or HUDs.

enum Relation { FRIENDLY, NEUTRAL, HOSTILE }

@export var schema_version: int = 1
@export var relation_by_pair: Dictionary = {}
@export var trust_by_pair: Dictionary = {}
@export var accepted_orders: Dictionary = {}


static func pair_key(left_id: String, right_id: String) -> String:
	var ids := [left_id, right_id]
	ids.sort()
	return "%s|%s" % [ids[0], ids[1]]


func relation(left_id: String, right_id: String, fallback: int = Relation.HOSTILE) -> int:
	if left_id.is_empty() or right_id.is_empty() or left_id == right_id:
		return Relation.FRIENDLY
	return int(relation_by_pair.get(pair_key(left_id, right_id), fallback))


func set_relation(left_id: String, right_id: String, value: int) -> void:
	if left_id.is_empty() or right_id.is_empty() or left_id == right_id:
		return
	relation_by_pair[pair_key(left_id, right_id)] = clampi(value, Relation.FRIENDLY, Relation.HOSTILE)


func trust(left_id: String, right_id: String) -> float:
	return clampf(float(trust_by_pair.get("%s>%s" % [left_id, right_id], 0.0)), -12.0, 12.0)


func adjust_trust(left_id: String, right_id: String, delta: float) -> float:
	var next := clampf(trust(left_id, right_id) + delta, -12.0, 12.0)
	trust_by_pair["%s>%s" % [left_id, right_id]] = next
	return next


func order_for(actor_id: String) -> String:
	return str(accepted_orders.get(actor_id, ""))


func set_order(actor_id: String, order_id: String) -> void:
	if not actor_id.is_empty():
		accepted_orders[actor_id] = order_id


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"relation_by_pair": relation_by_pair.duplicate(true),
		"trust_by_pair": trust_by_pair.duplicate(true),
		"accepted_orders": accepted_orders.duplicate(true),
	}


static func validation_error(value: Variant) -> String:
	if not value is Dictionary:
		return "Relationship state is not a Dictionary."
	var data: Dictionary = value
	var schema_version := int(data.get("schema_version", 1))
	if schema_version != 1:
		return "Unsupported relationship-state schema version: %d." % schema_version
	for field_name in ["relation_by_pair", "trust_by_pair", "accepted_orders"]:
		if not data.get(field_name, {}) is Dictionary:
			return "Relationship field is not a Dictionary: %s." % field_name
	var relations: Dictionary = data.get("relation_by_pair", {})
	for raw_key in relations.keys():
		var parts := str(raw_key).split("|")
		if parts.size() != 2 or str(parts[0]).is_empty() or str(parts[1]).is_empty() or parts[0] == parts[1]:
			return "Invalid relationship pair key: %s." % str(raw_key)
		var raw_value = relations[raw_key]
		if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT] or int(raw_value) != float(raw_value):
			return "Invalid relationship value for %s." % str(raw_key)
		if int(raw_value) < Relation.FRIENDLY or int(raw_value) > Relation.HOSTILE:
			return "Relationship value is outside the enum range for %s." % str(raw_key)
	var trust_values: Dictionary = data.get("trust_by_pair", {})
	for raw_key in trust_values.keys():
		var trust_parts := str(raw_key).split(">")
		if trust_parts.size() != 2 or str(trust_parts[0]).is_empty() or str(trust_parts[1]).is_empty():
			return "Invalid trust pair key: %s." % str(raw_key)
		var raw_trust = trust_values[raw_key]
		if typeof(raw_trust) not in [TYPE_INT, TYPE_FLOAT]:
			return "Invalid trust value for %s." % str(raw_key)
		if float(raw_trust) < -12.0 or float(raw_trust) > 12.0:
			return "Trust value is outside the supported range for %s." % str(raw_key)
	var orders: Dictionary = data.get("accepted_orders", {})
	for raw_key in orders.keys():
		if str(raw_key).is_empty() or not orders[raw_key] is String:
			return "Invalid accepted order entry: %s." % str(raw_key)
	return ""


static func from_dict(data: Variant) -> CombatRelationshipLedger:
	var ledger := CombatRelationshipLedger.new()
	var source: Dictionary = data if data is Dictionary else {}
	ledger.schema_version = maxi(1, int(source.get("schema_version", 1)))
	# Older encounter records were authored by hand and sometimes stored the
	# pair in encounter order instead of the ledger's canonical sorted order.
	# Normalize that input once at hydration so every consumer observes the same
	# deterministic relation, regardless of which actor was listed first.
	var raw_relations_value: Variant = source.get("relation_by_pair", {})
	var raw_relations: Dictionary = raw_relations_value if raw_relations_value is Dictionary else {}
	var relation_keys: Array[String] = []
	for raw_key in raw_relations.keys():
		relation_keys.append(str(raw_key))
	relation_keys.sort()
	for raw_key in relation_keys:
		var parts := raw_key.split("|")
		if parts.size() == 2:
			ledger.relation_by_pair[pair_key(str(parts[0]), str(parts[1]))] = clampi(
				int(raw_relations[raw_key]), Relation.FRIENDLY, Relation.HOSTILE
			)
		else:
			ledger.relation_by_pair[raw_key] = raw_relations[raw_key]
	var raw_trust: Variant = source.get("trust_by_pair", {})
	if raw_trust is Dictionary:
		for key in (raw_trust as Dictionary).keys():
			ledger.trust_by_pair[str(key)] = clampf(
				float((raw_trust as Dictionary)[key]), -12.0, 12.0
			)
	var raw_orders: Variant = source.get("accepted_orders", {})
	if raw_orders is Dictionary:
		ledger.accepted_orders = (raw_orders as Dictionary).duplicate(true)
	return ledger
