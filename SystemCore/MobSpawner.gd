extends Node


## Procedural mob factory. Rolls randomized genetics and assigns faction-appropriate
## loadouts from preloaded item pools. Uses strict Base-12 math for all attribute rolls.

# Mob definition presets keyed by faction
var _loadout_presets: Dictionary = {} # GameEnums.Faction -> Array[SpawnLoadout]

# ---------------------------------------------------------
# THE GENETICS RANDOMIZER (Base-12 Bell Curve)
# ---------------------------------------------------------

## Rolls a Base-12 attribute with a bell curve centered on the given average.
## Uses 2d6 distribution (2-12 range, peaking at 7) offset by the faction bias.
func _roll_attribute(
	average: int,
	variance: int = 3,
	rng: RandomNumberGenerator = null
) -> int:
	# Bell curve: roll two dice and average with the target
	var first_die := rng.randi_range(1, 6) if rng else randi_range(1, 6)
	var second_die := rng.randi_range(1, 6) if rng else randi_range(1, 6)
	var roll: int = first_die + second_die
	var result: int = int((roll + average) / 2.0)
	var variance_roll := (
		rng.randi_range(-variance, variance)
		if rng
		else randi_range(-variance, variance)
	)
	return clampi(result + variance_roll / 2, 1, 12)

# ---------------------------------------------------------
# LOADOUT GENERATORS (Faction-Specific Gear Tables)
# ---------------------------------------------------------

## Build a loadout from item IDs. Returns null if no items found.
func _build_loadout(weapon_id: String, armor_ids: Array[String], consumable_ids: Array[String]) -> SpawnLoadout:
	var loadout = SpawnLoadout.new()
	
	var weapon_definition := _get_item_definition(weapon_id)
	if weapon_definition:
		loadout.weapon = weapon_definition
		var weapon: ItemData = loadout.weapon
		if weapon.is_ranged():
			loadout.vest = _get_item_definition("webbing")
			for support_id in [weapon.magazine_id, weapon.reload_aid_id]:
				var support := _get_item_definition(support_id)
				if support:
					loadout.starting_items.append(support)
			var ammunition := _get_item_definition(weapon.ammunition_id)
			if ammunition:
				for _round_index in range(mini(12, weapon.max_magazine)):
					loadout.starting_items.append(ammunition)
	
	for armor_id in armor_ids:
		var item := _get_item_definition(armor_id)
		if not item:
			continue
		match item.target_slot:
			GameEnums.EquipmentSlot.INNER_TORSO: loadout.inner_torso = item
			GameEnums.EquipmentSlot.OUTER_TORSO: loadout.outer_torso = item
			GameEnums.EquipmentSlot.LEGS: loadout.legs = item
			GameEnums.EquipmentSlot.FEET: loadout.feet = item
			GameEnums.EquipmentSlot.VEST: loadout.vest = item
			GameEnums.EquipmentSlot.BACKPACK: loadout.backpack_gear = item
	
	for con_id in consumable_ids:
		var consumable := _get_item_definition(con_id)
		if consumable:
			loadout.starting_items.append(consumable)
	
	return loadout

func _get_item_definition(item_id: String) -> ItemData:
	if item_id.is_empty():
		return null
	var catalog := get_node_or_null("/root/LootCatalog") if is_inside_tree() else null
	if catalog != null:
		var definition := catalog.call("get_item_definition", item_id) as ItemData
		if definition != null:
			return definition
	# Factories are also used detached from the scene tree by previews and smoke
	# tests. Item IDs remain data paths, so that context does not need an autoload.
	var item_path := "res://ItemCore/Items/%s.tres" % item_id
	return load(item_path) as ItemData if ResourceLoader.exists(item_path) else null

## Generate a random SCAVENGER loadout.
func _generate_scavenger_loadout(rng: RandomNumberGenerator = null) -> SpawnLoadout:
	var weapons: Array[String] = [
		"rebar",
		"service_pistol",
		"revolver",
	]
	var weapon_index := rng.randi_range(0, weapons.size() - 1) if rng else randi() % weapons.size()
	var chosen_weapon: String = weapons[weapon_index]
	
	# Scavengers always have a coat and boots, sometimes greaves
	var armor: Array[String] = ["coat_leather", "boot_service"]
	var armor_roll := rng.randf() if rng else randf()
	if armor_roll > 0.4:
		armor.append("pants_cargo")
	
	# Random consumable roll (1-3 items)
	var consumables: Array[String] = []
	var possible_cons: Array[String] = ["mre", "water_bottle", "blood_bag"]
	var num_cons: int = rng.randi_range(1, 3) if rng else randi_range(1, 3)
	for i in range(num_cons):
		var item_index := (
			rng.randi_range(0, possible_cons.size() - 1)
			if rng
			else randi() % possible_cons.size()
		)
		consumables.append(possible_cons[item_index])
	
	return _build_loadout(chosen_weapon, armor, consumables)

