@tool
extends SceneTree

# Regression for a 4.7.2 Segmentation Fault: component-cache lookup must not
# reload the very @tool script whose method is currently executing.
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const CACHE_SCRIPT := "res://addons/better_tooltips/core/tooltip_cache.gd"
const CONTRACT_SCENE := "res://tests/components/scenes/component_root.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var cache := Cache.new()
	for index in 3:
		cache.invalidate_component_document(CACHE_SCRIPT)
		var script_doc: Dictionary = cache.get_component_document(CACHE_SCRIPT)
		if not script_doc.is_empty():
			push_error("Uncontracted tooltip cache script must not produce contract data")
			quit(1)
			return
	var scene_doc: Dictionary = cache.get_component_document(CONTRACT_SCENE)
	if not bool(scene_doc.get("has_contract", false)):
		push_error("Contract scene must remain documented")
		quit(1)
		return
	cache.cleanup()
	print("PASS test_component_self_script_reload")
	quit()
