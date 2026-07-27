extends Control
class_name NewRunIntro

enum Step { IDENTITY, CONFIRMATION, EVICTION, DEPARTURE }

const FLOW_PATH := "res://UI/Intro/opening_flow.tres"

@onready var _title: Label = $Backdrop/PageMargin/Page/TitleLabel
@onready var _step_label: Label = $Backdrop/PageMargin/Page/StepLabel
@onready var _body: Label = $Backdrop/PageMargin/Page/BodyLabel
@onready var _identity_panel: VBoxContainer = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/IdentityPanel
@onready var _message_panel: VBoxContainer = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/MessagePanel
@onready var _message_text: RichTextLabel = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/MessagePanel/MessageText
@onready var _departure_panel: HBoxContainer = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/DeparturePanel
@onready var _departure_graph: Control = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/DeparturePanel/DepartureGraph
@onready var _selected_node_label: Label = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/DeparturePanel/DepartureSide/SelectedNodeLabel
@onready var _occupation_option: OptionButton = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/IdentityPanel/OccupationOption
@onready var _occupation_summary: Label = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/IdentityPanel/OccupationSummary
@onready var _trait_option: OptionButton = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/IdentityPanel/TraitOption
@onready var _trait_summary: Label = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/IdentityPanel/TraitSummary
@onready var _flaw_option: OptionButton = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/IdentityPanel/FlawOption
@onready var _flaw_summary: Label = $Backdrop/PageMargin/Page/ContentPanel/ContentMargin/IdentityPanel/FlawSummary
@onready var _error_label: Label = $Backdrop/PageMargin/Page/ErrorLabel
@onready var _back_button: Button = $Backdrop/PageMargin/Page/Actions/BackButton
@onready var _next_button: Button = $Backdrop/PageMargin/Page/Actions/NextButton

var _flow: OpeningFlowDefinition
var _step: Step = Step.IDENTITY
var _selected_start_node_id: String = ""
var _committed := false


