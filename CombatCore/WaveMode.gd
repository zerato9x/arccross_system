extends Node2D
class_name WaveMode

const DUEL_SCENE := preload("res://CombatCore/MainDuelScene.tscn")
const PLAYER_DEFINITION := preload("res://BiologicalCore/player_def.tres")
const PROFILE_TEXTURE := preload("res://Asset/Innawoods_Asset/Humanoid/Body/Body_Nude.png")
const LOADOUT_PRESET_DIR := "res://ItemCore/Loadouts"

const FACTION_ROTATION: Array[GameEnums.Faction] = [
	GameEnums.Faction.CRAVEN_HIVE,
	GameEnums.Faction.SCAVENGER_CELL,
	GameEnums.Faction.SCAVENGER_CELL,
	GameEnums.Faction.ARCBORN_RESISTANCE,
]

const SLOT_BUTTON_NAMES := {
	GameEnums.EquipmentSlot.HEAD: "HeadSlotButton",
	GameEnums.EquipmentSlot.EYES: "EyesSlotButton",
	GameEnums.EquipmentSlot.FACE: "FaceSlotButton",
	GameEnums.EquipmentSlot.NECK: "NeckSlotButton",
	GameEnums.EquipmentSlot.ARMS: "ArmsSlotButton",
	GameEnums.EquipmentSlot.INNER_TORSO: "InnerTorsoSlotButton",
	GameEnums.EquipmentSlot.OUTER_TORSO: "OuterTorsoSlotButton",
	GameEnums.EquipmentSlot.VEST: "VestSlotButton",
	GameEnums.EquipmentSlot.BELT: "BeltSlotButton",
	GameEnums.EquipmentSlot.SLING: "SlingSlotButton",
	GameEnums.EquipmentSlot.BACKPACK: "BackpackSlotButton",
	GameEnums.EquipmentSlot.LEGS: "LegsSlotButton",
	GameEnums.EquipmentSlot.FEET: "FeetSlotButton",
	GameEnums.EquipmentSlot.HAND: "HandSlotButton",
	GameEnums.EquipmentSlot.OFFHAND: "OffhandSlotButton",
}

@export_range(0.0, 10.0, 0.1) var intermission_seconds: float = 1.5

@onready var arena_root: Node2D = %ArenaRoot
@onready var precombat_screen: Control = %PreCombatScreen
@onready var combat_hud: Control = %CombatHUD
@onready var run_over: Control = %RunOver
@onready var wave_label: Label = %WaveLabel
@onready var status_label: Label = %StatusLabel
@onready var exit_button: Button = %ExitButton

@onready var player_tab: Button = %PlayerTab
@onready var enemy_tab: Button = %EnemyTab
@onready var staged_name: Label = %StagedName
@onready var reset_button: Button = %ResetButton
@onready var menu_button: Button = %MenuButton

@onready var profile_portrait: TextureRect = %ProfilePortrait
@onready var profile_name: Label = %ProfileName
@onready var profile_meta: Label = %ProfileMeta
@onready var attributes_label: Label = %AttributesLabel
@onready var combat_stats_label: Label = %CombatStatsLabel
@onready var resistance_label: Label = %ResistanceLabel

@onready var slot_selection_label: Label = %SlotSelectionLabel
@onready var paper_doll_model: PaperDollModel = %PaperDollModel

@onready var search_edit: LineEdit = %SearchEdit
@onready var category_filter: OptionButton = %CategoryFilter
@onready var catalog_count: Label = %CatalogCount
@onready var catalog_list: ItemList = %CatalogList
@onready var item_details: RichTextLabel = %ItemDetails
@onready var quantity_spin: SpinBox = %QuantitySpin
@onready var add_button: Button = %AddButton
@onready var equip_button: Button = %EquipButton
@onready var unequip_button: Button = %UnequipButton
@onready var remove_button: Button = %RemoveButton
@onready var capacity_label: Label = %CapacityLabel
@onready var inventory_list: ItemList = %InventoryList

@onready var player_summary: Label = %PlayerSummary
@onready var enemy_summary: Label = %EnemySummary
@onready var validation_label: Label = %ValidationLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var start_button: Button = %StartButton

@onready var run_summary: Label = %RunSummary
@onready var restart_button: Button = %RestartButton
@onready var run_menu_button: Button = %RunMenuButton

var wave_number: int = 1
var waves_cleared: int = 0
var _arena: Node = null
var _player_runtime: Dictionary = {}
var _transitioning: bool = false

var _player_stage := WaveLoadoutStaging.new()
var _enemy_stage := WaveLoadoutStaging.new()
var _staged_enemy_record: Dictionary = {}
var _target_enemy: bool = false

var _item_catalog: Array[Dictionary] = []
var _visible_catalog: Array[Dictionary] = []
var _weapon_supply_presets: Dictionary = {}
var _slot_buttons: Dictionary = {}
var _selected_item_path: String = ""
var _selected_equipment_slot: int = GameEnums.EquipmentSlot.NONE
var _selected_inventory_index: int = -1
var _selection_source: String = ""

