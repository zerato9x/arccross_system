extends RefCounted
class_name MacroWorldActionCoordinator

## Macro application adapter for the shared world-action kernel. The manager
## retains its old entry points, while player and NPC callers use this one seam.

var kernel: WorldActionKernel


func configure(action_kernel: WorldActionKernel) -> void:
	kernel = action_kernel


func profile_for_id(profile_id: String) -> WorldWorkTaskProfile:
	return kernel.profile_for_id(profile_id) if kernel != null else null


func apply_method_profile(profile: WorldWorkTaskProfile, method_id: String) -> void:
	if kernel != null:
		kernel.apply_method_profile(profile, method_id)


func method_ids() -> PackedStringArray:
	return kernel.method_ids() if kernel != null else PackedStringArray()


func query_affordances(
	actor_context: Dictionary,
	target: WorldObjectRecord
) -> Array[WorldAffordance]:
	return kernel.query_affordances(actor_context, target) if kernel != null else []


func build_preview(
	request: WorldActionRequest,
	affordance: WorldAffordance,
	actor_context: Dictionary,
	target_context: Dictionary,
	task_profile: WorldWorkTaskProfile = null
) -> WorldActionPreview:
	return kernel.build_preview(
		request,
		affordance,
		actor_context,
		target_context,
		task_profile
	) if kernel != null else WorldActionPreview.new()


func resolve_work_attempt(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile,
	work_state: Dictionary,
	hit_success_window: bool,
	severe_miss: bool = false
) -> WorldActionReceipt:
	return kernel.resolve_work_attempt(
		request,
		profile,
		work_state,
		hit_success_window,
		severe_miss
	) if kernel != null else WorldActionReceipt.new()


func resolve_ai_work(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile,
	actor_context: Dictionary,
	work_state: Dictionary,
	seed: int
) -> WorldActionReceipt:
	return kernel.resolve_ai_work(
		request,
		profile,
		actor_context,
		work_state,
		seed
	) if kernel != null else WorldActionReceipt.new()


func resolve_direct_action(
	request: WorldActionRequest,
	elapsed_minutes: int,
	exertion: float = 0.0,
	noise_intensity: float = 0.0,
	message: String = "Action committed."
) -> WorldActionReceipt:
	return kernel.resolve_direct_action(
		request,
		elapsed_minutes,
		exertion,
		noise_intensity,
		message
	) if kernel != null else WorldActionReceipt.new()


func commit(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile = null,
	work_state: Dictionary = {},
	hit_success_window: bool = true,
	severe_miss: bool = false
) -> WorldActionReceipt:
	return kernel.commit(
		request,
		profile,
		work_state,
		hit_success_window,
		severe_miss
	) if kernel != null else WorldActionReceipt.new()


func apply_receipt(
	receipt: WorldActionReceipt,
	target_state: Dictionary = {}
) -> Dictionary:
	return kernel.apply_receipt(receipt, target_state) if kernel != null else target_state.duplicate(true)


func apply_work_consequences(
	target: WorldObjectRecord,
	verb_id: String,
	receipt: WorldActionReceipt
) -> void:
	if kernel != null:
		kernel.apply_work_consequences(target, verb_id, receipt)
