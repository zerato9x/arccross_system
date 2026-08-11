extends Resource
class_name OpeningFlowDefinition

const PRESENTATION_SCENES := preload("res://PresentationCore/PresentationSceneRegistry.gd")

@export var flow_id: String = "central_eviction_v1"
@export var intro_version: int = 1
@export var world_seed: String = "ARCCROSS_DIRECTIONAL_WEB_01"
@export_file("*.tres") var identity_catalog_path: String = "res://BiologicalCore/Identity/identity_catalog.tres"
@export_file("*.tres") var campaign_definition_path: String = "res://WorldCore/campaign_graph.tres"
@export_file("*.tres") var base_player_definition_path: String = "res://BiologicalCore/player_def.tres"
@export_file("*.tscn") var game_scene_path: String = PRESENTATION_SCENES.GAME_SCENE
@export_file("*.tscn") var menu_scene_path: String = PRESENTATION_SCENES.MAIN_MENU_SCENE
@export var identity_title: String = "CENTRAL PERSONNEL RECORD"
@export_multiline var identity_body: String = "Confirm the three entries Central permits you to retain. Pillars and appearance are not editable during expulsion processing."
@export var confirmation_title: String = "RECORD CONFIRMATION"
@export_multiline var confirmation_body: String = "This identity is written into the character record when you accept the eviction order."
@export var eviction_title: String = "ACCESS REVOKED"
@export_multiline var eviction_body: String = "Central has closed your ration account and revoked access to the hub interior. Regional infrastructure restoration is the only accepted route of appeal."
@export_group("Eviction Staging")
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var eviction_background_path: String
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var eviction_npc_portrait_path: String
@export var eviction_speaker_name: String = "CENTRAL EVICTION CLERK"
@export_multiline var eviction_dialogue: String = "Unfortunately for you, you've won Central's eviction lottery. Your access is revoked. Collect your assigned kit, choose a gate, and good luck out there."
@export_group("")
@export var departure_title: String = "SELECT DEPARTURE NODE"
@export_multiline var departure_body: String = "Choose any adjacent Route 1 zone. The inner ring is open; only the northern route continues into deeper territory."
