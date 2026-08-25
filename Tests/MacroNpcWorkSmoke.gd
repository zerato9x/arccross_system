extends SceneTree

const _NpcWorkService := preload("res://WorldCore/MacroNpcWorkService.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_state := RuntimeStateStore.new()
	world_state.begin_new_world("NPC_WORK_SMOKE")
	var record := EntityRecord.new()
	record.entity_id = "npc_work_smoke"
	record.definition = {
		"finesse": 9,
		"loadout": {
			"weapon": "res://ItemCore/Items/multitool.tres",
			"starting_items": ["res://ItemCore/Items/scrap.tres"],
		},
	}
	record.runtime = {
		"inventory_items": [
			{
				"instance_id": "npc-tool",
				"definition": {"id": "multitool", "functional_roles": [], "tags": []},
				"current_condition": 10.0,
			},
			{
				"instance_id": "npc-material",
				"definition": {
					"id": "scrap",
					"functional_roles": ["repair_material"],
					"tags": [],
				},
				"stack_count": 2,
			},
		],
	}
	var service := _NpcWorkService.new()
	service.configure(world_state, null, null, null)
	var context := service.actor_context(record)
	if not context.get("capabilities", []).has("repair_tool"):
		_fail("NPC work context did not resolve the authored multitool capability.")
		return
	if not context.get("capabilities", []).has("material"):
		_fail("NPC work context did not resolve neutral repair material state.")
		return
	if service.method_for_record(record) != "multitool":
		_fail("NPC work method did not select the usable multitool.")
		return
	var selected_material := service.select_repair_material(record)
	if str(selected_material.get("instance_id", "")) != "npc-material":
		_fail("NPC work did not select the neutral repair material instance.")
		return
	print("[MACRO_NPC_WORK] PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("[MACRO_NPC_WORK] " + message)
	quit(1)
