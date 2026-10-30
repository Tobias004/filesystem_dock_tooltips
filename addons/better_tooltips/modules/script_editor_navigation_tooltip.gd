@tool
class_name BTScriptEditorNavigationTooltip
extends RefCounted

## Adds shared project documentation/resource previews to ScriptEditor navigation
## controls. It recognizes Godot's stock open-file and method lists, plus
## optional Quill IDE and Script-IDE tabs/outlines from public controls and metadata. Third-party
## plugins are never modified: the integration only observes the controls they add.

const Settings := preload(
	"res://addons/better_tooltips/tooltip_settings.gd"
)
const DocumentationParser := preload(
	"res://addons/better_tooltips/core/gdscript_documentation_parser.gd"
)
const DocumentationRenderer := preload(
	"res://addons/better_tooltips/core/documentation_renderer.gd"
)
const TooltipAppearance := preload(
	"res://addons/better_tooltips/core/tooltip_appearance.gd"
)
const TextPreviewRenderer := preload(
	"res://addons/better_tooltips/core/text_preview_renderer.gd"
)
const TooltipLifetime := preload(
	"res://addons/better_tooltips/core/tooltip_lifetime_manager.gd"
)

const TOOLTIP_PANEL_VARIATION := &"TooltipPanel"
const POPUP_NAME := &"BTScriptNavigationTooltip"
const NATIVE_SECTION_NAME := &"BTNavigationDocumentation"
const TIMER_NAME := &"BTScriptNavigationTooltipTimer"
const MIN_WIDTH := 420.0
const MAX_WIDTH := 760.0
const HORIZONTAL_PADDING := 28.0

var _script_editor: ScriptEditor = null
var _renderer: BTDocumentationRenderer = null
var _preview_pipeline: BTTooltipPipeline = null
var _watched_controls: Dictionary = {}
var _tooltip_lifetime: RefCounted = null

# Starts observing navigation controls that belong to Godot's ScriptEditor. The
# caller may invoke refresh_controls() again whenever editor/plugin layouts change.
func setup(
	script_editor: ScriptEditor,
	preview_pipeline: BTTooltipPipeline = null
) -> void:
	_script_editor = script_editor
	_preview_pipeline = preview_pipeline
	if _tooltip_lifetime == null:
		_tooltip_lifetime = TooltipLifetime.new()
	refresh_controls()

# Disconnects every observed navigation control and closes any add-on popup.
# Native script-path tooltips are never modified by this integration.
func cleanup() -> void:
	for control_id_value in _watched_controls.keys():
		_disconnect_control(int(control_id_value))
	_watched_controls.clear()
	if _tooltip_lifetime != null:
		_tooltip_lifetime.clear()
	_tooltip_lifetime = null
	_renderer = null
	_preview_pipeline = null
	_script_editor = null

# Cancels pending/visible navigation tooltips when the editor window loses focus.
func cancel_active_tooltips() -> void:
	for control_id_value in _watched_controls.keys():
		_stop_hover(int(control_id_value), true)

# Discovers controls by behavior rather than fixed editor-node positions. The
# stock script list is identified by .gd resource metadata/tooltips. Quill is
# recognized from the signal connections installed by its managers, while
# Script-IDE is recognized from the scripts attached to its custom tab/outline
# controls. Each compatibility bridge can be disabled independently.
func refresh_controls() -> void:
	if not is_instance_valid(_script_editor):
		return
	_prune_dead_controls()
	for candidate in _script_editor.find_children("*", "ItemList", true, false):
		var item_list := candidate as ItemList
		if item_list == null:
			continue
		if _looks_like_script_list(item_list):
			_watch_control(item_list, &"script_list")
		elif _looks_like_stock_method_list(item_list):
			_watch_control(item_list, &"stock_method_list")
	# Godot 4.8 changed the built-in method overview to a Tree, grouped by
	# inner class. This is separate from the optional Quill outline Tree.
	for candidate in _script_editor.find_children("*", "Tree", true, false):
		var tree := candidate as Tree
		if tree != null and _looks_like_stock_method_tree(tree):
			_watch_control(tree, &"stock_method_tree")
	var optional_control_ids: Dictionary = {}
	if Settings.is_quill_ide_integration_enabled():
		for candidate in _script_editor.find_children("*", "TabContainer", true, false):
			var tab_container := candidate as TabContainer
			if tab_container == null:
				continue
			var tab_bar := tab_container.get_tab_bar()
			if tab_bar == null or not _looks_like_quill_tab_bar(tab_bar):
				continue
			_watch_control(tab_bar, &"quill_script_tabs", tab_container)
			optional_control_ids[tab_bar.get_instance_id()] = true
		for candidate in _script_editor.find_children("*", "Tree", true, false):
			var tree := candidate as Tree
			if tree == null or not _looks_like_quill_outline(tree):
				continue
			_watch_control(tree, &"quill_outline_tree")
			optional_control_ids[tree.get_instance_id()] = true
	if Settings.is_script_ide_integration_enabled():
		for candidate in _script_editor.find_children("*", "Button", true, false):
			var button := candidate as Button
			if button == null or not _looks_like_script_ide_tab(button):
				continue
			_watch_control(button, &"script_ide_tab")
			optional_control_ids[button.get_instance_id()] = true
		for candidate in _script_editor.find_children("*", "ItemList", true, false):
			var outline := candidate as ItemList
			if outline == null or not _looks_like_script_ide_outline(outline):
				continue
			_watch_control(outline, &"script_ide_outline")
			optional_control_ids[outline.get_instance_id()] = true
	_disconnect_optional_controls_not_in(optional_control_ids)

func _watch_control(
	control: Control,
	kind: StringName,
	related_control: Control = null
) -> void:
	if not is_instance_valid(control):
		return
	var control_id := control.get_instance_id()
	if _watched_controls.has(control_id):
		var existing: Dictionary = _watched_controls[control_id]
		existing["kind"] = kind
		existing["related_reference"] = (
			weakref(related_control) if is_instance_valid(related_control) else null
		)
		_watched_controls[control_id] = existing
		_repair_control_connections(control, existing)
		return
	var gui_callback := Callable(self, "_on_control_gui_input").bind(control)
	var exit_callback := Callable(self, "_on_control_mouse_exited").bind(control)
	var child_callback := Callable(self, "_on_control_child_entered").bind(control)
	control.gui_input.connect(gui_callback)
	control.mouse_exited.connect(exit_callback)
	control.child_entered_tree.connect(child_callback)
	var timer := Timer.new()
	timer.name = TIMER_NAME
	timer.one_shot = true
	timer.wait_time = _get_tooltip_delay_seconds()
	control.add_child(timer)
	var timer_callback := Callable(self, "_on_tooltip_timer_timeout").bind(control)
	timer.timeout.connect(timer_callback)
	_watched_controls[control_id] = {
		"reference": weakref(control),
		"kind": kind,
		"related_reference": (
			weakref(related_control) if is_instance_valid(related_control) else null
		),
		"gui_callback": gui_callback,
		"exit_callback": exit_callback,
		"child_callback": child_callback,
		"timer_reference": weakref(timer),
		"timer_callback": timer_callback,
		"hover_key": "",
		"resolved": {},
		"trigger_rect": Rect2i(),
		"pending_hover_key": "",
		"pending_trigger_rect": Rect2i(),
		"popup_reference": null,
	}

