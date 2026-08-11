@tool
extends "res://SystemCore/NpcBehaviorProfileCatalog.gd"
class_name WorldNpcBehaviorProfileCatalog

## Compatibility script for legacy WorldCore resource paths.


func profile_ids() -> PackedStringArray:
	_ensure_index()
	return PackedStringArray(_index.keys())