func _ready() -> void:
	_collect_slot_buttons()
	for button in [
		exit_button,
		player_tab,
		enemy_tab,
		reset_button,
		menu_button,
		add_button,
		equip_button,
		unequip_button,
		remove_button,
		start_button,
		restart_button,
		run_menu_button,
	]:
		HUDAssetLibrary.apply_button(button)
	for slot_button in _slot_buttons.values():
		HUDAssetLibrary.apply_button(slot_button)

	exit_button.pressed.connect(_return_to_menu)
	menu_button.pressed.connect(_return_to_menu)
	run_menu_button.pressed.connect(_return_to_menu)
	restart_button.pressed.connect(_show_loadout_selection)
	reset_button.pressed.connect(_reset_staging)
	start_button.pressed.connect(_start_selected_run)
	player_tab.pressed.connect(_select_target.bind(false))
	enemy_tab.pressed.connect(_select_target.bind(true))
	search_edit.text_changed.connect(_on_catalog_filter_changed)
	category_filter.item_selected.connect(_on_category_selected)
	catalog_list.item_selected.connect(_on_catalog_item_selected)
	inventory_list.item_selected.connect(_on_inventory_item_selected)
	add_button.pressed.connect(_add_selected_to_inventory)
	equip_button.pressed.connect(_equip_selected_item)
	unequip_button.pressed.connect(_unequip_selected_slot)
	remove_button.pressed.connect(_remove_selected_item)

	profile_portrait.texture = PROFILE_TEXTURE
	_populate_category_filter()
	_populate_catalog()
	_load_weapon_supply_presets()
	run_over.visible = false
	combat_hud.visible = false
	_show_loadout_selection()

func _collect_slot_buttons() -> void:
	_slot_buttons.clear()
	for slot_value in SLOT_BUTTON_NAMES:
		var slot := int(slot_value)
		var button := get_node_or_null("%" + str(SLOT_BUTTON_NAMES[slot])) as Button
		if button == null:
			push_error("[WaveMode] Missing authored slot button: %s" % SLOT_BUTTON_NAMES[slot])
			continue
		_slot_buttons[slot] = button
		button.pressed.connect(_on_slot_pressed.bind(slot))

func _populate_category_filter() -> void:
	category_filter.clear()
	for filter_entry in [
		{"label": "ALL ITEMS", "key": "all"},
		{"label": "WEAPONS", "key": "weapon"},
		{"label": "ARMOR", "key": "armor"},
		{"label": "AMMUNITION", "key": "ammunition"},
		{"label": "MEDICAL", "key": "medical"},
		{"label": "CONSUMABLES", "key": "consumable"},
		{"label": "STORAGE", "key": "storage"},
		{"label": "TOOLS", "key": "tool"},
		{"label": "MATERIALS", "key": "material"},
		{"label": "ATTACHMENTS", "key": "attachment"},
		{"label": "OTHER", "key": "other"},
	]:
		var index := category_filter.item_count
		category_filter.add_item(str(filter_entry["label"]))
		category_filter.set_item_metadata(index, str(filter_entry["key"]))
	category_filter.select(0)

func _populate_catalog() -> void:
	_item_catalog.clear()
	var loot_catalog := get_node_or_null("/root/LootCatalog")
	if loot_catalog == null or not loot_catalog.has_method("get_all_item_descriptors"):
		catalog_count.text = "CATALOG UNAVAILABLE"
		return
	_item_catalog = loot_catalog.get_all_item_descriptors()
	_refresh_catalog()

func _load_weapon_supply_presets() -> void:
	_weapon_supply_presets.clear()
	var preset_files := DirAccess.get_files_at(LOADOUT_PRESET_DIR)
	preset_files.sort()
	for file_name in preset_files:
		if not file_name.ends_with(".tres"):
			continue
		var preset_path := LOADOUT_PRESET_DIR.path_join(file_name)
		var preset := load(preset_path) as SpawnLoadout
		if preset == null or preset.weapon == null or not preset.weapon.is_ranged():
			continue
		var accepted_ids := [
			preset.weapon.ammunition_id,
			preset.weapon.magazine_id,
			preset.weapon.reload_aid_id,
		]
		var supplies: Dictionary = {}
		for item in preset.starting_items:
			if item == null or item.id not in accepted_ids:
				continue
			var supply_path := item.resource_path
			if supply_path.is_empty():
				continue
			supplies[supply_path] = int(supplies.get(supply_path, 0)) + 1
		if not supplies.is_empty():
			_weapon_supply_presets[preset.weapon.resource_path] = {
				"source": preset_path,
				"supplies": supplies,
			}

func _refresh_catalog() -> void:
	_visible_catalog.clear()
	catalog_list.clear()
	var needle := search_edit.text.strip_edges().to_lower() if is_instance_valid(search_edit) else ""
	var filter_key := "all"
	if category_filter.item_count > 0:
		filter_key = str(category_filter.get_item_metadata(category_filter.selected))
	for descriptor in _item_catalog:
		var path := str(descriptor.get("template_path", ""))
		var item := _load_item(path)
		if item == null or not _matches_category(item, filter_key):
			continue
		var searchable := "%s %s %s %s %s" % [
			item.display_name,
			item.id,
			_item_type_name(item.item_type),
			path.get_file().get_basename(),
			" ".join(item.tags),
		]
		if not needle.is_empty() and not searchable.to_lower().contains(needle):
			continue
		_visible_catalog.append(descriptor)
		var icon := _load_item_icon(item)
		var row := "%s  |  %s  |  %s" % [
			item.display_name,
			_item_type_name(item.item_type),
			_item_compact_summary(item),
		]
		catalog_list.add_item(row, icon)
		catalog_list.set_item_metadata(catalog_list.item_count - 1, path)
	catalog_count.text = "%d / %d AUTHORED RESOURCES" % [
		_visible_catalog.size(),
		_item_catalog.size(),
	]
	if catalog_list.item_count > 0 and _selection_source.is_empty():
		catalog_list.select(0)
		_on_catalog_item_selected(0)