func _repair_control_connections(control: Control, entry: Dictionary) -> void:
	var gui_callback: Callable = entry.get("gui_callback", Callable())
	if gui_callback.is_valid() and not control.gui_input.is_connected(gui_callback):
		control.gui_input.connect(gui_callback)
	var exit_callback: Callable = entry.get("exit_callback", Callable())
	if exit_callback.is_valid() and not control.mouse_exited.is_connected(exit_callback):
		control.mouse_exited.connect(exit_callback)
	var child_callback: Callable = entry.get("child_callback", Callable())
	if child_callback.is_valid() and not control.child_entered_tree.is_connected(child_callback):
		control.child_entered_tree.connect(child_callback)

func _disconnect_control(control_id: int) -> void:
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	var reference := entry.get("reference", null) as WeakRef
	var control := reference.get_ref() as Control if reference != null else null
	if is_instance_valid(control):
		var gui_callback: Callable = entry.get("gui_callback", Callable())
		if gui_callback.is_valid() and control.gui_input.is_connected(gui_callback):
			control.gui_input.disconnect(gui_callback)
		var exit_callback: Callable = entry.get("exit_callback", Callable())
		if exit_callback.is_valid() and control.mouse_exited.is_connected(exit_callback):
			control.mouse_exited.disconnect(exit_callback)
		var child_callback: Callable = entry.get("child_callback", Callable())
		if child_callback.is_valid() and control.child_entered_tree.is_connected(child_callback):
			control.child_entered_tree.disconnect(child_callback)
	_close_popup(entry)
	var timer_reference := entry.get("timer_reference", null) as WeakRef
	var timer := timer_reference.get_ref() as Timer if timer_reference != null else null
	if is_instance_valid(timer):
		var timer_callback: Callable = entry.get("timer_callback", Callable())
		if timer_callback.is_valid() and timer.timeout.is_connected(timer_callback):
			timer.timeout.disconnect(timer_callback)
		timer.queue_free()
	_watched_controls.erase(control_id)

func _prune_dead_controls() -> void:
	for control_id_value in _watched_controls.keys():
		var control_id := int(control_id_value)
		var entry: Dictionary = _watched_controls[control_id]
		var reference := entry.get("reference", null) as WeakRef
		var control := reference.get_ref() as Control if reference != null else null
		if not is_instance_valid(control):
			_disconnect_control(control_id)

# Removes optional third-party navigation watchers that are no longer discovered,
# including all controls from an integration disabled in Settings. Standard Godot
# script-list watchers are deliberately not touched.
func _disconnect_optional_controls_not_in(active_ids: Dictionary) -> void:
	for control_id_value in _watched_controls.keys():
		var control_id := int(control_id_value)
		var entry: Dictionary = _watched_controls.get(control_id, {}) as Dictionary
		var kind := StringName(entry.get("kind", &""))
		if kind not in [
			&"quill_script_tabs",
			&"quill_outline_tree",
			&"script_ide_tab",
			&"script_ide_outline",
		]:
			continue
		if not active_ids.has(control_id):
			_disconnect_control(control_id)

func _on_control_gui_input(event: InputEvent, control: Control) -> void:
	if not is_instance_valid(control):
		return
	if event is InputEventMouseButton:
		# Fallback for editor controls that receive gui_input before the editor
		# plugin's global _input callback. Do not let ItemList/Tree scroll or
		# close a tooltip when the central router consumes the wheel.
		if _preview_pipeline != null and _preview_pipeline.handle_input(event):
			control.accept_event()
			return
		_stop_hover(control.get_instance_id(), true)
		return
	if not (event is InputEventMouseMotion):
		return
	_update_hover_target(control, event.position)

# Updates one watched navigation control when the pointed item changes. Keeping
# this in one path lets normal mouse events and the popup-time monitor behave
# identically.
func _update_hover_target(control: Control, mouse_position: Vector2) -> void:
	if not is_instance_valid(control):
		return
	var control_id := control.get_instance_id()
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	var hover := _resolve_hover(control, entry, mouse_position)
	var hover_key := str(hover.get("hover_key", "")) if not hover.is_empty() else ""
	var current_key := str(entry.get("hover_key", ""))
	var timer := _get_timer(entry)
	var popup_ref := entry.get("popup_reference", null) as WeakRef
	var active_popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
	var has_popup := is_instance_valid(active_popup) and active_popup.visible

	if current_key == hover_key:
		# Crossing back over the original row must cancel a pending switch.
		if not str(entry.get("pending_hover_key", "")).is_empty():
			_clear_pending_navigation_hover(control_id)
		return

	if has_popup:
		# Moving from the original row into the popup can cross other outline
		# entries. Do not destroy a usable popup on the first motion event from
		# such a row. A genuinely different hovered row replaces it only after
		# the normal tooltip delay, provided the pointer is still on that row.
		# Empty space and the gap to the popup are handled by the lifetime manager.
		if hover.is_empty():
			_clear_pending_navigation_hover(control_id)
			return
		if hover_key == str(entry.get("pending_hover_key", "")):
			return
		entry["pending_hover_key"] = hover_key
		entry["pending_trigger_rect"] = _navigation_trigger_screen_rect(control, mouse_position)
		_watched_controls[control_id] = entry
		if timer != null:
			timer.wait_time = _get_tooltip_delay_seconds()
			timer.start()
		return

	_stop_hover(control_id, true)
	if hover.is_empty():
		return
	entry = _watched_controls.get(control_id, {}) as Dictionary
	entry["hover_key"] = hover_key
	entry["resolved"] = hover.get("resolved", {})
	# Capture the original item geometry before the delayed popup appears.
	entry["trigger_rect"] = _navigation_trigger_screen_rect(control, mouse_position)
	_watched_controls[control_id] = entry
	if _uses_native_path_tooltip(entry):
		return
	if timer != null:
		timer.wait_time = _get_tooltip_delay_seconds()
		timer.start()


func _clear_pending_navigation_hover(control_id: int) -> void:
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	if str(entry.get("pending_hover_key", "")).is_empty():
		return
	var timer := _get_timer(entry)
	if timer != null:
		timer.stop()
	entry["pending_hover_key"] = ""
	entry["pending_trigger_rect"] = Rect2i()
	_watched_controls[control_id] = entry

# Only item resolution belongs here. The shared lifetime manager performs the
# hover-area, pointer-gap and drag checks before invoking this callback.
func _on_navigation_popup_source_hover(control_id: int) -> void:
	var entry: Dictionary = _watched_controls.get(control_id, {}) as Dictionary
	if entry.is_empty():
		return
	var control_ref := entry.get("reference", null) as WeakRef
	var control := control_ref.get_ref() as Control if control_ref != null else null
	if is_instance_valid(control):
		_update_hover_target(control, control.get_local_mouse_position())

func _on_navigation_popup_lifetime_expired(control_id: int) -> void:
	_stop_hover(control_id, true)

func _on_control_mouse_exited(control: Control) -> void:
	if is_instance_valid(control):
		call_deferred("_verify_control_mouse_exit", weakref(control))

