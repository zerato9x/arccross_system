extends RefCounted
class_name CombatActorPresentationProjection

## Presentation projection for one player's view of the combat actor snapshot.
##
## CombatActionController remains the authority for exact state. This class
## only decides which already-authoritative facts are safe and useful to show
## for the relationship/knowledge level represented by the snapshot.

const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")

const _RELATIONSHIP_LABELS := {
	_RelationshipLedger.Relation.FRIENDLY: "friendly",
	_RelationshipLedger.Relation.NEUTRAL: "neutral",
	_RelationshipLedger.Relation.HOSTILE: "hostile",
}

const _RELATIONSHIP_ROLES := {
	_RelationshipLedger.Relation.FRIENDLY: "success",
	_RelationshipLedger.Relation.NEUTRAL: "caution",
	_RelationshipLedger.Relation.HOSTILE: "critical",
}


static func build(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var player_id := _player_id(snapshot)
	for raw_actor in snapshot.get("actors", []):
		if not raw_actor is Dictionary:
			continue
		var actor: Dictionary = raw_actor
		var actor_id := str(actor.get("actor_id", ""))
		if actor_id.is_empty():
			continue
		var relation := _relation_for(snapshot, player_id, actor_id)
		result[actor_id] = project_actor(actor, actor_id == player_id, relation)
	return result


static func project_actor(actor: Dictionary, is_player: bool, relation: int) -> Dictionary:
	var exact_view := is_player or relation == _RelationshipLedger.Relation.FRIENDLY
	var wounds: Array = actor.get("wounds", [])
	var limbs: Array = actor.get("limbs", [])
	var projected := {
		"actor_id": str(actor.get("actor_id", "")),
		"name": str(actor.get("name", "ACTOR")),
		"relationship": relation,
		"relationship_id": _RELATIONSHIP_LABELS.get(relation, "unknown"),
		"relationship_color": _relationship_color(relation),
		"semantic_role": "info" if is_player else _RELATIONSHIP_ROLES.get(relation, "muted"),
		"knowledge_level": "self" if is_player else ("friendly_exact" if exact_view else "observable"),
		"is_player": is_player,
		"intent": _intent_projection(actor),
		"body_condition": _body_condition(actor, wounds),
		"critical_alerts": _critical_alerts(actor, wounds, exact_view),
		"weapon": _weapon_projection(actor, exact_view),
		"stance_band": _stance_band(actor),
		"burden_tier": _burden_tier(actor),
		"visible_wounds": _visible_wounds(wounds, exact_view),
		"observable_equipment": _observable_equipment(actor.get("equipment", []), actor, exact_view),
	}

	if exact_view:
		projected["blood"] = float(actor.get("blood", 0.0))
		projected["pain"] = float(actor.get("pain", 0.0))
		projected["shock"] = float(actor.get("shock", 0.0))
		projected["consciousness"] = float(actor.get("consciousness", 0.0))
		projected["max_ap"] = int(actor.get("max_ap", 12))
		projected["stance"] = float(actor.get("stance", 0.0))
		projected["max_stance"] = float(actor.get("max_stance", 12.0))
		projected["burden"] = int(actor.get("burden", 0))
		projected["limbs"] = limbs.duplicate(true)
		projected["wounds"] = wounds.duplicate(true)
		projected["items"] = actor.get("items", []).duplicate(true)
		projected["equipment"] = actor.get("equipment", []).duplicate(true)
	else:
		projected["stance"] = null
		projected["max_stance"] = null
		projected["burden"] = null
		projected["max_ap"] = null
		projected["limbs"] = _qualitative_limbs(limbs, wounds)
		projected["wounds"] = _visible_wounds(wounds, false)
		# Carried inventory and exact hidden condition/ammunition never cross the
		# relationship-neutral presentation boundary.
		projected["items"] = []
		projected["equipment"] = projected["observable_equipment"].duplicate(true)
	return projected


static func _player_id(snapshot: Dictionary) -> String:
	for raw_actor in snapshot.get("actors", []):
		if not raw_actor is Dictionary:
			continue
		var actor: Dictionary = raw_actor
		if str(actor.get("actor_id", "")) == "player" or bool(actor.get("direct_player", false)):
			return str(actor.get("actor_id", ""))
	for raw_actor in snapshot.get("actors", []):
		if raw_actor is Dictionary and str(raw_actor.get("team_id", "")) == "player":
			return str(raw_actor.get("actor_id", ""))
	return ""


static func _relation_for(snapshot: Dictionary, left_id: String, right_id: String) -> int:
	if left_id.is_empty() or right_id.is_empty() or left_id == right_id:
		return _RelationshipLedger.Relation.FRIENDLY
	var arena: Dictionary = snapshot.get("arena", {})
	var relationships: Dictionary = arena.get("relationships", {})
	var relation_by_pair: Dictionary = relationships.get("relation_by_pair", {})
	var key := _RelationshipLedger.pair_key(left_id, right_id)
	if relation_by_pair.has(key):
		return clampi(int(relation_by_pair[key]), _RelationshipLedger.Relation.FRIENDLY, _RelationshipLedger.Relation.HOSTILE)
	var left := _actor(snapshot, left_id)
	var right := _actor(snapshot, right_id)
	if not str(left.get("team_id", "")).is_empty() and str(left.get("team_id", "")) == str(right.get("team_id", "")):
		return _RelationshipLedger.Relation.FRIENDLY
	# Missing pairwise authorship is neutral. A different team/faction name is
	# not itself permission to expose hostility or manufacture an attack.
	return _RelationshipLedger.Relation.NEUTRAL


static func _actor(snapshot: Dictionary, actor_id: String) -> Dictionary:
	for raw_actor in snapshot.get("actors", []):
		if raw_actor is Dictionary and str(raw_actor.get("actor_id", "")) == actor_id:
			return raw_actor
	return {}


static func _intent_projection(actor: Dictionary) -> Dictionary:
	var intent: Dictionary = actor.get("public_intent", {})
	if intent.is_empty():
		return {"id": "holding", "label": "Holding", "readable_label": "HOLDING", "icon_id": "hold", "coarse": "HOLD"}
	return {
		"id": str(intent.get("intent_id", intent.get("id", "holding"))),
		"label": str(intent.get("label", intent.get("readable_label", "Holding"))),
		"readable_label": str(intent.get("readable_label", intent.get("label", "HOLDING"))).to_upper(),
		"icon_id": str(intent.get("icon_id", intent.get("id", "hold"))),
		"coarse": str(intent.get("motive", intent.get("intent_id", "HOLD"))).to_upper(),
	}


static func _relationship_color(relation: int) -> String:
	return {
		_RelationshipLedger.Relation.FRIENDLY: "friendly",
		_RelationshipLedger.Relation.HOSTILE: "hostile",
	}.get(relation, "neutral")


static func _body_condition(actor: Dictionary, wounds: Array) -> Dictionary:
	var band := "stable"
	var label := "Stable"
	if bool(actor.get("dead", false)):
		band = "dead"
		label = "Dead"
	elif bool(actor.get("incapacitated", false)) or bool(actor.get("surrendered", false)):
		band = "incapacitated"
		label = "Incapacitated"
	elif bool(actor.get("broken", false)):
		band = "broken"
		label = "Broken"
	elif float(actor.get("blood", 12.0)) <= 3.0 or float(actor.get("consciousness", 12.0)) <= 3.0:
		band = "critical"
		label = "Critical"
	elif not wounds.is_empty():
		band = "wounded"
		label = "Wounded"
	return {"band": band, "label": label}


static func _critical_alerts(actor: Dictionary, wounds: Array, exact_view: bool) -> Array[String]:
	var alerts: Array[String] = []
	if bool(actor.get("dead", false)):
		alerts.append("DEAD")
	elif bool(actor.get("incapacitated", false)):
		alerts.append("INCAPACITATED")
	if bool(actor.get("broken", false)):
		alerts.append("BROKEN")
	for raw_wound in wounds:
		if not raw_wound is Dictionary:
			continue
		var wound: Dictionary = raw_wound
		if float(wound.get("bleeding_rate", 0.0)) > 0.0:
			alerts.append("BLEEDING")
			break
	var weapon: Dictionary = actor.get("ranged_weapon", {})
	if weapon.is_empty():
		weapon = actor.get("melee_weapon", {})
	if bool(weapon.get("is_jammed", weapon.get("jammed", false))):
		alerts.append("WEAPON JAMMED")
	if exact_view and float(actor.get("pain", 0.0)) >= 6.0:
		alerts.append("PAIN HIGH")
	return _unique_strings(alerts)


static func _weapon_projection(actor: Dictionary, exact_view: bool) -> Dictionary:
	var weapon: Dictionary = actor.get("ranged_weapon", {})
	if weapon.is_empty():
		weapon = actor.get("melee_weapon", {})
	if weapon.is_empty():
		return {"present": false, "label": "Unarmed", "ranged": false}
	var result := {
		"present": true,
		"label": str(weapon.get("name", weapon.get("display_name", weapon.get("id", "Weapon")))),
		"ranged": bool(weapon.get("ranged", weapon.get("max_magazine", 0) > 0)),
		"sprite_path": str(weapon.get("sprite_path", weapon.get("inventory_sprite_path", ""))),
		"readiness": str(weapon.get("readiness", {}).get("reason", "ready")).capitalize(),
	}
	if exact_view:
		result["instance_id"] = str(weapon.get("instance_id", ""))
		result["current_magazine"] = int(weapon.get("current_magazine", 0))
		result["max_magazine"] = int(weapon.get("max_magazine", 0))
		result["condition"] = float(weapon.get("condition", weapon.get("current_condition", 12.0)))
		result["condition_band"] = _condition_band(float(result["condition"]))
	else:
		# A player-facing qualitative ammo band is observable enough to support
		# tactical reading without exposing the exact hidden magazine count.
		var current := int(weapon.get("current_magazine", -1))
		var maximum := int(weapon.get("max_magazine", -1))
		result["ammo_band"] = _ammo_band(current, maximum)
	return result


static func _observable_equipment(equipment: Array, actor: Dictionary, exact_view: bool) -> Array:
	var result: Array = []
	var source: Array = equipment
	if source.is_empty():
		var weapon := _weapon_projection(actor, exact_view)
		if bool(weapon.get("present", false)):
			result.append({
				"name": weapon.get("label", "Weapon"),
				"slot": "hand",
				"sprite_path": weapon.get("sprite_path", ""),
				"condition_band": weapon.get("condition_band", "fine"),
			})
		return result
	for raw_item in source:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		var descriptor := {
			"name": str(item.get("name", item.get("display_name", item.get("id", "EQUIPMENT")))),
			"slot": int(item.get("equipment_slot", item.get("equipped_slot", GameEnums.EquipmentSlot.NONE))),
			"sprite_path": str(item.get("sprite_path", item.get("equipped_sprite_path", item.get("inventory_sprite_path", "")))),
		}
		if exact_view:
			descriptor["instance_id"] = str(item.get("instance_id", ""))
			descriptor["condition"] = float(item.get("condition", item.get("current_condition", 12.0)))
			descriptor["condition_band"] = str(item.get("condition_band", _condition_band(float(descriptor["condition"]))))
		result.append(descriptor)
	return result


static func _visible_wounds(wounds: Array, exact_view: bool) -> Array:
	var result: Array = []
	for raw_wound in wounds:
		if not raw_wound is Dictionary:
			continue
		var wound: Dictionary = raw_wound
		var region := int(wound.get("body_region", wound.get("region", -1)))
		var descriptor := {
			"wound_id": str(wound.get("wound_id", "")) if exact_view else "",
			"body_region": region,
			"wound_type": str(wound.get("wound_type", "wound")),
			"bleeding": float(wound.get("bleeding_rate", 0.0)) > 0.0,
			"stabilized": bool(wound.get("stabilized", false)),
			"severity_band": _severity_band(float(wound.get("severity", 0.0))),
			"trauma": str(wound.get("fracture_state", wound.get("burn_state", "none"))),
		}
		if exact_view:
			descriptor["severity"] = float(wound.get("severity", 0.0))
			descriptor["bleeding_rate"] = float(wound.get("bleeding_rate", 0.0))
			descriptor["depth"] = float(wound.get("depth", 0.0))
		result.append(descriptor)
	return result


static func _qualitative_limbs(limbs: Array, wounds: Array) -> Array:
	var result: Array = []
	for raw_limb in limbs:
		if not raw_limb is Dictionary:
			continue
		var limb: Dictionary = raw_limb
		result.append({
			"region": limb.get("region", -1),
			"region_id": limb.get("region_id", ""),
			"function_band": _function_band(float(limb.get("function", limb.get("current", 12.0))), float(limb.get("maximum", 12.0))),
			"bleeding": float(limb.get("bleeding_rate", 0.0)) > 0.0,
		})
	if result.is_empty() and not wounds.is_empty():
		for wound in _visible_wounds(wounds, false):
			result.append({
				"region": wound.get("body_region", -1),
				"function_band": "wounded",
				"bleeding": wound.get("bleeding", false),
			})
	return result


static func _stance_band(actor: Dictionary) -> String:
	if bool(actor.get("broken", false)):
		return "broken"
	var maximum := maxf(1.0, float(actor.get("max_stance", 12.0)))
	var ratio := float(actor.get("stance", maximum)) / maximum
	if ratio <= 0.25:
		return "unbalanced"
	if ratio <= 0.55:
		return "strained"
	return "steady"


static func _burden_tier(actor: Dictionary) -> String:
	var authored := str(actor.get("burden_tier", ""))
	if not authored.is_empty():
		return authored.to_lower()
	var burden := int(actor.get("burden", 0))
	if burden >= 9:
		return "agonizing"
	if burden >= 4:
		return "labored"
	return "fluid"


static func _condition_band(value: float) -> String:
	if value <= 0.0:
		return "broken"
	if value <= 3.0:
		return "critical"
	if value <= 7.0:
		return "worn"
	return "fine"


static func _severity_band(value: float) -> String:
	if value >= 9.0:
		return "critical"
	if value >= 6.0:
		return "severe"
	if value >= 3.0:
		return "moderate"
	return "minor"


static func _function_band(value: float, maximum: float) -> String:
	var ratio := value / maxf(1.0, maximum)
	if ratio <= 0.0:
		return "disabled"
	if ratio <= 0.5:
		return "impaired"
	if ratio < 0.95:
		return "wounded"
	return "functional"


static func _ammo_band(current: int, maximum: int) -> String:
	if maximum <= 0:
		return "not_applicable"
	if current <= 0:
		return "empty"
	if current <= maxi(1, ceili(float(maximum) * 0.25)):
		return "low"
	return "loaded"


static func _unique_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if value not in result:
			result.append(value)
	return result
