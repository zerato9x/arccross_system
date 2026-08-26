extends RefCounted
class_name WorldActionReceiptValidationService

## Pure receipt and optimistic-concurrency validation for the world-action
## application boundary. This service never mutates RuntimeStateStore.

const ALLOWED_MUTATION_TYPES := [
	"work_progress",
	"elapsed_time",
	"authored_effect",
	"target_damaged",
	"target_became_debris",
	"forced_entry",
	"dismantled",
	"consume_material",
	"transfer_ground_item",
	"drop_ground_item",
	"move_actor",
	"movement_trace",
	"set_hex_explored",
	"trap_armed",
	"medical_application",
	"inventory_action",
	"poi_selection_application",
	"camp_cycle_application",
	"search_application",
	"npc_work_application",
	"negotiation_application",
	"macro_event_application",
	"trade_application",
	"add_ground_item",
	"biological_hit",
	"append_trace",
	"door_open",
	"set_run_flag",
]

var store: RuntimeStateStore
var _inventory_transaction: WorldActionInventoryTransactionService
var _poi_selection_transaction: WorldActionPoiSelectionTransactionService
var _camp_transaction: WorldActionCampTransactionService
var _movement_transaction: WorldActionMovementTransactionService
var _search_transaction: WorldActionSearchTransactionService
var _npc_work_transaction: WorldActionNpcWorkTransactionService
var _negotiation_transaction: WorldActionNegotiationTransactionService
var _macro_event_transaction: WorldActionMacroEventTransactionService
var _trade_transaction: WorldActionTradeTransactionService


func configure(
	state: RuntimeStateStore,
	inventory_transaction: WorldActionInventoryTransactionService,
	poi_selection_transaction: WorldActionPoiSelectionTransactionService,
	camp_transaction: WorldActionCampTransactionService,
	movement_transaction: WorldActionMovementTransactionService,
	search_transaction: WorldActionSearchTransactionService,
	npc_work_transaction: WorldActionNpcWorkTransactionService,
	negotiation_transaction: WorldActionNegotiationTransactionService,
	macro_event_transaction: WorldActionMacroEventTransactionService,
	trade_transaction: WorldActionTradeTransactionService
) -> void:
	store = state
	_inventory_transaction = inventory_transaction
	_poi_selection_transaction = poi_selection_transaction
	_camp_transaction = camp_transaction
	_movement_transaction = movement_transaction
	_search_transaction = search_transaction
	_npc_work_transaction = npc_work_transaction
	_negotiation_transaction = negotiation_transaction
	_macro_event_transaction = macro_event_transaction
	_trade_transaction = trade_transaction


func validation_error(receipt: WorldActionReceipt) -> String:
	if store == null:
		return "RuntimeStateStore is unavailable."
	if receipt == null or not receipt.committed:
		return "World-action receipt is missing or uncommitted."
	var payload_error := payload_integrity_error(receipt)
	if not payload_error.is_empty():
		return payload_error
	if receipt.node_id != store.active_node_id:
		return "World-action receipt targets a different active node."
	var reservation := store.get_world_action_reservation(receipt.action_id)
	if reservation == null:
		return "World-action reservation is missing."
	if (
		reservation.actor_id != receipt.actor_id
		or reservation.target_id != receipt.target_id
		or reservation.node_id != receipt.node_id
		or reservation.target_coords != receipt.target_coords
	):
		return "World-action receipt does not match its reservation."
	if reservation.next_receipt_id() != receipt.receipt_id:
		return "World-action receipt attempt identity does not match its reservation."
	if receipt.expected_actor_revision != actor_revision(receipt.actor_id):
		return "World-action actor revision drifted before application."
	var hex := store.get_hex_record(receipt.target_coords)
	if hex == null or receipt.expected_hex_revision != hex.revision:
		return "World-action hex revision drifted before application."
	if not receipt.target_state.is_empty():
		var target := _world_object(hex, receipt.target_id)
		if target == null or target.revision != receipt.expected_target_revision:
			return "World-action target revision drifted before application."
	return ""


