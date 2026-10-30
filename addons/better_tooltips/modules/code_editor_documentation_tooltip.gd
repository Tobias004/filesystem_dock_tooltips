@tool
class_name BTCodeEditorDocumentationTooltip
extends RefCounted

## Extends Godot's native ScriptEditor symbol tooltip with documentation resolved
## from project GDScript source. Godot's native title/signature remains the symbol
## resolver: local source is preferred for unqualified symbols, while class_name
## owners named by Godot can resolve members used from another script, and local
## preload/load aliases can resolve the referenced script class. Literal resource
## references assigned to hovered variables/constants reuse the central preview
## pipeline and cache. Matching project ## descriptions can be replaced by the
## shared add-on renderer; engine API help and other distinct native descriptions
## remain visible.

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
const NavigationTooltip := preload(
	"res://addons/better_tooltips/modules/script_editor_navigation_tooltip.gd"
)
const TooltipLifetime := preload(
	"res://addons/better_tooltips/core/tooltip_lifetime_manager.gd"
)

const TOOLTIP_PANEL_VARIATION := &"TooltipPanel"
# Godot renamed these theme variations in newer 4.x releases. Supporting both
# spellings keeps the integration robust across the supported Godot 4.7+ editor variants.
const HELP_TITLE_VARIATIONS := [
	&"EditorHelpBitTitle",
	&"EditorHelpBitTooltipTitle",
]
const HELP_CONTENT_VARIATIONS := [
	&"EditorHelpBitContent",
	&"EditorHelpBitTooltipContent",
]
const LOCAL_SECTION_NAME := &"BTLocalDocumentation"
const FALLBACK_POPUP_NAME := &"BTProjectClassTooltip"
const FALLBACK_TIMER_NAME := &"BTProjectClassTooltipTimer"
const FALLBACK_MIN_WIDTH := 420.0
const FALLBACK_MAX_WIDTH := 760.0
const FALLBACK_HORIZONTAL_PADDING := 28.0
const FALLBACK_NATIVE_GRACE_SECONDS := 0.08
const FALLBACK_NATIVE_SYMBOL_GRACE_SECONDS := 0.30
const WATCH_REFRESH_TIMER_NAME := &"BTCodeEditorRefreshTimer"
const WATCH_REFRESH_INTERVAL_SECONDS := 0.15
const STARTUP_REFRESH_ATTEMPTS := 12
const FOCUS_REFRESH_ATTEMPTS := 4
var _script_editor: ScriptEditor = null
var _editor_window: Window = null
var _watched_editors: Dictionary = {}
var _renderer: BTDocumentationRenderer = null
var _navigation_tooltips: BTScriptEditorNavigationTooltip = null
var _preview_pipeline: BTTooltipPipeline = null
var _fallback_lifetime: BTTooltipLifetimeManager = null
var _watch_refresh_timer: Timer = null
var _refresh_attempts_remaining := 0
var _refresh_burst_reason := ""

# Connects to Godot's ScriptEditor rather than editor layout nodes. Every already
# open ScriptEditorBase is watched, and the set is refreshed after script changes,
# editor-tree changes and application focus changes. This avoids relying on one
# startup-time get_current_editor() result and self-heals if Godot recreates a
# CodeEdit while restoring or rearranging the editor UI.
func setup(preview_pipeline: BTTooltipPipeline = null) -> void:
	_preview_pipeline = preview_pipeline
	if _fallback_lifetime == null:
		_fallback_lifetime = TooltipLifetime.new() as BTTooltipLifetimeManager
	_script_editor = EditorInterface.get_script_editor()
	if _script_editor == null:
		return
	_navigation_tooltips = NavigationTooltip.new() as BTScriptEditorNavigationTooltip
	_navigation_tooltips.setup(_script_editor, _preview_pipeline)
	var script_changed := Callable(self, "_on_editor_script_changed")
	if not _script_editor.editor_script_changed.is_connected(script_changed):
		_script_editor.editor_script_changed.connect(script_changed)
	var editor_child_entered := Callable(self, "_on_script_editor_child_entered")
	if not _script_editor.child_entered_tree.is_connected(editor_child_entered):
		_script_editor.child_entered_tree.connect(editor_child_entered)
	_setup_watch_refresh_timer()
	_editor_window = EditorInterface.get_base_control().get_window()
	if is_instance_valid(_editor_window):
		var focus_entered := Callable(self, "_on_editor_window_focus_entered")
		if not _editor_window.focus_entered.is_connected(focus_entered):
			_editor_window.focus_entered.connect(focus_entered)
		var focus_exited := Callable(self, "_on_editor_window_focus_exited")
		if not _editor_window.focus_exited.is_connected(focus_exited):
			_editor_window.focus_exited.connect(focus_exited)
	_refresh_editor_watchers("setup")
	call_deferred("_refresh_editor_watchers", "setup_deferred")
	_schedule_refresh_burst("startup", STARTUP_REFRESH_ATTEMPTS)

# Re-evaluates optional ScriptEditor navigation integrations after settings such
# as Quill IDE or Script-IDE compatibility are changed, without disturbing CodeEdit hooks.
func refresh_navigation_controls() -> void:
	if _navigation_tooltips != null:
		_navigation_tooltips.refresh_controls()

# Disconnects every CodeEdit watcher without taking ownership of editor controls.
func cleanup() -> void:
	if is_instance_valid(_script_editor):
		var script_changed := Callable(self, "_on_editor_script_changed")
		if _script_editor.editor_script_changed.is_connected(script_changed):
			_script_editor.editor_script_changed.disconnect(script_changed)
		var editor_child_entered := Callable(self, "_on_script_editor_child_entered")
		if _script_editor.child_entered_tree.is_connected(editor_child_entered):
			_script_editor.child_entered_tree.disconnect(editor_child_entered)
	if is_instance_valid(_editor_window):
		var focus_entered := Callable(self, "_on_editor_window_focus_entered")
		if _editor_window.focus_entered.is_connected(focus_entered):
			_editor_window.focus_entered.disconnect(focus_entered)
		var focus_exited := Callable(self, "_on_editor_window_focus_exited")
		if _editor_window.focus_exited.is_connected(focus_exited):
			_editor_window.focus_exited.disconnect(focus_exited)
	for editor_id in _watched_editors.keys():
		_disconnect_watched_editor(int(editor_id))
	_watched_editors.clear()
	if _fallback_lifetime != null:
		_fallback_lifetime.clear()
	_fallback_lifetime = null
	if is_instance_valid(_watch_refresh_timer):
		var refresh_timeout := Callable(self, "_on_watch_refresh_timer_timeout")
		if _watch_refresh_timer.timeout.is_connected(refresh_timeout):
			_watch_refresh_timer.timeout.disconnect(refresh_timeout)
		_watch_refresh_timer.queue_free()
	_watch_refresh_timer = null
	_refresh_attempts_remaining = 0
	_refresh_burst_reason = ""
	if _navigation_tooltips != null:
		_navigation_tooltips.cleanup()
	_navigation_tooltips = null
	_preview_pipeline = null
	_renderer = null
	_editor_window = null
	_script_editor = null

# A script switch can expose a different ScriptEditorBase. Refreshing the full
# open-editor set is cheap and also repairs a watcher whose signals disappeared.
func _on_editor_script_changed(_script: Script) -> void:
	call_deferred("_refresh_editor_watchers", "editor_script_changed")

# ScriptEditor may create/restore editor controls after the plugin setup pass.
func _on_script_editor_child_entered(_node: Node) -> void:
	call_deferred("_refresh_editor_watchers", "script_editor_child_entered")

# Returning from another application is one of the observed intermittent failure
# paths. Re-enumerate every open CodeEdit immediately and once more deferred.
func _on_editor_window_focus_entered() -> void:
	_refresh_editor_watchers("focus_entered")
	call_deferred("_refresh_editor_watchers", "focus_entered_deferred")
	_schedule_refresh_burst("focus", FOCUS_REFRESH_ATTEMPTS)

func _on_editor_window_focus_exited() -> void:
	for editor_id in _watched_editors.keys():
		_stop_fallback_for_editor(int(editor_id), true)
	if _navigation_tooltips != null:
		_navigation_tooltips.cancel_active_tooltips()

# A short one-shot retry burst covers startup/layout restoration phases where the
# ScriptEditor object exists before its ScriptEditorBase/CodeEdit children do. It
# is not permanent polling: startup and focus-return bursts stop after a bounded
# number of inexpensive enumerations.
func _setup_watch_refresh_timer() -> void:
	if is_instance_valid(_watch_refresh_timer):
		return
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return
	_watch_refresh_timer = Timer.new()
	_watch_refresh_timer.name = WATCH_REFRESH_TIMER_NAME
	_watch_refresh_timer.one_shot = true
	_watch_refresh_timer.wait_time = WATCH_REFRESH_INTERVAL_SECONDS
	base_control.add_child(_watch_refresh_timer)
	var refresh_timeout := Callable(self, "_on_watch_refresh_timer_timeout")
	_watch_refresh_timer.timeout.connect(refresh_timeout)

