extends SceneTree

## Run with --headless --editor --script res://tests/components/test_component_cache.gd
## Verifies scene-root-only detection, positive/negative entries, file-size/mtime
## invalidation, dependency stamps, defensive copies and shared Clear Caches.
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const Module := preload("res://addons/better_tooltips/modules/component_documentation_tooltip.gd")
const ROOT_SCENE := "res://tests/components/scenes/component_root.tscn"
const ORDINARY_SCENE := "res://tests/components/scenes/ordinary_root.tscn"
const GENERATED_SCENE := "res://tests/components/scenes/generated_cache_test.tscn"
const SOURCE_SCRIPT := "res://tests/components/example_component.gd"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var cache := Cache.new()
	cache.setup(EditorInterface.get_base_control())
	var document: Dictionary = cache.get_component_document(ROOT_SCENE)
	check(not document.is_empty(), "Component scene should be detected")
	check(document.get("scene_description") == "Saved root description.", "Saved root metadata missing")
	check(cache._component_documents.has(ROOT_SCENE), "Positive document should be cached")
	check(cache._component_documents[ROOT_SCENE].stamps.has(SOURCE_SCRIPT), "Script dependency stamp missing")
	var original_title: String = document.get("title", "")
	document["title"] = "TEST_MUTATION"
	check(cache.get_component_document(ROOT_SCENE).get("title") == original_title,
		"Public caller must not mutate cached document")
	check(cache.get_component_document(ORDINARY_SCENE).is_empty(),
		"A child contract must not classify an ordinary scene root")
	check(cache._component_documents.has(ORDINARY_SCENE), "Negative result should be cached")
	check(cache.get_component_document(ORDINARY_SCENE).is_empty(), "Negative cache should be reusable")
	var script_stamp: Vector2i = cache._component_documents[ROOT_SCENE].stamps[SOURCE_SCRIPT]
	check(cache._component_file_stamp(SOURCE_SCRIPT) == script_stamp, "Dependency stamp should be current")
	var original: String = FileAccess.get_file_as_string(ORDINARY_SCENE)
	var added: String = original.replace('[node name="OrdinaryRoot" type="Node"]',
		'[node name="OrdinaryRoot" type="Node"]\nscript = ExtResource("1_component")')
	check(FileAccess.open(GENERATED_SCENE, FileAccess.WRITE) != null, "Test scene creation failed")
	var file := FileAccess.open(GENERATED_SCENE, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	check(cache.get_component_document(GENERATED_SCENE).is_empty(), "Generated scene starts without root contract")
	var before: Dictionary = cache._component_documents[GENERATED_SCENE].stamps.duplicate(true)
	file = FileAccess.open(GENERATED_SCENE, FileAccess.WRITE)
	file.store_string(added)
	file.close()
	check(not cache._component_stamps_current(before), "Changed scene must invalidate mtime/size signature")
	var updated := cache.get_component_document(GENERATED_SCENE)
	check(not updated.is_empty(), "Negative scene cache should refresh to positive")
	check(cache._component_documents[GENERATED_SCENE].stamps != before, "Stamp should be replaced")
	cache.invalidate_component_document(GENERATED_SCENE)
	check(not cache._component_documents.has(GENERATED_SCENE), "Shift-hover invalidation not working")
	cache.get_component_document(GENERATED_SCENE)
	cache.clear()
	check(cache._component_documents.is_empty() and not cache.has_entries(),
		"Clear Tooltip Caches should also clear component documents")
	var module := Module.new()
	module.setup_cache(cache)
	check(module._cache == cache, "Shared cache not attached to module")
	cache.cleanup()
	DirAccess.remove_absolute(GENERATED_SCENE)
	if failures.is_empty():
		print("Component scene cache, invalidation, root and dependencies: PASS")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
