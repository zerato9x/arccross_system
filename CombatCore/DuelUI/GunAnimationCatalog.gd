extends RefCounted
class_name GunAnimationCatalog

const EFFECT_SHOOT := "shoot"
const EFFECT_AIM := "aim"
const EFFECT_RELOAD := "reload"
const EFFECT_CYCLE := "cycle"
const EFFECT_EMPTY := "empty"

const _PATHS := {
	"service_pistol": {
		EFFECT_SHOOT: "res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - SHOOTING (ALL FX).png",
		EFFECT_AIM: "res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - SHOOTING (ALL FX).png",
		EFFECT_RELOAD: "res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - RELOAD.png",
		EFFECT_CYCLE: "res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - EMPTYING.png",
		EFFECT_EMPTY: "res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - EMPTYING.png",
	},
	"carbon_pistol": {
		EFFECT_SHOOT: "res://Asset/Guns_Animation/pistol_carbon/[SHOOT WITH CASING AND MUZZLE FLASH] Glock - P80.png",
		EFFECT_AIM: "res://Asset/Guns_Animation/pistol_carbon/[SHOOT WITH CASING AND MUZZLE FLASH] Glock - P80.png",
		EFFECT_RELOAD: "res://Asset/Guns_Animation/pistol_carbon/[RELOAD] Glock - P80.png",
		EFFECT_CYCLE: "res://Asset/Guns_Animation/pistol_carbon/[EMPTY] Glock - P80.png",
		EFFECT_EMPTY: "res://Asset/Guns_Animation/pistol_carbon/[EMPTY] Glock - P80.png",
	},
	"revolver": {
		EFFECT_SHOOT: "res://Asset/Guns_Animation/pistol_revolver/[SHOOT WITH MUZZLE FLASH] Revolver - Colt 45.png",
		EFFECT_AIM: "res://Asset/Guns_Animation/pistol_revolver/[SHOOT WITH MUZZLE FLASH] Revolver - Colt 45.png",
		EFFECT_RELOAD: "res://Asset/Guns_Animation/pistol_revolver/[RELOAD WITH BULLETS] Revolver - Colt 45.png",
		EFFECT_CYCLE: "res://Asset/Guns_Animation/pistol_revolver/[EMPTY WITH CASINGS] Revolver - Colt 45.png",
		EFFECT_EMPTY: "res://Asset/Guns_Animation/pistol_revolver/[EMPTY NO CASINGS] Revolver - Colt 45.png",
	},
	"carbon_rifle": {
		EFFECT_SHOOT: "res://Asset/Guns_Animation/rifle_carbon/[SINGLE_SHOT] Assault_rifle_V1.00.png",
		EFFECT_AIM: "res://Asset/Guns_Animation/rifle_carbon/[FULL_MUZZLE_FLASH] Assault_rifle_V1.00.png",
		EFFECT_RELOAD: "res://Asset/Guns_Animation/rifle_carbon/[RELOAD] Assault_rifle_V1.00 - Reload.png",
		EFFECT_CYCLE: "res://Asset/Guns_Animation/rifle_carbon/[CASING_SINGLE_SHOT] Assault_rifle_V1.00.png",
		EFFECT_EMPTY: "res://Asset/Guns_Animation/rifle_carbon/[EMPTYING] Assault_rifle_V1.00.png",
	},
	"ak47": {
		EFFECT_SHOOT: "res://Asset/Guns_Animation/ak47/[SHOOT WITH CASING AND MUZZLE FLASH] AK 47.png",
		EFFECT_AIM: "res://Asset/Guns_Animation/ak47/[SHOOT WITH CASING AND MUZZLE FLASH] FULL AUTO - AK 47.png",
		EFFECT_RELOAD: "res://Asset/Guns_Animation/ak47/[RELOAD] AK 47.png",
		EFFECT_CYCLE: "res://Asset/Guns_Animation/ak47/[EMPTY] AK 47.png",
		EFFECT_EMPTY: "res://Asset/Guns_Animation/ak47/[EMPTY] AK 47.png",
	},
	"service_rifle": {
		EFFECT_SHOOT: "res://Asset/Guns_Animation/rifle_service/[SNIPER_SHOOTING]_Sniper_rifle_[KAR98]_V1.00.png",
		EFFECT_AIM: "res://Asset/Guns_Animation/rifle_service/[SNIPER_MUZZLE_FLASH]_Sniper_rifle_[KAR98]_V1.00.png",
		EFFECT_RELOAD: "res://Asset/Guns_Animation/rifle_service/[SINGLE_RELOADING]_Sniper_rifle_[KAR98]_V1.00.png",
		EFFECT_CYCLE: "res://Asset/Guns_Animation/rifle_service/[RELOADING_CASING_ONLY]_Sniper_rifle_[KAR98]_V1.00.png",
		EFFECT_EMPTY: "res://Asset/Guns_Animation/rifle_service/[SNIPER_EMPTYING]_Sniper_rifle_[KAR98]_V1.00.png",
	},
	"shotgun": {
		EFFECT_SHOOT: "res://Asset/Guns_Animation/shotgun/[FULL_MUZZLE_FLASH] Shotgun_V1.02.png",
		EFFECT_AIM: "res://Asset/Guns_Animation/shotgun/[SHOOTING_CHAMBER_CLOSED] Shotgun_V1.02.png",
		EFFECT_RELOAD: "res://Asset/Guns_Animation/shotgun/[RELOAD] Shotgun_V1.02 - Rreloading_01.png",
		EFFECT_CYCLE: "res://Asset/Guns_Animation/shotgun/[SHOOTING_CHAMBER_OPEN] Shotgun_V1.02.png",
		EFFECT_EMPTY: "res://Asset/Guns_Animation/shotgun/[EMPTYING] Shotgun_V1.02.png",
	},
}