func _schedule_refresh_burst(reason: String, attempts: int) -> void:
	if not is_instance_valid(_watch_refresh_timer) or attempts <= 0:
		return
	_refresh_burst_reason = reason
	_refresh_attempts_remaining = maxi(_refresh_attempts_remaining, attempts)
	_watch_refresh_timer.start(WATCH_REFRESH_INTERVAL_SECONDS)


func _on_watch_refresh_timer_timeout() -> void:
	if _refresh_attempts_remaining <= 0:
		return
	var attempt_index := _refresh_attempts_remaining
	_refresh_attempts_remaining -= 1
	_refresh_editor_watchers(
		"%s_retry_%d" % [_refresh_burst_reason, attempt_index]
	)
	if _refresh_attempts_remaining > 0 and is_instance_valid(_watch_refresh_timer):
		_watch_refresh_timer.start(WATCH_REFRESH_INTERVAL_SECONDS)

# Enumerates every ScriptEditorBase currently known to Godot instead of assuming
# the selected editor is the only relevant CodeEdit. Existing connections are
# verified and repaired; dead WeakRefs are pruned.
func _refresh_editor_watchers(_reason: String) -> void:
	if not is_instance_valid(_script_editor):
		return
	_prune_dead_watchers()
	if _navigation_tooltips != null:
		_navigation_tooltips.refresh_controls()
	var candidates: Array[CodeEdit] = []
	var candidate_ids: Dictionary = {}
	if _script_editor.has_method("get_open_script_editors"):
		var open_editors_value: Variant = _script_editor.call("get_open_script_editors")
		if open_editors_value is Array:
			for editor_value in (open_editors_value as Array):
				if editor_value == null or not editor_value.has_method("get_base_editor"):
					continue
				var base_editor_value: Variant = editor_value.call("get_base_editor")
				if not (base_editor_value is CodeEdit):
					continue
				var code_edit := base_editor_value as CodeEdit
				var editor_id := code_edit.get_instance_id()
				if candidate_ids.has(editor_id):
					continue
				candidate_ids[editor_id] = true
				candidates.append(code_edit)
	var current_editor := _script_editor.get_current_editor()
	if current_editor != null:
		var current_base := current_editor.get_base_editor()
		if current_base is CodeEdit:
			var current_code_edit := current_base as CodeEdit
			var current_id := current_code_edit.get_instance_id()
			if not candidate_ids.has(current_id):
				candidate_ids[current_id] = true
				candidates.append(current_code_edit)
	for code_edit in candidates:
		_watch_code_edit(code_edit)

# Installs both the native-tooltip child watcher and a non-invasive mouse timer
# used for project class/resource fallback tooltips when Godot creates no help bit.
# Return 1 = newly attached, 2 = an existing watcher needed repair, 0 = unchanged.
func _watch_code_edit(code_edit: CodeEdit) -> int:
	if not is_instance_valid(code_edit):
		return 0
	var editor_id := code_edit.get_instance_id()
	if _watched_editors.has(editor_id):
		var existing: Dictionary = _watched_editors[editor_id]
		var repaired := false
		var child_callback: Callable = existing.get("child_callback", Callable())
		if child_callback.is_valid() and not code_edit.child_entered_tree.is_connected(child_callback):
			code_edit.child_entered_tree.connect(child_callback)
			repaired = true
		var gui_callback: Callable = existing.get("gui_callback", Callable())
		if gui_callback.is_valid() and not code_edit.gui_input.is_connected(gui_callback):
			code_edit.gui_input.connect(gui_callback)
			repaired = true
		var exit_callback: Callable = existing.get("exit_callback", Callable())
		if exit_callback.is_valid() and not code_edit.mouse_exited.is_connected(exit_callback):
			code_edit.mouse_exited.connect(exit_callback)
			repaired = true
		return 2 if repaired else 0
	var child_callback := Callable(self, "_on_code_edit_child_entered").bind(code_edit)
	var gui_callback := Callable(self, "_on_code_edit_gui_input").bind(code_edit)
	var exit_callback := Callable(self, "_on_code_edit_mouse_exited").bind(code_edit)
	code_edit.child_entered_tree.connect(child_callback)
	code_edit.gui_input.connect(gui_callback)
	code_edit.mouse_exited.connect(exit_callback)
	var timer := Timer.new()
	timer.name = FALLBACK_TIMER_NAME
	timer.one_shot = true
	timer.wait_time = _get_fallback_delay_seconds()
	code_edit.add_child(timer)
	var timer_callback := Callable(self, "_on_fallback_timer_timeout").bind(code_edit)
	timer.timeout.connect(timer_callback)
	_watched_editors[editor_id] = {
		"reference": weakref(code_edit),
		"child_callback": child_callback,
		"gui_callback": gui_callback,
		"exit_callback": exit_callback,
		"timer_reference": weakref(timer),
		"timer_callback": timer_callback,
		"hover_key": "",
		"fallback_symbol": "",
		"fallback_line": -1,
		"fallback_resource_path": "",
		"fallback_context": {},
		"popup_reference": null,
	}
	return 1

func _disconnect_watched_editor(editor_id: int) -> void:
	if not _watched_editors.has(editor_id):
		return
	var entry: Dictionary = _watched_editors[editor_id]
	var reference := entry.get("reference", null) as WeakRef
	var code_edit := reference.get_ref() as CodeEdit if reference != null else null
	if is_instance_valid(code_edit):
		var child_callback: Callable = entry.get("child_callback", Callable())
		if child_callback.is_valid() and code_edit.child_entered_tree.is_connected(child_callback):
			code_edit.child_entered_tree.disconnect(child_callback)
		var gui_callback: Callable = entry.get("gui_callback", Callable())
		if gui_callback.is_valid() and code_edit.gui_input.is_connected(gui_callback):
			code_edit.gui_input.disconnect(gui_callback)
		var exit_callback: Callable = entry.get("exit_callback", Callable())
		if exit_callback.is_valid() and code_edit.mouse_exited.is_connected(exit_callback):
			code_edit.mouse_exited.disconnect(exit_callback)
	_stop_fallback_for_editor(editor_id, true)
	var timer_reference := entry.get("timer_reference", null) as WeakRef
	var timer := timer_reference.get_ref() as Timer if timer_reference != null else null
	if is_instance_valid(timer):
		var timer_callback: Callable = entry.get("timer_callback", Callable())
		if timer_callback.is_valid() and timer.timeout.is_connected(timer_callback):
			timer.timeout.disconnect(timer_callback)
		timer.queue_free()
	_watched_editors.erase(editor_id)

func _prune_dead_watchers() -> void:
	for editor_id_value in _watched_editors.keys():
		var editor_id := int(editor_id_value)
		var entry: Dictionary = _watched_editors[editor_id]
		var reference := entry.get("reference", null) as WeakRef
		var code_edit := reference.get_ref() as CodeEdit if reference != null else null
		if not is_instance_valid(code_edit):
			_watched_editors.erase(editor_id)

# Observes pointer motion without replacing CodeEdit.set_tooltip_request_func().
# A documented project class or a source-resolvable preview resource can arm the
# fallback timer. Ordinary symbols remain under Godot's native tooltip callback.
func _on_code_edit_gui_input(event: InputEvent, code_edit: CodeEdit) -> void:
	if not (event is InputEventMouseMotion) or not is_instance_valid(code_edit):
		return
	var editor_id := code_edit.get_instance_id()
	if not _watched_editors.has(editor_id):
		return
	var pointer_context := _get_pointer_context(code_edit)
	var context := _get_mouse_context(code_edit)
	var special_context := _resolve_special_hover(code_edit, pointer_context)
	var symbol := str(context.get("symbol", ""))
	var line := int(pointer_context.get("line", -1))
	var hover_key := "%s:%d:%s" % [
		symbol,
		line,
		str(special_context.get("key", "")),
	]
	var entry: Dictionary = _watched_editors[editor_id]
	if str(entry.get("hover_key", "")) == hover_key:
		return
	_stop_fallback_for_editor(editor_id, true)
	entry = _watched_editors.get(editor_id, {}) as Dictionary
	entry["hover_key"] = hover_key
	entry["fallback_symbol"] = ""
	entry["fallback_line"] = -1
	entry["fallback_resource_path"] = ""
	entry["fallback_context"] = {}
	_watched_editors[editor_id] = entry
	var class_entry := _find_project_class_by_name(symbol) if not symbol.is_empty() else {}
	var resource_path := _resolve_local_resource_path(code_edit, context) if not context.is_empty() else ""
	if resource_path.is_empty():
		resource_path = str(special_context.get("resource_path", ""))
	var has_resource_preview := (
		_preview_pipeline != null
		and not resource_path.is_empty()
		and _preview_pipeline.supports_preview_path(resource_path)
	)
	if class_entry.is_empty() and not has_resource_preview and special_context.is_empty():
		return
	# Plain variable/constant symbols normally receive a native Godot help bit.
	# Give that popup a little longer to arrive before showing our own fallback;
	# direct literals and project-class gaps still use the short normal grace.
	var wait_for_native_symbol := (
		has_resource_preview
		and not symbol.is_empty()
		and class_entry.is_empty()
		and special_context.is_empty()
	)
	entry["fallback_symbol"] = symbol
	entry["fallback_line"] = line
	entry["fallback_resource_path"] = resource_path if has_resource_preview else ""
	entry["fallback_context"] = special_context
	_watched_editors[editor_id] = entry
	var timer := _get_fallback_timer(entry)
	if timer != null:
		timer.wait_time = _get_fallback_delay_seconds(wait_for_native_symbol)
		timer.start()

