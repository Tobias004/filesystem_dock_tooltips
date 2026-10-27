@tool
class_name BTScriptEditorNavigationTooltip
extends RefCounted

## Adds shared project documentation/resource previews to ScriptEditor navigation
## controls. It recognizes Godot's stock open-file list plus optional Quill IDE
## and Script-IDE tabs/outlines from their public controls and metadata. Third-party
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

const TOOLTIP_PANEL_VARIATION := &"TooltipPanel"
const POPUP_NAME := &"BTScriptNavigationTooltip"
const NATIVE_SECTION_NAME := &"BTNavigationDocumentation"
const TIMER_NAME := &"BTScriptNavigationTooltipTimer"
const HOVER_MONITOR_TIMER_NAME := &"BTScriptNavigationHoverMonitor"
const HOVER_MONITOR_INTERVAL_SECONDS := 0.05
const MIN_WIDTH := 420.0
const MAX_WIDTH := 760.0
const HORIZONTAL_PADDING := 28.0

var _script_editor: ScriptEditor = null
var _renderer: BTDocumentationRenderer = null
var _preview_pipeline: BTTooltipPipeline = null
var _watched_controls: Dictionary = {}

# Starts observing navigation controls that belong to Godot's ScriptEditor. The
# caller may invoke refresh_controls() again whenever editor/plugin layouts change.
func setup(
	script_editor: ScriptEditor,
	preview_pipeline: BTTooltipPipeline = null
) -> void:
	_script_editor = script_editor
	_preview_pipeline = preview_pipeline
	refresh_controls()

# Disconnects every observed navigation control and closes any add-on popup.
# Native script-path tooltips are never modified by this integration.
func cleanup() -> void:
	for control_id_value in _watched_controls.keys():
		_disconnect_control(int(control_id_value))
	_watched_controls.clear()
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
		if item_list != null and _looks_like_script_list(item_list):
			_watch_control(item_list, &"script_list")
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
	# A visible PopupPanel can intercept mouse motion before the underlying Tree
	# receives it. Poll only while our popup is visible so moving directly from one
	# Quill outline member to the next always replaces the old tooltip.
	var hover_monitor := Timer.new()
	hover_monitor.name = HOVER_MONITOR_TIMER_NAME
	hover_monitor.one_shot = false
	hover_monitor.wait_time = HOVER_MONITOR_INTERVAL_SECONDS
	control.add_child(hover_monitor)
	var hover_monitor_callback := Callable(self, "_on_hover_monitor_timeout").bind(control)
	hover_monitor.timeout.connect(hover_monitor_callback)
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
		"hover_monitor_reference": weakref(hover_monitor),
		"hover_monitor_callback": hover_monitor_callback,
		"hover_key": "",
		"resolved": {},
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
	var hover_monitor := _get_hover_monitor(entry)
	if is_instance_valid(hover_monitor):
		var hover_monitor_callback: Callable = entry.get(
			"hover_monitor_callback", Callable()
		)
		if (
			hover_monitor_callback.is_valid()
			and hover_monitor.timeout.is_connected(hover_monitor_callback)
		):
			hover_monitor.timeout.disconnect(hover_monitor_callback)
		hover_monitor.queue_free()
	_watched_controls.erase(control_id)

func _prune_dead_controls() -> void:
	for control_id_value in _watched_controls.keys():
		var control_id := int(control_id_value)
		var entry: Dictionary = _watched_controls[control_id]
		var reference := entry.get("reference", null) as WeakRef
		var control := reference.get_ref() as Control if reference != null else null
		if not is_instance_valid(control):
			_watched_controls.erase(control_id)

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
	if str(entry.get("hover_key", "")) == hover_key:
		return
	_stop_hover(control_id, true)
	if hover.is_empty():
		return
	entry = _watched_controls.get(control_id, {}) as Dictionary
	entry["hover_key"] = hover_key
	entry["resolved"] = hover.get("resolved", {})
	_watched_controls[control_id] = entry
	# Script lists and script tabs already provide a useful native resource-path
	# tooltip. Leave that tooltip intact and append our documentation to the
	# native TooltipPanel when Godot creates it. Outlines have no useful native
	# tooltip, so they continue to use the add-on's delayed popup.
	if _uses_native_path_tooltip(entry):
		return
	var timer := _get_timer(entry)
	if timer != null:
		timer.wait_time = _get_tooltip_delay_seconds()
		timer.start()

