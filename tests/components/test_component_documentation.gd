extends SceneTree

const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const Fixture := preload("res://tests/components/example_component.gd")
const Derived := preload("res://tests/components/derived_component.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var component: Node = Fixture.new()
	component.name = "ExampleInstrument"
	var source := Node.new()
	source.name = "Data"
	component.add_child(source)
	source.owner = component
	component.data_source = source
	component.editor_description = "Scene-specific assembly hint."
	var packed := PackedScene.new()
	_expect(packed.pack(component) == OK, "Fixture pack failed")
	var path := "user://bt_component_documentation_test.tscn"
	_expect(ResourceSaver.save(packed, path) == OK, "Fixture save failed")
	component.free()
	Engine.remove_meta("bt_component_fixture_instantiated")
	Engine.remove_meta("bt_component_fixture_warnings_called")
	var file_doc := Reader.for_path(path)
	_expect(not Engine.has_meta("bt_component_fixture_instantiated"), "Hover must never instantiate a PackedScene")
	_expect(not Engine.has_meta("bt_component_fixture_warnings_called"), "Hover must not execute component methods")
	_expect(file_doc.get("title") == "BTExampleComponent", "Native script class missing")
	_expect(str(file_doc.get("description")).contains("reusable instrument"), "Class documentation missing")
	_expect(file_doc.get("scene_description") == "Scene-specific assembly hint.", "Scene description missing")
	_expect(file_doc.get("properties", []).size() == 2, "Exported properties not reflected")
	var data := _property(file_doc, "data_source")
	_expect(data.get("requirement") == "Required" and data.get("type") == "Node", "Required typed dependency missing")
	_expect(data.get("assignment") == "Data", "Serialized NodePath assignment missing")
	_expect(str(data.get("description")).contains("Subscribes"), "Property documentation missing")
	_expect(file_doc.get("signals", []).size() == 1 and str(file_doc.signals[0].signature).contains("identifier: StringName"), "Typed signal missing")
	_expect(file_doc.get("commands", []).size() == 1 and file_doc.commands[0].signature == 'reset_display(_scope: StringName = &"local") -> void', "Public command types/defaults/void return missing")
	var live := Fixture.new()
	root.add_child(live)
	var live_doc := Reader.for_node(live)
	_expect(_property(live_doc, "data_source").get("assignment") == "Unassigned", "Missing live dependency not shown")
	live.caption = "Unsaved caption"
	live.data_source = live
	live_doc = Reader.for_node(live)
	_expect(_property(live_doc, "caption").get("assignment") == "Unsaved caption", "Unsaved Inspector value missing")
	_expect(_property(live_doc, "data_source").get("assignment") == ".", "Live Node reference missing")
	live.free()
	var inherited := Reader.for_script(Derived)
	_expect(_property(inherited, "data_source").get("requirement") == "Required", "Inherited contract missing")
	_expect(str(_property(inherited, "data_source").get("description")).contains("Subscribes"), "Inherited documentation missing")
	_expect(_property(inherited, "precision").get("type") == "int", "Derived export missing")
	var undocumented := GDScript.new()
	undocumented.source_code = "extends Node\n"
	_expect(undocumented.reload() == OK and Reader.for_script(undocumented).is_empty(), "Ordinary scripts must retain existing behavior")
	var invalid := GDScript.new()
	invalid.source_code = 'extends Node\nconst COMPONENT_CONTRACT = {"version": 1, "required": [&"missing"], "optional": []}\n'
	_expect(invalid.reload() == OK and Reader.for_script(invalid).issues.size() == 1, "Stale metadata needs a diagnostic")
	var future := GDScript.new()
	future.source_code = 'extends Node\nconst COMPONENT_CONTRACT = {"version": 99}\n'
	_expect(future.reload() == OK and str(Reader.for_script(future).description).contains("Unsupported"), "Unknown schema version must degrade clearly")
	DirAccess.remove_absolute(path)
	if failures.is_empty():
		print("Component documentation extraction: PASS")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _property(document: Dictionary, name: String) -> Dictionary:
	for property: Dictionary in document.get("properties", []):
		if property.name == name: return property
	return {}