func _show_loadout_selection() -> void:
	_cleanup_arena()
	_transitioning = false
	run_over.visible = false
	combat_hud.visible = false
	precombat_screen.visible = true
	_reset_staging()

func _reset_staging() -> void:
	_cleanup_arena()
	wave_number = 1
	waves_cleared = 0
	_player_runtime.clear()
	var player_definition := PLAYER_DEFINITION.to_state().duplicate(true)
	var player_loadout: Dictionary = player_definition.get("loadout", {}).duplicate(true)
	_player_stage.configure("PLAYER", player_definition, player_loadout)

	_staged_enemy_record = _generate_enemy_record(1)
	var enemy_definition: Dictionary = _staged_enemy_record.get("definition", {}).duplicate(true)
	var enemy_loadout: Dictionary = enemy_definition.get("loadout", {}).duplicate(true)
	_enemy_stage.configure("ENEMY", enemy_definition, enemy_loadout)

	_target_enemy = false
	_selected_equipment_slot = GameEnums.EquipmentSlot.NONE
	_selected_inventory_index = -1
	_selection_source = ""
	_selected_item_path = ""
	if catalog_list.item_count > 0:
		catalog_list.select(0)
		_selected_item_path = str(catalog_list.get_item_metadata(0))
		_selection_source = "catalog"
	feedback_label.text = "RESET POLICY // authored player kit + deterministic wave-one enemy"
	feedback_label.modulate = Color("#b9a789")
	_render_all()

func _select_target(target_enemy: bool) -> void:
	_target_enemy = target_enemy
	_selected_equipment_slot = GameEnums.EquipmentSlot.NONE
	_selected_inventory_index = -1
	_selection_source = ""
	_selected_item_path = ""
	_render_all()

func _render_all() -> void:
	player_tab.button_pressed = not _target_enemy
	enemy_tab.button_pressed = _target_enemy
	_render_profile()
	_render_slots()
	_render_inventory()
	_render_summaries()
	_render_validation()
	_render_selected_item()
	_render_action_states()

func _render_profile() -> void:
	var stage := _current_stage()
	var definition := stage.definition_state
	var stats := stage.get_derived_stats()
	var faction := int(definition.get("faction", GameEnums.Faction.UNALIGNED))
	var tactic := int(definition.get("combat_tactic", GameEnums.CombatTactic.BRUTE))
	var agenda := int(definition.get("agenda", GameEnums.Agenda.SURVIVALIST))
	profile_name.text = "%s // %s" % [
		stage.target_name,
		str(definition.get("archetype_name", "Unknown combatant")),
	]
	profile_meta.text = "FACTION  %s\nARCHETYPE  %s\nTACTIC  %s\nAGENDA  %s" % [
		_enum_name(GameEnums.Faction.keys(), faction),
		str(definition.get("archetype_name", "Unknown")),
		_enum_name(GameEnums.CombatTactic.keys(), tactic),
		_enum_name(GameEnums.Agenda.keys(), agenda),
	]
	attributes_label.text = "PRIMARY ATTRIBUTES\nBRAWN %d   FINESSE %d\nFORTITUDE %d   WILL %d" % [
		int(definition.get("brawn", 6)),
		int(definition.get("finesse", 6)),
		int(definition.get("fortitude", 6)),
		int(definition.get("will", 6)),
	]
	combat_stats_label.text = (
		"DERIVED COMBAT\nBLOOD %d/12   STANCE %d/12   AP %d\n"
		+ "KINETIC %s (BURDEN %d)\nMOVE 1 LANE / %d AP\nRANGE %d OPTIMAL / %d EFFECTIVE\n"
		+ "WEIGHT %.1f   BULK %.1f   THREAT %.1f"
	) % [
		int(stats["blood"]),
		int(stats["stance"]),
		int(stats["ap"]),
		_enum_name(GameEnums.KineticTier.keys(), int(stats["kinetic_tier"])),
		int(stats["burden"]),
		int(stats["movement_cost"]),
		int(stats["optimal_range"]),
		int(stats["effective_range"]),
		float(stats["weight"]),
		float(stats["bulk"]),
		float(stats["threat"]),
	]
	resistance_label.text = (
		"RESISTANCE / PROTECTION\nBLUNT %.1f   SHARP %.1f   BALLISTIC %.1f\n"
		+ "INSULATION %.1f   RED MIST %.1f/12"
	) % [
		float(stats["blunt"]),
		float(stats["sharp"]),
		float(stats["ballistic"]),
		float(stats["insulation"]),
		float(definition.get("red_mist_resistance", 0.0)),
	]
	staged_name.text = "%s LOADOUT // %s" % [
		stage.target_name,
		str(definition.get("archetype_name", "UNNAMED")),
	]

