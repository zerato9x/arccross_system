extends RefCounted
class_name BiologicalSnapshotService

## BiologicalCore-owned neutral capture boundary. World and presentation code
## receive dictionaries only; wound objects and treatment resources stay here.

const _WOUND_TREATMENTS: WoundTreatmentProfile = preload(
	"res://BiologicalCore/default_wound_treatments.tres"
)


static func capture(core: HumanoidCore) -> Dictionary:
	if core == null or core.body == null:
		return {}
	var body := core.body
	return {
		"character": capture_character(core),
		"blood": body.blood_level,
		"pain": body.get_total_pain(),
		"shock": body.shock,
		"consciousness": body.consciousness,
		"bleeding_rate": body.get_total_bleeding_rate(),
		"wound_count": body.get_total_wound_count(),
		"infection_risk": body.get_infection_risk(),
		"hunger": body.hunger,
		"thirst": body.thirst,
		"fatigue": body.fatigue,
		"core_temperature": body.core_temperature,
		"morale": core.current_morale,
		"arc_energy": core.current_arc_energy,
		"red_mist": core.red_mist_corruption,
		"burden": core.total_burden,
		"kinetic_tier": GameEnums.KineticTier.keys()[core.kinetic_tier],
		"threat": core.get_effective_threat(),
		"limbs": capture_limbs(body),
		"emergencies": capture_emergencies(body),
	}


static func capture_character(core: HumanoidCore) -> Dictionary:
	if core == null or core.definition == null:
		return {
			"archetype_name": "Unknown",
			"brawn": 6,
			"finesse": 6,
			"fortitude": 6,
			"will": 6,
			"occupation": {},
			"traits": [],
			"flaws": [],
		}
	var definition := core.definition
	var occupations := IdentityCatalog.occupation_descriptors(definition.occupation_id)
	return {
		"archetype_name": definition.archetype_name,
		"brawn": definition.brawn,
		"finesse": definition.finesse,
		"fortitude": definition.fortitude,
		"will": definition.will,
		"occupation": occupations[0] if not occupations.is_empty() else {},
		"traits": IdentityCatalog.trait_descriptors(definition.trait_ids),
		"flaws": IdentityCatalog.flaw_descriptors(definition.flaw_ids),
	}


static func capture_limbs(body: HumanoidBody) -> Array:
	var limbs: Array = []
	if body == null:
		return limbs
	for region in [
		GameEnums.LimbRegion.HEAD,
		GameEnums.LimbRegion.UPPER_TORSO,
		GameEnums.LimbRegion.LOWER_TORSO,
		GameEnums.LimbRegion.LEFT_ARM,
		GameEnums.LimbRegion.RIGHT_ARM,
		GameEnums.LimbRegion.LEFT_LEG,
		GameEnums.LimbRegion.RIGHT_LEG,
	]:
		var trauma_index := int(body.limb_trauma.get(region, GameEnums.TraumaType.NONE))
		var damage_key := "BLUNT"
		if body.limb_damage_types.has(region):
			damage_key = GameEnums.DamageType.keys()[int(body.limb_damage_types[region])]
		var wounds: Array = []
		for wound in body.get_wounds_for_limb(region):
			if wound is Wound:
				wounds.append({
					"id": wound.wound_id,
					"type": wound.display_name().to_upper(),
					"severity": wound.severity,
					"bleeding_rate": wound.active_bleeding_rate(),
					"pain": wound.pain,
					"contamination": wound.contamination,
					"treated": wound.treated,
					"treatment": _WOUND_TREATMENTS.descriptor_for(int(wound.wound_type)),
				})
		limbs.append({
			"region": GameEnums.LimbRegion.keys()[region],
			"current": float(body.limb_hp.get(region, 0.0)),
			"maximum": body.get_limb_max(region),
			"trauma": GameEnums.TraumaType.keys()[trauma_index],
			"damage_type": damage_key,
			"bleeding_rate": body.get_limb_bleeding_rate(region),
			"wounds": wounds,
		})
	return limbs


static func capture_emergencies(body: HumanoidBody) -> Array:
	var emergencies: Array = []
	if body == null:
		return emergencies
	if body.blood_level <= 4.0:
		emergencies.append("LOW_BLOOD")
	if body.hunger <= 3.0:
		emergencies.append("STARVING")
	if body.thirst <= 3.0:
		emergencies.append("DEHYDRATED")
	if body.fatigue >= 9.0:
		emergencies.append("EXHAUSTED")
	if body.get_total_bleeding_rate() > 0.0:
		emergencies.append("BLEEDING")
	if body.get_total_pain() >= 8.0:
		emergencies.append("SEVERE_PAIN")
	if body.get_infection_risk() >= 8.0:
		emergencies.append("INFECTION_RISK")
	return emergencies