## Generate a random ARCBORN RESISTANCE loadout (better equipped).
func _generate_arcborn_loadout() -> SpawnLoadout:
	# Arcborn always carry a sidearm and full armor kit
	var armor: Array[String] = ["shirt_thermo", "armor_arcborn", "pants_carbon", "boot_service", "backpack_service_big"]
	var consumables: Array[String] = ["mre", "water_bottle", "life_booster", "blood_bag"]
	
	return _build_loadout("carbon_pistol", armor, consumables)

## Generate a CRAVEN HIVE loadout (mindless, no tools, bare fists).
func _generate_craven_loadout() -> SpawnLoadout:
	# Cravens are feral. They have nothing but their rage.
	return _build_loadout("", [], [])

# ---------------------------------------------------------
# PUBLIC API: SPAWN A MOB
# ---------------------------------------------------------

## Spawn a fully procedural EntityDefinition with randomized genetics and gear.
## Internal factory helper — external callers should use generate_mob_record().
func generate_mob(
	faction: GameEnums.Faction,
	difficulty_bias: int = 0,
	rng: RandomNumberGenerator = null
) -> EntityDefinition:
	var def = EntityDefinition.new()
	
	match faction:
		GameEnums.Faction.SCAVENGER_CELL:
			def.archetype_name = _pick_scavenger_name(rng)
			def.faction = faction
			def.agenda = GameEnums.Agenda.SURVIVALIST
			def.brawn = _roll_attribute(5 + difficulty_bias, 3, rng)
			def.finesse = _roll_attribute(6 + difficulty_bias, 3, rng)
			def.fortitude = _roll_attribute(4 + difficulty_bias, 3, rng)
			def.will = _roll_attribute(3 + difficulty_bias, 3, rng)
			def.loadout = _generate_scavenger_loadout(rng)
			def.npc_role_id = "raider"
			
		GameEnums.Faction.ARCBORN_RESISTANCE:
			def.archetype_name = _pick_arcborn_name(rng)
			def.faction = faction
			def.agenda = GameEnums.Agenda.BELLIGERENT
			def.brawn = _roll_attribute(7 + difficulty_bias, 3, rng)
			def.finesse = _roll_attribute(7 + difficulty_bias, 3, rng)
			def.fortitude = _roll_attribute(6 + difficulty_bias, 3, rng)
			def.will = _roll_attribute(8 + difficulty_bias, 3, rng)
			def.arc_tier = GameEnums.ArcbornTier.TIER_1
			def.max_arc_energy = 6.0
			def.red_mist_resistance = 4.0
			def.loadout = _generate_arcborn_loadout()
			def.npc_role_id = "patrol"
			
		GameEnums.Faction.CRAVEN_HIVE:
			def.archetype_name = "Craven Thrall"
			def.faction = faction
			def.agenda = GameEnums.Agenda.MINDLESS
			# "Craven" = cowardly. These are malnourished, frail thralls — the
			# weakest melee bruiser in the bestiary, not a damage sponge. Stats
			# sit at/below the Drifter baseline (6) and the Scavenger (B5/T4).
			def.brawn = _roll_attribute(6 + difficulty_bias, 3, rng) # Feral rush threat
			def.finesse = _roll_attribute(3, 3, rng) # Clumsy, feral
			# Naked, malnourished thralls should actually be fragile. The old bell-
			# curve centered them near ordinary human durability despite this comment.
			var craven_variance := (
				rng.randi_range(0, 2) if rng else randi_range(0, 2)
			)
			def.fortitude = clampi(
				2 + difficulty_bias + craven_variance,
				2,
				8
			)
			def.will = 1 # No willpower, pure instinct
			def.red_mist_resistance = 0.0
			def.loadout = _generate_craven_loadout()
			def.npc_role_id = "stalker"
			
		_: # UNALIGNED / Fallback
			def.archetype_name = "Drifter"
			def.faction = GameEnums.Faction.UNALIGNED
			def.agenda = GameEnums.Agenda.SURVIVALIST
			def.brawn = _roll_attribute(6 + difficulty_bias, 3, rng)
			def.finesse = _roll_attribute(6 + difficulty_bias, 3, rng)
			def.fortitude = _roll_attribute(6 + difficulty_bias, 3, rng)
			def.will = _roll_attribute(6 + difficulty_bias, 3, rng)
			def.loadout = _generate_scavenger_loadout(rng)
			def.npc_role_id = "salvager"

	var role_loadout := _generate_role_loadout(def.npc_role_id, rng)
	if role_loadout != null:
		def.loadout = role_loadout
	
	print("[MOB SPAWNER] Generated: ", def.archetype_name, " | B:", def.brawn, " F:", def.finesse, " T:", def.fortitude, " W:", def.will)
	print(
		"[Stats] Rolled ", def.archetype_name,
		" (", GameEnums.Faction.keys()[def.faction], ", bias ", difficulty_bias, ")",
		" -> BRAWN ", def.brawn, " FINESSE ", def.finesse,
		" FORT ", def.fortitude, " WILL ", def.will,
		" | agenda ", GameEnums.Agenda.keys()[def.agenda]
	)
	return def

