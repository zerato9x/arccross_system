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


static func from_dict(data: Dictionary) -> CombatRelationshipLedger:
	var ledger := CombatRelationshipLedger.new()
	ledger.schema_version = maxi(1, int(data.get("schema_version", 1)))
	# Older encounter records were authored by hand and sometimes stored the
	# pair in encounter order instead of the ledger's canonical sorted order.
	# Normalize that input once at hydration so every consumer observes the same
	# deterministic relation, regardless of which actor was listed first.
	var raw_relations: Dictionary = data.get("relation_by_pair", {})
	var relation_keys: Array[String] = []
	for raw_key in raw_relations.keys():
		relation_keys.append(str(raw_key))
	relation_keys.sort()
	for raw_key in relation_keys:
		var parts := raw_key.split("|")
		if parts.size() == 2:
			ledger.relation_by_pair[pair_key(str(parts[0]), str(parts[1]))] = int(raw_relations[raw_key])
		else:
			ledger.relation_by_pair[raw_key] = raw_relations[raw_key]
	ledger.trust_by_pair = data.get("trust_by_pair", {}).duplicate(true)
	ledger.accepted_orders = data.get("accepted_orders", {}).duplicate(true)
	return ledger