# Tooltip PopupPanels are subwindows and can make Godot emit mouse_exited on the
# owner even though the pointer is physically still over the same tab/item. Use
# the Control's own coordinate transform instead of mixing DisplayServer screen
# coordinates with editor-Control coordinates. This avoids Quill's tab tooltip
# being repeatedly closed and rearmed after the popup appears.
func _verify_control_mouse_exit(control_reference: WeakRef) -> void:
	if control_reference == null:
		return
	var control := control_reference.get_ref() as Control
	if not is_instance_valid(control):
		return
	var local_mouse := control.get_local_mouse_position()
	if Rect2(Vector2.ZERO, control.size).has_point(local_mouse):
		return
	var control_id := control.get_instance_id()
	_clear_pending_navigation_hover(control_id)
	var entry: Dictionary = _watched_controls.get(control_id, {})
	# A visible navigation popup manages its own close delay in the monitor.
	# Closing here would prevent crossing the popup's small pointer gap.
	var popup_reference := entry.get("popup_reference", null) as WeakRef
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	if is_instance_valid(popup) and popup.visible:
		return
	_stop_hover(control.get_instance_id(), true)

# Standard script lists/tabs already have a native resource-path tooltip. Rather
# than suppressing it or opening a competing subwindow, extend that same Godot
# TooltipPanel with the shared documentation renderer. This mirrors the CodeEdit
# integration and avoids Quill's native/custom tooltip windows fighting each other.
func _on_control_child_entered(node: Node, control: Control) -> void:
	if not (node is PopupPanel) or not is_instance_valid(control):
		return
	var popup := node as PopupPanel
	if popup.name == POPUP_NAME or popup.theme_type_variation != TOOLTIP_PANEL_VARIATION:
		return
	var control_id := control.get_instance_id()
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	if not _uses_native_path_tooltip(entry):
		return
	if (entry.get("resolved", {}) as Dictionary).is_empty():
		return
	call_deferred(
		"_finish_native_navigation_tooltip",
		weakref(popup),
		weakref(control)
	)

func _finish_native_navigation_tooltip(
	popup_reference: WeakRef,
	control_reference: WeakRef
) -> void:
	if popup_reference == null or control_reference == null:
		return
	var popup := popup_reference.get_ref() as PopupPanel
	var control := control_reference.get_ref() as Control
	if not is_instance_valid(popup) or not is_instance_valid(control):
		return
	if popup.theme_type_variation != TOOLTIP_PANEL_VARIATION:
		return
	if popup.has_node(NodePath(str(NATIVE_SECTION_NAME))):
		return
	var control_id := control.get_instance_id()
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	if not _uses_native_path_tooltip(entry):
		return
	var resolved := entry.get("resolved", {}) as Dictionary
	if resolved.is_empty():
		return
	var native_root := _find_native_tooltip_root(popup)
	if native_root == null:
		return
	var renderer := _get_renderer()
	renderer.refresh_theme()
	var title_text := str(resolved.get("title", ""))
	var documentation := resolved.get("documentation", {}) as Dictionary
	var resource_path := str(resolved.get("resource_path", ""))
	var has_documentation := not title_text.is_empty() and not documentation.is_empty()
	var has_preview := (
		_preview_pipeline != null
		and not resource_path.is_empty()
		and _preview_pipeline.supports_preview_path(resource_path)
	)
	if not has_documentation and not has_preview:
		return
	# Godot's default tooltip content is usually a TooltipLabel directly below the
	# PopupPanel. Wrap that existing root and every add-on section in one VBox so
	# opened-file lists and Quill/Script-IDE tabs reuse the exact same preview path
	# as FileSystem and Code Editor tooltips.
	var combined := VBoxContainer.new()
	combined.name = NATIVE_SECTION_NAME
	combined.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(combined)
	native_root.reparent(combined)
	combined.move_child(native_root, 0)
	if has_documentation:
		var content_width := _calculate_width(documentation, title_text, renderer)
		combined.add_child(_create_documentation_panel(resolved, content_width, renderer))
	if has_preview:
		_preview_pipeline.append_preview_for_path(
			resource_path,
			combined,
			popup,
			{
				"source": "script_navigation_native",
				"trigger_control": control,
			}
		)
	popup.reset_size()

func _find_native_tooltip_root(popup: PopupPanel) -> Control:
	if popup == null:
		return null
	for candidate in popup.find_children("*", "Label", true, false):
		var label := candidate as Label
		if label == null or label.theme_type_variation != &"TooltipLabel":
			continue
		var root: Control = label
		while root.get_parent() != popup:
			var parent_control := root.get_parent() as Control
			if parent_control == null:
				return null
			root = parent_control
		return root
	return null

func _uses_native_path_tooltip(entry: Dictionary) -> bool:
	return StringName(entry.get("kind", &"")) in [
		&"script_list",
		&"quill_script_tabs",
		&"script_ide_tab",
	]

func _on_tooltip_timer_timeout(control: Control) -> void:
	if not is_instance_valid(control):
		return
	call_deferred("_show_pending_tooltip", weakref(control))

func _show_pending_tooltip(control_reference: WeakRef) -> void:
	if control_reference == null:
		return
	var control := control_reference.get_ref() as Control
	if not is_instance_valid(control):
		return
	var control_id := control.get_instance_id()
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	var pending_key := str(entry.get("pending_hover_key", ""))
	var current_popup_ref := entry.get("popup_reference", null) as WeakRef
	var current_popup := (
		current_popup_ref.get_ref() as PopupPanel
		if current_popup_ref != null else null
	)
	# A deferred timer can fire after the pending hover was cancelled. Never
	# rebuild the already-visible original popup in that case.
	if pending_key.is_empty() and is_instance_valid(current_popup) and current_popup.visible:
		return
	if not pending_key.is_empty():
		# An already-open popup must not be replaced after the pointer has
		# crossed into it, or after the new hover target has changed again.
		var popup_ref := entry.get("popup_reference", null) as WeakRef
		var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
		var pointer := DisplayServer.mouse_get_position()
		if is_instance_valid(popup) and Rect2i(popup.position, popup.size).grow(3).has_point(pointer):
			_clear_pending_navigation_hover(control_id)
			return
		var current_hover := _resolve_hover(control, entry, control.get_local_mouse_position())
		if str(current_hover.get("hover_key", "")) != pending_key:
			_clear_pending_navigation_hover(control_id)
			return
		_close_popup(entry)
		entry["popup_reference"] = null
		entry["hover_key"] = pending_key
		entry["resolved"] = current_hover.get("resolved", {})
		entry["trigger_rect"] = entry.get("pending_trigger_rect", Rect2i())
		entry["pending_hover_key"] = ""
		entry["pending_trigger_rect"] = Rect2i()
		_watched_controls[control_id] = entry
	var resolved := entry.get("resolved", {}) as Dictionary
	if resolved.is_empty():
		return
	_show_documentation_popup(control, entry, resolved)

