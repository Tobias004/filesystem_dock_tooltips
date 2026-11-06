extends SceneTree

## Run with --headless --editor --script res://tests/components/test_scene_dock_editor_tree.gd
## Integration test of the actual Godot SceneTreeDock metadata on both versions.
## Distinguishes 4.7 absolute paths from 4.8 relative paths using strategies.
const Bridge := preload("res://addons/better_tooltips/modules/scene_component_tooltip.gd")
const Resolver47 := preload("res://addons/better_tooltips/modules/scene_node_resolvers/scene_node_resolver_47.gd")
const Resolver48 := preload("res://addons/better_tooltips/modules/scene_node_resolvers/scene_node_resolver_48.gd")
const SCENE := "res://tests/components/scenes/component_root.tscn"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	await create_timer(0.5).timeout
	EditorInterface.get_resource_filesystem().scan()
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	EditorInterface.open_scene_from_path(SCENE)
	await create_timer(1.0).timeout
	var tree := Bridge.find_scene_tree(EditorInterface.get_base_control())
	var edited := EditorInterface.get_edited_scene_root()
	check(tree != null and edited != null, "Editor did not open a local Scene-Dock Tree")
	if tree != null and edited != null:
		var version := Engine.get_version_info()
		var is_relative := int(version.major) > 4 or (int(version.major) == 4 and int(version.minor) >= 8)
		var resolver = Resolver48.new() if is_relative else Resolver47.new()
		var item := tree.get_root()
		var found_root := false
		var found_child := false
		while item != null:
			var metadata = item.get_metadata(0)
			if metadata is NodePath:
				var node: Node = resolver.resolve(tree, edited, metadata)
				if node == edited:
					found_root = true
				elif node != null and node.name == &"Source":
					found_child = true
			item = item.get_next_visible()
		check(found_root, "Root scene node was not resolved by current version strategy")
		check(found_child, "Child scene node was not resolved by current version strategy")
	if failures.is_empty():
		print("Real Godot Scene dock node resolution: PASS")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
