extends SceneTree

## Run with --headless --editor --script res://tests/components/test_scene_component_refresh.gd
## Tests polling without GDScript reparsing, unsaved Inspector values, external
## native tooltip replacement, script change invalidation and cleanup.
const Bridge := preload("res://addons/better_tooltips/modules/scene_component_tooltip.gd")
const Fixture := preload("res://tests/components/example_component.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func popup_text(bridge: Bridge) -> String:
	if bridge._popup == null:
		return ""
	var parts: PackedStringArray = []
	for child: Node in bridge._popup.find_children("*", "Label", true, false):
		parts.append((child as Label).text)
	var label := bridge._popup.find_child("ComponentDocumentation", true, false) as RichTextLabel
	if label != null:
		parts.append(label.get_parsed_text())
	return "\n".join(parts)

func _run() -> void:
	var tree := Tree.new()
	EditorInterface.get_base_control().add_child(tree)
	var item := tree.create_item()
	item.set_tooltip_text(0, "Godot native node description")
	var node: Node = Fixture.new()
	root.add_child(node)
	var bridge := Bridge.new()
	bridge.update_item(item, node)
	await process_frame
	await process_frame
	check(item.get_tooltip_text(0) == Bridge.NATIVE_SCENE_TOOLTIP_PLACEHOLDER, "Native tooltip should be suppressed while scene popup is active")
	check(popup_text(bridge).contains("Component: BTExampleComponent"), "Component popup missing")
	check(bridge._parsed_document.size() > 0, "Expected reflection cache")
	bridge._parsed_document["test_marker"] = 123
	bridge.update_item(item, node)
	await process_frame
	check(bridge._parsed_document.has("test_marker"), "Unchanged node reparsed unnecessarily")
	node.caption = "Not yet saved in scene"
	bridge.update_item(item, node)
	await process_frame
	await process_frame
	check(popup_text(bridge).contains("Not yet saved in scene"), "Unsaved Inspector assignment not visible")
	check(bridge._parsed_document.has("test_marker"), "Property assignment triggered full reparse")
	node.caption = "Inspector event before save"
	bridge._on_property_edited(&"caption")
	await process_frame
	await process_frame
	check(popup_text(bridge).contains("Inspector event before save"),
		"Inspector edit signal should immediately refresh unsaved values")
	item.set_tooltip_text(0, "Godot rebuilt description")
	bridge.update_item(item, node)
	await process_frame
	await process_frame
	check(popup_text(bridge).contains("Godot rebuilt description"),
		"Popup should reflect refreshed native description")
	bridge._on_script_changed()
	bridge.update_item(item, node)
	check(not bridge._parsed_document.has("test_marker"), "Script change should invalidate reflection")
	bridge.cleanup()
	check(item.get_tooltip_text(0) == "Godot rebuilt description", "Cleanup must restore native tooltip")
	check(bridge._active_node == null, "Node signal listeners not released")
	bridge.update_item(item, node)
	await process_frame
	await process_frame
	check(bridge._popup != null and bridge._popup.visible, "Module should still work after test seam reuse")
	bridge.cleanup()
	bridge.setup()
	check(bridge._timer != null and not bridge._timer.is_stopped(),
		"Enabled module must create its Scene-Dock polling timer")
	var version := Engine.get_version_info()
	var expected := "scene_node_resolver_48.gd" if int(version.minor) >= 8 else "scene_node_resolver_47.gd"
	check(str(bridge._node_resolver.get_script().resource_path).ends_with(expected),
		"Wrong Godot version strategy selected at startup")
	bridge.cleanup()
	item = null
	tree.free()
	node.free()
	if failures.is_empty():
		print("Scene component live refresh, unsaved values, tooltip restoration: PASS")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
