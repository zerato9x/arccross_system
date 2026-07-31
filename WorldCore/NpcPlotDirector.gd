extends Resource
class_name NpcPlotDirector

const DEFAULT_PATH := "res://WorldCore/npc_plot_deployments.tres"

@export var deployments: Array[NpcPlotDeploymentDefinition] = []


func eligible_deployment(
	codex_ids: Array,
	node_id: String,
	run_flags: Dictionary
) -> NpcPlotDeploymentDefinition:
	for deployment in deployments:
		if deployment != null and deployment.is_eligible(codex_ids, node_id, run_flags):
			return deployment
	return null


static func data() -> NpcPlotDirector:
	return load(DEFAULT_PATH) as NpcPlotDirector
