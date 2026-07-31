extends Resource
class_name SearchSiteCatalog

const DEFAULT_PATH := "res://WorldCore/search_sites.tres"

@export var sites: Array[SearchSiteDefinition] = []


func get_site(site_id: String) -> SearchSiteDefinition:
	for site in sites:
		if site != null and site.site_id == site_id:
			return site
	return null


func descriptor(site_id: String) -> Dictionary:
	var site := get_site(site_id)
	return site.to_descriptor() if site != null else {}


func assignment_ids_for_arm(arm_id: String) -> Array[String]:
	var matching: Array[SearchSiteDefinition] = []
	for site in sites:
		if site != null and site.assignment_arm_ids.has(arm_id):
			matching.append(site)
	matching.sort_custom(func(a: SearchSiteDefinition, b: SearchSiteDefinition) -> bool:
		if a.assignment_order == b.assignment_order:
			return a.site_id < b.site_id
		return a.assignment_order < b.assignment_order
	)
	var assigned: Array[String] = []
	for site in matching:
		for _copy_index in range(site.assignment_count):
			assigned.append(site.site_id)
	return assigned


func validate() -> PackedStringArray:
	var failures := PackedStringArray()
	var seen: Dictionary = {}
	for site in sites:
		if site == null or site.site_id.is_empty():
			failures.append("Search site has no ID.")
			continue
		if seen.has(site.site_id):
			failures.append("Duplicate search site: %s" % site.site_id)
		seen[site.site_id] = true
		if site.loot_profile_id.is_empty():
			failures.append("Search site %s has no loot profile." % site.site_id)
	return failures


static func data() -> SearchSiteCatalog:
	return load(DEFAULT_PATH) as SearchSiteCatalog
