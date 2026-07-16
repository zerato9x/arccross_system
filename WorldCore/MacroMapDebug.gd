extends RefCounted
class_name MacroMapDebug

## ASCII / listing helpers for campaign graph + active zone.


static func print_graph(graph: MacroMapGraph) -> String:
	if graph == null:
		return "(null graph)"
	return graph.debug_print()


static func print_zone(zone: MacroZoneGenerator) -> String:
	if zone == null:
		return "(null zone)"
	return zone.debug_ascii()


static func print_campaign(progress: MacroProgressController) -> String:
	if progress == null:
		return "(null progress)"
	return progress.debug_print_map()