# Resolves one hover target into renderer-ready documentation. Script list/tabs
# show the script class documentation; Quill outline items show the documentation
# of the corresponding member in the currently edited script.
func _resolve_hover(
	control: Control,
	entry: Dictionary,
	mouse_position: Vector2
) -> Dictionary:
	match StringName(entry.get("kind", &"")):
		&"script_list":
			return _resolve_script_list_hover(control as ItemList, mouse_position)
		&"stock_method_list":
			return _resolve_stock_method_hover(control as ItemList, mouse_position)
		&"stock_method_tree":
			return _resolve_stock_method_tree_hover(control as Tree, mouse_position)
		&"quill_script_tabs":
			return _resolve_script_tab_hover(control as TabBar, entry, mouse_position)
		&"quill_outline_tree":
			return _resolve_outline_hover(control as Tree, mouse_position)
		&"script_ide_tab":
			return _resolve_script_ide_tab_hover(control as Button, entry, mouse_position)
		&"script_ide_outline":
			return _resolve_script_ide_outline_hover(control as ItemList, mouse_position)
	return {}

func _resolve_script_list_hover(item_list: ItemList, mouse_position: Vector2) -> Dictionary:
	if item_list == null:
		return {}
	var index := item_list.get_item_at_position(mouse_position, false)
	if index < 0:
		return {}
	var path := _get_item_list_navigation_path(item_list, index)
	var resolved := _resolve_navigation_path(path)
	if resolved.is_empty():
		return {}
	resolved["ui_index"] = index
	return {
		"hover_key": "file:%d:%s" % [index, path],
		"index": index,
		"resolved": resolved,
	}

# Godot's built-in "Filter Methods" list stores the method name as item text
# and a zero-based source line as item metadata. Unlike the open-script list,
# these integer values are NOT file paths. Reuse the same source-only member
# resolver used by Quill and Script-IDE, using the line to disambiguate names.
func _resolve_stock_method_hover(
	item_list: ItemList,
	mouse_position: Vector2
) -> Dictionary:
	if item_list == null or not item_list.is_visible_in_tree():
		return {}
	var index := item_list.get_item_at_position(mouse_position, true)
	if index < 0:
		return {}
	var line_value: Variant = item_list.get_item_metadata(index)
	if not (line_value is int):
		return {}
	var label := item_list.get_item_text(index).strip_edges()
	if label.is_empty():
		return {}
	# Inner-class functions can be displayed as InnerClass.method. The parser
	# identifies the declaration by its final identifier and nearest source line.
	var symbol := label.get_slice("(", 0).strip_edges()
	if symbol.contains("."):
		symbol = symbol.substr(symbol.rfind(".") + 1)
	if symbol.is_empty():
		return {}
	var resolved := _resolve_current_member(symbol, int(line_value))
	if resolved.is_empty():
		return {}
	return {
		"hover_key": "stock_method:%d:%s:%d" % [index, label, int(line_value)],
		"resolved": resolved,
	}

# Godot 4.8's stock method outline uses TreeItems with an integer source
# line and a "function" metadata string. Group headings are not selectable and
# must never be interpreted as symbols.
func _resolve_stock_method_tree_hover(tree: Tree, mouse_position: Vector2) -> Dictionary:
	if tree == null or not tree.is_visible_in_tree():
		return {}
	var item := tree.get_item_at_position(mouse_position)
	if item == null or not item.is_selectable(0):
		return {}
	var line_value: Variant = item.get_metadata(0)
	if not (line_value is int):
		return {}
	var label := item.get_text(0).strip_edges()
	if label.is_empty():
		return {}
	var symbol := label.get_slice("(", 0).strip_edges()
	if symbol.contains("."):
		symbol = symbol.substr(symbol.rfind(".") + 1)
	if symbol.is_empty():
		return {}
	var resolved := _resolve_current_member(symbol, int(line_value))
	if resolved.is_empty():
		return {}
	return {
		"hover_key": "stock_tree_method:%d:%s:%d" % [
			item.get_instance_id(), symbol, int(line_value)
		],
		"resolved": resolved,
	}

func _resolve_script_tab_hover(
	tab_bar: TabBar,
	entry: Dictionary,
	mouse_position: Vector2
) -> Dictionary:
	if tab_bar == null or not tab_bar.has_method("get_tab_idx_at_point"):
		return {}
	var index := int(tab_bar.call("get_tab_idx_at_point", mouse_position))
	if index < 0:
		return {}
	var related_reference := entry.get("related_reference", null) as WeakRef
	var tab_container := (
		related_reference.get_ref() as TabContainer
		if related_reference != null else null
	)
	if not is_instance_valid(tab_container):
		return {}
	var path := _get_tab_navigation_path(tab_container, tab_bar, index)
	var resolved := _resolve_navigation_path(path)
	if resolved.is_empty():
		return {}
	resolved["ui_index"] = index
	return {
		"hover_key": "tab:%d:%s" % [index, path],
		"index": index,
		"resolved": resolved,
	}

# Script-IDE implements its tabs as custom Button controls rather than a TabBar.
# Their native tooltip contains the script resource path used by Script-IDE's own
# tab synchronization, so the class documentation can be resolved without
# modifying Script-IDE or reaching into its manager object.
func _resolve_script_ide_tab_hover(
	button: Button,
	entry: Dictionary,
	mouse_position: Vector2
) -> Dictionary:
	if button == null or not Rect2(Vector2.ZERO, button.size).has_point(mouse_position):
		return {}
	var path := _project_path_from_text(button.tooltip_text)
	var resolved := _resolve_navigation_path(path)
	if resolved.is_empty():
		return {}
	resolved["ui_index"] = 0
	return {
		"hover_key": "script_ide_tab:%d:%s" % [button.get_instance_id(), path],
		"index": 0,
		"resolved": resolved,
	}

# Script-IDE's outline is an ItemList using {type, modifier} metadata. Function
# labels contain signatures, therefore only the identifier before '(' is used
# for source-documentation lookup.
func _resolve_script_ide_outline_hover(
	item_list: ItemList,
	mouse_position: Vector2
) -> Dictionary:
	if item_list == null:
		return {}
	var index := item_list.get_item_at_position(mouse_position, false)
	if index < 0:
		return {}
	var metadata: Variant = item_list.get_item_metadata(index)
	if not (metadata is Dictionary):
		return {}
	var metadata_dictionary := metadata as Dictionary
	if not metadata_dictionary.has(&"type") or not metadata_dictionary.has(&"modifier"):
		return {}
	var label := item_list.get_item_text(index)
	var symbol := _outline_symbol_from_label(
		label,
		str(metadata_dictionary.get(&"type", ""))
	)
	if symbol.is_empty():
		return {}
	var resolved := _resolve_current_member(symbol)
	if resolved.is_empty():
		return {}
	return {
		"hover_key": "script_ide_member:%s:%s" % [
			str(metadata_dictionary.get(&"type", "")),
			symbol,
		],
		"resolved": resolved,
	}

func _outline_symbol_from_label(label: String, member_type: String) -> String:
	if member_type == "func":
		var signature_start := label.find("(")
		if signature_start >= 0:
			return label.substr(0, signature_start).strip_edges()
	return label.strip_edges()

func _resolve_outline_hover(tree: Tree, mouse_position: Vector2) -> Dictionary:
	if tree == null:
		return {}
	var item := tree.get_item_at_position(mouse_position)
	if item == null:
		return {}
	var metadata: Variant = item.get_metadata(0)
	if not (metadata is Dictionary):
		return {}
	var metadata_dictionary := metadata as Dictionary
	if not metadata_dictionary.has(&"type") or not metadata_dictionary.has(&"modifier"):
		return {}
	var symbol := item.get_text(0)
	if symbol.is_empty():
		return {}
	var resolved := _resolve_current_member(symbol)
	if resolved.is_empty():
		return {}
	return {
		"hover_key": "member:%s:%s" % [str(metadata_dictionary.get(&"type", "")), symbol],
		"resolved": resolved,
	}

