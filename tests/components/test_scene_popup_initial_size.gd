extends SceneTree

## Regression: the first Scene-dock popup must have its final height BEFORE it
## becomes visible. A native header without a width was initially wrapped into
## a one-character column until Godot performed its first visible layout pass.
const Bridge := preload("res://addons/better_tooltips/modules/scene_component_tooltip.gd")
const Fixture := preload("res://tests/components/example_component.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var tree := Tree.new()
	EditorInterface.get_base_control().add_child(tree)
	var item := tree.create_item()
	item.set_tooltip_text(0, "Saved root description. This native header must not wrap into a single-character column.")
	var node: Node = Fixture.new()
	root.add_child(node)
	var bridge := Bridge.new()
	bridge.update_item(item, node)
	var popup := bridge._popup as PopupPanel
	check(is_instance_valid(popup) and popup.visible, "Component popup must open")
	if is_instance_valid(popup):
		var native_header := bridge._popup_body.get_child(0) as Label
		check(native_header != null, "Native header missing")
		if native_header != null:
			check(native_header.custom_minimum_size.x >= 400.0,
				"Native header must have width before the first window layout")
			check(native_header.size.y < 80.0,
				"Native header must not begin as a narrow multi-line column")
		var first_size := popup.size
		var first_contents := popup.get_contents_minimum_size()
		for index in range(5):
			await process_frame
		var stable_contents := popup.get_contents_minimum_size()
		check(absf(first_contents.y - stable_contents.y) <= 2.0,
			"Scene popup must not recompute a radically different height after opening")
		check(absf(float(first_size.y - popup.size.y)) <= 2.0,
			"Scene popup must keep its initial window height after rich text layout")
		# A value refresh without changes must not re-open/reposition the popup.
		var first_position := popup.position
		bridge.update_item(item, node)
		for index in range(3):
			await process_frame
		check(popup.visible and popup.position == first_position and popup.size == first_size,
			"Unchanged Scene-dock hover must not reposition or resize popup")
	bridge.cleanup()
	check(item.get_tooltip_text(0).begins_with("Saved root description."),
		"Native tooltip was not restored")
	tree.free()
	node.free()
	if failures.is_empty():
		print("Scene component popup initial sizing and stable refresh: PASS")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
