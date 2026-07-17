extends RefCounted
class_name DuelWeaponProfileCatalog

static var _cache: Dictionary = {}

static func profile_for(weapon: ItemData) -> DuelWeaponProfile:
	var key := _profile_key(weapon)
	if not _cache.has(key):
		_cache[key] = _build_profile(key, weapon)
	return _cache[key] as DuelWeaponProfile

static func _profile_key(weapon: ItemData) -> String:
	if weapon == null:
		return "unarmed"
	if not weapon.realtime_profile_id.is_empty():
		return weapon.realtime_profile_id
	return "weapon_%s" % GameEnums.WeaponClass.keys()[weapon.weapon_type].to_lower()

static func _build_profile(key: String, weapon: ItemData) -> DuelWeaponProfile:
	var profile := DuelWeaponProfile.new()
	profile.profile_id = key
	if weapon == null:
		profile.light_flesh_multiplier = 1.0
		profile.heavy_flesh_multiplier = 1.15
		profile.heavy_stance_multiplier = 1.7
		return profile

	match weapon.weapon_type:
		GameEnums.WeaponClass.BLUNT:
			profile.light_stance_multiplier = 1.0
			profile.heavy_stance_multiplier = 1.8
			profile.finisher_stance_multiplier = 2.4
			profile.heavy_duration = 3.75
			profile.heavy_impact_time = 2.35
			profile.heavy_commit_time = 1.3
		GameEnums.WeaponClass.BLADE:
			profile.light_duration = 2.0
			profile.light_impact_time = 1.22
			profile.light_flesh_multiplier = 0.95
			profile.heavy_flesh_multiplier = 1.45
		GameEnums.WeaponClass.PISTOL:
			profile.base_aim_time = 2.05
			profile.full_aim_head_weight = 0.42
		GameEnums.WeaponClass.RIFLE:
			profile.base_aim_time = 2.65
			profile.full_aim_accuracy_bonus = 0.3
			profile.full_aim_head_weight = 0.5
		GameEnums.WeaponClass.SHOTGUN:
			profile.base_aim_time = 2.3
			profile.full_aim_accuracy_bonus = 0.16
			profile.full_aim_head_weight = 0.18
	return profile
