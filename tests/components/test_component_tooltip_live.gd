extends SceneTree

## Run with --editor; exercises the real live-text pipeline and native Tree items.
const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const Module := preload("res://addons/better_tooltips/modules/component_documentation_tooltip.gd")
const Bridge := preload("res://addons/better_tooltips/modules/scene_component_tooltip.gd")
const Fixture := preload("res://tests/components/example_component.gd")
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	await create_timer(1).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var fixture: Node = Fixture.new()
	fixture.name = "Instrument"
	var packed := PackedScene.new()
	_expect(packed.pack(fixture) == OK, "Pack failed")
	var path: String = "res://tests/components/generated_live_fixture.tscn"
	_expect(ResourceSaver.save(packed, path) == OK, "Save failed")
	fixture.free()
	# Root scene inheritance must retain script, metadata and saved overrides.
	var inherited: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	inherited.scene_file_path = path
	inherited.caption = "Inherited override"
	var inherited_scene := PackedScene.new()
	_expect(inherited_scene.pack(inherited) == OK, "Inherited pack failed")
	var inherited_path: String = "res://tests/components/generated_live_inherited.tscn"
	_expect(ResourceSaver.save(inherited_scene, inherited_path) == OK, "Inherited save failed")
	inherited.free()
	var document := Reader.for_path(inherited_path)
	var found_override: bool = false
	for property: Dictionary in document.get("properties", []):
		if property.name == "caption" and property.assignment == "Inherited override": found_override = true
	_expect(found_override, "Inherited scene root override missing")
	EditorInterface.get_resource_filesystem().scan()
	await create_timer(0.5).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	var cache := Cache.new()
	cache.setup(EditorInterface.get_base_control())
	var pipeline := Pipeline.new()
	pipeline.setup(cache, EditorInterface.get_base_control())
	pipeline.add_module(Settings.MODULE_COMPONENT_DOCUMENTATION, "Component", Module.new())
	var popup := PopupPanel.new()
	EditorInterface.get_base_control().add_child(popup)
	var content := VBoxContainer.new()
	popup.add_child(content)
	popup.popup(Rect2i(300, 100, 650, 500))
	_expect(pipeline.append_preview_for_path(path, content, popup), "Pipeline rejected PackedScene component")
	for frame: int in range(6): await process_frame
	var label := popup.find_child("ComponentDocumentation", true, false) as RichTextLabel
	_expect(label != null, "Expected a live rich-text component section")
	if label != null:
		_expect(label.get_parsed_text().contains("Required") and label.get_parsed_text().contains("activated(identifier: StringName)"), "Rendered dependency or typed signal missing")
	var tree := Tree.new()
	EditorInterface.get_base_control().add_child(tree)
	var item := tree.create_item()
	item.set_tooltip_text(0, "Original native tooltip")
	var live: Node = Fixture.new()
	root.add_child(live)
	var bridge := Bridge.new()
	bridge.update_item(item, live)
	await process_frame
	await process_frame
	_expect(item.get_tooltip_text(0) == Bridge.NATIVE_SCENE_TOOLTIP_PLACEHOLDER, "Native scene tooltip should be suppressed while the rich popup is active")
	_expect(bridge._popup != null and bridge._popup.visible, "Scene popup was not shown")
	var scene_label := bridge._popup.find_child("ComponentDocumentation", true, false) as RichTextLabel
	_expect(scene_label != null, "Scene popup rich-text section missing")
	if scene_label != null:
		_expect(scene_label.get_parsed_text().contains("Unassigned"), "Live missing dependency missing")
		_expect(scene_label.get_parsed_text().contains("Example reusable instrument"), "Popup must include the class purpose")
	live.caption = "Unsaved live change"
	bridge.update_item(item, live)
	await process_frame
	await process_frame
	scene_label = bridge._popup.find_child("ComponentDocumentation", true, false) as RichTextLabel
	if scene_label != null:
		_expect(scene_label.get_parsed_text().contains("Unsaved live change"), "Live editor changes not refreshed")
	live.caption = "long/path/".repeat(25)
	for line: String in Bridge.summary(Reader.for_node(live)).split("\n"):
		_expect(line.length() <= 88, "Debug summary helper must still wrap long paths and descriptions")
	bridge.cleanup()
	_expect(item.get_tooltip_text(0) == "Original native tooltip", "Disabling addon must restore tooltip")
	bridge.update_item(item, live)
	tree.clear()
	bridge.cleanup()
	_expect(Bridge.find_scene_tree(EditorInterface.get_base_control()) != null, "Native local Scene dock was not detected")
	live.free()
	tree.free()
	popup.free()
	pipeline.cleanup()
	cache.cleanup()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(inherited_path)
	if failures.is_empty(): print("Component live tooltip pipeline/tree/inheritance: PASS")
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
