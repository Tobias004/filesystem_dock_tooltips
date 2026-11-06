extends SceneTree

## Editor-only regression: other menus/dialogs must win over the Scene-dock
## hover timer even if the pointer is geometrically over a Tree underneath.
const Bridge := preload("res://addons/better_tooltips/modules/scene_component_tooltip.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	await process_frame
	var base := EditorInterface.get_base_control()
	var tree := Tree.new()
	tree.custom_minimum_size = Vector2(250, 150)
	base.add_child(tree)
	await process_frame
	check(not Bridge.has_blocking_editor_window(tree, null), "Uncovered Scene Tree incorrectly blocked")

	var menu := PopupMenu.new()
	base.add_child(menu)
	menu.add_item("Keep this menu open")
	menu.popup(Rect2i(40, 50, 220, 90))
	await process_frame
	check(menu.visible, "Test popup menu failed to open")
	check(Bridge.has_blocking_editor_window(tree, null), "Active PopupMenu must block Scene-dock hover")
	# The timer must not create another popup or dismiss the menu.
	var bridge := Bridge.new()
	bridge._tree = tree
	bridge._refresh_hover()
	check(menu.visible, "Scene-dock polling closed the open menu")
	check(bridge._popup == null, "Scene tooltip opened over another popup")
	menu.hide()
	await process_frame

	var dialog := AcceptDialog.new()
	base.add_child(dialog)
	dialog.popup(Rect2i(40, 50, 320, 160))
	await process_frame
	check(Bridge.has_blocking_editor_window(tree, null), "Open editor dialog must block Scene-dock hover")
	dialog.hide()
	await process_frame

	var own := PopupPanel.new()
	base.add_child(own)
	own.add_child(Label.new())
	own.popup(Rect2i(40, 50, 250, 130))
	await process_frame
	check(not Bridge.has_blocking_editor_window(tree, own), "Own tooltip must be exempt")
	own.hide()
	await process_frame

	own.queue_free()
	dialog.queue_free()
	menu.queue_free()
	tree.queue_free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Scene-dock popup/menu/dialog overlay guard: PASS")
	quit(0 if failures.is_empty() else 1)
