extends RefCounted
class_name PresentationSceneRegistry

## Shared presentation scene paths. Runtime domains reference these when they
## need a scene transition, while GameEnums stays a closed gameplay vocabulary.

const MAIN_MENU_SCENE := "res://UI/MainMenu.tscn"
const PAPER_DOLL_SCENE := "res://UI/Inventory/PaperDollModel.tscn"
const HUMANOID_TOKEN_SCENE := "res://UI/Humanoid/HumanoidToken.tscn"
const INVENTORY_UI_SCENE := "res://UI/Inventory/InventoryUI.tscn"
const MACRO_HUD_SCENE := "res://UI/HUD/Macro/MacroHudShell.tscn"
const REALTIME_DUEL_SCENE := "res://CombatCore/MainDuelScene.tscn"
const TURN_BASED_DUEL_SCENE := "res://CombatCore/TurnBased/TurnBasedDuelScene.tscn"
const POCKET_INVENTORY_THEME := "res://UI/HUD/PocketInventoryTheme.tres"
