extends SceneTree

const GUN_ANIMATION_CATALOG := preload(
	"res://CombatCore/DuelUI/GunAnimationCatalog.gd"
)

const ANIMATED_WEAPONS := [
	"service_pistol",
	"carbon_pistol",
	"revolver",
	"carbon_rifle",
	"ak47",
	"service_rifle",
	"shotgun",
]

const LAYERED_EFFECTS := {
	"carbon_rifle": ["shoot", "cycle"],
	"service_rifle": ["shoot", "cycle"],
	"shotgun": ["shoot"],
}

const STATIC_UNIQUE_WEAPONS := [
	"unique_arcbornblaster",
	"unique_modifiedrifle",
	"unique_railgun",
	"unique_theoperator",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for weapon_id in ANIMATED_WEAPONS:
		var error := _validate_catalog_weapon(weapon_id)
		if not error.is_empty():
			return _fail(error)

	for weapon_id in STATIC_UNIQUE_WEAPONS:
		var item := load("res://ItemCore/Items/%s.tres" % weapon_id) as ItemData
		if item == null:
			return _fail("Could not load %s." % weapon_id)
		if (
			item.inventory_sprite_path.is_empty()
			or not ResourceLoader.exists(item.inventory_sprite_path)
			or GUN_ANIMATION_CATALOG.has_weapon(weapon_id)
		):
			return _fail("%s does not have a valid static-art fallback." % weapon_id)

	var impact_path := (
		"res://SoundCore/Sound/sfx/"
		+ "universfield-fatal-body-fall-thud-352716.mp3"
	)
	var impact_stream := GUN_ANIMATION_CATALOG.impact_sound_stream()
	if impact_stream == null or impact_stream.resource_path != impact_path:
		return _fail("The mislabeled asset was not wired as the impact sound.")

	print(
		"[GUN_PRESENTATION_SMOKE] PASS // animated=%d static_unique=%d layered=%d"
		% [ANIMATED_WEAPONS.size(), STATIC_UNIQUE_WEAPONS.size(), LAYERED_EFFECTS.size()]
	)
	quit(0)

func _validate_catalog_weapon(weapon_id: String) -> String:
	for effect in ["shoot", "aim", "reload", "cycle", "empty"]:
		var texture := GUN_ANIMATION_CATALOG.texture(weapon_id, effect)
		var spec := GUN_ANIMATION_CATALOG.frame_spec(weapon_id, effect)
		if texture == null:
			return "%s has no %s texture." % [weapon_id, effect]
		var width := int(spec.get("w", 0))
		var height := int(spec.get("h", 0))
		if (
			width <= 0
			or height <= 0
			or texture.get_width() % width != 0
			or texture.get_height() % height != 0
		):
			return "%s has an invalid %s frame grid." % [weapon_id, effect]
		var overlay := GUN_ANIMATION_CATALOG.effect_texture(weapon_id, effect)
		var expects_overlay: bool = (
			LAYERED_EFFECTS.has(weapon_id)
			and effect in LAYERED_EFFECTS[weapon_id]
		)
		if expects_overlay != (overlay != null):
			return "%s has the wrong %s overlay mapping." % [weapon_id, effect]
		if overlay != null:
			var overlay_spec := GUN_ANIMATION_CATALOG.effect_frame_spec(
				weapon_id,
				effect
			)
			if (
				texture.get_size() != overlay.get_size()
				or width != int(overlay_spec.get("w", -1))
				or height != int(overlay_spec.get("h", -1))
			):
				return "%s has a misaligned %s overlay." % [weapon_id, effect]
	return ""

func _fail(message: String) -> void:
	push_error("[GUN_PRESENTATION_SMOKE] FAIL // " + message)
	quit(1)
