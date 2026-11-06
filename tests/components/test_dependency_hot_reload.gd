extends SceneTree
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const SCENE := "res://tests/components/scenes/generated_dependency_scene.tscn"
const SCRIPT := "res://tests/components/scenes/generated_dependency_component.gd"
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, reason: String) -> void:
	if not value:
		failures.append(reason)
func write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()
func _run() -> void:
	write(SCRIPT, '@tool\nextends Node\nconst COMPONENT_CONTRACT: Dictionary = {"version": 1}\n## Initial export\n@export var first_label: String = "one"\n')
	write(SCENE, '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="' + SCRIPT + '" id="1_s"]\n[node name="Root" type="Node"]\nscript = ExtResource("1_s")\n')
	# EditorFileSystem notices new scripts in actual project; isolated test invokes parser.
	var cache := Cache.new()
	cache.setup(EditorInterface.get_base_control())
	var first_doc := cache.get_component_document(SCENE)
	check(not first_doc.is_empty(), "First script should be recognized")
	check(str(first_doc).contains("first_label"), "First export should be present")
	var stamp: Dictionary = cache._component_documents[SCENE].stamps.duplicate(true)
	check(stamp.has(SCRIPT), "Script is a dependency")
	write(SCRIPT, '@tool\nextends Node\nconst COMPONENT_CONTRACT: Dictionary = {"version": 1}\n## Second export and a new comment with different length\n@export var second_label: String = "two"\n')
	check(not cache._component_stamps_current(stamp), "Script change invalidates dependency signature")
	var second_doc := cache.get_component_document(SCENE)
	check(str(second_doc).contains("second_label"), "Changed dependent script reflected without restarting the Editor")
	# A removed contract must be cached as a negative result, also across saves.
	write(SCRIPT, '@tool\nextends Node\n## No component contract any more, but the file is longer than before\n@export var third_label: String = "three"\n')
	check(cache.get_component_document(SCENE).is_empty(), "Removed contract must invalidate positive cache")
	write(SCRIPT, '@tool\nextends Node\nconst COMPONENT_CONTRACT: Dictionary = {"version": 1}\n## Restored contract and longer descriptive comment\n@export var fourth_label: String = "four"\n')
	check(str(cache.get_component_document(SCENE)).contains("fourth_label"),
		"Restored contract must invalidate negative cache")
	cache.cleanup()
	DirAccess.remove_absolute(SCRIPT)
	DirAccess.remove_absolute(SCENE)
	if failures.is_empty(): print("Changed dependent script refresh: PASS")
	for error in failures: push_error(error)
	quit(0 if failures.is_empty() else 1)
