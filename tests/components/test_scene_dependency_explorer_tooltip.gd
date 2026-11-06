extends SceneTree

## Targeted integration: SDE Tree discovery, saved scene metadata, common rich
## renderer, optional contract modes, negative results, hover cache, cleanup.
const Bridge := preload("res://addons/better_tooltips/modules/scene_dependency_explorer_tooltip.gd")
const MockDock := preload("res://tests/components/scene_explorer_dock.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func popup_text(bridge: Bridge) -> String:
	if not is_instance_valid(bridge._popup):
		return ""
	var label := bridge._popup.find_child("ComponentDocumentation", true, false) as RichTextLabel
	return label.get_parsed_text() if is_instance_valid(label) else ""

func _run() -> void:
	var dock := MockDock.new() as VBoxContainer
	dock.name = "Scene Dependencies"
	var tree := Tree.new()
	dock.add_child(tree)
	EditorInterface.get_base_control().add_child(dock)
	check(Bridge.find_explorer_tree(EditorInterface.get_base_control()) == tree,
		"Cannot discover SDE Tree by dock identity")
	var root := tree.create_item()
	var path := "res://tests/components/scenes/osc_repo_cockpit_view.tscn"
	root.set_metadata(0, path)
	root.set_tooltip_text(0, path)
	check(Bridge.scene_path_for_item(root) == path, "SDE scene metadata was not recognized")
	var bridge := Bridge.new()
	bridge.set_documentation_modes(false, true)
	bridge._tree = tree
	bridge.update_path_item(root, path)
	await process_frame
	await process_frame
	var doc_text := popup_text(bridge)
	check(doc_text.contains("Implementation notes"), "Script notes not visible without contract")
	check(doc_text.contains("No COMPONENT_CONTRACT"), "OSC missing-contract rationale not shown")
	check(root.get_tooltip_text(0) == Bridge.SUPPRESSED_NATIVE_TOOLTIP,
		"SDE native tooltip must suppress Godot's fallback to the TreeItem label")
	check(is_instance_valid(bridge._popup) and bridge._popup.visible,
		"SDE tooltip popup was not opened")
	if is_instance_valid(bridge._popup):
		check(not bridge._popup.get_flag(Window.FLAG_POPUP),
			"SDE tooltip must not exclusively capture clicks needed for item_activated")
		check(bridge._popup.get_flag(Window.FLAG_NO_FOCUS),
			"SDE tooltip must not steal focus from the scene tree")
	bridge._parsed_document["sentinel"] = true
	bridge.update_path_item(root, path)
	check(bridge._parsed_document.has("sentinel"), "Same SDE scene reparsed despite no changes")
	check(root.get_tooltip_text(0) == Bridge.SUPPRESSED_NATIVE_TOOLTIP,
		"A repeated hover update must not replace the suppressed tooltip with the path or label")
	bridge.set_documentation_modes(true, true)
	bridge._tree = tree
	var hud_path := "res://tests/components/scenes/osc_repo_hud.tscn"
	root.set_metadata(0, hud_path)
	root.set_tooltip_text(0, hud_path)
	bridge.update_path_item(root, hud_path)
	await process_frame
	await process_frame
	doc_text = popup_text(bridge)
	check(doc_text.contains("Required"), "Contract properties missing")
	check(doc_text.contains("Implementation notes"), "Contract notes missing")
	check(doc_text.contains("Emitted signals"), "Contract API sections missing")
	check(bridge._watched_paths.has(hud_path), "Saved scene not tracked")
	check(bridge._watched_paths.has("res://tests/components/osc_repo_hud.gd"),
		"Scene's external script dependency not tracked for cache invalidation")
	var unchanged_stamp := Bridge._file_stamp(bridge._watched_paths)
	check(unchanged_stamp == bridge._watched_stamp, "Stable saved dependency stamp changed")
	bridge.set_documentation_modes(false, false)
	check(root.get_tooltip_text(0) == hud_path,
		"Disabling both documentation modules should restore native tooltip")
	bridge.cleanup()
	check(root.get_tooltip_text(0) == hud_path, "Original SDE path tooltip not restored")
	var other := tree.create_item()
	other.set_metadata(0, NodePath("/root/SomeNode"))
	check(Bridge.scene_path_for_item(other).is_empty(), "Native Scene-Dock NodePath must be excluded")
	var undocumented := "res://tests/components/scenes/ordinary_root.tscn"
	other.set_metadata(0, undocumented)
	other.set_tooltip_text(0, undocumented)
	var second_bridge := Bridge.new()
	second_bridge.set_documentation_modes(false, true)
	second_bridge._tree = tree
	second_bridge.update_path_item(other, undocumented)
	check(other.get_tooltip_text(0) == undocumented and second_bridge._parsed_document.is_empty(),
		"Undocumented scene must preserve the SDE native path tooltip")
	second_bridge.cleanup()
	dock.free()
	if failures.is_empty():
		print("Scene Dependency Explorer tooltip integration: PASS")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