func payload_integrity_error(receipt: WorldActionReceipt) -> String:
	if receipt == null:
		return "World-action receipt is missing."
	if (
		receipt.receipt_id.is_empty()
		or receipt.action_id.is_empty()
		or receipt.actor_id.is_empty()
		or receipt.target_id.is_empty()
	):
		return "World-action receipt contains an empty identity."
	if receipt.elapsed_minutes < 0 or receipt.expected_actor_revision < 0:
		return "World-action receipt contains invalid timing or actor revision."
	if receipt.expected_hex_revision < 0:
		return "World-action receipt contains no expected hex revision."
	var consumed_ids: Dictionary = {}
	var transferred_ids: Dictionary = {}
	var medical_application_count := 0
	var ground_transfer_count := 0
	var ground_transfer_id := ""
	for mutation_value in receipt.mutations:
		if not mutation_value is Dictionary:
			return "World-action receipt contains a malformed mutation."
		var mutation: Dictionary = mutation_value
		var mutation_type := str(mutation.get("type", ""))
		if mutation_type not in ALLOWED_MUTATION_TYPES:
			return "World-action receipt contains an unsupported mutation: %s" % mutation_type
		if mutation_type == "consume_material":
			var instance_id := str(mutation.get("instance_id", ""))
			if instance_id.is_empty() or consumed_ids.has(instance_id):
				return "World-action receipt contains a duplicate or empty consumed item."
			consumed_ids[instance_id] = true
		elif mutation_type == "medical_application":
			medical_application_count += 1
			var instance_id := str(mutation.get("instance_id", ""))
			var limb_region := int(mutation.get("limb_region", -1))
			if (
				instance_id.is_empty()
				or receipt.target_id != instance_id
				or limb_region not in GameEnums.LimbRegion.values()
			):
				return "World-action medical mutation is malformed."
		elif mutation_type in ["transfer_ground_item", "drop_ground_item"]:
			var instance_id := str(mutation.get("instance_id", ""))
			if instance_id.is_empty() or transferred_ids.has(instance_id):
				return "World-action receipt contains a duplicate or empty transferred item."
			if mutation_type == "drop_ground_item":
				var item_state: Variant = mutation.get("item_state", {})
				if not item_state is Dictionary or str(item_state.get("instance_id", "")) != instance_id:
					return "World-action drop mutation has malformed item state."
			else:
				ground_transfer_count += 1
				ground_transfer_id = instance_id
			transferred_ids[instance_id] = true
		elif mutation_type == "move_actor":
			if mutation.get("to", receipt.target_coords) != receipt.target_coords:
				return "World-action movement destination does not match the receipt."
		elif mutation_type == "movement_trace":
			var trace: Variant = mutation.get("trace", {})
			if not trace is Dictionary or trace.is_empty():
				return "World-action movement trace is malformed."
		elif mutation_type == "append_trace":
			var trace: Variant = mutation.get("trace", {})
			if not trace is Dictionary or trace.is_empty():
				return "World-action trace is malformed."
		elif mutation_type == "add_ground_item":
			var item_state: Variant = mutation.get("item_state", {})
			var instance_id := str(item_state.get("instance_id", "")) if item_state is Dictionary else ""
			if instance_id.is_empty() or transferred_ids.has(instance_id):
				return "World-action ground insertion has a duplicate or empty item identity."
			transferred_ids[instance_id] = true
		elif mutation_type == "biological_hit":
			if float(mutation.get("damage", 0.0)) < 0.0:
				return "World-action biological hit has invalid damage."
	if medical_application_count > 0:
		if medical_application_count != 1:
			return "World-action receipt contains duplicate medical applications."
		if receipt.actor_id != "player":
			return "World-action medical treatment only supports the player actor."
		if receipt.verb_id != "treat" or receipt.method_id != "medical_item":
			return "World-action medical treatment has the wrong verb or method."
		if not consumed_ids.is_empty():
			return "World-action medical treatment contains conflicting actor mutations."
	if ground_transfer_count > 0:
		if (
			ground_transfer_count != 1
			or receipt.actor_id == "player"
			or receipt.verb_id != "pick_up"
			or receipt.target_id != ground_transfer_id
		):
			return "World-action neutral pickup mutation is malformed."
		for mutation in receipt.mutations:
			if str(mutation.get("type", "")) in [
				"consume_material",
				"drop_ground_item",
				"inventory_action",
				"poi_selection_application",
				"camp_cycle_application",
				"search_application",
				"npc_work_application",
				"negotiation_application",
				"macro_event_application",
				"trade_application",
				"add_ground_item",
			]:
				return "World-action neutral pickup contains a conflicting mutation."
	for transaction in [
		_inventory_transaction,
		_poi_selection_transaction,
		_camp_transaction,
		_movement_transaction,
		_search_transaction,
		_npc_work_transaction,
		_negotiation_transaction,
		_macro_event_transaction,
		_trade_transaction,
	]:
		if transaction == null:
			return "World-action validation transaction is unavailable."
		var semantic_error: String = transaction.validation_error(receipt)
		if not semantic_error.is_empty():
			return semantic_error
	var signal_ids: Dictionary = {}
	for signal_value in receipt.signals:
		if not signal_value is Dictionary:
			return "World-action receipt contains a malformed signal."
		var signal_id := str(signal_value.get("signal_id", ""))
		if signal_id.is_empty() or signal_ids.has(signal_id):
			return "World-action receipt contains a duplicate or empty signal identity."
		signal_ids[signal_id] = true
	if not receipt.target_state.is_empty():
		if str(receipt.target_state.get("object_id", "")) != receipt.target_id:
			return "World-action receipt target state has the wrong identity."
		if int(receipt.target_state.get("revision", -1)) != receipt.expected_target_revision:
			return "World-action receipt target state has the wrong source revision."
	return ""


func actor_revision(actor_id: String) -> int:
	if store == null:
		return -1
	if actor_id == "player":
		return store.player_record.revision if store.player_record != null else -1
	return int(store.get_entity_snapshot(actor_id).get("revision", -1))


func _world_object(hex: HexRecord, object_id: String) -> WorldObjectRecord:
	if hex == null:
		return null
	for value in hex.world_objects:
		if value is Dictionary and str(value.get("object_id", "")) == object_id:
			return WorldObjectRecord.from_dict(value)
	return null
