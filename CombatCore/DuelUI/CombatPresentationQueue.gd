extends Node
class_name CombatPresentationQueue

## Ordered combat presentation queue extracted from CombatLaneHUD.
##
## Presentation timing is intentionally independent of the HUD frame.  Keep
## combat events ordered so movement/impact animations finish before snapshots
## replace the actors underneath them.

signal presentation_queue_drained

var _presentation_queue: Array[Dictionary] = []
var _is_processing_queue: bool = false

var _apply_snapshot: Callable = Callable()
var _apply_reaction: Callable = Callable()
var _apply_feedback: Callable = Callable()
var _apply_presentation_event: Callable = Callable()

func configure(
	apply_snapshot: Callable,
	apply_reaction: Callable,
	apply_feedback: Callable,
	apply_presentation_event: Callable
) -> void:
	_apply_snapshot = apply_snapshot
	_apply_reaction = apply_reaction
	_apply_feedback = apply_feedback
	_apply_presentation_event = apply_presentation_event

func show_snapshot(snapshot: Dictionary) -> void:
	_presentation_queue.append({ "type": "snapshot", "data": snapshot.duplicate(true) })
	_try_process_queue()

func show_reaction(prompt: Dictionary) -> void:
	_presentation_queue.append({ "type": "reaction", "data": prompt.duplicate(true) })
	_try_process_queue()

func show_feedback(message: String) -> void:
	_presentation_queue.append({ "type": "feedback", "data": message })
	_try_process_queue()

func show_presentation_event(event: Dictionary) -> void:
	_presentation_queue.append({ "type": "presentation", "data": event.duplicate(true) })
	_try_process_queue()

func is_busy() -> bool:
	return _is_processing_queue or not _presentation_queue.is_empty()

func clear() -> void:
	_presentation_queue.clear()

func wait_for_presentation_idle() -> void:
	# Always yield once so events emitted in the current resolution stack can
	# enter the queue before we decide it is empty.
	await get_tree().process_frame
	while _is_processing_queue or not _presentation_queue.is_empty():
		await get_tree().process_frame

func _try_process_queue() -> void:
	if _is_processing_queue or _presentation_queue.is_empty():
		return
	_is_processing_queue = true
	_process_queue()

func _process_queue() -> void:
	while not _presentation_queue.is_empty():
		var item: Dictionary = _presentation_queue.pop_front()
		match str(item.get("type", "")):
			"snapshot":
				@warning_ignore("redundant_await")
				await _apply_snapshot.call(item.get("data", {}))
			"reaction":
				_apply_reaction.call(item.get("data", {}))
			"feedback":
				_apply_feedback.call(item.get("data", ""))
			"presentation":
				@warning_ignore("redundant_await")
				await _apply_presentation_event.call(item.get("data", {}))
				await get_tree().create_timer(_presentation_delay(item.get("data", {}))).timeout
	_is_processing_queue = false
	presentation_queue_drained.emit()

func _presentation_delay(event: Dictionary) -> float:
	if str(event.get("type", "")) == "shot":
		return 0.05
	return 0.08