# PopupPanel is a subwindow and can temporarily consume the pointer stream. While
# our outline popup is visible, resolve the current local mouse position directly
# from the watched Control so moving between members replaces stale documentation.
func _on_hover_monitor_timeout(control: Control) -> void:
	if not is_instance_valid(control):
		return
	var control_id := control.get_instance_id()
	if not _watched_controls.has(control_id):
		return
	var entry: Dictionary = _watched_controls[control_id]
	var popup_reference := entry.get("popup_reference", null) as WeakRef
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	if not is_instance_valid(popup) or not popup.visible:
		var hover_monitor := _get_hover_monitor(entry)
		if hover_monitor != null:
			hover_monitor.stop()
		return
	var local_mouse := control.get_local_mouse_position()
	_update_hover_target(control, local_mouse)

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
func _resolve_current_member(symbol: String) -> Dictionary:
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
	return _resolve_member_from_source(source, current_script.resource_path, symbol)

# Source-only counterpart used by the navigation bridges and regression tests.
# It deliberately shares DocumentationParser.find_resource_reference() with the
# normal Code Editor integration rather than introducing plugin-specific Resource
# parsing for Quill or Script-IDE.
func _resolve_member_from_source(
	source: String,
	source_path: String,
	symbol: String
) -> Dictionary:
	if source.is_empty() or symbol.is_empty():
		return {}
	var context_class := DocumentationParser.get_script_class_name(source)
	var result: Dictionary = {
		"context_class": context_class,
		"source_path": source_path,
	}
	var documentation := DocumentationParser.find_member_documentation(
		source,
		symbol,
		-1,
		Settings.is_documentation_comments_enabled(),
		Settings.is_single_hash_member_documentation_enabled()
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
	if not result.has("documentation") and not result.has("resource_path"):
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
	var has_preview := (
		_preview_pipeline != null
		and not resource_path.is_empty()
		and _preview_pipeline.supports_preview_path(resource_path)
	)
	if not has_documentation and not has_preview:
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
	combined.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(combined)
	if has_documentation:
		combined.add_child(_create_documentation_panel(resolved, content_width, renderer))
	elif not title_text.is_empty():
		combined.add_child(_create_resource_title_panel(title_text, renderer))
	if has_preview:
		_preview_pipeline.append_preview_for_path(
			resource_path,
			combined,
			popup,
			{
				"source": "script_navigation",
				"symbol": str(resolved.get("title", "")),
				"trigger_control": control,
			}
		)
	var control_id := control.get_instance_id()
	if not _watched_controls.has(control_id):
		popup.queue_free()
		return
	entry = _watched_controls[control_id]
	entry["popup_reference"] = weakref(popup)
	_watched_controls[control_id] = entry
	var screen_position := control.get_screen_position() + control.get_local_mouse_position()
	popup.position = Vector2i(screen_position) + Vector2i(12, 20)
	popup.reset_size()
	popup.popup()
	entry = _watched_controls.get(control_id, {}) as Dictionary
	var hover_monitor := _get_hover_monitor(entry)
	if hover_monitor != null:
		hover_monitor.start(HOVER_MONITOR_INTERVAL_SECONDS)

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
	renderer: BTDocumentationRenderer
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
	TooltipAppearance.limit_rich_text_height(description)
	return panel

func _calculate_width(
	documentation: Dictionary,
	title: String,
	renderer: BTDocumentationRenderer
) -> float:
	var editor_scale := EditorInterface.get_editor_scale()
	var minimum_width := MIN_WIDTH * editor_scale
	var maximum_width := MAX_WIDTH * editor_scale
	var available_width := EditorInterface.get_base_control().size.x * 0.65
	maximum_width = maxf(minimum_width, minf(maximum_width, available_width))
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
	var hover_monitor := _get_hover_monitor(entry)
	if hover_monitor != null:
		hover_monitor.stop()
	if close_popup:
		_close_popup(entry)
	entry["hover_key"] = ""
	entry["resolved"] = {}
	entry["popup_reference"] = null if close_popup else entry.get("popup_reference", null)
	_watched_controls[control_id] = entry

func _close_popup(entry: Dictionary) -> void:
	var popup_reference := entry.get("popup_reference", null) as WeakRef
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	if is_instance_valid(popup):
		popup.hide()
		popup.queue_free()

func _get_timer(entry: Dictionary) -> Timer:
	var timer_reference := entry.get("timer_reference", null) as WeakRef
	return timer_reference.get_ref() as Timer if timer_reference != null else null

func _get_hover_monitor(entry: Dictionary) -> Timer:
	var timer_reference := entry.get("hover_monitor_reference", null) as WeakRef
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
