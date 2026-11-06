extends SceneTree

## Focused regression for Quill Tree, Script-IDE ItemList, and stock method list.
## A source scrollbar must not prolong its item tooltip; the non-exclusive
## popup must leave ordinary mouse events and external keyboard shortcuts alone.
const Navigation = preload("res://addons/better_tooltips/modules/script_editor_navigation_tooltip.gd")
const Lifetime = preload("res://addons/better_tooltips/core/tooltip_lifetime_manager.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for kind: StringName in [&"quill_outline_tree", &"script_ide_outline", &"stock_method_list"]:
		var source: Control
		if kind == &"quill_outline_tree":
			var tree := Tree.new()
			tree.hide_root = true
			var parent := tree.create_item()
			for i in range(45):
				var item := tree.create_item(parent)
				item.set_text(0, "method_%d" % i)
			source = tree
		else:
			var list := ItemList.new()
			for i in range(45):
				list.add_item("method_%d" % i)
			source = list
		source.size = Vector2(240, 110)
		EditorInterface.get_base_control().add_child(source)
		await process_frame
		await process_frame
		var bar: ScrollBar = null
		for node in source.get_children(true):
			if node is VScrollBar and node.is_visible_in_tree() and node.size.x > 0.0:
				bar = node
				break
		if bar == null:
			_fail("No visible vertical scrollbar on %s" % kind)
			return
		var lifetime: BTTooltipLifetimeManager = Lifetime.new()
		var source_rect := Rect2i(source.get_screen_position(), Vector2i(source.size))
		var scoped := {"trigger_rect": source_rect, "item_only_source_hover": true}
		var old_scope := {"trigger_rect": source_rect, "item_only_source_hover": false}
		var bar_local := bar.position + bar.size / 2.0
		var bar_screen := Vector2i(source.get_screen_transform() * bar_local)
		if lifetime._source_hover_is_valid(source, bar_screen, bar_local, scoped):
			_fail("Scrollbar still keeps the %s tooltip alive" % kind)
			return
		if not lifetime._source_hover_is_valid(source, bar_screen, bar_local, old_scope):
			_fail("Control scope changed for unrelated tooltips: %s" % kind)
			return
		var item_local := Vector2(16.0, 14.0)
		var item_screen := Vector2i(source.get_screen_transform() * item_local)
		if not lifetime._source_hover_is_valid(source, item_screen, item_local, scoped):
			_fail("Item hover incorrectly rejected: %s" % kind)
			return
		var outside_local := Vector2(16.0, 100.0)
		var item_rect := Rect2i(item_screen - Vector2i(10, 10), Vector2i(40, 25))
		if lifetime._source_hover_is_valid(source, Vector2i(source.get_screen_transform() * outside_local), outside_local, {"trigger_rect": item_rect, "item_only_source_hover": true}):
			_fail("A different row keeps the old %s tooltip alive" % kind)
			return
		var navigation: BTScriptEditorNavigationTooltip = Navigation.new()
		navigation._tooltip_lifetime = Lifetime.new()
		navigation._watch_control(source, kind)
		var entry: Dictionary = navigation._watched_controls[source.get_instance_id()]
		entry["trigger_rect"] = item_rect
		entry["hover_key"] = "method_1"
		navigation._watched_controls[source.get_instance_id()] = entry
		navigation._show_documentation_popup(source, entry, {
			"title": "method_1", "documentation": {"description": "Example method."}
		})
		var popup_ref := (navigation._watched_controls[source.get_instance_id()] as Dictionary).get("popup_reference", null) as WeakRef
		var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
		if not is_instance_valid(popup):
			_fail("No navigation popup created: %s" % kind)
			return
		# Opening the window must not restore Godot's exclusive popup behavior.
		popup.popup(Rect2i(Vector2i(70, 80), Vector2i(230, 130)))
		if popup.get_flag(Window.FLAG_POPUP) or not popup.get_flag(Window.FLAG_NO_FOCUS):
			_fail("Navigation popup intercepts clicks or keyboard focus: %s" % kind)
			return
		navigation._register_navigation_popup_lifetime(popup, source.get_instance_id(), source, item_rect)
		var session: Dictionary = navigation._tooltip_lifetime._sessions.get(popup.get_instance_id(), {})
		if not bool(session.get("item_only_source_hover", false)):
			_fail("Navigation lifetime is not scoped to an item: %s" % kind)
			return
		navigation.cleanup()
		source.queue_free()
		await process_frame
	print("Navigation popup scrollbar/focus regression: PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