func _render_slots() -> void:
	var stage := _current_stage()
	var paper_doll_descriptors: Array = []
	for slot_value in WaveLoadoutStaging.SLOT_ORDER:
		var slot := int(slot_value)
		var button := _slot_buttons.get(slot) as Button
		if button == null:
			continue
		var item := stage.get_equipped_item(slot)
		button.text = "%s\n%s" % [
			_slot_name(slot),
			item.display_name if item != null else "EMPTY",
		]
		button.tooltip_text = (
			_item_detail_text(item)
			if item != null
			else "%s is empty. Select a catalogue item and press EQUIP." % _slot_name(slot)
		)
		button.button_pressed = slot == _selected_equipment_slot
		button.icon = _load_item_icon(item) if item != null else null
		if item != null:
			var descriptor := item.to_definition_state()
			descriptor["equipment_slot"] = slot
			paper_doll_descriptors.append(descriptor)
	paper_doll_model.update_model(paper_doll_descriptors)
	paper_doll_model.set_backdrop_visible(false)
	if _selected_equipment_slot == GameEnums.EquipmentSlot.NONE:
		slot_selection_label.text = "SELECT A REAL INVENTORYSYSTEM SLOT"
	else:
		slot_selection_label.text = "SELECTED SLOT // %s" % _slot_name(_selected_equipment_slot)

func _render_inventory() -> void:
	inventory_list.clear()
	var stage := _current_stage()
	for index in range(stage.starting_items.size()):
		var path := stage.starting_items[index]
		var item := _load_item(path)
		var item_name := item.display_name if item != null else path.get_file()
		var summary := _item_compact_summary(item) if item != null else "MISSING RESOURCE"
		inventory_list.add_item("%02d  %s  |  %s" % [index + 1, item_name, summary], _load_item_icon(item))
		inventory_list.set_item_metadata(index, path)
	var validation := stage.validate()
	capacity_label.text = "LOOSE INVENTORY // %d ITEMS // CAPACITY %d / %d%s" % [
		stage.starting_items.size(),
		int(validation.get("used", 0)),
		int(validation.get("capacity", 0)),
		" // LAB STORAGE AUTO-PROVISIONED" if bool(validation.get("auto_storage", false)) else "",
	]

func _render_summaries() -> void:
	player_summary.text = _player_stage.get_summary()
	enemy_summary.text = _enemy_stage.get_summary()

func _render_validation() -> void:
	var errors: Array[String] = []
	for pair in [
		{"name": "PLAYER", "validation": _player_stage.validate()},
		{"name": "ENEMY", "validation": _enemy_stage.validate()},
	]:
		var validation: Dictionary = pair["validation"]
		for raw_error in validation.get("errors", []):
			errors.append("%s // %s" % [pair["name"], str(raw_error)])
	start_button.disabled = not errors.is_empty() or _transitioning
	if errors.is_empty():
		var notices: Array[String] = []
		if _player_stage.auto_storage_provisioned:
			notices.append("PLAYER lab storage auto-provisioned")
		if _enemy_stage.auto_storage_provisioned:
			notices.append("ENEMY lab storage auto-provisioned")
		validation_label.text = "VALIDATION // READY%s" % (
			" // " + " // ".join(notices) if not notices.is_empty() else ""
		)
		validation_label.modulate = Color("#9fcf91")
	else:
		validation_label.text = "VALIDATION BLOCKED // " + "  |  ".join(errors)
		validation_label.modulate = Color("#ef7468")

func _render_selected_item() -> void:
	var item := _load_item(_selected_item_path)
	if item == null:
		item_details.text = "Select a catalogue, loose-inventory, or equipped item for real authored details."
		return
	item_details.text = _item_detail_text(item)

func _render_action_states() -> void:
	var has_item := _load_item(_selected_item_path) != null
	add_button.disabled = not has_item or _selection_source != "catalog"
	equip_button.disabled = not has_item or _selection_source == "equipment"
	unequip_button.disabled = (
		_selected_equipment_slot == GameEnums.EquipmentSlot.NONE
		or _current_stage().get_equipped_path(_selected_equipment_slot).is_empty()
	)
	remove_button.disabled = not (
		_selection_source == "inventory"
		or (
			_selected_equipment_slot != GameEnums.EquipmentSlot.NONE
			and not _current_stage().get_equipped_path(_selected_equipment_slot).is_empty()
		)
	)

func _on_slot_pressed(slot: int) -> void:
	_selected_equipment_slot = slot
	_selected_inventory_index = -1
	_selection_source = "equipment"
	_selected_item_path = _current_stage().get_equipped_path(slot)
	_render_all()

func _on_catalog_item_selected(index: int) -> void:
	if index < 0 or index >= catalog_list.item_count:
		return
	_selected_item_path = str(catalog_list.get_item_metadata(index))
	_selected_inventory_index = -1
	_selection_source = "catalog"
	_render_selected_item()
	_render_action_states()