## Generate a neutral persistent record. WorldCore never needs the biological
## definition object; CombatCore reconstructs it only when an encounter starts.
func generate_mob_record(
	coords: Vector2i,
	faction: GameEnums.Faction,
	difficulty_bias: int = 0,
	deterministic_key: String = ""
) -> EntityRecord:
	var rng: RandomNumberGenerator = null
	if not deterministic_key.is_empty():
		rng = RandomNumberGenerator.new()
		rng.seed = deterministic_key.hash()

	var definition := generate_mob(faction, difficulty_bias, rng)
	var record := EntityRecord.new()
	record.entity_id = (
		"entity_" + str(abs(deterministic_key.hash()))
		if not deterministic_key.is_empty()
		else "entity_" + str(ResourceUID.create_id())
	)
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = GameEnums.EntityWorldStatus.HOSTILE
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = {}
	return record

## Convenience: spawn N mobs of a faction and return them as an array.
func generate_mob_squad(faction: GameEnums.Faction, count: int, difficulty_bias: int = 0) -> Array[EntityDefinition]:
	var squad: Array[EntityDefinition] = []
	for i in range(count):
		squad.append(generate_mob(faction, difficulty_bias))
	return squad


const CENTRAL_GUARD_DEF_PATH := "res://BiologicalCore/central_guard_def.tres"
const CENTRAL_GUARD_AK_LOADOUT_PATH := "res://ItemCore/Loadouts/central_guard_ak_loadout.tres"
const CENTRAL_GUARD_KAR98_LOADOUT_PATH := "res://ItemCore/Loadouts/central_guard_kar98_loadout.tres"


## Authored Central Guard record for Route 1 rim pairs.
func generate_central_guard_record(
	coords: Vector2i,
	use_kar98: bool,
	squad_id: String,
	deterministic_key: String = ""
) -> EntityRecord:
	var base_def := load(CENTRAL_GUARD_DEF_PATH) as EntityDefinition
	var definition := EntityDefinition.new()
	if base_def != null:
		definition = EntityDefinition.from_state(base_def.to_state())
	else:
		definition.archetype_name = "Central Guard"
		definition.faction = GameEnums.Faction.UNALIGNED
		definition.agenda = GameEnums.Agenda.BELLIGERENT
		definition.combat_tactic = GameEnums.CombatTactic.MARKSMAN
		definition.blocks_ambush = true
		definition.template_id = "central_guard"
		definition.blocks_central_reentry = true
		definition.allows_trade = false
		definition.dialogue_id = "central_guard"
		definition.npc_role_id = "sentry"
		definition.brawn = 7
		definition.finesse = 7
		definition.fortitude = 7
		definition.will = 6

	var loadout_path := (
		CENTRAL_GUARD_KAR98_LOADOUT_PATH if use_kar98 else CENTRAL_GUARD_AK_LOADOUT_PATH
	)
	if ResourceLoader.exists(loadout_path):
		definition.loadout = load(loadout_path) as SpawnLoadout

	var record := EntityRecord.new()
	record.entity_id = (
		"entity_" + str(absi(deterministic_key.hash()))
		if not deterministic_key.is_empty()
		else "entity_" + str(ResourceUID.create_id())
	)
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = GameEnums.EntityWorldStatus.HOSTILE
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = {
		"squad_id": squad_id,
		"template_id": "central_guard",
		"macro_purpose": GameEnums.NPC_PURPOSE_HOLD,
		"macro_purpose_label": "Hold",
		"macro_origin_coords": coords,
		"macro_target_coords": coords,
		"stationary": true,
		"npc_role_id": "sentry",
	}
	return record