func _ready() -> void:
	_flow = load(FLOW_PATH) as OpeningFlowDefinition
	if _flow == null:
		_error_label.text = "Opening flow data is unavailable."
		_next_button.disabled = true
		return
	_populate_option(_occupation_option, IdentityCatalog.all_occupation_descriptors())
	_populate_option(_trait_option, IdentityCatalog.all_trait_descriptors())
	_populate_option(_flaw_option, IdentityCatalog.all_flaw_descriptors())
	_occupation_option.item_selected.connect(func(_index: int): _refresh_identity_summaries())
	_trait_option.item_selected.connect(func(_index: int): _refresh_identity_summaries())
	_flaw_option.item_selected.connect(func(_index: int): _refresh_identity_summaries())
	_back_button.pressed.connect(_on_back_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_departure_graph.connect("node_selected", _on_departure_node_selected)
	HUDAssetLibrary.apply_button(_back_button)
	HUDAssetLibrary.apply_button(_next_button, "pass")
	_refresh_identity_summaries()
	_show_step(Step.IDENTITY)
	var bus := get_node_or_null("/root/GameEventBus")
	if bus != null and bus.has_method("emit_scene_audio"):
		bus.emit_scene_audio("silent")


func _populate_option(option: OptionButton, descriptors: Array) -> void:
	option.clear()
	for descriptor_value in descriptors:
		if not descriptor_value is Dictionary:
			continue
		var descriptor: Dictionary = descriptor_value
		option.add_item(str(descriptor.get("display_name", descriptor.get("id", "Unknown"))))
		option.set_item_metadata(option.item_count - 1, str(descriptor.get("id", "")))
	if option.item_count > 0:
		option.select(0)


func _selected_id(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _refresh_identity_summaries() -> void:
	_occupation_summary.text = str(IdentityCatalog.occupation_descriptor(
		_selected_id(_occupation_option)).get("summary", ""))
	_trait_summary.text = str(IdentityCatalog.trait_descriptor(
		_selected_id(_trait_option)).get("summary", ""))
	_flaw_summary.text = str(IdentityCatalog.flaw_descriptor(
		_selected_id(_flaw_option)).get("summary", ""))


func _show_step(step: Step) -> void:
	_step = step
	_error_label.text = ""
	_identity_panel.visible = step == Step.IDENTITY
	_message_panel.visible = step in [Step.CONFIRMATION, Step.EVICTION]
	_departure_panel.visible = step == Step.DEPARTURE
	_step_label.text = "STEP %d / 4" % (int(step) + 1)
	_back_button.text = "CANCEL" if step == Step.IDENTITY else "BACK"
	match step:
		Step.IDENTITY:
			_title.text = _flow.identity_title
			_body.text = _flow.identity_body
			_next_button.text = "REVIEW RECORD"
		Step.CONFIRMATION:
			_title.text = _flow.confirmation_title
			_body.text = _flow.confirmation_body
			_message_text.text = _identity_summary_text()
			_next_button.text = "ACCEPT EVICTION ORDER"
		Step.EVICTION:
			_title.text = _flow.eviction_title
			_body.text = _flow.eviction_body
			var occupation := IdentityCatalog.occupation_descriptor(_selected_id(_occupation_option))
			_message_text.text = "[b]%s FILE[/b]\n\n%s\n\nCENTRAL NODE ACCESS: REVOKED" % [
				str(occupation.get("display_name", "Occupation")).to_upper(),
				str(occupation.get("exile_text", "Your access is revoked.")),
			]
			_next_button.text = "SELECT DEPARTURE"
		Step.DEPARTURE:
			_title.text = _flow.departure_title
			_body.text = _flow.departure_body
			_next_button.text = "BEGIN EXILE"
			_next_button.disabled = _selected_start_node_id.is_empty()
			_departure_graph.call("prepare_open")
			_departure_graph.call("apply_snapshot", NewRunDepartureSnapshot.build(_flow.world_seed))
			_departure_graph.call_deferred("reset_camera")


func _identity_summary_text() -> String:
	var occupation := IdentityCatalog.occupation_descriptor(_selected_id(_occupation_option))
	var trait_entry := IdentityCatalog.trait_descriptor(_selected_id(_trait_option))
	var flaw_entry := IdentityCatalog.flaw_descriptor(_selected_id(_flaw_option))
	return "[b]OCCUPATION[/b]  %s\n%s\n\n[b]TRAIT[/b]  %s\n%s\n\n[b]FLAW[/b]  %s\n%s" % [
		occupation.get("display_name", ""), occupation.get("summary", ""),
		trait_entry.get("display_name", ""), trait_entry.get("summary", ""),
		flaw_entry.get("display_name", ""), flaw_entry.get("summary", ""),
	]


func _on_back_pressed() -> void:
	if _committed:
		return
	if _step == Step.IDENTITY:
		get_tree().change_scene_to_file(_flow.menu_scene_path)
	else:
		_show_step((int(_step) - 1) as Step)


func _on_next_pressed() -> void:
	if _committed:
		return
	if _step == Step.DEPARTURE:
		_finalize_new_run()
	else:
		_show_step((int(_step) + 1) as Step)


func _on_departure_node_selected(node_id: String) -> void:
	if not MacroGraphGenerator.allowed_start_node_ids().has(node_id):
		_selected_node_label.text = "That node is not an adjacent departure point."
		return
	_selected_start_node_id = node_id
	var graph := MacroGraphGenerator.generate_web(_flow.world_seed)
	var node := graph.get_node(node_id)
	_selected_node_label.text = "DEPLOY TO\n%s" % (
		node.display_name if node != null else node_id
	)
	_next_button.disabled = false


func _finalize_new_run() -> void:
	if _selected_start_node_id.is_empty():
		return
	var setup := NewRunSetup.new()
	setup.world_seed = _flow.world_seed
	setup.base_definition_path = _flow.base_player_definition_path
	setup.occupation_id = _selected_id(_occupation_option)
	setup.trait_ids = PackedStringArray([_selected_id(_trait_option)])
	setup.flaw_ids = PackedStringArray([_selected_id(_flaw_option)])
	setup.start_node_id = _selected_start_node_id
	setup.arrival_direction = MacroGraphGenerator.arrival_direction_for_start(_selected_start_node_id)
	setup.intro_version = _flow.intro_version
	var save_service := get_node_or_null("/root/SaveLoadService")
	if save_service == null:
		_error_label.text = "Save/load service is unavailable."
		return
	var failures: PackedStringArray = save_service.begin_new_world_from_setup(
		setup,
		MacroGraphGenerator.allowed_start_node_ids()
	)
	if not failures.is_empty():
		_error_label.text = "\n".join(failures)
		return
	_committed = true
	_back_button.disabled = true
	_next_button.disabled = true
	get_tree().change_scene_to_file(_flow.game_scene_path)
