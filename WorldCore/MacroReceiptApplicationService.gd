extends RefCounted
class_name MacroReceiptApplicationService

## World-facing adapter around the SystemCore atomic application boundary.
## This class prepares compatibility receipts and performs post-commit
## projection/presentation only; it never mutates authoritative runtime state.

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var player_token: MacroPlayer
var notify_signal: Callable
var emit_presentation: Callable
var refresh_hud: Callable
var diagnostic_callback: Callable
var _application_service := WorldActionApplicationService.new()


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	player: MacroPlayer,
	signal_notifier: Callable = Callable(),
	_tool_wear_applier: Callable = Callable(),
	presentation_emitter: Callable = Callable(),
	hud_refresher: Callable = Callable(),
	diagnostics: Callable = Callable()
) -> void:
	world_state = state
	world_generator = generator
	player_token = player
	notify_signal = signal_notifier
	emit_presentation = presentation_emitter
	refresh_hud = hud_refresher
	diagnostic_callback = diagnostics
	_application_service.configure(state, diagnostics)


func commit(
	receipt: WorldActionReceipt,
	coords: Vector2i,
	target: WorldObjectRecord = null,
	actor_id: String = "player"
) -> WorldActionApplicationReceipt:
	var rejected := WorldActionApplicationReceipt.new()
	if receipt == null or not receipt.committed or world_state == null:
		rejected.error = "World-action receipt is unavailable."
		return rejected
	_prepare_receipt(receipt, coords, target, actor_id)
	var application := _application_service.apply(receipt)
	if not application.applied:
		return application

	_debug_mark("receipt projection start")
	if world_generator != null:
		world_generator.refresh_hex_projection(coords)
		for signal_value in receipt.signals:
			if signal_value is Dictionary:
				world_generator.refresh_hex_projection(
					signal_value.get("coords", coords)
				)
	_debug_mark("receipt projection end")
	if actor_id == "player" and player_token != null and world_state.player_record != null:
		_debug_mark("receipt player projection start")
		player_token.restore_runtime_record(world_state.player_record)
		# Travel already owns its authored walk animation. Replacing it with a
		# generic action cue at the receipt boundary is the classic "arrived but
		# frozen" presentation race.
		if receipt.verb_id != "travel":
			player_token.play_action_cue(receipt.verb_id)
		_debug_mark("receipt player projection end")
	_debug_mark("receipt signal fanout start")
	for signal_value in receipt.signals:
		if notify_signal.is_valid() and signal_value is Dictionary:
			notify_signal.call(WorldSignalRecord.from_dict(signal_value))
	_debug_mark("receipt signal fanout end")
	_debug_mark("receipt presentation start")
	if emit_presentation.is_valid():
		var presentation_receipt := receipt.to_dict()
		presentation_receipt["coords"] = coords
		presentation_receipt["application"] = application.to_dict()
		var presentation: Dictionary = presentation_receipt.get(
			"presentation",
			{}
		).duplicate(true)
		presentation["player_visible"] = actor_id == "player"
		presentation["audio_policy"] = "player" if actor_id == "player" else "silent"
		presentation_receipt["presentation"] = presentation
		emit_presentation.call(presentation_receipt)
	_debug_mark("receipt presentation end")
	_debug_mark("receipt HUD refresh start")
	if refresh_hud.is_valid():
		refresh_hud.call()
	_debug_mark("receipt HUD refresh end")
	return application


func _debug_mark(label: String) -> void:
	if diagnostic_callback.is_valid():
		diagnostic_callback.call(label)


func _prepare_receipt(
	receipt: WorldActionReceipt,
	coords: Vector2i,
	target: WorldObjectRecord,
	actor_id: String
) -> void:
	receipt.actor_id = actor_id
	receipt.target_coords = coords
	receipt.node_id = world_state.active_node_id
	var hex := world_state.get_hex_record(coords)
	receipt.expected_hex_revision = hex.revision if hex != null else -1
	if receipt.expected_actor_revision < 0:
		receipt.expected_actor_revision = (
			world_state.player_record.revision
			if actor_id == "player" and world_state.player_record != null
			else int(world_state.get_entity_snapshot(actor_id).get("revision", -1))
		)
	if target != null:
		receipt.target_id = target.object_id
		if receipt.expected_target_revision < 0:
			receipt.expected_target_revision = target.revision
		receipt.target_state = target.to_dict()
	# An absent action_id starts a new session. Let RuntimeStateStore assign the
	# unique namespace; explicit IDs remain the replay/continuation contract.
	var reservation: WorldActionReservationRecord = null
	if not receipt.action_id.is_empty():
		reservation = world_state.get_world_action_reservation(receipt.action_id)
	if reservation == null:
		var request := WorldActionRequest.new()
		request.actor_id = receipt.actor_id
		request.target_id = receipt.target_id
		request.target_coords = receipt.target_coords
		request.verb_id = receipt.verb_id
		request.method_id = receipt.method_id
		request.expected_actor_revision = receipt.expected_actor_revision
		request.expected_target_revision = receipt.expected_target_revision
		request.payload = {
			"expected_hex_revision": receipt.expected_hex_revision,
		}
		if not receipt.action_id.is_empty():
			request.payload["action_id"] = receipt.action_id
		reservation = world_state.begin_world_action(request)
	if reservation != null:
		receipt.action_id = reservation.action_id
		receipt.receipt_id = reservation.next_receipt_id()