func _on_code_edit_mouse_exited(code_edit: CodeEdit) -> void:
	if not is_instance_valid(code_edit):
		return
	var editor_id := code_edit.get_instance_id()
	var entry: Dictionary = _watched_editors.get(editor_id, {}) as Dictionary
	var popup_reference := entry.get("popup_reference", null) as WeakRef
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	# A visible fallback remains interactive while the pointer crosses into it.
	# A pending fallback must still be cancelled when CodeEdit loses hover.
	if is_instance_valid(popup) and _fallback_lifetime != null and _fallback_lifetime.has_popup(popup):
		_stop_fallback_timer_for_editor(editor_id)
		return
	_stop_fallback_for_editor(editor_id, true)

func _on_fallback_timer_timeout(code_edit: CodeEdit) -> void:
	if not is_instance_valid(code_edit):
		return
	call_deferred(
		"_try_show_code_fallback",
		weakref(code_edit)
	)

# Gives Godot one extra idle pass after its normal tooltip delay, then provides a
# project class/resource tooltip only when the native callback still produced nothing.
func _try_show_code_fallback(code_edit_reference: WeakRef) -> void:
	if code_edit_reference == null:
		return
	var code_edit := code_edit_reference.get_ref() as CodeEdit
	if not is_instance_valid(code_edit):
		return
	var editor_id := code_edit.get_instance_id()
	if not _watched_editors.has(editor_id):
		return
	var entry: Dictionary = _watched_editors[editor_id]
	var expected_symbol := str(entry.get("fallback_symbol", ""))
	var expected_line := int(entry.get("fallback_line", -1))
	var expected_resource_path := str(entry.get("fallback_resource_path", ""))
	var expected_special := entry.get("fallback_context", {}) as Dictionary
	if expected_symbol.is_empty() and expected_special.is_empty():
		return
	var pointer_context := _get_pointer_context(code_edit)
	var context := _get_mouse_context(code_edit)
	if int(pointer_context.get("line", -1)) != expected_line:
		return
	if not expected_symbol.is_empty() and str(context.get("symbol", "")) != expected_symbol:
		return
	var current_special := _resolve_special_hover(code_edit, pointer_context)
	if (
		not expected_special.is_empty()
		and str(current_special.get("key", "")) != str(expected_special.get("key", ""))
	):
		return
	if _has_visible_native_tooltip(code_edit):
		return
	var native_text := code_edit.get_tooltip(code_edit.get_local_mouse_position())
	if not native_text.strip_edges().is_empty():
		return
	var resolved := (
		_resolve_project_class_documentation(code_edit, expected_symbol)
		if not expected_symbol.is_empty() else {}
	)
	if resolved.is_empty() and expected_resource_path.is_empty() and expected_special.is_empty():
		return
	_show_code_fallback(
		code_edit,
		expected_symbol,
		resolved,
		expected_resource_path,
		expected_special
	)

func _has_visible_native_tooltip(code_edit: CodeEdit) -> bool:
	for child in code_edit.get_children():
		if not (child is PopupPanel):
			continue
		var popup := child as PopupPanel
		if popup.name == FALLBACK_POPUP_NAME:
			continue
		if popup.theme_type_variation == TOOLTIP_PANEL_VARIATION and popup.visible:
			return true
	return false

# Resolves a hovered global class_name directly from the project class registry.
# This is deliberately narrower than a general semantic resolver: it exists only
# because Godot currently creates no native help-bit popup for some type tokens.
func _resolve_project_class_documentation(
	code_edit: CodeEdit,
	class_name_value: String
) -> Dictionary:
	var allow_documentation_comments := Settings.is_documentation_comments_enabled()
	var allow_single_hash := Settings.is_single_hash_member_documentation_enabled()
	if not allow_documentation_comments and not allow_single_hash:
		return {}
	var class_entry := _find_project_class_by_name(class_name_value)
	if class_entry.is_empty():
		return {}
	var class_path := str(class_entry.get("path", ""))
	var current_path := _get_current_script_path()
	var source := code_edit.text if class_path == current_path else _read_project_script_source(class_path)
	if source.is_empty():
		return {}
	var documentation := DocumentationParser.find_member_documentation(
		source,
		class_name_value,
		-1,
		allow_documentation_comments,
		allow_single_hash
	)
	if documentation.is_empty():
		return {}
	return {
		"documentation": documentation,
		"context_class": class_name_value,
		"source_path": class_path,
		"base_class": str(class_entry.get("base", "")),
	}

func _find_project_class_by_name(class_name_value: String) -> Dictionary:
	if class_name_value.is_empty():
		return {}
	for entry_value in ProjectSettings.get_global_class_list():
		if not (entry_value is Dictionary):
			continue
		var entry := entry_value as Dictionary
		if str(entry.get("class", "")) != class_name_value:
			continue
		return {
			"class_name": class_name_value,
			"path": str(entry.get("path", "")),
			"base": str(entry.get("base", "")),
		}
	return {}

# Builds a small TooltipPanel when Godot itself returned no help bit. Project
# class documentation and source-resolved resource previews can use the same
# fallback independently or together without replacing CodeEdit's callback.
func _show_code_fallback(
	code_edit: CodeEdit,
	symbol: String,
	resolved: Dictionary,
	resource_path: String,
	special_context: Dictionary = {}
) -> void:
	var editor_id := code_edit.get_instance_id()
	_stop_fallback_for_editor(editor_id, false)
	if not _watched_editors.has(editor_id):
		return
	var documentation := resolved.get("documentation", {}) as Dictionary
	var context_class := str(resolved.get("context_class", ""))
	if documentation.is_empty() and resource_path.is_empty() and special_context.is_empty():
		return
	var renderer := _get_renderer()
	renderer.refresh_theme()
	var extra_text := resource_path
	if not special_context.is_empty():
		extra_text += "\n" + str(special_context.get("plain_text", ""))
	var content_width := _calculate_fallback_width(
		documentation,
		renderer,
		extra_text
	)
	var popup := PopupPanel.new()
	popup.name = FALLBACK_POPUP_NAME
	popup.theme_type_variation = TOOLTIP_PANEL_VARIATION
	popup.wrap_controls = true
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	code_edit.add_child(popup)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TooltipAppearance.style_addon_panel(panel)
	popup.add_child(panel)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = content_width
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	var title := Label.new()
	renderer.style_type_label(title)
	content.add_child(title)
	if not documentation.is_empty() and not context_class.is_empty():
		var base_class := str(resolved.get("base_class", ""))
		title.text = "Class %s%s" % [
			context_class,
			(" < " + base_class) if not base_class.is_empty() else "",
		]
		var description: RichTextLabel = RichTextLabel.new()
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
		renderer.render_document(description, documentation, context_class, false)
		TooltipAppearance.limit_rich_text_height(description)
	else:
		title.text = (
			str(special_context.get("title", ""))
			if not str(special_context.get("title", "")).is_empty()
			else symbol
		)
	if not special_context.is_empty():
		_append_special_context_to_fallback(content, special_context, content_width)
	if not resource_path.is_empty():
		var path_label := Label.new()
		path_label.text = resource_path
		path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		path_label.custom_minimum_size.x = content_width
		path_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(path_label)
	var entry: Dictionary = _watched_editors[editor_id]
	entry["popup_reference"] = weakref(popup)
	_watched_editors[editor_id] = entry
	var local_mouse: Vector2 = code_edit.get_local_mouse_position()
	var popup_anchor := Vector2i(code_edit.get_screen_position() + local_mouse)
	popup.reset_size()
	if resource_path.is_empty():
		_show_fallback_after_layout(weakref(popup), popup_anchor)
	else:
		popup.position = popup_anchor + Vector2i(12, 20)
		popup.popup()
	if _preview_pipeline != null and not resource_path.is_empty():
		_preview_pipeline.append_preview_for_path(
			resource_path,
			content,
			popup,
			{
				"source": "code_editor",
				"trigger_control": code_edit,
			}
		)
	# Use the same hover/drag lifetime rules as FileSystem and navigation
	# popups, but keep a separate manager so integrations fail independently.
	if _fallback_lifetime != null:
		_fallback_lifetime.register_popup(
			popup, Rect2i(), code_edit, Callable(),
			Callable(self, "_on_fallback_lifetime_expired").bind(
				editor_id, popup.get_instance_id()
			),
			0.30, 0.04
		)
	# Forward the wheel only when the fallback actually has a scrollable area.
	if _preview_pipeline != null:
		_preview_pipeline.register_external_text_popup(popup, content, code_edit)