## Neutral resident posted at a Route 1 settlement to orient new arrivals.
func generate_starter_wayfinder_record(
	coords: Vector2i,
	arm_id: String,
	deterministic_key: String = ""
) -> EntityRecord:
	var definition := EntityDefinition.new()
	definition.archetype_name = "%s Fringe Wayfinder" % arm_id.capitalize()
	definition.faction = GameEnums.Faction.UNALIGNED
	definition.agenda = GameEnums.Agenda.SURVIVALIST
	definition.combat_tactic = GameEnums.CombatTactic.BRUTE
	definition.dialogue_id = "starter_wayfinder:%s" % arm_id
	definition.template_id = "starter_wayfinder"
	definition.npc_role_id = "technician"
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		deterministic_key if not deterministic_key.is_empty()
		else "starter_wayfinder:%s" % arm_id
	).hash()
	definition.loadout = _generate_role_loadout("technician", rng)
	# Dialogue is authored now; settlement stock is not. Keep Trade visibly
	# unavailable instead of offering an NPC whose generated pack is empty.
	definition.allows_trade = false
	definition.blocks_ambush = true

	var record := EntityRecord.new()
	record.entity_id = (
		"entity_" + str(absi(deterministic_key.hash()))
		if not deterministic_key.is_empty()
		else "entity_" + str(ResourceUID.create_id())
	)
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = GameEnums.EntityWorldStatus.CEASEFIRE
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = {
		"template_id": "starter_wayfinder",
		"starter_arm": arm_id,
		"macro_purpose": GameEnums.NPC_PURPOSE_HOLD,
		"macro_purpose_label": "Wayfinder",
		"macro_origin_coords": coords,
		"macro_target_coords": coords,
		"stationary": true,
		"npc_role_id": "technician",
	}
	return record


## Builds a deterministic persistent NPC for authored route populations. Role,
## faction, status, and equipment remain separate data axes.
func generate_role_record(
	coords: Vector2i,
	role_id: String,
	faction: GameEnums.Faction,
	world_status: GameEnums.EntityWorldStatus,
	template_id: String,
	deterministic_key: String = ""
) -> EntityRecord:
	var rng := RandomNumberGenerator.new()
	rng.seed = (deterministic_key if not deterministic_key.is_empty() else template_id).hash()
	var definition := generate_mob(faction, 0, rng)
	definition.npc_role_id = role_id
	definition.template_id = template_id
	var role_catalog := NpcRoleCatalog.data()
	var role := role_catalog.get_role(role_id) if role_catalog != null else null
	if role != null:
		definition.archetype_name = "%s %s" % [
			_pick_route_name(rng),
			role.display_name,
		]
	var role_loadout := _generate_role_loadout(role_id, rng)
	if role_loadout != null:
		definition.loadout = role_loadout
	definition.blocks_ambush = world_status != GameEnums.EntityWorldStatus.HOSTILE

	var record := EntityRecord.new()
	record.entity_id = "entity_" + str(absi((deterministic_key + template_id).hash()))
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = world_status
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = {
		"template_id": template_id,
		"npc_role_id": role_id,
	}
	return record


## Builds a persistent authored plot actor while preserving the ordinary loadout
## and record pipeline. Plot data remains owned by WorldCore resources.
func generate_authored_actor_record(
	coords: Vector2i,
	actor_id: String,
	actor_name: String,
	faction: GameEnums.Faction,
	world_status: GameEnums.EntityWorldStatus,
	role_id: String,
	dialogue_id: String,
	visual_mode: String = "equipment_rig",
	token_sprite_path: String = "",
	deterministic_key: String = ""
) -> EntityRecord:
	var rng := RandomNumberGenerator.new()
	rng.seed = (deterministic_key if not deterministic_key.is_empty() else actor_id).hash()
	var definition := generate_mob(faction, 0, rng)
	definition.archetype_name = actor_name
	definition.template_id = actor_id
	definition.npc_role_id = role_id
	var role_loadout := _generate_role_loadout(role_id, rng)
	if role_loadout != null:
		definition.loadout = role_loadout
	definition.dialogue_id = dialogue_id
	definition.token_visual_mode = visual_mode
	definition.token_sprite_path = token_sprite_path
	definition.blocks_ambush = world_status != GameEnums.EntityWorldStatus.HOSTILE

	var record := EntityRecord.new()
	record.entity_id = "entity_plot_" + str(absi((deterministic_key + actor_id).hash()))
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = world_status
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = {
		"template_id": actor_id,
		"npc_role_id": role_id,
		"plot_actor": true,
		"plot_actor_id": actor_id,
	}
	return record


