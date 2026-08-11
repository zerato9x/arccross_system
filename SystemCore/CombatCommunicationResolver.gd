extends RefCounted
class_name CombatCommunicationResolver

const _Ledger := preload("res://SystemCore/CombatRelationshipLedger.gd")
const PROFILE_PATH := "res://SystemCore/default_combat_communication_profile.tres"


static func load_default_profile() -> CombatCommunicationProfile:
	return load(PROFILE_PATH) as CombatCommunicationProfile


static func communication_points_for(inputs: Dictionary, profile: CombatCommunicationProfile = null) -> int:
	var authored := profile if profile != null else load_default_profile()
	if authored == null:
		authored = CombatCommunicationProfile.new()
	var points := authored.resolved_base_communication_points()
	points += floori(float(inputs.get("player_will", 0)) / float(maxi(1, authored.will_divisor)))
	points += authored.morale_modifier(str(inputs.get("morale_band", "normal")))
	points += authored.cohesion_modifier(str(inputs.get("cohesion_band", "normal")))
	points += int(inputs.get("trait_modifier", 0))
	points -= clampi(int(inputs.get("biological_crisis", 0)), 0, authored.biological_crisis_penalty)
	return clampi(points, 0, 12)


## Compatibility alias for older callers and saved combat fixtures.
static func squad_points_for(inputs: Dictionary, profile: CombatCommunicationProfile = null) -> int:
	return communication_points_for(inputs, profile)


static func evaluate(
	intent: String,
	initiator: Dictionary,
	target: Dictionary,
	relation: int,
	context: Dictionary = {},
	profile: CombatCommunicationProfile = null
) -> Dictionary:
	var authored := profile if profile != null else load_default_profile()
	if authored == null:
		authored = CombatCommunicationProfile.new()
	var normalized_intent := intent.to_lower()
	var target_id := str(target.get("actor_id", ""))
	var initiator_id := str(initiator.get("actor_id", ""))
	if bool(target.get("mindless", false)) or str(target.get("agenda", "")).to_lower() == "mindless":
		return _receipt(normalized_intent, initiator_id, target_id, false, "mindless", -99.0, authored.acceptance_threshold)
	var score := authored.intent_bias(normalized_intent)
	score += authored.agenda_bias(str(target.get("agenda", "")))
	score += (float(target.get("morale", 6.0)) - 6.0) * 0.35
	score -= float(target.get("pain", 0.0)) * 0.12
	score -= float(target.get("shock", 0.0)) * 0.16
	var target_stance := float(target.get("stance", target.get("max_stance", 12.0)))
	var max_stance := maxf(1.0, float(target.get("max_stance", 12.0)))
	score += (1.0 - target_stance / max_stance) * 2.0
	var pressure := clampf(float(target.get("survival_pressure", 0.0)), 0.0, 12.0)
	var agenda := str(target.get("agenda", "")).to_lower()
	if agenda == "survivalist":
		score += pressure * (0.35 if normalized_intent in ["ceasefire", "flee"] else -0.08)
	if agenda in ["zealot", "mindless"]:
		# Zealots do not get a hidden survival bonus; mindless was handled above.
		score -= pressure * 0.0
	if bool(target.get("broken", false)) and normalized_intent in ["threaten", "ceasefire"]:
		score += 2.0
	var relative_force := float(context.get("relative_force", 0.0))
	score += relative_force * (0.18 if normalized_intent in ["ceasefire", "flee"] else -0.05)
	var accepted := score >= authored.acceptance_threshold
	var reason := "accepted" if accepted else "refused"
	return _receipt(normalized_intent, initiator_id, target_id, accepted, reason, score, authored.acceptance_threshold)


static func _receipt(intent: String, initiator_id: String, target_id: String, accepted: bool, reason: String, score: float, threshold: float) -> Dictionary:
	return {
		"intent": intent,
		"initiator_id": initiator_id,
		"target_id": target_id,
		"accepted": accepted,
		"reason": reason,
		"score": score,
		"threshold": threshold,
		"deterministic": true,
	}
