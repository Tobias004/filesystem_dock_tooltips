extends SceneTree

## Focused regression for scene-tree context-menu clicks while BT's own rich
## tooltip is open. Use the graphical editor for actual mouse-event routing.
const Bridge := preload("res://addons/better_tooltips/modules/scene_component_tooltip.gd")
const Lifetime := preload("res://addons/better_tooltips/core/tooltip_lifetime_manager.gd")
const Fixture := preload("res://tests/components/example_component.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	var base := EditorInterface.get_base_control()
	var tree := Tree.new()
	tree.position = Vector2(175, 180)
	tree.custom_minimum_size = Vector2(310, 190)
	tree.size = tree.custom_minimum_size
	base.add_child(tree)
	var item := tree.create_item()
	item.set_text(0, "Example component")
	item.set_tooltip_text(0, "Native node help")
	var node := Fixture.new() as Node
	root.add_child(node)
	await process_frame
	await process_frame
	var hover_pos := tree.get_screen_transform().origin + Vector2(55, 15)
	Input.warp_mouse(hover_pos - Vector2(DisplayServer.window_get_position()))
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		_check(Rect2(Vector2.ZERO, tree.size).has_point(tree.get_local_mouse_position()),
			"Test pointer did not reach the Scene Tree")

	var bridge := Bridge.new()
	bridge._tree = tree
	bridge._popup_lifetime = Lifetime.new()
	bridge.update_item(item, node)
	await process_frame
	_check(is_instance_valid(bridge._popup) and bridge._popup.visible,
		"Rich Scene-Dock tooltip did not open")
	_check(not bridge._popup.get_flag(Window.FLAG_POPUP),
		"PopupPanel still grabs the first right-click for closing")
	_check(bridge._popup.get_flag(Window.FLAG_NO_FOCUS),
		"Scene-Dock popup must not steal tree focus")
	if DisplayServer.get_name() != "headless":
		var right_clicks := [0]
		tree.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				right_clicks[0] += 1
		)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		click.position = tree.get_global_transform_with_canvas().origin + Vector2(55, 15)
		click.global_position = click.position
		Input.parse_input_event(click)
		await process_frame
		_check(right_clicks[0] > 0,
			"Scene Tree did not receive a right-click while the rich popup was visible")
	_check(item.get_tooltip_text(0) == Bridge.NATIVE_SCENE_TOOLTIP_PLACEHOLDER,
		"Native Tree label fallback not suppressed")
	bridge.update_item(item, node)
	_check(bridge._original == "Native node help",
		"Repeated polling must not replace saved native tooltip with placeholder")

	# A blank native Tree popup may be created even for whitespace on 4.8.
	# Ensure it is suppressed without closing BT's own non-exclusive popup.
	var native := PopupPanel.new()
	var label := Label.new()
	label.text = "Example component"
	native.add_child(label)
	tree.add_child(native)
	native.popup(Rect2i(Vector2i(tree.get_screen_transform().origin) + Vector2i(5, 5), Vector2i(180, 40)))
	await process_frame
	bridge._hide_native_tree_tooltip()
	_check(not native.visible, "Godot's fallback Tree tooltip was not suppressed")
	_check(bridge._popup.visible, "Hiding native popup also closed BT rich tooltip")
	native.queue_free()

	# Keep the hover alive beyond the lifetime grace interval.
	await create_timer(0.8).timeout
	_check(bridge._popup.visible, "Scene-Dock rich popup expired while source was present")
	bridge.cleanup()
	_check(item.get_tooltip_text(0) == "Native node help",
		"Scene-Dock cleanup did not restore the native tooltip text")
	tree.queue_free()
	node.queue_free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("Scene-Dock non-exclusive right-click popup: PASS")
	quit(0 if failures.is_empty() else 1)