# Add-on-owned text fallback windows can be fully measured before their first
# visible frame. This does not intercept Godot's native help popups or graphics.
func _show_fallback_after_layout(popup_ref: WeakRef, pointer: Vector2i) -> void:
	var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
	if not is_instance_valid(popup):
		return
	await popup.get_tree().process_frame
	if not is_instance_valid(popup):
		return
	await popup.get_tree().process_frame
	if not is_instance_valid(popup):
		return
	var prepared_size := TooltipAppearance.prepared_text_popup_size(popup)
	var screen := popup.current_screen
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var margin := roundi(8.0 * EditorInterface.get_editor_scale())
	var x := pointer.x + margin
	var y := pointer.y + margin
	if x + prepared_size.x > usable.end.x - margin:
		x = pointer.x - prepared_size.x - margin
	if y + prepared_size.y > usable.end.y - margin:
		y = pointer.y - prepared_size.y - margin
	var position := Vector2i(
		clampi(x, usable.position.x + margin, maxi(usable.position.x + margin, usable.end.x - prepared_size.x - margin)),
		clampi(y, usable.position.y + margin, maxi(usable.position.y + margin, usable.end.y - prepared_size.y - margin))
	)
	popup.popup(Rect2i(position, prepared_size))

# Do not let a delayed expiry of an old popup close a newer one for the editor.
func _on_fallback_lifetime_expired(editor_id: int, popup_id: int) -> void:
	var entry: Dictionary = _watched_editors.get(editor_id, {}) as Dictionary
	var reference := entry.get("popup_reference", null) as WeakRef
	var popup := reference.get_ref() as PopupPanel if reference != null else null
	if is_instance_valid(popup) and popup.get_instance_id() == popup_id:
		_stop_fallback_for_editor(editor_id, true)

