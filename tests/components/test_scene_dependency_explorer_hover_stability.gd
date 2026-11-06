extends SceneTree

## Graphical regression: a stationary pointer must not alternate between
## Godot's fallback TreeItem tooltip and our non-exclusive rich popup.
## Run with a graphical editor (not --headless); no SDE plugin is required.
const Bridge := preload("res://addons/better_tooltips/modules/scene_dependency_explorer_tooltip.gd")
const Lifetime := preload("res://addons/better_tooltips/core/tooltip_lifetime_manager.gd")
const TEST_SCENE := "res://tests/components/scenes/osc_repo_cockpit_view.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	var base := EditorInterface.get_base_control()
	var dock := Control.new()
	dock.name = &"SDEHoverRegressionDock"
	dock.position = Vector2(200, 200)
	dock.size = Vector2(300, 240)
	base.add_child(dock)
	var tree := Tree.new()
	tree.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.add_child(tree)
	var item := tree.create_item()
	item.set_text(0, "Cockpit View")
	item.set_metadata(0, TEST_SCENE)
	item.set_tooltip_text(0, TEST_SCENE)
	await process_frame
	await process_frame

	# Input.warp_mouse expects editor-window coordinates, while mouse position
	# and PopupPanel rectangles use global desktop coordinates.
	var screen_position := tree.get_screen_transform().origin + Vector2(65, 17)
	Input.warp_mouse(screen_position - Vector2(DisplayServer.window_get_position()))
	await process_frame
	await process_frame
	_check(tree.get_item_at_position(tree.get_local_mouse_position()) == item,
		"Pointer did not land on the test TreeItem")

	var bridge := Bridge.new()
	bridge.set_documentation_modes(false, true)
	bridge._tree = tree
	bridge.set("_popup_lifetime", Lifetime.new())
	bridge.update_path_item(item, TEST_SCENE)
	_check(is_instance_valid(bridge._popup) and bridge._popup.visible,
		"Rich tooltip did not open")
	_check(item.get_tooltip_text(0) == Bridge.SUPPRESSED_NATIVE_TOOLTIP,
		"Native fallback tooltip is not suppressed")
	if is_instance_valid(bridge._popup):
		_check(not bridge._popup.get_flag(Window.FLAG_POPUP),
			"Rich popup must not grab the Tree's double-clicks")

	# Wait longer than Godot's native-tooltip delay and the lifetime grace.
	for index in range(9):
		await create_timer(0.25).timeout
		bridge._refresh_hover()
		_check(bridge._popup != null and bridge._popup.visible,
			"Rich tooltip disappeared with a stationary pointer (step %d)" % index)
		_check(bridge._active_scene_path == TEST_SCENE,
			"Active item was discarded with a stationary pointer (step %d)" % index)
		for child in tree.get_children():
			if child is PopupPanel and child.visible:
				var native_text := ""
				if child.get_child_count() > 0 and child.get_child(0) is Label:
					native_text = (child.get_child(0) as Label).text
				_check(false, "Godot opened a second, native TreeItem tooltip (text: %s)" % native_text)

	# Godot 4.8 may create a separate native popup even for a whitespace
	# tooltip. It must be hidden without dismissing our rich window.
	var native_popup := PopupPanel.new()
	var native_label := Label.new()
	native_label.text = "Cockpit View"
	native_popup.add_child(native_label)
	native_popup.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.add_child(native_popup)
	native_popup.popup(Rect2i(Vector2i(screen_position) + Vector2i(10, 10), Vector2i(40, 24)))
	await process_frame
	_check(native_popup.visible, "Native popup test fixture could not open")
	bridge._refresh_hover()
	_check(not native_popup.visible, "SDE native popup was not suppressed")
	_check(bridge._popup != null and bridge._popup.visible,
		"Suppressing native popup closed the rich tooltip")
	native_popup.queue_free()

	bridge.cleanup()
	_check(item.get_tooltip_text(0) == TEST_SCENE,
		"Original scene path tooltip was not restored")
	dock.free()
	if failures.is_empty():
		print("Scene Dependency Explorer stationary hover: PASS")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