# Resolves a script-list/tab resource to its class_name documentation. Scripts
# without class_name or without enabled documentation keep their normal path tooltip.
func _resolve_script_class(path: String) -> Dictionary:
	if path.is_empty() or not path.ends_with(".gd"):
		return {}
	var source := _read_script_source(path)
	if source.is_empty():
		return {}
	var class_name_value := DocumentationParser.get_script_class_name(source)
	if class_name_value.is_empty():
		return {}
	var documentation := DocumentationParser.find_member_documentation(
		source,
		class_name_value,
		-1,
		Settings.is_documentation_comments_enabled(),
		Settings.is_single_hash_member_documentation_enabled()
	)
	if documentation.is_empty():
		return {}
	var base_class := ""
	for class_entry_value in ProjectSettings.get_global_class_list():
		if not (class_entry_value is Dictionary):
			continue
		var class_entry := class_entry_value as Dictionary
		if (
			str(class_entry.get("class", "")) == class_name_value
			or str(class_entry.get("path", "")) == path
		):
			base_class = str(class_entry.get("base", ""))
			break
	return {
		"documentation": documentation,
		"context_class": class_name_value,
		"title": "Class %s%s" % [
			class_name_value,
			(" < " + base_class) if not base_class.is_empty() else "",
		],
		"source_path": path,
	}

# Uses the current CodeEdit text when available so Quill's outline immediately
# reflects unsaved documentation edits just like the normal Code Editor tooltip.
func _resolve_current_member(symbol: String, source_line: int = -1) -> Dictionary:
	if not is_instance_valid(_script_editor) or symbol.is_empty():
		return {}
	var current_script := _script_editor.get_current_script()
	if current_script == null:
		return {}
	var source := ""
	var current_editor := _script_editor.get_current_editor()
	if current_editor != null:
		var base_editor := current_editor.get_base_editor()
		if base_editor is CodeEdit:
			source = (base_editor as CodeEdit).text
	if source.is_empty():
		source = current_script.source_code
	if source.is_empty():
		source = _read_script_source(current_script.resource_path)
	return _resolve_member_from_source(source, current_script.resource_path, symbol, source_line)

# Source-only counterpart used by the navigation bridges and regression tests.
# It deliberately shares DocumentationParser.find_resource_reference() with the
# normal Code Editor integration rather than introducing plugin-specific Resource
# parsing for Quill or Script-IDE.
func _resolve_member_from_source(
	source: String,
	source_path: String,
	symbol: String,
	source_line: int = -1
) -> Dictionary:
	if source.is_empty() or symbol.is_empty():
		return {}
	var context_class := DocumentationParser.get_script_class_name(source)
	var result: Dictionary = {
		"context_class": context_class,
		"source_path": source_path,
	}
	var method_source := DocumentationParser.extract_method_source(source, symbol, source_line)
	var documentation := (
		DocumentationParser.find_method_documentation_at_line(
			source,
			symbol,
			int(method_source.get("line", -1)),
			Settings.is_documentation_comments_enabled(),
			Settings.is_single_hash_member_documentation_enabled()
		)
		if not method_source.is_empty() else DocumentationParser.find_member_documentation(
			source,
			symbol,
			source_line,
			Settings.is_documentation_comments_enabled(),
			Settings.is_single_hash_member_documentation_enabled()
		)
	)
	if not documentation.is_empty():
		var kind := str(documentation.get("member_kind", "member"))
		result["documentation"] = documentation
		result["title"] = _format_member_title(kind, context_class, symbol)

	var resource_reference := DocumentationParser.find_resource_reference(
		source,
		symbol,
		-1
	)
	var resource_path := str(resource_reference.get("path", ""))
	# Script constants are loadable GDScript Resources but deliberately are not
	# part of the graphical preview pipeline. Show the referenced class docs in
	# outlines just as CodeEdit's native help does for the same constant.
	if resource_path.ends_with(".gd") and not result.has("documentation"):
		var script_class := _resolve_script_class(resource_path)
		if not script_class.is_empty():
			result["documentation"] = script_class["documentation"]
			result["title"] = _format_member_title("constant", context_class, symbol)
			# Rich-text member links belong to the referenced class, not the
			# showcase script that declares the preload constant.
			result["context_class"] = str(script_class.get("context_class", ""))
			result["referenced_script_path"] = resource_path
	if _preview_pipeline != null:
		if (
			not resource_path.is_empty()
			and _preview_pipeline.supports_preview_path(resource_path)
		):
			result["resource_path"] = resource_path
			if not result.has("title"):
				var qualified := symbol if context_class.is_empty() else "%s.%s" % [
					context_class,
					symbol,
				]
				result["title"] = "Project file %s" % qualified
	# The method's source is useful even without a ##/# documentation comment.
	# Other outline entries continue using the existing documentation/preview path.
	if not method_source.is_empty():
		result["method_source"] = str(method_source.get("text", ""))
		result["method_line"] = int(method_source.get("line", -1))
		if not result.has("title"):
			result["title"] = _format_member_title("function", context_class, symbol)
	if (
		not result.has("documentation")
		and not result.has("resource_path")
		and not result.has("method_source")
	):
		return {}
	return result

func _format_member_title(kind: String, context_class: String, symbol: String) -> String:
	var kind_label := "Member"
	match kind:
		"function":
			kind_label = "Method"
		"property":
			kind_label = "Property"
		"signal":
			kind_label = "Signal"
		"constant":
			kind_label = "Constant"
		"enum":
			kind_label = "Enum"
		"enum_value":
			kind_label = "Enum value"
		"inner_class":
			kind_label = "Class"
		"class":
			kind_label = "Class"
	var qualified := symbol if context_class.is_empty() else "%s.%s" % [context_class, symbol]
	return "%s %s" % [kind_label, qualified]