const _AUDIO_FAMILIES := {
	"service_pistol": "pistols",
	"carbon_pistol": "pistols",
	"revolver": "revolver",
	"carbon_rifle": "rifle_carbon",
	"ak47": "ak47",
	"service_rifle": "rifle_service",
	"shotgun": "shotgun",
}

const _FRAME_SPECS := {
	"res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - SHOOTING (ALL FX).png": {"w": 80, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - RELOAD.png": {"w": 80, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_service/Pistol_V1.00 - EMPTYING.png": {"w": 80, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_carbon/[SHOOT WITH CASING AND MUZZLE FLASH] Glock - P80.png": {"w": 128, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_carbon/[RELOAD] Glock - P80.png": {"w": 128, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_carbon/[EMPTY] Glock - P80.png": {"w": 128, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_revolver/[SHOOT WITH MUZZLE FLASH] Revolver - Colt 45.png": {"w": 64, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_revolver/[RELOAD WITH BULLETS] Revolver - Colt 45.png": {"w": 64, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_revolver/[EMPTY WITH CASINGS] Revolver - Colt 45.png": {"w": 64, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/pistol_revolver/[EMPTY NO CASINGS] Revolver - Colt 45.png": {"w": 64, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_carbon/[SINGLE_SHOT] Assault_rifle_V1.00.png": {"w": 128, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_carbon/[FULL_MUZZLE_FLASH] Assault_rifle_V1.00.png": {"w": 128, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_carbon/[CASING_SINGLE_SHOT] Assault_rifle_V1.00.png": {"w": 128, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_carbon/[RELOAD] Assault_rifle_V1.00 - Reload.png": {"w": 128, "h": 64, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_carbon/[EMPTYING] Assault_rifle_V1.00.png": {"w": 128, "h": 64, "fps": 14.0},
	"res://Asset/Guns_Animation/ak47/[SHOOT WITH CASING AND MUZZLE FLASH] AK 47.png": {"w": 96, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/ak47/[SHOOT WITH CASING AND MUZZLE FLASH] FULL AUTO - AK 47.png": {"w": 96, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/ak47/[RELOAD] AK 47.png": {"w": 96, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/ak47/[EMPTY] AK 47.png": {"w": 96, "h": 48, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_service/[SNIPER_SHOOTING]_Sniper_rifle_[KAR98]_V1.00.png": {"w": 160, "h": 128, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_service/[SNIPER_MUZZLE_FLASH]_Sniper_rifle_[KAR98]_V1.00.png": {"w": 160, "h": 128, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_service/[SINGLE_RELOADING]_Sniper_rifle_[KAR98]_V1.00.png": {"w": 128, "h": 128, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_service/[RELOADING_CASING_ONLY]_Sniper_rifle_[KAR98]_V1.00.png": {"w": 128, "h": 128, "fps": 14.0},
	"res://Asset/Guns_Animation/rifle_service/[SNIPER_EMPTYING]_Sniper_rifle_[KAR98]_V1.00.png": {"w": 128, "h": 128, "fps": 14.0},
	"res://Asset/Guns_Animation/shotgun/[FULL_MUZZLE_FLASH] Shotgun_V1.02.png": {"w": 160, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/shotgun/[SHOOTING_CHAMBER_CLOSED] Shotgun_V1.02.png": {"w": 160, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/shotgun/[SHOOTING_CHAMBER_OPEN] Shotgun_V1.02.png": {"w": 160, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/shotgun/[RELOAD] Shotgun_V1.02 - Rreloading_01.png": {"w": 128, "h": 32, "fps": 14.0},
	"res://Asset/Guns_Animation/shotgun/[EMPTYING] Shotgun_V1.02.png": {"w": 160, "h": 32, "fps": 14.0},
}

static func animation_path(weapon_id: String, effect: String) -> String:
	var weapon_paths: Dictionary = _PATHS.get(weapon_id, {})
	var path := str(weapon_paths.get(effect, ""))
	if path.is_empty():
		path = str(weapon_paths.get(EFFECT_SHOOT, ""))
	return path

static func texture(weapon_id: String, effect: String) -> Texture2D:
	var path := animation_path(weapon_id, effect)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func audio_family(weapon_id: String) -> String:
	return str(_AUDIO_FAMILIES.get(weapon_id, "generic"))

static func has_weapon(weapon_id: String) -> bool:
	return _PATHS.has(weapon_id)

static func frame_spec(weapon_id: String, effect: String) -> Dictionary:
	var path := animation_path(weapon_id, effect)
	return (_FRAME_SPECS.get(path, {}) as Dictionary).duplicate(true)