func _on_inventory_item_selected(index: int) -> void:
	if index < 0 or index >= _current_stage().starting_items.size():
		return
	_selected_inventory_index = index
	_selected_item_path = _current_stage().starting_items[index]
	_selected_equipment_slot = GameEnums.EquipmentSlot.NONE
	_selection_source = "inventory"
	_render_all()

func _on_catalog_filter_changed(_text: String) -> void:
	_selection_source = ""
	_selected_item_path = ""
	_refresh_catalog()

func _on_category_selected(_index: int) -> void:
	_selection_source = ""
	_selected_item_path = ""
	_refresh_catalog()

func _add_selected_to_inventory() -> void:
	var result := _current_stage().add_loose_path(
		_selected_item_path,
		maxi(1, int(quantity_spin.value))
	)
	_handle_stage_result(result)

func _equip_selected_item() -> void:
	var result: Dictionary
	if _selection_source == "inventory":
		result = _equip_stage_item(
			_current_stage(),
			_selected_item_path,
			_selected_equipment_slot,
			_selected_inventory_index,
		)
	else:
		result = _equip_stage_item(
			_current_stage(),
			_selected_item_path,
			_selected_equipment_slot,
		)
	if bool(result.get("ok", false)):
		_selected_equipment_slot = int(result.get("slot", _selected_equipment_slot))
		_selection_source = "equipment"
	_handle_stage_result(result)

func _unequip_selected_slot() -> void:
	var result := _current_stage().unequip_slot(_selected_equipment_slot)
	if bool(result.get("ok", false)):
		_selected_equipment_slot = GameEnums.EquipmentSlot.NONE
		_selection_source = ""
		_selected_item_path = ""
	_handle_stage_result(result)

func _remove_selected_item() -> void:
	var result: Dictionary
	if _selection_source == "inventory":
		result = _current_stage().remove_loose_index(
			_selected_inventory_index,
			maxi(1, int(quantity_spin.value))
		)
	else:
		result = _current_stage().remove_equipped(_selected_equipment_slot)
	if bool(result.get("ok", false)):
		_selected_equipment_slot = GameEnums.EquipmentSlot.NONE
		_selected_inventory_index = -1
		_selection_source = ""
		_selected_item_path = ""
	_handle_stage_result(result)

func _handle_stage_result(result: Dictionary) -> void:
	var ok := bool(result.get("ok", false))
	feedback_label.text = ("OK // " if ok else "REJECTED // ") + str(result.get("message", "Unknown staging result."))
	feedback_label.modulate = Color("#9fcf91") if ok else Color("#ef7468")
	_render_all()

func _equip_stage_item(
	stage: WaveLoadoutStaging,
	item_path: String,
	requested_slot: int,
	loose_index: int = -1
) -> Dictionary:
	var result := (
		stage.equip_loose_index(loose_index, requested_slot)
		if loose_index >= 0
		else stage.equip_path(item_path, requested_slot)
	)
	if not bool(result.get("ok", false)):
		return result
	var weapon := _load_item(item_path)
	if weapon == null or not weapon.is_ranged():
		return result
	var replaced_weapon := _load_item(str(result.get("replaced_path", "")))
	var retired_supplies := _retire_replaced_weapon_supplies(
		stage,
		replaced_weapon,
		weapon
	)
	var supply_result := _ensure_weapon_supplies(stage, weapon)
	result["auto_supplies"] = supply_result
	result["retired_supplies"] = retired_supplies
	if not retired_supplies.is_empty():
		result["message"] = "%s RETIRED SUPPLY // %s." % [
			result.get("message", ""),
			", ".join(retired_supplies),
		]
	var supply_message := str(supply_result.get("message", ""))
	if not supply_message.is_empty():
		result["message"] = "%s %s" % [result.get("message", ""), supply_message]
	return result

func _retire_replaced_weapon_supplies(
	stage: WaveLoadoutStaging,
	replaced_weapon: ItemData,
	new_weapon: ItemData
) -> Array[String]:
	var retired: Array[String] = []
	if (
		replaced_weapon == null
		or not replaced_weapon.is_ranged()
		or replaced_weapon.resource_path == new_weapon.resource_path
	):
		return retired
	var retired_ids := [replaced_weapon.magazine_id, replaced_weapon.reload_aid_id]
	if replaced_weapon.ammunition_id != new_weapon.ammunition_id:
		retired_ids.append(replaced_weapon.ammunition_id)
	for item_id in retired_ids:
		if str(item_id).is_empty():
			continue
		var supply_path := _catalog_path_for_item_id(str(item_id))
		if supply_path.is_empty():
			continue
		var removed := stage.starting_items.count(supply_path)
		if removed == 0:
			continue
		stage.starting_items = stage.starting_items.filter(
			func(path: String) -> bool: return path != supply_path
		)
		var supply_item := _load_item(supply_path)
		var label := supply_item.display_name if supply_item != null else str(item_id)
		retired.append("%d x %s" % [removed, label])
	return retired