func _show_documentation_popup(
	control: Control,
	entry: Dictionary,
	resolved: Dictionary
) -> void:
	_close_popup(entry)
	var documentation := resolved.get("documentation", {}) as Dictionary
	var title_text := str(resolved.get("title", ""))
	var resource_path := str(resolved.get("resource_path", ""))
	var has_documentation := not documentation.is_empty() and not title_text.is_empty()
	var method_source := str(resolved.get("method_source", ""))
	var has_preview := (
		_preview_pipeline != null
		and not resource_path.is_empty()
		and _preview_pipeline.supports_preview_path(resource_path)
	)
	var has_live_text_preview := (
		has_preview
		and _preview_pipeline.supports_live_text_preview_path(resource_path)
	)
	if not has_documentation and not has_preview and method_source.is_empty():
		return
	var renderer := _get_renderer()
	renderer.refresh_theme()
	var content_width := (
		_calculate_width(documentation, title_text, renderer)
		if has_documentation else MIN_WIDTH * EditorInterface.get_editor_scale()
	)
	var popup := PopupPanel.new()
	popup.name = POPUP_NAME
	popup.theme_type_variation = TOOLTIP_PANEL_VARIATION
	popup.wrap_controls = true
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	var popup_parent := EditorInterface.get_base_control()
	if is_instance_valid(popup_parent):
		popup_parent.add_child(popup)
	else:
		control.add_child(popup)
	var combined := VBoxContainer.new()
	combined.name = &"BTNavigationContent"
	combined.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(combined)
	if has_documentation:
		combined.add_child(_create_documentation_panel(resolved, content_width, renderer, not method_source.is_empty()))
	elif not title_text.is_empty():
		combined.add_child(_create_resource_title_panel(title_text, renderer))
	if not method_source.is_empty():
		combined.add_child(_create_method_source_panel(method_source))
	if has_preview:
		var preview_metadata := {
			"source": "script_navigation",
			"host_manages_popup": true,
			"symbol": str(resolved.get("title", "")),
			"trigger_control": control,
		}
		if has_live_text_preview:
			preview_metadata["layout_ready_callback"] = Callable(
				self, "_show_navigation_live_preview_ready"
			).bind(weakref(popup), control.get_instance_id())
		_preview_pipeline.append_preview_for_path(
			resource_path, combined, popup, preview_metadata
		)
	var control_id := control.get_instance_id()
	if not _watched_controls.has(control_id):
		popup.queue_free()
		return
	entry = _watched_controls[control_id]
	entry["popup_reference"] = weakref(popup)
	_watched_controls[control_id] = entry
	var pointer_local := control.get_local_mouse_position()
	var trigger_rect := entry.get("trigger_rect", Rect2i()) as Rect2i
	if not trigger_rect.has_area():
		trigger_rect = _navigation_trigger_screen_rect(control, pointer_local)
	var screen_position := control.get_screen_position() + pointer_local
	# Live text previews are opened by the pipeline's layout-ready callback.
	# Graphical previews retain their existing window and zoom behavior.
	if not has_live_text_preview:
		if has_preview:
			popup.position = Vector2i(screen_position) + Vector2i(12, 20)
			popup.reset_size()
			popup.popup()
		else:
			_show_navigation_popup_after_layout(weakref(popup), Vector2i(screen_position))
	if _preview_pipeline != null:
		_preview_pipeline.register_external_text_popup(popup, combined, control)
	# Method source and documentation are sized together in the staged opener.
	if not has_live_text_preview:
		_register_navigation_popup_lifetime(popup, control_id, control, trigger_rect)

# The pipeline calls this only after a live text preview's height and scroll
# constraints have been applied. A stale callback must never reopen a popup
# after the pointer has moved to another source or the editor has rebuilt it.
func _show_navigation_live_preview_ready(popup_reference: WeakRef, control_id: int) -> void:
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	var entry: Dictionary = _watched_controls.get(control_id, {}) as Dictionary
	var current_ref := entry.get("popup_reference", null) as WeakRef
	if not is_instance_valid(popup) or current_ref == null or current_ref.get_ref() != popup:
		return
	var source_ref := entry.get("reference", null) as WeakRef
	var control := source_ref.get_ref() as Control if source_ref != null else null
	if not is_instance_valid(control):
		return
	var pointer := DisplayServer.mouse_get_position()
	var trigger_rect := entry.get("trigger_rect", Rect2i()) as Rect2i
	if not trigger_rect.grow(3).has_point(pointer):
		_stop_hover(control_id, true)
		return
	_show_navigation_popup_after_layout(
		popup_reference, pointer, control_id
	)

func _register_navigation_popup_lifetime(
	popup: PopupPanel,
	control_id: int,
	control: Control,
	trigger_rect: Rect2i
) -> void:
	if _tooltip_lifetime != null:
		_tooltip_lifetime.register_popup(
			popup, trigger_rect, control,
			Callable(self, "_on_navigation_popup_source_hover").bind(control_id),
			Callable(self, "_on_navigation_popup_lifetime_expired").bind(control_id),
			0.22, 0.05
		)

# A navigation popup belongs to the *hovered item*, not to the entire
# ItemList/Tree. Compute the item's screen rectangle before opening the PopupPanel
# so leaving the icon/row can be handled by the shared lifetime grace period.
func _navigation_trigger_screen_rect(control: Control, pointer_local: Vector2) -> Rect2i:
	var local_rect := Rect2(Vector2.ZERO, control.size)
	if control is Tree:
		var tree := control as Tree
		var item := tree.get_item_at_position(pointer_local)
		if item != null:
			local_rect = tree.get_item_area_rect(item)
	elif control is ItemList:
		var list := control as ItemList
		var index := list.get_item_at_position(pointer_local, false)
		if index >= 0:
			local_rect = list.get_item_rect(index)
	elif control is TabBar:
		var tabs := control as TabBar
		var index := tabs.get_tab_idx_at_point(pointer_local)
		if index >= 0:
			local_rect = tabs.get_tab_rect(index)
	var xform := control.get_screen_transform()
	var a := xform * local_rect.position
	var b := xform * local_rect.end
	var screen_rect := Rect2(a, b - a).abs()
	return Rect2i(Vector2i(screen_rect.position.floor()), Vector2i(screen_rect.size.ceil()))

# Wait for RichTextLabel layout before deciding whether each region needs
# a scrollbar, then constrain the combined popup to the available screen.
func _show_navigation_popup_after_layout(
	popup_reference: WeakRef,
	pointer_position: Vector2i,
	register_lifetime_control_id: int = -1
) -> void:
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	if not is_instance_valid(popup):
		return
	# Hidden windows still own a Control tree. Allow it to resolve wrapping
	# and RichTextLabel heights without exposing the initial location.
	await popup.get_tree().process_frame
	if not is_instance_valid(popup):
		return
	await popup.get_tree().process_frame
	if not is_instance_valid(popup):
		return
	var scale := EditorInterface.get_editor_scale()
	var budget := maxf(90.0 * scale, TooltipAppearance.get_text_max_height_pixels() - 110.0 * scale)
	var docs := popup.find_child("NavigationMethodDocumentation", true, false) as RichTextLabel
	var source := popup.find_child("MethodSourcePreview", true, false) as RichTextLabel
	if docs != null and source != null:
		_set_navigation_text_height(docs, minf(220.0 * scale, budget * 0.36))
		_set_navigation_text_height(source, minf(360.0 * scale, budget * 0.60))
	elif docs != null:
		_set_navigation_text_height(docs, budget)
	elif source != null:
		_set_navigation_text_height(source, budget)
	popup.reset_size()
	await popup.get_tree().process_frame
	if not is_instance_valid(popup):
		return
	popup.reset_size()
	var screen := popup.current_screen
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var margin := roundi(8.0 * scale)
	# Hidden Window.size may still be stale; account for measured contents.
	var popup_size := TooltipAppearance.prepared_text_popup_size(popup)
	var right_x := pointer_position.x + roundi(12.0 * scale)
	var left_x := pointer_position.x - popup_size.x - margin
	var below_y := pointer_position.y + roundi(20.0 * scale)
	var above_y := pointer_position.y - popup_size.y - margin
	var x := left_x if right_x + popup_size.x > usable.end.x - margin else right_x
	var y := above_y if below_y + popup_size.y > usable.end.y - margin else below_y
	x = clampi(x, usable.position.x + margin, maxi(usable.position.x + margin, usable.end.x - popup_size.x - margin))
	y = clampi(y, usable.position.y + margin, maxi(usable.position.y + margin, usable.end.y - popup_size.y - margin))
	# Window.popup(Rect2i) sets position and dimensions together. Setting the
	# position first and then calling popup() allowed Godot to size the window
	# *after* opening and visibly shift it across the hovered method row.
	popup.popup(Rect2i(Vector2i(x, y), popup_size))
	if register_lifetime_control_id >= 0:
		var entry: Dictionary = _watched_controls.get(register_lifetime_control_id, {}) as Dictionary
		var popup_ref := entry.get("popup_reference", null) as WeakRef
		var source_ref := entry.get("reference", null) as WeakRef
		var source_control := source_ref.get_ref() as Control if source_ref != null else null
		if popup_ref != null and popup_ref.get_ref() == popup and is_instance_valid(source_control):
			_register_navigation_popup_lifetime(
				popup, register_lifetime_control_id, source_control,
				entry.get("trigger_rect", Rect2i()) as Rect2i
			)