func _generate_role_loadout(
	role_id: String,
	rng: RandomNumberGenerator = null
) -> SpawnLoadout:
	var catalog := NpcLoadoutCatalog.data()
	var profile := catalog.for_role(role_id) if catalog != null else null
	if profile == null:
		return null
	var active_rng := rng
	if active_rng == null:
		active_rng = RandomNumberGenerator.new()
		active_rng.randomize()
	var loadout := SpawnLoadout.new()
	for slot_key_value in profile.slot_pools.keys():
		var slot_key := str(slot_key_value)
		var item_id := _roll_weighted_item_id(profile.slot_pools[slot_key_value], active_rng)
		_set_loadout_slot(loadout, slot_key, _get_item_definition(item_id))
	var minimum := mini(profile.starting_item_min, profile.starting_item_max)
	var maximum := maxi(profile.starting_item_min, profile.starting_item_max)
	var item_count := active_rng.randi_range(minimum, maximum)
	for _item_index in range(item_count):
		var item_id := _roll_weighted_item_id(profile.starting_item_pool, active_rng)
		var item := _get_item_definition(item_id)
		if item != null:
			loadout.starting_items.append(item)
	_append_weapon_support(loadout)
	return loadout


func _append_weapon_support(loadout: SpawnLoadout) -> void:
	if loadout.weapon == null or not loadout.weapon.is_ranged():
		return
	if loadout.vest == null:
		loadout.vest = _get_item_definition("webbing")
	for support_id in [loadout.weapon.magazine_id, loadout.weapon.reload_aid_id]:
		var support := _get_item_definition(support_id)
		if support != null:
			loadout.starting_items.append(support)
	var ammunition := _get_item_definition(loadout.weapon.ammunition_id)
	if ammunition != null:
		for _round_index in range(mini(6, loadout.weapon.max_magazine)):
			loadout.starting_items.append(ammunition)


func _roll_weighted_item_id(pool_value, rng: RandomNumberGenerator) -> String:
	var pool: Array = pool_value if pool_value is Array else []
	var total := 0.0
	for entry_value in pool:
		if entry_value is Dictionary:
			total += maxf(0.0, float(entry_value.get("weight", 1.0)))
	if total <= 0.0:
		return ""
	var roll := rng.randf_range(0.0, total)
	for entry_value in pool:
		if not entry_value is Dictionary:
			continue
		roll -= maxf(0.0, float(entry_value.get("weight", 1.0)))
		if roll <= 0.0:
			return str(entry_value.get("item_id", ""))
	return str(pool.back().get("item_id", "")) if pool.back() is Dictionary else ""


func _set_loadout_slot(loadout: SpawnLoadout, slot_key: String, item: ItemData) -> void:
	match slot_key:
		"weapon": loadout.weapon = item
		"offhand": loadout.offhand = item
		"inner_torso": loadout.inner_torso = item
		"outer_torso": loadout.outer_torso = item
		"legs": loadout.legs = item
		"feet": loadout.feet = item
		"vest": loadout.vest = item
		"backpack_gear": loadout.backpack_gear = item
		"head": loadout.head = item
		"eyes": loadout.eyes = item
		"face": loadout.face = item
		"neck": loadout.neck = item
		"arms": loadout.arms = item
		"belt": loadout.belt = item
		"sling": loadout.sling = item


func _pick_route_name(rng: RandomNumberGenerator) -> String:
	var names: Array[String] = [
		"Amber", "Blue", "Cinder", "Juniper", "Moss", "Ochre", "Rust", "Violet",
	]
	return names[rng.randi_range(0, names.size() - 1)]

# ---------------------------------------------------------
# NAME GENERATORS (Lore Flavor)
# ---------------------------------------------------------

func _pick_scavenger_name(rng: RandomNumberGenerator = null) -> String:
	var names: Array[String] = [
		"Rattler", "Dustmouth", "Hollowjack", "Gutspill", "Needlefingers",
		"Ashburn", "Plagueknot", "Splintertooth", "Mudblood", "Blacklung",
		"Rotgut", "Scrapjaw", "Bonesaw", "Fleshpenny", "Grimewalker"
	]
	var index := rng.randi_range(0, names.size() - 1) if rng else randi() % names.size()
	return names[index]

func _pick_arcborn_name(rng: RandomNumberGenerator = null) -> String:
	var names: Array[String] = [
		"Warden Kael", "Striker Voss", "Arc-Sentry Mira", "Breacher Thorne",
		"Operative Sable", "Conduit Ashara", "Arc-Shield Grent", "Pathfinder Lyrae"
	]
	var index := rng.randi_range(0, names.size() - 1) if rng else randi() % names.size()
	return names[index]