func _ensure_weapon_supplies(stage: WaveLoadoutStaging, weapon: ItemData) -> Dictionary:
	var plan := _weapon_supply_plan(weapon)
	var supplies: Dictionary = plan.get("supplies", {})
	var added_labels: Array[String] = []
	var missing_labels: Array[String] = []
	for raw_path in supplies:
		var supply_path := str(raw_path)
		var desired := int(supplies[raw_path])
		var existing := stage.starting_items.count(supply_path)
		var deficit := maxi(0, desired - existing)
		if deficit == 0:
			continue
		var add_result := stage.add_loose_path(supply_path, deficit)
		var added := int(add_result.get("added", 0))
		var supply_item := _load_item(supply_path)
		var label := supply_item.display_name if supply_item != null else supply_path.get_file()
		if added > 0:
			added_labels.append("%d x %s" % [added, label])
		if added < deficit:
			missing_labels.append("%d x %s" % [deficit - added, label])
	var source_path := str(plan.get("source", ""))
	var source_label := (
		source_path.get_file().get_basename()
		if not source_path.is_empty()
		else "weapon fields"
	)
	var message := ""
	if not added_labels.is_empty():
		message = "AUTO SUPPLY [%s] // %s." % [source_label, ", ".join(added_labels)]
	if not missing_labels.is_empty():
		message += " Storage could not accept %s." % ", ".join(missing_labels)
	return {
		"source": source_path,
		"added": added_labels,
		"missing": missing_labels,
		"message": message.strip_edges(),
	}

func _weapon_supply_plan(weapon: ItemData) -> Dictionary:
	if _weapon_supply_presets.has(weapon.resource_path):
		return _weapon_supply_presets[weapon.resource_path].duplicate(true)
	var supplies: Dictionary = {}
	for supply in [
		{"id": weapon.magazine_id, "quantity": 1},
		{"id": weapon.reload_aid_id, "quantity": 1},
		{"id": weapon.ammunition_id, "quantity": maxi(1, weapon.max_magazine)},
	]:
		var supply_id := str(supply["id"])
		if supply_id.is_empty():
			continue
		var supply_path := _catalog_path_for_item_id(supply_id)
		if not supply_path.is_empty():
			supplies[supply_path] = int(supply["quantity"])
	return {"source": "", "supplies": supplies}

func _catalog_path_for_item_id(item_id: String) -> String:
	for descriptor in _item_catalog:
		if str(descriptor.get("id", "")) == item_id:
			return str(descriptor.get("template_path", ""))
	return ""

func _start_selected_run() -> void:
	if _transitioning:
		return
	var validation := get_staging_validation()
	if not bool(validation.get("valid", false)):
		feedback_label.text = "START BLOCKED // %s" % validation.get("reason", "Invalid staged loadout.")
		feedback_label.modulate = Color("#ef7468")
		return
	precombat_screen.visible = false
	combat_hud.visible = true
	_start_run()

func _start_run() -> void:
	_transitioning = true
	_cleanup_arena()
	await get_tree().process_frame
	wave_number = 1
	waves_cleared = 0
	_player_runtime.clear()
	run_over.visible = false
	_transitioning = false
	_start_wave()

func _start_wave() -> void:
	if _transitioning:
		return
	_transitioning = true
	_cleanup_arena()
	await get_tree().process_frame

	var enemy_record := _build_enemy_record(wave_number)
	if enemy_record.is_empty():
		status_label.text = "WAVE LAB ERROR // enemy fabrication failed"
		_transitioning = false
		return
	_arena = DUEL_SCENE.instantiate()
	arena_root.add_child(_arena)
	_arena.duel_finished.connect(_on_duel_finished, CONNECT_ONE_SHOT)

	var player_definition := PLAYER_DEFINITION.to_state().duplicate(true)
	player_definition["loadout"] = _player_stage.to_loadout_state()
	var player_record := {
		"entity_id": "wave_player",
		"definition": player_definition,
		"runtime": _player_runtime.duplicate(true),
	}
	var faction := int(enemy_record.get("definition", {}).get(
		"faction",
		GameEnums.Faction.UNALIGNED
	))
	wave_label.text = "WAVE %02d // %s" % [
		wave_number,
		_enum_name(GameEnums.Faction.keys(), faction),
	]
	status_label.text = "Normal EntityDefinition -> SpawnLoadout -> InventorySystem materialization"
	_arena.setup_duel_from_records(
		player_record,
		enemy_record,
		{
			"context": GameEnums.EncounterContext.NEUTRAL_MEET,
			"initiator_id": "player",
		}
	)
	_transitioning = false

func _generate_enemy_record(for_wave: int) -> Dictionary:
	var mob_spawner := get_node_or_null("/root/MobSpawner") as MobSpawner
	if mob_spawner == null:
		push_error("[WaveMode] MobSpawner is unavailable.")
		return {}
	var faction := FACTION_ROTATION[(for_wave - 1) % FACTION_ROTATION.size()]
	var difficulty_bias := mini(int((for_wave - 1) / 2.0), 6)
	var record := mob_spawner.generate_mob_record(
		Vector2i.ZERO,
		faction,
		difficulty_bias,
		"wave_%d" % for_wave
	).to_dict()
	var definition: Dictionary = record.get("definition", {}).duplicate(true)
	match faction:
		GameEnums.Faction.CRAVEN_HIVE:
			definition["agenda"] = GameEnums.Agenda.MINDLESS
			definition["combat_tactic"] = GameEnums.CombatTactic.BRUTE
		GameEnums.Faction.ARCBORN_RESISTANCE:
			definition["agenda"] = GameEnums.Agenda.BELLIGERENT
			definition["combat_tactic"] = GameEnums.CombatTactic.MARKSMAN
		_:
			definition["agenda"] = GameEnums.Agenda.BELLIGERENT
			definition["will"] = maxi(int(definition.get("will", 6)), 6)
			definition["combat_tactic"] = (
				GameEnums.CombatTactic.MARKSMAN
				if for_wave % 2 == 0
				else GameEnums.CombatTactic.OPPORTUNIST
			)
	definition["archetype_name"] = "Wave %02d // %s" % [
		for_wave,
		str(definition.get("archetype_name", "Hostile")),
	]
	record["definition"] = definition
	record["runtime"] = {}
	return record

