extends RefCounted
class_name PresentationSceneRegistry

## Shared presentation scene paths. Runtime domains reference these when they
## need a scene transition, while GameEnums stays a closed gameplay vocabulary.

const MAIN_MENU_SCENE := "res://UI/MainMenu.tscn"
const GAME_SCENE := "res://SystemCore/game_director.tscn"
const PAPER_DOLL_SCENE := "res://UI/Inventory/PaperDollModel.tscn"
const HUMANOID_TOKEN_SCENE := "res://UI/Humanoid/HumanoidToken.tscn"
const INVENTORY_UI_SCENE := "res://UI/Inventory/InventoryUI.tscn"
const MACRO_HUD_SCENE := "res://UI/HUD/Macro/MacroHudShell.tscn"
const TACTICAL_COMBAT_SCENE := "res://CombatCore/Tactical/TacticalCombatScene.tscn"
const POCKET_INVENTORY_THEME := "res://UI/HUD/PocketInventoryTheme.tres"


static func load_scene(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


static func instantiate_scene(path: String) -> Node:
	var scene := load_scene(path)
	return scene.instantiate() if scene != null else null