func _calculate_fallback_width(
	documentation: Dictionary,
	renderer: BTDocumentationRenderer,
	extra_text: String = ""
) -> float:
	var editor_scale := EditorInterface.get_editor_scale()
	var minimum_width := FALLBACK_MIN_WIDTH * editor_scale
	var maximum_width := minf(FALLBACK_MAX_WIDTH * editor_scale, TooltipAppearance.text_content_width(2000.0 * editor_scale))
	var available_width := EditorInterface.get_base_control().size.x * 0.65
	maximum_width = maxf(120.0 * editor_scale, minf(maximum_width, available_width))
	minimum_width = minf(minimum_width, maximum_width)
	var font := renderer.get_document_font()
	var font_size := renderer.get_document_font_size()
	var plain_text := renderer.to_plain_text(str(documentation.get("description", "")))
	var measured_width := 0.0
	for line in plain_text.split("\n"):
		measured_width = maxf(
			measured_width,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	if not extra_text.is_empty():
		measured_width = maxf(
			measured_width,
			font.get_string_size(
				extra_text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size
			).x
		)
	return clampf(
		measured_width + FALLBACK_HORIZONTAL_PADDING * editor_scale,
		minimum_width,
		maximum_width
	)

func _get_fallback_delay_seconds(wait_for_native_symbol: bool = false) -> float:
	var native_delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	var grace := (
		FALLBACK_NATIVE_SYMBOL_GRACE_SECONDS
		if wait_for_native_symbol
		else FALLBACK_NATIVE_GRACE_SECONDS
	)
	return maxf(0.05, native_delay + grace)

func _get_fallback_timer(entry: Dictionary) -> Timer:
	var timer_reference := entry.get("timer_reference", null) as WeakRef
	return timer_reference.get_ref() as Timer if timer_reference != null else null

# Stops only the pending fallback timer without clearing the hover identity or
# closing a visible fallback. Native-tooltip handoff uses this so tiny pointer
# movements during Godot's deferred popup population cannot re-arm the fallback.
func _stop_fallback_timer_for_editor(editor_id: int) -> void:
	if not _watched_editors.has(editor_id):
		return
	var entry: Dictionary = _watched_editors[editor_id]
	var timer := _get_fallback_timer(entry)
	if timer != null:
		timer.stop()

# Closes only the visible add-on popup while preserving the current hover state.
# This is used during native-tooltip handoff so the fallback can remain visible
# until Godot's help-bit controls have actually been populated.
func _close_fallback_popup_for_editor(editor_id: int) -> void:
	if not _watched_editors.has(editor_id):
		return
	var entry: Dictionary = _watched_editors[editor_id]
	var popup_reference := entry.get("popup_reference", null) as WeakRef
	var popup := popup_reference.get_ref() as PopupPanel if popup_reference != null else null
	if is_instance_valid(popup):
		if _fallback_lifetime != null:
			_fallback_lifetime.unregister_popup(popup)
		if _preview_pipeline != null:
			_preview_pipeline.unregister_external_text_popup(popup)
		popup.hide()
		popup.queue_free()
	entry["popup_reference"] = null
	_watched_editors[editor_id] = entry

# Stops a pending class/resource fallback and optionally closes an already visible one.
func _stop_fallback_for_editor(editor_id: int, close_popup: bool) -> void:
	if not _watched_editors.has(editor_id):
		return
	var entry: Dictionary = _watched_editors[editor_id]
	var timer := _get_fallback_timer(entry)
	if timer != null:
		timer.stop()
	if close_popup:
		_close_fallback_popup_for_editor(editor_id)
		entry = _watched_editors.get(editor_id, {}) as Dictionary
	entry["hover_key"] = ""
	entry["fallback_symbol"] = ""
	entry["fallback_line"] = -1
	entry["fallback_resource_path"] = ""
	entry["fallback_context"] = {}
	_watched_editors[editor_id] = entry

# Godot creates EditorHelpBitTooltip as a direct CodeEdit child. Defer the
# augmentation by one idle pass: EditorHelpBit populates its RichTextLabels only
# after add_child() returns, so the native title can then identify whether this
# tooltip came from the pointer or from Godot's keyboard tooltip command.
func _on_code_edit_child_entered(node: Node, code_edit: CodeEdit) -> void:
	if not (node is PopupPanel) or not is_instance_valid(code_edit):
		return
	var popup := node as PopupPanel
	if popup.theme_type_variation != TOOLTIP_PANEL_VARIATION:
		return
	if popup.name == FALLBACK_POPUP_NAME:
		return
	if _find_native_help_controls(popup).is_empty():
		return
	# Stop a pending fallback immediately, but keep both the current hover identity
	# and an already visible popup until the deferred pass sees Godot's populated
	# help controls. This avoids both re-arming and a blank/replacement flash.
	_stop_fallback_timer_for_editor(code_edit.get_instance_id())
	call_deferred(
		"_finish_native_tooltip",
		weakref(popup),
		weakref(code_edit)
	)

# Resolves the symbol against the now-populated native title, then independently
# adds matching project documentation and/or a source-resolved Resource preview.
# Both additions leave Godot's semantic symbol lookup and native title intact.
func _finish_native_tooltip(
	popup_reference: WeakRef,
	code_edit_reference: WeakRef
) -> void:
	if popup_reference == null or code_edit_reference == null:
		return
	var popup := popup_reference.get_ref() as PopupPanel
	var code_edit := code_edit_reference.get_ref() as CodeEdit
	if not is_instance_valid(popup) or not is_instance_valid(code_edit):
		return
	var help_controls := _find_native_help_controls(popup)
	if help_controls.is_empty():
		return
	# At this point Godot's native help-bit structure exists after the deferred
	# population pass, so it can replace any add-on fallback without a blank gap.
	_close_fallback_popup_for_editor(code_edit.get_instance_id())
	var native_title := help_controls["title"] as RichTextLabel
	var native_content := help_controls["content"] as RichTextLabel
	_apply_native_font_scale(native_title)
	_apply_native_font_scale(native_content)
	var hover_context := _get_symbol_context(code_edit, native_title)
	if hover_context.is_empty():
		_schedule_native_tooltip_fit(popup, native_content)
		return
	var changed := false
	var resolved := _resolve_source_documentation(
		code_edit,
		native_title,
		hover_context
	)
	if not resolved.is_empty():
		var documentation := resolved.get("documentation", {}) as Dictionary
		var context_class := str(resolved.get("context_class", ""))
		if _native_contains_same_local_documentation(
			native_title,
			native_content,
			documentation,
			context_class
		):
			if Settings.is_replace_godot_member_documentation_enabled():
				_replace_native_documentation(
					help_controls["container"] as VBoxContainer,
					native_content,
					documentation,
					context_class
				)
				changed = true
		elif _native_is_no_description_placeholder(native_content):
			# Once the add-on has real source documentation, Godot's placeholder adds
			# no information and should not remain as a second empty-looking section.
			_replace_native_documentation(
				help_controls["container"] as VBoxContainer,
				native_content,
				documentation,
				context_class
			)
			changed = true
		else:
			_append_local_documentation(
				help_controls["container"] as VBoxContainer,
				native_content,
				documentation,
				context_class
			)
			changed = true
	var resource_reference := _resolve_resource_reference(
		code_edit,
		native_title,
		hover_context
	)
	if _preview_pipeline != null and not resource_reference.is_empty():
		changed = _preview_pipeline.append_preview_for_path(
			str(resource_reference.get("path", "")),
			help_controls["container"] as VBoxContainer,
			popup,
			{
				"source": "code_editor",
				"symbol": str(hover_context.get("symbol", "")),
				"trigger_control": code_edit,
			}
		) or changed
	var pointer_context := _get_pointer_context(code_edit)
	var special_context := _resolve_special_hover(code_edit, pointer_context)
	if not special_context.is_empty():
		_append_special_context_to_native(
			help_controls["container"] as VBoxContainer,
			native_content,
			special_context
		)
		var special_resource_path := str(special_context.get("resource_path", ""))
		if _preview_pipeline != null and not special_resource_path.is_empty():
			changed = _preview_pipeline.append_preview_for_path(
				special_resource_path,
				help_controls["container"] as VBoxContainer,
				popup,
				{
					"source": "code_editor_literal",
					"trigger_control": code_edit,
				}
			) or changed
		changed = true
	if changed:
		popup.reset_size()
	# Even an unmodified Godot help bit can be much taller than the screen
	# (e.g. a Camera2D engine-class description). Limit its native text and
	# reposition after Godot and the injected sections have finished layout.
	_schedule_native_tooltip_fit(popup, native_content)

# Godot creates the Code Editor help bits itself. Apply the same text-only
# scaling to its theme fonts without changing its markup, images or logic.
func _apply_native_font_scale(label: RichTextLabel) -> void:
	if label == null or label.has_meta("_bt_native_font_scaled"):
		return
	label.set_meta("_bt_native_font_scaled", true)
	for size_name: String in [
		"normal_font_size", "bold_font_size", "italics_font_size",
		"bold_italics_font_size", "mono_font_size",
	]:
		var theme_size := label.get_theme_font_size(size_name)
		if theme_size > 0:
			label.add_theme_font_size_override(
				size_name, Settings.scale_text_font_size(theme_size)
			)

func _schedule_native_tooltip_fit(popup: PopupPanel, content: RichTextLabel) -> void:
	if not is_instance_valid(popup) or not is_instance_valid(content):
		return
	TooltipAppearance.limit_rich_text_height(content)
	call_deferred("_fit_native_tooltip_after_layout", weakref(popup), weakref(content))

func _fit_native_tooltip_after_layout(popup_ref: WeakRef, content_ref: WeakRef) -> void:
	var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
	var content := content_ref.get_ref() as RichTextLabel if content_ref != null else null
	if not is_instance_valid(popup) or not is_instance_valid(content):
		return
	if not popup.visible:
		return
	TooltipAppearance.limit_rich_text_height(content)
	popup.reset_size()
	var screen := popup.current_screen
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var margin := roundi(8.0 * EditorInterface.get_editor_scale())
	var max_x := maxi(usable.position.x + margin, usable.end.x - popup.size.x - margin)
	var max_y := maxi(usable.position.y + margin, usable.end.y - popup.size.y - margin)
	popup.position = Vector2i(
		clampi(popup.position.x, usable.position.x + margin, max_x),
		clampi(popup.position.y, usable.position.y + margin, max_y)
	)

# Resolves one hovered variable/constant to a literal preload()/load() path. The
# current unsaved script is preferred for local/unqualified symbols; if Godot's
# native title identifies another project class as owner, that class source is
# searched as well. The preview pipeline decides whether the resource type is supported.
func _resolve_resource_reference(
	code_edit: CodeEdit,
	native_title: RichTextLabel,
	hover_context: Dictionary
) -> Dictionary:
	var symbol := str(hover_context.get("symbol", ""))
	if symbol.is_empty():
		return {}
	var current_source := code_edit.text
	var explicitly_external := _is_explicit_external_qualification(
		code_edit,
		int(hover_context.get("line", -1)),
		int(hover_context.get("column", -1)),
		symbol
	)
	if not explicitly_external:
		var current_reference := DocumentationParser.find_resource_reference(
			current_source,
			symbol,
			int(hover_context.get("line", -1))
		)
		if not current_reference.is_empty():
			current_reference["source_path"] = _get_current_script_path()
			return current_reference
	var owner := _find_project_class_owner(
		native_title.get_parsed_text(),
		symbol
	)
	if owner.is_empty():
		return {}
	var owner_path := str(owner.get("path", ""))
	if owner_path.is_empty():
		return {}
	var owner_source := (
		current_source
		if owner_path == _get_current_script_path()
		else _read_project_script_source(owner_path)
	)
	if owner_source.is_empty():
		return {}
	var owner_reference := DocumentationParser.find_resource_reference(
		owner_source,
		symbol,
		-1
	)
	if owner_reference.is_empty():
		return {}
	owner_reference["source_path"] = owner_path
	return owner_reference

# Narrow fallback resolver used before a native help title exists. Qualified
# external symbols are skipped because without Godot's semantic title there is no
# reliable project-class owner to follow.
func _resolve_local_resource_path(
	code_edit: CodeEdit,
	hover_context: Dictionary
) -> String:
	if hover_context.is_empty():
		return ""
	var symbol := str(hover_context.get("symbol", ""))
	if symbol.is_empty():
		return ""
	if _is_explicit_external_qualification(
		code_edit,
		int(hover_context.get("line", -1)),
		int(hover_context.get("column", -1)),
		symbol
	):
		return ""
	var reference := DocumentationParser.find_resource_reference(
		code_edit.text,
		symbol,
		int(hover_context.get("line", -1))
	)
	return str(reference.get("path", ""))

# Resolves the hovered symbol back to project source while leaving Godot in
# charge of semantic symbol lookup. Unqualified/self-qualified symbols first use
# the current unsaved CodeEdit text. If Godot's populated title names another
# project class_name owner, that class source is then used for class/member docs.
func _resolve_source_documentation(
	code_edit: CodeEdit,
	native_title: RichTextLabel,
	hover_context: Dictionary
) -> Dictionary:
	var allow_documentation_comments := Settings.is_documentation_comments_enabled()
	var allow_single_hash := Settings.is_single_hash_member_documentation_enabled()
	if not allow_documentation_comments and not allow_single_hash:
		return {}
	var symbol := str(hover_context.get("symbol", ""))
	if symbol.is_empty():
		return {}
	var current_source := code_edit.text
	var current_class := DocumentationParser.get_script_class_name(current_source)
	var explicitly_external := _is_explicit_external_qualification(
		code_edit,
		int(hover_context.get("line", -1)),
		int(hover_context.get("column", -1)),
		symbol
	)
	if not explicitly_external:
		var current_documentation := DocumentationParser.find_member_documentation(
			current_source,
			symbol,
			int(hover_context.get("line", -1)),
			allow_documentation_comments,
			allow_single_hash
		)
		if not current_documentation.is_empty():
			return {
				"documentation": current_documentation,
				"context_class": current_class,
				"source_path": _get_current_script_path(),
			}
		# A preload()/load() constant is a local symbol too, but its useful
		# documentation belongs to the target script class rather than the alias.
		var current_reference := _resolve_script_reference_documentation(
			current_source,
			symbol,
			allow_documentation_comments,
			allow_single_hash
		)
		if not current_reference.is_empty():
			return current_reference
	var owner := _find_project_class_owner(
		native_title.get_parsed_text(),
		symbol
	)
	if owner.is_empty():
		return {}
	var owner_class := str(owner.get("class_name", ""))
	var owner_path := str(owner.get("path", ""))
	if owner_class.is_empty():
		return {}
	var owner_source := current_source if owner_class == current_class else ""
	if owner_source.is_empty():
		owner_source = _read_project_script_source(owner_path)
	if owner_source.is_empty():
		return {}
	var documentation := DocumentationParser.find_member_documentation(
		owner_source,
		symbol,
		-1,
		allow_documentation_comments,
		allow_single_hash
	)
	if not documentation.is_empty():
		return {
			"documentation": documentation,
			"context_class": owner_class,
			"source_path": owner_path,
		}
	# Also follow script aliases that belong to another project class, e.g. a
	# public `Owner.SomeScript` constant resolved by Godot's native help title.
	return _resolve_script_reference_documentation(
		owner_source,
		symbol,
		allow_documentation_comments,
		allow_single_hash
	)

# Follows a top-level preload()/load() constant to the referenced GDScript and
# returns that script's class documentation. The target is read as source only;
# no Script resource is instantiated merely to build a tooltip.
func _resolve_script_reference_documentation(
	source: String,
	symbol: String,
	allow_documentation_comments: bool,
	allow_single_hash: bool
) -> Dictionary:
	var reference := DocumentationParser.find_script_reference_constant(
		source,
		symbol
	)
	if reference.is_empty():
		return {}
	var target_path := str(reference.get("path", ""))
	if target_path.is_empty():
		return {}
	var target_source := _read_project_script_source(target_path)
	if target_source.is_empty():
		return {}
	var target_class := DocumentationParser.get_script_class_name(target_source)
	if target_class.is_empty():
		return {}
	var documentation := DocumentationParser.find_member_documentation(
		target_source,
		target_class,
		-1,
		allow_documentation_comments,
		allow_single_hash
	)
	if documentation.is_empty():
		return {}
	return {
		"documentation": documentation,
		"context_class": target_class,
		"source_path": target_path,
	}

# Finds the project class_name that Godot identifies as the owner of the hovered
# symbol. Candidates must occur before (or be) the symbol in the native title so
# project classes mentioned only as return/parameter types cannot be mistaken for
# the owner. Built-in API owners therefore naturally fall back to Godot help.
func _find_project_class_owner(title_text: String, symbol: String) -> Dictionary:
	if title_text.is_empty() or symbol.is_empty():
		return {}
	var symbol_position := _find_identifier_occurrence(title_text, symbol)
	if symbol_position < 0:
		return {}
	var best := {}
	var best_distance := 1 << 30
	for entry_value in ProjectSettings.get_global_class_list():
		if not (entry_value is Dictionary):
			continue
		var entry := entry_value as Dictionary
		var project_class_name := str(entry.get("class", ""))
		if project_class_name.is_empty():
			continue
		var class_position := _find_identifier_occurrence(title_text, project_class_name)
		if class_position < 0:
			continue
		if project_class_name != symbol and class_position > symbol_position:
			continue
		var distance := absi(symbol_position - class_position)
		if distance >= best_distance:
			continue
		best_distance = distance
		best = {
			"class_name": project_class_name,
			"path": str(entry.get("path", "")),
		}
	return best

# Returns one identifier-bounded occurrence so substrings in longer class/member
# names do not influence project-class owner selection.
static func _find_identifier_occurrence(text: String, identifier: String) -> int:
	if text.is_empty() or identifier.is_empty():
		return -1
	var position := text.find(identifier)
	while position >= 0:
		var before_ok := (
			position == 0
			or not _is_identifier_character(text.substr(position - 1, 1))
		)
		var after_position := position + identifier.length()
		var after_ok := (
			after_position >= text.length()
			or not _is_identifier_character(text.substr(after_position, 1))
		)
		if before_ok and after_ok:
			return position
		position = text.find(identifier, position + 1)
	return -1

# Prefers an already open Script resource for another project script so recent
# editor source can participate without loading or instantiating that class just
# for a tooltip. Closed scripts fall back to plain text read directly from disk.
func _read_project_script_source(path: String) -> String:
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

func _get_current_script_path() -> String:
	if not is_instance_valid(_script_editor):
		return ""
	var current_script := _script_editor.get_current_script()
	return current_script.resource_path if current_script != null else ""

# Identifies EditorHelpBit structurally instead of relying on an internal class
# name unavailable to GDScript. Both legacy and current theme-variation names
# are accepted so ordinary TooltipPanel popups are not modified by accident.
func _find_native_help_controls(popup: PopupPanel) -> Dictionary:
	var title: RichTextLabel = null
	var content: RichTextLabel = null
	for candidate in popup.find_children("*", "RichTextLabel", true, false):
		var label := candidate as RichTextLabel
		if label == null:
			continue
		if label.theme_type_variation in HELP_TITLE_VARIATIONS:
			title = label
		elif label.theme_type_variation in HELP_CONTENT_VARIATIONS:
			content = label
	if title == null or content == null or title.get_parent() != content.get_parent():
		return {}
	var container := title.get_parent() as VBoxContainer
	if container == null:
		return {}
	if container.has_node(NodePath(str(LOCAL_SECTION_NAME))):
		return {}
	return {
		"container": container,
		"title": title,
		"content": content,
	}

# Resolves the source position that caused Godot's tooltip. Pointer hovers use
# CodeEdit's current mouse position; the built-in "Show Tooltip" shortcut uses
# the caret instead. The native title disambiguates these two contexts without
# replacing or intercepting Godot's own symbol lookup.
func _get_symbol_context(
	code_edit: CodeEdit,
	native_title: RichTextLabel
) -> Dictionary:
	var title_text := native_title.get_parsed_text() if native_title != null else ""
	var mouse_context := _get_mouse_context(code_edit)
	if (
		not mouse_context.is_empty()
		and _title_mentions_symbol(title_text, str(mouse_context["symbol"]))
	):
		return mouse_context
	var caret_symbol := code_edit.get_word_under_caret()
	var caret_context := {}
	if not caret_symbol.is_empty():
		caret_context = {
			"symbol": caret_symbol,
			"line": code_edit.get_caret_line(),
			"column": code_edit.get_caret_column(),
		}
	if (
		not caret_context.is_empty()
		and _title_mentions_symbol(title_text, str(caret_context["symbol"]))
	):
		return caret_context
	# Custom/older help-bit variants may expose no usable title. Normal hover
	# tooltips still have a mouse word; keyboard tooltip requests do not, so fall
	# back to the caret only when the pointer cannot identify a symbol at all.
	if mouse_context.is_empty():
		return caret_context
	return mouse_context

func _get_pointer_context(code_edit: CodeEdit) -> Dictionary:
	var local_mouse: Vector2 = code_edit.get_local_mouse_position()
	var line_column: Vector2i = code_edit.get_line_column_at_pos(Vector2i(local_mouse))
	if line_column.y < 0 or line_column.y >= code_edit.get_line_count():
		return {}
	return {
		"symbol": code_edit.get_word_at_pos(local_mouse),
		"line": line_column.y,
		"column": line_column.x,
	}

func _get_mouse_context(code_edit: CodeEdit) -> Dictionary:
	var context: Dictionary = _get_pointer_context(code_edit)
	if str(context.get("symbol", "")).is_empty():
		return {}
	return context

# Resolves string-/path-oriented editor hovers that Godot does not expose as
# ordinary symbols. These are intentionally source-position based and only cover
# APIs with stable literal semantics: resource loads, InputMap actions,
# NodePaths and ProjectSettings keys.
func _resolve_special_hover(code_edit: CodeEdit, pointer_context: Dictionary) -> Dictionary:
	if pointer_context.is_empty():
		return {}
	var line_index: int = int(pointer_context.get("line", -1))
	var column: int = int(pointer_context.get("column", -1))
	if line_index < 0 or line_index >= code_edit.get_line_count():
		return {}
	var line: String = code_edit.get_line(line_index)
	var literal: Dictionary = _find_string_literal_at_column(line, column)
	if not literal.is_empty():
		var value: String = str(literal.get("value", ""))
		var literal_start: int = int(literal.get("start", -1))
		var is_project_path := value.begins_with("res://") or value.begins_with("uid://")
		var is_load_literal := _is_near_call(
			code_edit,
			line_index,
			literal_start,
			["preload", "load"]
		)
		var has_direct_preview := (
			_preview_pipeline != null
			and _preview_pipeline.supports_preview_path(value)
		)
		if is_project_path and (is_load_literal or has_direct_preview):
			return {
				"key": "resource:%s" % value,
				"title": "Project file reference",
				"plain_text": value,
				"resource_path": value,
			}
		var input_call: String = _nearest_matching_call(
			code_edit,
			line_index,
			literal_start,
			[
				"Input.is_action_pressed",
				"Input.is_action_just_pressed",
				"Input.is_action_just_released",
				"Input.get_axis",
				"Input.get_vector",
				"InputMap.has_action",
				"InputMap.action_get_events",
			]
		)
		if not input_call.is_empty():
			return _build_input_action_context(value, input_call)
		var project_call: String = _nearest_matching_call(
			code_edit,
			line_index,
			literal_start,
			[
				"ProjectSettings.get_setting",
				"ProjectSettings.get_setting_with_override",
				"ProjectSettings.has_setting",
				"ProjectSettings.set_setting",
			]
		)
		if not project_call.is_empty():
			return _build_project_setting_context(value, project_call)
		var node_call: String = _nearest_matching_call(
			code_edit,
			line_index,
			literal_start,
			[
				"get_node",
				"get_node_or_null",
				"has_node",
				"NodePath",
			]
		)
		if not node_call.is_empty():
			return _build_node_path_context(code_edit, value, node_call, false)
	var node_token: Dictionary = _find_node_path_token_at_column(line, column)
	if not node_token.is_empty():
		var token: String = str(node_token.get("value", ""))
		return _build_node_path_context(code_edit, token, token, true)
	# A variable can itself be the useful hover target when its initializer is a
	# statically identifiable scene-node reference. Follow the same short, source-only
	# alias model used by Resource previews instead of depending on the declared type.
	var symbol_context: Dictionary = _resolve_node_symbol_context(code_edit, pointer_context)
	if not symbol_context.is_empty():
		return symbol_context
	return {}

# Resolves a hovered local/member symbol back to a scene-node initializer.
# Qualified members of other objects are deliberately left to Godot because this
# source-only resolver cannot establish the owning instance reliably.
func _resolve_node_symbol_context(
	code_edit: CodeEdit,
	hover_context: Dictionary
) -> Dictionary:
	if hover_context.is_empty():
		return {}
	var symbol: String = str(hover_context.get("symbol", ""))
	if symbol.is_empty():
		return {}
	var line_index: int = int(hover_context.get("line", -1))
	var column: int = int(hover_context.get("column", -1))
	if _is_explicit_external_qualification(code_edit, line_index, column, symbol):
		return {}
	var reference: Dictionary = DocumentationParser.find_node_reference(
		code_edit.text,
		symbol,
		line_index
	)
	if reference.is_empty():
		return {}
	var path_value: String = str(reference.get("path", ""))
	if path_value.is_empty():
		return {}
	var node_kind: String = str(reference.get("node_kind", "node"))
	var context: Dictionary = _build_node_path_context(
		code_edit,
		path_value,
		"symbol:%s:%s" % [symbol, node_kind],
		bool(reference.get("is_shorthand", false))
	)
	if context.is_empty():
		return {}
	context["key"] = "node_symbol:%s:%s" % [symbol, path_value]
	context["title"] = "Node reference"
	var details: PackedStringArray = PackedStringArray()
	details.append("Symbol: %s" % symbol)
	details.append("Initializer: %s" % path_value)
	var alias_depth: int = int(reference.get("alias_depth", 0))
	if alias_depth > 0:
		details.append("Alias depth: %d" % alias_depth)
	var resolved_text: String = str(context.get("plain_text", ""))
	if not resolved_text.is_empty():
		details.append(resolved_text)
	context["plain_text"] = "\n".join(details)
	return context

# Finds the quoted literal containing the pointer column while respecting simple
# GDScript escapes. The returned value excludes quote characters.
static func _find_string_literal_at_column(line: String, column: int) -> Dictionary:
	var quote: String = ""
	var start: int = -1
	var escaped: bool = false
	for index: int in range(line.length()):
		var character: String = line.substr(index, 1)
		if quote.is_empty():
			if character == "\"" or character == "'":
				quote = character
				start = index
			continue
		if escaped:
			escaped = false
			continue
		if character == "\\":
			escaped = true
			continue
		if character == quote:
			if column >= start and column <= index:
				return {
					"start": start,
					"end": index,
					"value": line.substr(start + 1, index - start - 1),
				}
			quote = ""
			start = -1
	return {}

# Searches a small source window before the literal. Requiring the call name to
# occur after the most recent statement/newline boundary keeps this conservative
# while still supporting the common multiline preload()/load() form.
func _nearest_matching_call(
	code_edit: CodeEdit,
	line_index: int,
	column: int,
	call_names: Array[String]
) -> String:
	var start_line: int = maxi(0, line_index - 4)
	var window: String = ""
	for index: int in range(start_line, line_index + 1):
		var part: String = code_edit.get_line(index)
		if index == line_index:
			part = part.left(clampi(column, 0, part.length()))
		window += part + "\n"
	var best_name: String = ""
	var best_position: int = -1
	for name_value: String in call_names:
		var name: String = str(name_value)
		var position: int = window.rfind(name + "(")
		if position > best_position:
			best_position = position
			best_name = name
	if best_position < 0:
		return ""
	var tail: String = window.substr(best_position)
	if tail.count("(") <= tail.count(")"):
		return ""
	return best_name

func _is_near_call(
	code_edit: CodeEdit,
	line_index: int,
	column: int,
	call_names: Array[String]
) -> bool:
	return not _nearest_matching_call(code_edit, line_index, column, call_names).is_empty()

func _build_input_action_context(action: String, call_name: String) -> Dictionary:
	var exists: bool = InputMap.has_action(action)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Action: %s" % action)
	lines.append("Call: %s" % call_name)
	lines.append("Defined: %s" % ("yes" if exists else "no"))
	if exists:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty():
			lines.append("Events: none")
		else:
			lines.append("Events:")
			for event: InputEvent in events:
				lines.append("  • %s" % _format_input_event(event))
	return {
		"key": "input:%s:%s" % [call_name, action],
		"title": "Input action",
		"plain_text": "\n".join(lines),
	}

static func _format_input_event(event: InputEvent) -> String:
	if event == null:
		return "<null>"
	if event.has_method("as_text"):
		return str(event.call("as_text"))
	return str(event)

func _build_project_setting_context(setting: String, call_name: String) -> Dictionary:
	var exists: bool = ProjectSettings.has_setting(setting)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Setting: %s" % setting)
	lines.append("Call: %s" % call_name)
	lines.append("Defined: %s" % ("yes" if exists else "no"))
	if exists:
		var value: Variant = ProjectSettings.get_setting(setting)
		var value_text: String = str(value)
		if value_text.length() > 500:
			value_text = value_text.left(497) + "..."
		lines.append("Type: %s" % type_string(typeof(value)))
		lines.append("Current value: %s" % value_text)
	return {
		"key": "project_setting:%s:%s" % [call_name, setting],
		"title": "Project setting",
		"plain_text": "\n".join(lines),
	}

# Resolves $paths, %unique names and literal NodePath/get_node() arguments
# against the currently edited scene. If the current script is attached exactly
# once in that scene, relative $/get_node paths use that node as their base.
func _build_node_path_context(
	code_edit: CodeEdit,
	path_value: String,
	label: String,
	is_shorthand: bool
) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Path: %s" % path_value)
	if root == null:
		lines.append("Edited scene: none")
		return {
			"key": "node:%s" % path_value,
			"title": "Node path",
			"plain_text": "\n".join(lines),
		}
	var base: Node = _find_unique_scene_node_for_script(root, _get_current_script_path())
	if base == null:
		base = root
	var node_path_text: String = path_value
	if is_shorthand and node_path_text.begins_with("$"):
		node_path_text = node_path_text.trim_prefix("$")
	var target: Node = base.get_node_or_null(NodePath(node_path_text))
	lines.append("Base: %s" % str(base.get_path()))
	if target == null:
		lines.append("Resolved: no")
		return {
			"key": "node:%s:%s" % [label, path_value],
			"title": "Node path",
			"plain_text": "\n".join(lines),
		}
	lines.append("Resolved: %s" % str(target.get_path()))
	lines.append("Type: %s" % target.get_class())
	var result: Dictionary = {
		"key": "node:%s:%s" % [label, path_value],
		"title": "Node path",
	}
	var script: Script = target.get_script() as Script
	if script != null:
		var script_path: String = script.resource_path
		if not script_path.is_empty():
			lines.append("Script: %s" % script_path)
			var source: String = _read_project_script_source(script_path)
			if not source.is_empty():
				var class_name_value: String = DocumentationParser.get_script_class_name(source)
				if not class_name_value.is_empty():
					lines.append("Class: %s" % class_name_value)
					var documentation: Dictionary = DocumentationParser.find_member_documentation(
						source,
						class_name_value,
						-1,
						Settings.is_documentation_comments_enabled(),
						Settings.is_single_hash_member_documentation_enabled()
					)
					if not documentation.is_empty():
						result["documentation"] = documentation
						result["context_class"] = class_name_value
	result["plain_text"] = "\n".join(lines)
	return result

func _find_unique_scene_node_for_script(root: Node, script_path: String) -> Node:
	if root == null or script_path.is_empty():
		return null
	var matches: Array[Node] = []
	_collect_scene_nodes_for_script(root, script_path, matches)
	return matches[0] if matches.size() == 1 else null

func _collect_scene_nodes_for_script(node: Node, script_path: String, result: Array[Node]) -> void:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path == script_path:
		result.append(node)
	for child: Node in node.get_children():
		if child is Node:
			_collect_scene_nodes_for_script(child as Node, script_path, result)

# Matches common Godot NodePath shorthand tokens under the pointer. Quoted
# shorthand paths are already covered by the string-literal resolver above.
static func _find_node_path_token_at_column(line: String, column: int) -> Dictionary:
	var regex: RegEx = RegEx.new()
	regex.compile("(?:\\$[A-Za-z0-9_./]+|%[A-Za-z_][A-Za-z0-9_]*)")
	for match: RegExMatch in regex.search_all(line):
		if column >= match.get_start() and column <= match.get_end():
			return {
				"value": match.get_string(),
				"start": match.get_start(),
				"end": match.get_end(),
			}
	return {}

func _append_special_context_to_fallback(
	container: VBoxContainer,
	context: Dictionary,
	width: float
) -> void:
	var text: String = str(context.get("plain_text", ""))
	if not text.is_empty():
		var label: Label = Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = width
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(label)
	var documentation: Dictionary = context.get("documentation", {}) as Dictionary
	if not documentation.is_empty():
		var description: RichTextLabel = RichTextLabel.new()
		description.fit_content = true
		description.scroll_active = false
		description.selection_enabled = false
		description.focus_mode = Control.FOCUS_NONE
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x = width
		description.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		container.add_child(description)
		var renderer: BTDocumentationRenderer = _get_renderer()
		renderer.render_document(
			description,
			documentation,
			str(context.get("context_class", "")),
			false
		)
		TooltipAppearance.limit_rich_text_height(description)

func _append_special_context_to_native(
	help_container: VBoxContainer,
	native_content: RichTextLabel,
	context: Dictionary
) -> void:
	var section: VBoxContainer = VBoxContainer.new()
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_constant_override("separation", 0)
	var label: RichTextLabel = _create_documentation_label(native_content)
	label.text = str(context.get("plain_text", ""))
	section.add_child(label)
	var documentation: Dictionary = context.get("documentation", {}) as Dictionary
	if not documentation.is_empty():
		var document_label: RichTextLabel = _create_documentation_label(native_content)
		section.add_child(document_label)
		var renderer: BTDocumentationRenderer = _get_renderer()
		renderer.render_document(
			document_label,
			documentation,
			str(context.get("context_class", "")),
			false
		)
		TooltipAppearance.limit_rich_text_height(document_label)
	var separator: HSeparator = HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(separator)
	var native_index: int = native_content.get_index()
	help_container.add_child(section)
	help_container.move_child(section, native_index)

static func _title_mentions_symbol(title: String, symbol: String) -> bool:
	if title.is_empty() or symbol.is_empty():
		return false
	var position := title.find(symbol)
	while position >= 0:
		var before_ok := (
			position == 0
			or not _is_identifier_character(title.substr(position - 1, 1))
		)
		var after_position := position + symbol.length()
		var after_ok := (
			after_position >= title.length()
			or not _is_identifier_character(title.substr(after_position, 1))
		)
		if before_ok and after_ok:
			return true
		position = title.find(symbol, position + 1)
	return false

# Reports whether the hovered identifier is qualified through another object or
# class (e.g. `super.foo` or `other.foo`). Such symbols skip current-source lookup
# and instead rely on the owner class that Godot already resolved in its title.
# `self.foo` still refers to the current script and is therefore treated as local.
func _is_explicit_external_qualification(
	code_edit: CodeEdit,
	line_index: int,
	column: int,
	symbol: String
) -> bool:
	if line_index < 0 or line_index >= code_edit.get_line_count():
		return false
	var line: String = code_edit.get_line(line_index)
	var word_start := _find_symbol_start_near_column(line, symbol, column)
	if word_start <= 0 or line.substr(word_start - 1, 1) != ".":
		return false
	var qualifier_end := word_start - 1
	var qualifier_start := qualifier_end - 1
	while qualifier_start >= 0:
		var character := line.substr(qualifier_start, 1)
		if not _is_identifier_character(character):
			break
		qualifier_start -= 1
	var qualifier := line.substr(
		qualifier_start + 1,
		qualifier_end - qualifier_start - 1
	)
	return qualifier != "self"

static func _find_symbol_start_near_column(
	line: String,
	symbol: String,
	column: int
) -> int:
	if symbol.is_empty():
		return -1
	var search_from := maxi(0, column - symbol.length() - 1)
	var position := line.find(symbol, search_from)
	while position >= 0:
		var end := position + symbol.length()
		if column >= position and column <= end:
			return position
		position = line.find(symbol, position + 1)
	return line.find(symbol)

static func _is_identifier_character(character: String) -> bool:
	return (
		character == "_"
		or (character >= "a" and character <= "z")
		or (character >= "A" and character <= "Z")
		or (character >= "0" and character <= "9")
	)

# Detects Godot's empty-description placeholder in either the current editor
# language or the English fallback used by some help-bit variants.
func _native_is_no_description_placeholder(native_content: RichTextLabel) -> bool:
	var native_text := _normalize_comparison_text(native_content.get_parsed_text())
	return (
		native_text.is_empty()
		or native_text == _normalize_comparison_text(
			native_content.tr("No description available.")
		)
		or native_text == _normalize_comparison_text("No description available.")
	)

# Detects whether Godot's native description represents the same project ## block.
# That content can be replaced with the shared add-on renderer so FileSystem and
# Code Editor documentation use identical formatting. Base-class/engine help is
# not considered a duplicate and therefore remains visible below project docs.
func _native_contains_same_local_documentation(
	native_title: RichTextLabel,
	native_content: RichTextLabel,
	documentation: Dictionary,
	context_class: String
) -> bool:
	if str(documentation.get("source_marker", "")) != "##":
		return false
	var native_text := _normalize_comparison_text(native_content.get_parsed_text())
	var no_description_text := _normalize_comparison_text(
		native_content.tr("No description available.")
	)
	var no_description_english := _normalize_comparison_text(
		"No description available."
	)
	if (
		native_text.is_empty()
		or native_text == no_description_text
		or native_text == no_description_english
	):
		return false
	var description := str(documentation.get("description", "")).strip_edges()
	if not description.is_empty():
		var renderer: BTDocumentationRenderer = _get_renderer()
		var expected := _normalize_comparison_text(renderer.to_plain_text(description))
		if not expected.is_empty() and native_text.contains(expected):
			return true
	# Godot may enrich references while rendering (for example by appending ()
	# to method names), which makes exact plain-text comparison differ even for
	# the same documentation. If the populated native tooltip explicitly belongs
	# to this script member and already has content, treat it as authoritative.
	var member_name := str(documentation.get("member_name", ""))
	var title_text := native_title.get_parsed_text()
	return (
		not context_class.is_empty()
		and not member_name.is_empty()
		and _title_mentions_symbol(title_text, context_class)
		and _title_mentions_symbol(title_text, member_name)
	)

static func _normalize_comparison_text(text: String) -> String:
	return " ".join(text.replace("\r", " ").replace("\n", " ").split(" ", false))

# Replaces only Godot's description control when it contains the same project ##
# documentation. The native title/signature stays in place, while the shared
# renderer supplies line breaks, code blocks and links consistently with the
# FileSystem tooltip. The hidden native label remains owned by the popup.
func _replace_native_documentation(
	help_container: VBoxContainer,
	native_content: RichTextLabel,
	documentation: Dictionary,
	context_class: String
) -> void:
	var section: VBoxContainer = VBoxContainer.new()
	section.name = LOCAL_SECTION_NAME
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_constant_override("separation", 0)
	var label: RichTextLabel = _create_documentation_label(native_content)
	section.add_child(label)
	var native_index: int = native_content.get_index()
	help_container.add_child(section)
	help_container.move_child(section, native_index)
	native_content.hide()
	var renderer := _get_renderer()
	renderer.refresh_theme()
	renderer.render_document(label, documentation, context_class, false)
	TooltipAppearance.limit_rich_text_height(label)

# Inserts the add-on's normal documentation renderer after Godot's native title
# and before distinct native help content. Width is inherited from EditorHelpBit
# so formatting is identical in stock Godot and rearranged editor layouts.
func _append_local_documentation(
	help_container: VBoxContainer,
	native_content: RichTextLabel,
	documentation: Dictionary,
	context_class: String
) -> void:
	var section: VBoxContainer = VBoxContainer.new()
	section.name = LOCAL_SECTION_NAME
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_constant_override("separation", 0)
	var label: RichTextLabel = _create_documentation_label(native_content)
	section.add_child(label)
	var separator: HSeparator = HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(separator)
	var native_index: int = native_content.get_index()
	help_container.add_child(section)
	help_container.move_child(section, native_index)
	var renderer := _get_renderer()
	renderer.refresh_theme()
	renderer.render_document(label, documentation, context_class, false)
	TooltipAppearance.limit_rich_text_height(label)

# Creates the RichTextLabel used by both replacement and additive local sections.
# Copying the native help-content layout keeps the injected block aligned with
# Godot while TooltipAppearance applies the configured add-on background contrast.
func _create_documentation_label(native_content: RichTextLabel) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.focus_mode = Control.FOCUS_NONE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = native_content.autowrap_mode
	label.autowrap_trim_flags = native_content.autowrap_trim_flags
	label.custom_minimum_size.x = native_content.custom_minimum_size.x
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = native_content.theme_type_variation
	TooltipAppearance.style_addon_rich_text(
		label,
		native_content.get_theme_stylebox("normal")
	)
	return label

func _get_renderer() -> BTDocumentationRenderer:
	if _renderer == null:
		_renderer = DocumentationRenderer.new() as BTDocumentationRenderer
		_renderer.refresh_theme()
	return _renderer