func _build_enemy_record(for_wave: int) -> Dictionary:
	var record := (
		_staged_enemy_record.duplicate(true)
		if for_wave == 1
		else _generate_enemy_record(for_wave)
	)
	if record.is_empty():
		return {}
	var definition: Dictionary = record.get("definition", {}).duplicate(true)
	definition["loadout"] = _enemy_stage.to_loadout_state()
	record["definition"] = definition
	record["runtime"] = {}
	return record

func _on_duel_finished(
	outcome: GameEnums.CombatOutcome,
	_enemy_id: String,
	_enemy_runtime: Dictionary,
	player_runtime: Dictionary,
	_dropped_items: Array
) -> void:
	if _transitioning:
		return
	_transitioning = true
	if outcome in [
		GameEnums.CombatOutcome.PLAYER_VICTORY,
		GameEnums.CombatOutcome.ENEMY_ESCAPED,
	]:
		waves_cleared += 1
		_player_runtime = player_runtime.duplicate(true)
		status_label.text = "WAVE %02d CLEARED // next hostile inbound" % wave_number
		if intermission_seconds > 0.0:
			await get_tree().create_timer(intermission_seconds).timeout
		wave_number += 1
		_transitioning = false
		_start_wave()
		return
	status_label.text = "RUN ENDED"
	run_summary.text = (
		"WAVE RUN OVER\n\nCLEARED: %d\nREACHED: %d\n\nRestart returns to a clean authored loadout workstation."
		% [waves_cleared, wave_number]
	)
	run_over.visible = true
	_transitioning = false

func stage_item(
	item_key: String,
	target_enemy: bool,
	equip_at_start: bool,
	requested_slot: int = GameEnums.EquipmentSlot.NONE,
	quantity: int = 1
) -> Dictionary:
	if not precombat_screen.visible or is_instance_valid(_arena):
		return {"ok": false, "message": "Items can only be staged before combat."}
	var item_path := _resolve_catalog_path(item_key)
	if item_path.is_empty():
		return {"ok": false, "message": "Unknown authored item key: %s" % item_key}
	var stage := _enemy_stage if target_enemy else _player_stage
	var result := (
		_equip_stage_item(stage, item_path, requested_slot)
		if equip_at_start
		else stage.add_loose_path(item_path, quantity)
	)
	_render_all()
	return result

func get_catalog_item_count() -> int:
	return _item_catalog.size()

func get_staged_loadout_state(target_enemy: bool) -> Dictionary:
	return (_enemy_stage if target_enemy else _player_stage).to_loadout_state()

func get_staging_validation() -> Dictionary:
	var player_validation := _player_stage.validate()
	var enemy_validation := _enemy_stage.validate()
	var valid := bool(player_validation.get("valid", false)) and bool(enemy_validation.get("valid", false))
	var reason := ""
	if not bool(player_validation.get("valid", false)):
		reason = "PLAYER // %s" % player_validation.get("reason", "Invalid loadout")
	elif not bool(enemy_validation.get("valid", false)):
		reason = "ENEMY // %s" % enemy_validation.get("reason", "Invalid loadout")
	return {
		"valid": valid,
		"reason": reason,
		"player": player_validation,
		"enemy": enemy_validation,
	}

func select_target_enemy(target_enemy: bool) -> void:
	_select_target(target_enemy)

func unequip_staged_slot(target_enemy: bool, slot: int) -> Dictionary:
	var stage := _enemy_stage if target_enemy else _player_stage
	var result := stage.unequip_slot(slot)
	_render_all()
	return result

func remove_staged_loose_item(target_enemy: bool, index: int, quantity: int = 1) -> Dictionary:
	var stage := _enemy_stage if target_enemy else _player_stage
	var result := stage.remove_loose_index(index, quantity)
	_render_all()
	return result

func start_staged_run() -> void:
	_start_selected_run()

func get_current_arena() -> Node:
	return _arena

func _resolve_catalog_path(item_key: String) -> String:
	for descriptor in _item_catalog:
		if (
			str(descriptor.get("template_path", "")) == item_key
			or str(descriptor.get("id", "")) == item_key
		):
			return str(descriptor.get("template_path", ""))
	return ""

