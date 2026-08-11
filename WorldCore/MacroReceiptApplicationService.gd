extends RefCounted
class_name MacroReceiptApplicationService

## Applies a committed neutral world-action receipt at the application boundary.
## The rule kernel decides what happened; this service is the only place that
## fans that receipt into persistence, time, NPC perception, and presentation.

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var player_token: MacroPlayer
var notify_signal: Callable
var apply_player_tool_wear: Callable
var emit_presentation: Callable
var refresh_hud: Callable


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	player: MacroPlayer,
	signal_notifier: Callable = Callable(),
	tool_wear_applier: Callable = Callable(),
	presentation_emitter: Callable = Callable(),
	hud_refresher: Callable = Callable()
) -> void:
	world_state = state
	world_generator = generator
	player_token = player
	notify_signal = signal_notifier
	apply_player_tool_wear = tool_wear_applier
	emit_presentation = presentation_emitter
	refresh_hud = hud_refresher


func commit(
	receipt: WorldActionReceipt,
	coords: Vector2i,
	target: WorldObjectRecord = null,
	actor_id: String = "player"
) -> void:
	if receipt == null or not receipt.committed or world_state == null:
		return
	for signal_value in receipt.signals:
		var signal_record: WorldSignalRecord = WorldSignalRecord.from_dict(signal_value)
		if signal_record == null:
			continue
		world_state.register_world_signal(signal_record)
		var signal_hex := world_generator.get_hex_at(signal_record.coords)
		signal_hex.world_signals.append(signal_record.to_dict())
		world_state.set_hex_record(signal_record.coords, signal_hex.to_state())
		if notify_signal.is_valid():
			notify_signal.call(signal_record)

	var elapsed := maxi(0, receipt.elapsed_minutes)
	world_state.advance_world_time(elapsed)
	# The shared receipt owns elapsed time for both player and AI work. Keep the
	# player's biological state on that same clock instead of letting search or
	# repair silently skip hunger, thirst, fatigue, and exertion.
	if actor_id == "player" and elapsed > 0 and player_token != null:
		var player_core := player_token.get_humanoid_core()
		if player_core != null:
			player_core.process_survival_time(
				elapsed,
				15.0,
				maxf(0.1, receipt.exertion),
				float(receipt.presentation.get("insulation_bonus", 0.0))
			)

	if target != null:
		target.revision += 1
		target.last_simulated_minute = world_state.world_time_minutes
		var target_hex := world_generator.get_hex_at(coords)
		for index in range(target_hex.world_objects.size()):
			var object_value: Dictionary = target_hex.world_objects[index]
			if str(object_value.get("object_id", "")) != target.object_id:
				continue
			target_hex.world_objects[index] = target.to_dict()
			break
		world_state.set_hex_record(coords, target_hex.to_state())

	world_state.prune_world_signals()
	if actor_id == "player":
		if apply_player_tool_wear.is_valid():
			apply_player_tool_wear.call(receipt)
		if player_token != null:
			player_token.play_action_cue(receipt.verb_id)

	if emit_presentation.is_valid():
		var presentation_receipt := receipt.to_dict()
		presentation_receipt["coords"] = coords
		emit_presentation.call(presentation_receipt)

	if actor_id == "player":
		if player_token != null and player_token.get_humanoid_core() != null:
			world_state.update_player_runtime(
				player_token.get_humanoid_core().capture_runtime_state().to_dict(),
				player_token.current_hex_coords
			)
	else:
		var actor_snapshot := world_state.get_entity_snapshot(actor_id)
		if not actor_snapshot.is_empty():
			var actor_record := EntityRecord.from_dict(actor_snapshot)
			actor_record.last_simulated_minute = world_state.world_time_minutes
			actor_record.revision += 1
			world_state.patch_entity_record(actor_id, {
				"runtime": actor_record.runtime.duplicate(true),
				"revision": actor_record.revision,
				"last_simulated_minute": actor_record.last_simulated_minute,
			})
	if refresh_hud.is_valid():
		refresh_hud.call()
