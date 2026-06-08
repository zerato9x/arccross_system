extends Node


## Procedural mob factory. Rolls randomized genetics and assigns faction-appropriate
## loadouts from preloaded item pools. Uses strict Base-12 math for all attribute rolls.

# ---------------------------------------------------------
# PRELOADED ITEM POOLS (Loaded once at startup)
# ---------------------------------------------------------

var _item_pool: Dictionary = {} # String ID -> ItemData

# Mob definition presets keyed by faction
var _loadout_presets: Dictionary = {} # GameEnums.Faction -> Array[SpawnLoadout]

func _ready() -> void:
	_load_item_pool()

func _load_item_pool() -> void:
	var items_dir: String = "res://ItemCore/Items/"
	var dir = DirAccess.open(items_dir)
	if dir == null:
		push_error("[MOB SPAWNER] Cannot open items directory: " + items_dir)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var item = load(items_dir + file_name) as ItemData
			if item:
				_item_pool[item.id] = item
				print("[MOB SPAWNER] Loaded item: ", item.id)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	print("[MOB SPAWNER] Item pool loaded: ", _item_pool.size(), " items.")

# ---------------------------------------------------------
# THE GENETICS RANDOMIZER (Base-12 Bell Curve)
# ---------------------------------------------------------

## Rolls a Base-12 attribute with a bell curve centered on the given average.
## Uses 2d6 distribution (2-12 range, peaking at 7) offset by the faction bias.
func _roll_attribute(average: int, variance: int = 3) -> int:
	# Bell curve: roll two dice and average with the target
	var roll: int = (randi() % 6 + 1) + (randi() % 6 + 1) # 2d6: 2-12
	var result: int = int((roll + average) / 2.0)
	return clampi(result + randi_range(-variance, variance) / 2, 1, 12)

# ---------------------------------------------------------
# LOADOUT GENERATORS (Faction-Specific Gear Tables)
# ---------------------------------------------------------

## Build a loadout from item IDs. Returns null if no items found.
func _build_loadout(weapon_id: String, armor_ids: Array[String], consumable_ids: Array[String]) -> SpawnLoadout:
	var loadout = SpawnLoadout.new()
	
	if _item_pool.has(weapon_id):
		loadout.weapon = _item_pool[weapon_id]
	
	for armor_id in armor_ids:
		if not _item_pool.has(armor_id): continue
		var item: ItemData = _item_pool[armor_id]
		match item.target_slot:
			GameEnums.EquipmentSlot.INNER_TORSO: loadout.inner_torso = item
			GameEnums.EquipmentSlot.OUTER_TORSO: loadout.outer_torso = item
			GameEnums.EquipmentSlot.LEGS: loadout.legs = item
			GameEnums.EquipmentSlot.FEET: loadout.feet = item
			GameEnums.EquipmentSlot.BACKPACK: loadout.backpack_gear = item
	
	for con_id in consumable_ids:
		if _item_pool.has(con_id):
			loadout.starting_items.append(_item_pool[con_id])
	
	return loadout

## Generate a random SCAVENGER loadout.
func _generate_scavenger_loadout() -> SpawnLoadout:
	var weapons: Array[String] = ["rusty_pipe", "makeshift_sidearm"]
	var chosen_weapon: String = weapons[randi() % weapons.size()]
	
	# Scavengers always have a coat and boots, sometimes greaves
	var armor: Array[String] = ["scavenger_coat", "combat_boots"]
	if randf() > 0.4:
		armor.append("scavenger_greaves")
	
	# Random consumable roll (1-3 items)
	var consumables: Array[String] = []
	var possible_cons: Array[String] = ["ration_bar", "clean_water", "blood_bag"]
	var num_cons: int = randi_range(1, 3)
	for i in range(num_cons):
		consumables.append(possible_cons[randi() % possible_cons.size()])
	
	return _build_loadout(chosen_weapon, armor, consumables)

## Generate a random ARCBORN RESISTANCE loadout (better equipped).
func _generate_arcborn_loadout() -> SpawnLoadout:
	# Arcborn always carry a sidearm and full armor kit
	var armor: Array[String] = ["thermal_undershirt", "scavenger_coat", "scavenger_greaves", "combat_boots", "military_backpack"]
	var consumables: Array[String] = ["ration_bar", "clean_water", "stim_shot", "blood_bag"]
	
	return _build_loadout("makeshift_sidearm", armor, consumables)