func _matches_category(item: ItemData, filter_key: String) -> bool:
	match filter_key:
		"all": return true
		"weapon": return item.item_type == GameEnums.ItemType.WEAPON
		"armor": return item.item_type == GameEnums.ItemType.ARMOR
		"ammunition": return item.item_type == GameEnums.ItemType.AMMUNITION
		"medical": return item.catalog_category == GameEnums.ItemCategory.MEDICINE
		"consumable": return item.item_type == GameEnums.ItemType.CONSUMABLE
		"storage": return item.capacity_bonus > 0
		"tool": return item.item_type == GameEnums.ItemType.TOOL
		"material": return item.item_type == GameEnums.ItemType.MATERIAL
		"attachment": return item.item_type == GameEnums.ItemType.ATTACHMENT
		"other":
			return item.item_type in [GameEnums.ItemType.JUNK]
	return true

func _item_compact_summary(item: ItemData) -> String:
	if item == null:
		return "MISSING"
	if item.item_type == GameEnums.ItemType.WEAPON:
		return "DMG %.1f/%.1f  RNG %d" % [item.flesh_damage, item.stance_damage, item.effective_range]
	if item.item_type == GameEnums.ItemType.ARMOR:
		if item.capacity_bonus > 0:
			return "%s  CAP +%d" % [_slot_name(item.target_slot), item.capacity_bonus]
		return "%s  PRO %.1f/%.1f/%.1f" % [
			_slot_name(item.target_slot),
			item.protection_blunt,
			item.protection_sharp,
			item.protection_ballistic,
		]
	if item.item_type == GameEnums.ItemType.AMMUNITION:
		if item.is_magazine():
			return "MAG %d  %s" % [item.magazine_capacity, item.accepted_ammunition_id]
		return "AMMO  %s" % item.id
	if item.item_type == GameEnums.ItemType.CONSUMABLE:
		return "POTENCY %.1f" % item.consumable_potency
	if item.capacity_bonus > 0:
		return "STORAGE +%d" % item.capacity_bonus
	return "SIZE %d  COST %d" % [item.get_effective_item_size(), item.get_inventory_cost()]

func _item_detail_text(item: ItemData) -> String:
	if item == null:
		return ""
	var lines: Array[String] = [
		"%s  [%s]" % [item.display_name, _item_type_name(item.item_type)],
		"ID %s" % item.id,
		"RESOURCE %s" % item.resource_path,
		"TARGET %s  |  SIZE %s  |  COST %d  |  CAPACITY +%d" % [
			_slot_name(item.target_slot),
			_enum_name(GameEnums.ItemSize.keys(), item.get_effective_item_size()),
			item.get_inventory_cost(),
			item.capacity_bonus,
		],
	]
	if item.item_type == GameEnums.ItemType.WEAPON:
		lines.append("DAMAGE flesh %.1f / stance %.1f / penetration %.1f" % [
			item.flesh_damage,
			item.stance_damage,
			item.armor_penetration,
		])
		lines.append("RANGE optimal %d / effective %d  |  accuracy %.1f" % [
			item.optimal_range,
			item.effective_range,
			item.accuracy_rating,
		])
		lines.append("AMMO %s  |  MAGAZINE %s  |  CAPACITY %d" % [
			item.ammunition_id if not item.ammunition_id.is_empty() else "N/A",
			item.magazine_id if not item.magazine_id.is_empty() else "INTERNAL/N/A",
			item.max_magazine,
		])
	if item.item_type == GameEnums.ItemType.ARMOR:
		lines.append("PROTECTION blunt %.1f / sharp %.1f / ballistic %.1f" % [
			item.protection_blunt,
			item.protection_sharp,
			item.protection_ballistic,
		])
	lines.append("GEAR weight %.1f / bulk %.1f / threat %.1f / insulation %.1f" % [
		item.weight,
		item.bulk,
		item.threat,
		item.insulation,
	])
	if item.is_magazine():
		lines.append("MAGAZINE accepts %s / %d rounds" % [item.accepted_ammunition_id, item.magazine_capacity])
	if item.requires_two_hands:
		lines.append("REQUIREMENT // TWO FUNCTIONAL HANDS")
	if not item.compatible_weapon_ids.is_empty():
		lines.append("COMPATIBLE // " + ", ".join(item.compatible_weapon_ids))
	if not item.tags.is_empty():
		lines.append("TAGS // " + ", ".join(item.tags))
	if not item.lore_description.strip_edges().is_empty():
		lines.append(item.lore_description.strip_edges())
	return "\n".join(lines)

func _load_item(item_path: String) -> ItemData:
	if item_path.is_empty() or not ResourceLoader.exists(item_path):
		return null
	return load(item_path) as ItemData

func _load_item_icon(item: ItemData) -> Texture2D:
	if item == null:
		return null
	var path := item.get_inventory_sprite_path()
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _current_stage() -> WaveLoadoutStaging:
	return _enemy_stage if _target_enemy else _player_stage

func _item_type_name(item_type: int) -> String:
	return _enum_name(GameEnums.ItemType.keys(), item_type)

func _slot_name(slot: int) -> String:
	return _enum_name(GameEnums.EquipmentSlot.keys(), slot)

func _enum_name(keys: Array, index: int) -> String:
	if index < 0 or index >= keys.size():
		return "UNKNOWN"
	return str(keys[index]).replace("_", " ")

func _return_to_menu() -> void:
	get_tree().change_scene_to_file(PresentationSceneRegistry.MAIN_MENU_SCENE)

func _cleanup_arena() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
