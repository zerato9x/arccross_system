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
	var consumed := service.consume_repair_material(record)
	if str(consumed.get("instance_id", "")) != "npc-material":
		_fail("NPC work did not consume the neutral repair material instance.")
		return
	var remaining: Dictionary = record.runtime["inventory_items"][1]
	if int(remaining.get("stack_count", 0)) != 1:
		_fail("NPC repair material consumption did not preserve the remaining stack.")
		return
	var receipt := WorldActionReceipt.new()
	receipt.method_id = "multitool"
	receipt.tool_wear = 0.25
	world_state.register_entity(record)
	service.apply_tool_wear(record, receipt)
	var tool: Dictionary = record.runtime["inventory_items"][0]
	if float(tool.get("current_condition", 0.0)) != 9.75:
		_fail("NPC tool wear did not apply to the neutral carried state.")
		return
	print("[MACRO_NPC_WORK] PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("[MACRO_NPC_WORK] " + message)
	quit(1)