## Generate a CRAVEN HIVE loadout (mindless, no tools, bare fists).
func _generate_craven_loadout() -> SpawnLoadout:
	# Cravens are feral. They have nothing but their rage.
	return _build_loadout("", [], [])

# ---------------------------------------------------------
# PUBLIC API: SPAWN A MOB
# ---------------------------------------------------------

## Spawn a fully procedural EntityDefinition with randomized genetics and gear.
func generate_mob(faction: GameEnums.Faction, difficulty_bias: int = 0) -> EntityDefinition:
	var def = EntityDefinition.new()
	
	match faction:
		GameEnums.Faction.SCAVENGER_CELL:
			def.archetype_name = _pick_scavenger_name()
			def.faction = faction
			def.agenda = GameEnums.Agenda.SURVIVALIST
			def.brawn = _roll_attribute(5 + difficulty_bias)
			def.finesse = _roll_attribute(6 + difficulty_bias)
			def.fortitude = _roll_attribute(4 + difficulty_bias)
			def.will = _roll_attribute(3 + difficulty_bias)
			def.loadout = _generate_scavenger_loadout()
			
		GameEnums.Faction.ARCBORN_RESISTANCE:
			def.archetype_name = _pick_arcborn_name()
			def.faction = faction
			def.agenda = GameEnums.Agenda.BELLIGERENT
			def.brawn = _roll_attribute(7 + difficulty_bias)
			def.finesse = _roll_attribute(7 + difficulty_bias)
			def.fortitude = _roll_attribute(6 + difficulty_bias)
			def.will = _roll_attribute(8 + difficulty_bias)
			def.arc_tier = GameEnums.ArcbornTier.TIER_1
			def.max_arc_energy = 6.0
			def.red_mist_resistance = 0.3
			def.loadout = _generate_arcborn_loadout()
			
		GameEnums.Faction.CRAVEN_HIVE:
			def.archetype_name = "Craven Thrall"
			def.faction = faction
			def.agenda = GameEnums.Agenda.MINDLESS
			def.brawn = _roll_attribute(9 + difficulty_bias) # Muscle mutation
			def.finesse = _roll_attribute(3) # Clumsy, feral
			def.fortitude = _roll_attribute(10 + difficulty_bias) # Hard to kill
			def.will = 1 # No willpower, pure instinct
			def.red_mist_resistance = 0.0
			def.loadout = _generate_craven_loadout()
			
		_: # UNALIGNED / Fallback
			def.archetype_name = "Drifter"
			def.faction = GameEnums.Faction.UNALIGNED
			def.agenda = GameEnums.Agenda.SURVIVALIST
			def.brawn = _roll_attribute(6 + difficulty_bias)
			def.finesse = _roll_attribute(6 + difficulty_bias)
			def.fortitude = _roll_attribute(6 + difficulty_bias)
			def.will = _roll_attribute(6 + difficulty_bias)
			def.loadout = _generate_scavenger_loadout()
	
	print("[MOB SPAWNER] Generated: ", def.archetype_name, " | B:", def.brawn, " F:", def.finesse, " T:", def.fortitude, " W:", def.will)
	return def

## Convenience: spawn N mobs of a faction and return them as an array.
func generate_mob_squad(faction: GameEnums.Faction, count: int, difficulty_bias: int = 0) -> Array[EntityDefinition]:
	var squad: Array[EntityDefinition] = []
	for i in range(count):
		squad.append(generate_mob(faction, difficulty_bias))
	return squad

# ---------------------------------------------------------
# NAME GENERATORS (Lore Flavor)
# ---------------------------------------------------------

func _pick_scavenger_name() -> String:
	var names: Array[String] = [
		"Rattler", "Dustmouth", "Hollowjack", "Gutspill", "Needlefingers",
		"Ashburn", "Plagueknot", "Splintertooth", "Mudblood", "Blacklung",
		"Rotgut", "Scrapjaw", "Bonesaw", "Fleshpenny", "Grimewalker"
	]
	return names[randi() % names.size()]

func _pick_arcborn_name() -> String:
	var names: Array[String] = [
		"Warden Kael", "Striker Voss", "Arc-Sentry Mira", "Breacher Thorne",
		"Operative Sable", "Conduit Ashara", "Arc-Shield Grent", "Pathfinder Lyrae"
	]
	return names[randi() % names.size()]