func _set_navigation_text_height(label: RichTextLabel, ceiling: float) -> void:
	var height := float(label.get_content_height())
	if height <= 0.0:
		return
	if height > ceiling:
		label.fit_content = false
		label.scroll_active = true
		label.custom_minimum_size.y = ceiling
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		label.fit_content = true
		label.scroll_active = false
		label.custom_minimum_size.y = 0.0
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.update_minimum_size()

# Reuse the existing plain-text font, spacing and selection behavior instead
# of maintaining another code-preview renderer for navigation controls.
func _create_method_source_panel(source: String) -> Control:
	return TextPreviewRenderer.create_method_source_preview(source)

# Creates a compact navigation-title block for graphical outline items that have
# no documentation comments. Quill and Script-IDE therefore still identify the
# hovered project symbol before the shared Resource preview appears below it.
func _create_resource_title_panel(
	title_text: String,
	renderer: BTDocumentationRenderer
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TooltipAppearance.style_addon_panel(panel)
	var title := Label.new()
	title.text = title_text
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	renderer.style_type_label(title)
	panel.add_child(title)
	return panel

func _create_documentation_panel(
	resolved: Dictionary,
	content_width: float,
	renderer: BTDocumentationRenderer,
	with_method_source: bool = false
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TooltipAppearance.style_addon_panel(panel)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = content_width
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	var title := Label.new()
	title.text = str(resolved.get("title", ""))
	renderer.style_type_label(title)
	content.add_child(title)
	var documentation := resolved.get("documentation", {}) as Dictionary
	var description := RichTextLabel.new()
	description.fit_content = true
	description.scroll_active = false
	description.selection_enabled = false
	description.focus_mode = Control.FOCUS_NONE
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.autowrap_trim_flags = 0
	description.custom_minimum_size.x = content_width
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	content.add_child(description)
	renderer.render_document(
		description,
		documentation,
		str(resolved.get("context_class", "")),
		false
	)
	if with_method_source:
		# Reserve screen space for the source preview below the help section.
		description.name = &"NavigationMethodDocumentation"
		description.selection_enabled = true
		# Keep small documentation blocks compact. A deferred layout pass caps
		# only the long ones, leaving space for method source below.
	else:
		TooltipAppearance.limit_rich_text_height(description)
	return panel

func _calculate_width(
	documentation: Dictionary,
	title: String,
	renderer: BTDocumentationRenderer
) -> float:
	var editor_scale := EditorInterface.get_editor_scale()
	var minimum_width := MIN_WIDTH * editor_scale
	var maximum_width := minf(MAX_WIDTH * editor_scale, TooltipAppearance.text_content_width(2000.0 * editor_scale))
	var available_width := EditorInterface.get_base_control().size.x * 0.65
	maximum_width = maxf(120.0 * editor_scale, minf(maximum_width, available_width))
	minimum_width = minf(minimum_width, maximum_width)
	var font := renderer.get_document_font()
	var font_size := renderer.get_document_font_size()
	var measured_width := font.get_string_size(
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	).x
	var plain_text := renderer.to_plain_text(str(documentation.get("description", "")))
	for line in plain_text.split("\n"):
		measured_width = maxf(
			measured_width,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	return clampf(
		measured_width + HORIZONTAL_PADDING * editor_scale,
		minimum_width,
		maximum_width
	)

func _stop_hover(control_id: int, close_popup: bool) -> void:
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	var timer := _get_timer(entry)
	if timer != null:
		timer.stop()
	if close_popup:
		_close_popup(entry)
	entry["hover_key"] = ""
	entry["resolved"] = {}
	entry["trigger_rect"] = Rect2i()
	entry["pending_hover_key"] = ""
	entry["pending_trigger_rect"] = Rect2i()
	entry["popup_reference"] = null if close_popup else entry.get("popup_reference", null)
	_watched_controls[control_id] = entry

func _close_popup(entry: Dictionary) -> void:
	var popup_reference := entry.get("popup_reference", null) as WeakRef
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	if is_instance_valid(popup):
		if _tooltip_lifetime != null:
			_tooltip_lifetime.unregister_popup(popup)
		if _preview_pipeline != null:
			_preview_pipeline.unregister_external_text_popup(popup)
		popup.hide()
		popup.queue_free()

func _get_timer(entry: Dictionary) -> Timer:
	var timer_reference := entry.get("timer_reference", null) as WeakRef
	return timer_reference.get_ref() as Timer if timer_reference != null else null

func _get_tooltip_delay_seconds() -> float:
	return maxf(
		0.05,
		float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	)

func _looks_like_script_list(item_list: ItemList) -> bool:
	for index in range(item_list.item_count):
		if not _get_item_list_navigation_path(item_list, index).is_empty():
			return true
	return false

# In Godot 4.7 the Filter Methods LineEdit is nested inside a toolbar
# HBoxContainer, while the ItemList is a direct sibling of that toolbar in
# the containing VBoxContainer. Match the native text_changed callback rather
# than relying on a localized placeholder or editor-generated node names.
func _looks_like_stock_method_list(item_list: ItemList) -> bool:
	if item_list == null:
		return false
	var parent := item_list.get_parent()
	if parent == null:
		return false
	var found_filter := false
	for child in parent.get_children():
		if child is ItemList:
			if found_filter:
				return child == item_list
			continue
		# The filter may be a direct child or embedded in a toolbar.
		if child is LineEdit and _is_stock_method_filter(child as LineEdit):
			found_filter = true
		elif child is Container:
			for descendant in child.find_children("*", "LineEdit", true, false):
				if _is_stock_method_filter(descendant as LineEdit):
					found_filter = true
					break
	return false

func _is_stock_method_filter(line_edit: LineEdit) -> bool:
	if line_edit == null:
		return false
	for signal_connection in line_edit.get_signal_connection_list(&"text_changed"):
		var callback: Callable = signal_connection.get("callable", Callable())
		if (
			callback.is_valid()
			and callback.get_object() == _script_editor
			and _callback_method_matches(callback, &"_filter_methods_text_changed")
		):
			return true
	return false

# In Godot 4.8 the stock method outline is a Tree inside DocumentOutline.
# Its filter is a LineEdit nested under a sibling toolbar and connected to the
# owning outline's update_outline() method. This structural check avoids
# matching Quill, scene trees or the help search Tree by accident.
func _looks_like_stock_method_tree(tree: Tree) -> bool:
	if tree == null:
		return false
	var parent := tree.get_parent()
	if parent == null:
		return false
	for child in parent.get_children():
		if not (child is HBoxContainer):
			continue
		for subchild in child.get_children():
			if not (subchild is LineEdit):
				continue
			var filter_edit := subchild as LineEdit
			for signal_connection in filter_edit.get_signal_connection_list(&"text_changed"):
				var callback: Callable = signal_connection.get("callable", Callable())
				if (
					callback.is_valid()
					and callback.get_object() == parent
					and _callback_method_matches(callback, &"update_outline")
				):
					return true
	return false

# Native C++ Callables include the class name in get_method(), e.g.
# "ScriptEditor::_filter_methods_text_changed" on 4.7 and
# "DocumentOutline::update_outline" on 4.8. Script-defined Callables
# normally return just the method name. Accept both representations.
func _callback_method_matches(callback: Callable, method: StringName) -> bool:
	if not callback.is_valid():
		return false
	var actual_method := str(callback.get_method())
	var expected_method := str(method)
	return (
		actual_method == expected_method
		or actual_method.ends_with("::" + expected_method)
	)

# Quill connects its manager directly to the existing ScriptEditor TabBar/Tree.
# Inspecting those public signal connections avoids treating unrelated Godot
# navigation controls as Quill when the plugin is not active.
func _looks_like_quill_tab_bar(tab_bar: TabBar) -> bool:
	return _has_quill_signal_owner(
		tab_bar, &"gui_input", "tabs.gd", &"_on_tab_bar_gui_input"
	)

func _looks_like_quill_outline(tree: Tree) -> bool:
	return _has_quill_signal_owner(
		tree, &"gui_input", "outlines.gd", &"_on_outline_tree_gui_input"
	)

func _has_quill_signal_owner(
	control: Control,
	signal_name: StringName,
	expected_script_file: String,
	expected_method: StringName
) -> bool:
	if control == null or not control.has_signal(signal_name):
		return false
	for connection_value in control.get_signal_connection_list(signal_name):
		if not (connection_value is Dictionary):
			continue
		var connection := connection_value as Dictionary
		var callback: Callable = connection.get("callable", Callable())
		if not callback.is_valid():
			continue
		var owner := callback.get_object()
		if owner == null:
			continue
		var script := owner.get_script() as Script
		if script == null:
			continue
		var path := script.resource_path.replace("\\", "/")
		if (
			path.contains("/quill-ide/")
			and path.get_file() == expected_script_file
			and callback.get_method() == expected_method
		):
			return true
	return false

# Script-IDE 2.x provides a custom Button for every top script tab. The exact
# layout can move, but the attached script path is a stable compatibility marker.
func _looks_like_script_ide_tab(button: Button) -> bool:
	return _node_script_path_matches(
		button,
		"/script-ide/tabbar/custom_tab.gd"
	)

# Script-IDE's replacement outline is the ItemList owned by OutlineContainer.
# Walking ancestors keeps this independent from the outline scene's nesting.
func _looks_like_script_ide_outline(item_list: ItemList) -> bool:
	var current: Node = item_list
	while current != null and current != _script_editor:
		if _node_script_path_matches(
			current,
			"/script-ide/outline/outline_container.gd"
		):
			return true
		current = current.get_parent()
	return false

func _node_script_path_matches(node: Node, suffix: String) -> bool:
	if node == null:
		return false
	var script := node.get_script() as Script
	if script == null:
		return false
	return script.resource_path.replace("\\", "/").ends_with(suffix)

func _get_item_list_navigation_path(item_list: ItemList, index: int) -> String:
	if index < 0 or index >= item_list.item_count:
		return ""
	var metadata: Variant = item_list.get_item_metadata(index)
	var metadata_path := _project_path_from_variant(metadata)
	if not metadata_path.is_empty():
		return metadata_path
	return _project_path_from_text(item_list.get_item_tooltip(index))

func _get_tab_navigation_path(
	tab_container: TabContainer,
	tab_bar: TabBar,
	index: int
) -> String:
	if index < 0 or index >= tab_container.get_tab_count():
		return ""
	# The visible tab tooltip is the most stable cross-plugin source and supports
	# non-Resource text files such as Markdown, unlike Script-only properties.
	if tab_bar != null and index < tab_bar.tab_count:
		var tooltip_path := _project_path_from_text(tab_bar.get_tab_tooltip(index))
		if not tooltip_path.is_empty():
			return tooltip_path
	var tab_control := tab_container.get_tab_control(index)
	if tab_control != null:
		var script_value: Variant = tab_control.get("script")
		var script_path := _project_path_from_variant(script_value)
		if not script_path.is_empty():
			return script_path
		if tab_control.has_meta("_edit_res_path"):
			var meta_path := _project_path_from_variant(
				tab_control.get_meta("_edit_res_path")
			)
			if not meta_path.is_empty():
				return meta_path
		var path_value: Variant = tab_control.get("metadata/_edit_res_path")
		var property_path := _project_path_from_variant(path_value)
		if not property_path.is_empty():
			return property_path
	return ""

# Converts the common metadata forms used by Godot/IDE plugins into one res://
# path without assuming that the file is a Script or loadable Resource.
func _project_path_from_variant(value: Variant) -> String:
	if value is Resource:
		return _project_path_from_text((value as Resource).resource_path)
	if value is Dictionary:
		var dictionary := value as Dictionary
		for key: Variant in ["path", "resource_path", "file", "script_path"]:
			if dictionary.has(key):
				var candidate := _project_path_from_text(str(dictionary.get(key, "")))
				if not candidate.is_empty():
					return candidate
	if value != null:
		return _project_path_from_text(str(value))
	return ""

func _project_path_from_text(value: String) -> String:
	var text_value := value.strip_edges()
	var start := text_value.find("res://")
	if start < 0:
		return ""
	var candidate := text_value.substr(start)
	var newline := candidate.find("\n")
	if newline >= 0:
		candidate = candidate.substr(0, newline)
	return candidate.strip_edges()

# Resolves either script documentation or any project file supported by the
# central preview pipeline. This one path is shared by Godot's open-file list,
# Quill tabs and Script-IDE tabs.
func _resolve_navigation_path(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	if path.ends_with(".gd"):
		var script_result := _resolve_script_class(path)
		if not script_result.is_empty():
			return script_result
	if _preview_pipeline != null and _preview_pipeline.supports_preview_path(path):
		return {
			"resource_path": path,
			"title": "File %s" % path.get_file(),
			"source_path": path,
		}
	return {}

func _read_script_source(path: String) -> String:
	if path.is_empty():
		return ""
	if is_instance_valid(_script_editor) and _script_editor.has_method("get_open_scripts"):
		var open_scripts_value: Variant = _script_editor.call("get_open_scripts")
		if open_scripts_value is Array:
			for script_value in (open_scripts_value as Array):
				var script := script_value as Script
				if script == null or script.resource_path != path:
					continue
				var source := script.source_code
				if not source.is_empty():
					return source
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()

func _get_renderer() -> BTDocumentationRenderer:
	if _renderer == null:
		_renderer = DocumentationRenderer.new() as BTDocumentationRenderer
		_renderer.refresh_theme()
	return _renderer
