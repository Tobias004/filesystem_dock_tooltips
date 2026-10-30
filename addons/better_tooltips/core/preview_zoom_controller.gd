@tool
class_name BTPreviewZoomController
extends Node

## Owns transient graphical-preview hover sessions and mouse-wheel zoom.
## The central pipeline delegates zoom input here; rendering and layout are
## provided by dedicated generator/presenter collaborators.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const Debug := preload("res://addons/better_tooltips/tooltip_debug.gd")
const PreviewGenerator := preload("res://addons/better_tooltips/core/preview_generator.gd")

const PREVIEW_ZOOM_STEP_PERCENT := 10
const PREVIEW_ZOOM_MIN_PERCENT := 50
const PREVIEW_ZOOM_MAX_PERCENT := 250
const PREVIEW_ZOOM_DEBOUNCE_SECONDS := 0.12
const PREVIEW_ZOOM_TIMER_NAME := &"BTPreviewZoomTimer"
const MAX_GRAPHICAL_TOOLTIP_WIDTH_FRACTION := 0.82
const MAX_GRAPHICAL_TOOLTIP_HEIGHT_FRACTION := 0.78
const GRAPHICAL_TOOLTIP_EXIT_MARGIN := 56.0
const POINTER_CORNER_GUARD := 14.0
const PREVIEW_FRAME_NAME := &"PreviewFrame"
const PREVIEW_TEXTURE_NAME := &"PreviewTexture"

var _generator: Node = null
var _presenter: RefCounted = null
var _module_lookup: Callable
var _preview_sessions: Dictionary = {}
var _preview_session_sequence := 0
var _zoom_request_serial := 0
var _pending_zoom_session_id := 0
var _zoom_timer: Timer = null
var _tooltip_window_bindings: Dictionary = {}

func setup(
	parent: Node,
	generator: Node,
	presenter: RefCounted,
	module_lookup: Callable
) -> void:
	_generator = generator
	_presenter = presenter
	_module_lookup = module_lookup
	name = "BTPreviewZoomController"
	if get_parent() == null and is_instance_valid(parent):
		parent.add_child(self)
	_zoom_timer = Timer.new()
	_zoom_timer.name = PREVIEW_ZOOM_TIMER_NAME
	_zoom_timer.one_shot = true
	_zoom_timer.wait_time = PREVIEW_ZOOM_DEBOUNCE_SECONDS
	add_child(_zoom_timer)
	_zoom_timer.timeout.connect(_on_preview_zoom_timer_timeout)

func cleanup() -> void:
	_zoom_request_serial += 1
	_pending_zoom_session_id = 0
	if is_instance_valid(_zoom_timer):
		_zoom_timer.stop()
	_disconnect_tooltip_window_inputs()
	_preview_sessions.clear()
	_zoom_timer = null
	_generator = null
	_presenter = null
	_module_lookup = Callable()
	if is_inside_tree():
		queue_free()

func _get_module_entry(module_id: String) -> Dictionary:
	if not _module_lookup.is_valid():
		return {}
	var value: Variant = _module_lookup.call(module_id)
	return value as Dictionary if value is Dictionary else {}

func register_session(
	section: VBoxContainer,
	base: Control,
	resize_target: Node,
	module_id: String,
	path: String,
	entry: Dictionary
) -> void:
	if not is_instance_valid(section) or entry.is_empty():
		return
	_prune_preview_sessions()
	_preview_session_sequence += 1
	var configured_percent := Settings.get_preview_size_percent()
	var session_id := section.get_instance_id()
	_preview_sessions[session_id] = {
		"section": weakref(section),
		"base": weakref(base) if is_instance_valid(base) else null,
		"resize_target": weakref(resize_target) if is_instance_valid(resize_target) else null,
		"module_id": module_id,
		"path": path,
		"configured_percent": configured_percent,
		"default_percent": configured_percent,
		"requested_percent": configured_percent,
		"rendered_percent": configured_percent,
		"original_entry": entry.duplicate(),
		"default_entry": entry.duplicate(),
		"display_entry": entry.duplicate(),
		"sequence": _preview_session_sequence,
		"request_serial": 0,
	}
	# The containing native tooltip may not know its final size until the section
	# has entered the tree. A deferred limit pass makes the same screen-budget
	# decision for FileSystem and Code Editor previews.
	call_deferred("_apply_initial_preview_screen_limit", session_id)
	call_deferred("_bind_preview_session_window_input", session_id)

# Handles wheel input globally only while an add-on graphical preview is visible.
# Returning true lets plugin.gd mark the editor input as handled. For graphical
# tooltips the wheel is intentionally reserved for preview zoom; text-only
# tooltips have no preview session and keep their normal scrolling behavior.
func handle_input(event: InputEvent) -> bool:
	# Only the popup under (or immediately adjacent to) the pointer may
	# consume the editor-wide wheel event. Multiple tooltips can coexist while
	# Godot changes tabs or an IDE rebuilds its outline.
	if not (event is InputEventMouseButton):
		return false
	var pointer := DisplayServer.mouse_get_position()
	_prune_preview_sessions()
	var best_id := 0
	var best_sequence := -1
	for session_id_value: Variant in _preview_sessions.keys():
		var session_id := int(session_id_value)
		var session := _preview_sessions[session_id] as Dictionary
		var section := _get_preview_session_section(session)
		if section == null or not section.is_visible_in_tree():
			continue
		var rect := _get_session_tooltip_rect(session)
		if rect.size.x <= 0 or rect.size.y <= 0 or not rect.grow(32).has_point(pointer):
			continue
		var sequence := int(session.get("sequence", 0))
		if sequence > best_sequence:
			best_sequence = sequence
			best_id = session_id
	if best_id == 0:
		return false
	return _handle_input_for_session(event, best_id)

func _handle_input_for_session(event: InputEvent, session_id: int) -> bool:
	if not _preview_sessions.has(session_id):
		return false
	if not (event is InputEventMouseButton):
		return false
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return false
	if (
		mouse_event.button_index != MOUSE_BUTTON_WHEEL_UP
		and mouse_event.button_index != MOUSE_BUTTON_WHEEL_DOWN
	):
		return false
	var session := _preview_sessions[session_id] as Dictionary
	var section := _get_preview_session_section(session)
	if section == null or not section.is_visible_in_tree():
		return false
	# Do not consume editor-wide wheel events just because a different graphical
	# preview happens to remain visible somewhere in the editor.
	var active_rect := _get_session_tooltip_rect(session)
	if active_rect.size.x <= 0 or active_rect.size.y <= 0:
		return false
	if not active_rect.grow(32).has_point(DisplayServer.mouse_get_position()):
		return false
	var direction := 1 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
	var wheel_steps := maxi(1, roundi(maxf(1.0, absf(mouse_event.factor))))
	_adjust_preview_zoom(
		session_id,
		direction * PREVIEW_ZOOM_STEP_PERCENT * wheel_steps
	)
	return true

# A PopupPanel is its own Viewport. Wheel events generated while the pointer is
# directly over a native Code Editor/FileSystem tooltip therefore never reach
# EditorPlugin._input(). Bind the actual tooltip Window once and forward its
# window_input signal into the same session zoom path used everywhere else.
func _bind_preview_session_window_input(session_id: int) -> void:
	if not _preview_sessions.has(session_id):
		return
	var session := _preview_sessions[session_id] as Dictionary
	var base := _get_preview_session_node(session, "base") as Control
	var requested_target := _get_preview_session_node(session, "resize_target")
	var target := _presenter.resolve_tooltip_resize_target(base, requested_target) as Node
	var window := target as Window
	if window == null or not window.is_inside_tree():
		return
	var window_id := window.get_instance_id()
	var existing_value: Variant = _tooltip_window_bindings.get(window_id, null)
	if existing_value is Dictionary:
		var existing_ref: Variant = (existing_value as Dictionary).get("window", null)
		if existing_ref is WeakRef and is_instance_valid((existing_ref as WeakRef).get_ref()):
			return
	var callback := Callable(self, "_on_tooltip_window_input").bind(window_id)
	if not window.window_input.is_connected(callback):
		window.window_input.connect(callback)
	_tooltip_window_bindings[window_id] = {
		"window": weakref(window),
		"callback": callback,
	}

func _on_tooltip_window_input(event: InputEvent, window_id: int) -> void:
	var session_id := _find_latest_visible_preview_session_for_window(window_id)
	if session_id == 0 or not _handle_input_for_session(event, session_id):
		return
	var binding_value: Variant = _tooltip_window_bindings.get(window_id, null)
	if not (binding_value is Dictionary):
		return
	var window_ref: Variant = (binding_value as Dictionary).get("window", null)
	if window_ref is WeakRef:
		var window := (window_ref as WeakRef).get_ref() as Window
		if is_instance_valid(window):
			window.set_input_as_handled()

func _find_latest_visible_preview_session_for_window(window_id: int) -> int:
	_prune_preview_sessions()
	var best_id := 0
	var best_sequence := -1
	for session_id_value: Variant in _preview_sessions.keys():
		var session_id := int(session_id_value)
		var session := _preview_sessions[session_id] as Dictionary
		var section := _get_preview_session_section(session)
		if section == null or not section.is_visible_in_tree():
			continue
		var base := _get_preview_session_node(session, "base") as Control
		var requested_target := _get_preview_session_node(session, "resize_target")
		var target := _presenter.resolve_tooltip_resize_target(base, requested_target) as Node
		if not (target is Window) or target.get_instance_id() != window_id:
			continue
		var sequence := int(session.get("sequence", 0))
		if sequence > best_sequence:
			best_sequence = sequence
			best_id = session_id
	return best_id

func _disconnect_tooltip_window_inputs() -> void:
	for binding_value: Variant in _tooltip_window_bindings.values():
		if not (binding_value is Dictionary):
			continue
		var binding := binding_value as Dictionary
		var window_ref: Variant = binding.get("window", null)
		var callback_value: Variant = binding.get("callback", null)
		if not (window_ref is WeakRef) or not (callback_value is Callable):
			continue
		var window := (window_ref as WeakRef).get_ref() as Window
		var callback := callback_value as Callable
		if is_instance_valid(window) and window.window_input.is_connected(callback):
			window.window_input.disconnect(callback)
	_tooltip_window_bindings.clear()

# Applies the requested size immediately using the best texture already rendered,
# then debounces the expensive high-resolution regeneration. Returning to the
# effective hover default restores the cached/default display texture directly and
# cancels transient work. The effective default may be screen-limited for one hover.
func _adjust_preview_zoom(session_id: int, delta_percent: int) -> void:
	if not _preview_sessions.has(session_id):
		return
	var session := _preview_sessions[session_id] as Dictionary
	var section := _get_preview_session_section(session)
	if section == null or not section.is_visible_in_tree():
		_preview_sessions.erase(session_id)
		return
	var current_percent := int(session.get(
		"requested_percent",
		Settings.get_preview_size_percent()
	))
	var maximum_percent := _get_session_max_zoom_percent(session)
	var target_percent := clampi(
		current_percent + delta_percent,
		PREVIEW_ZOOM_MIN_PERCENT,
		maximum_percent
	)
	if target_percent == current_percent:
		return
	var pointer_context := _capture_pointer_resize_context(session)
	_zoom_request_serial += 1
	var request_serial := _zoom_request_serial
	session["requested_percent"] = target_percent
	session["request_serial"] = request_serial
	_preview_sessions[session_id] = session
	var default_percent := int(session.get(
		"default_percent",
		Settings.get_preview_size_percent()
	))
	if target_percent == default_percent:
		if is_instance_valid(_zoom_timer):
			_zoom_timer.stop()
		_pending_zoom_session_id = 0
		var default_entry := session.get("default_entry", {}) as Dictionary
		if not default_entry.is_empty():
			_presenter.set_section_preview(section, default_entry)
			session["display_entry"] = default_entry.duplicate()
			session["rendered_percent"] = default_percent
			_preview_sessions[session_id] = session
			_refresh_preview_session_layout(session)
			_queue_pointer_reposition(session_id, request_serial, pointer_context)
		return
	var display_entry := session.get("display_entry", {}) as Dictionary
	var rendered_percent := int(session.get("rendered_percent", default_percent))
	var scaled_entry := _scale_preview_entry(
		display_entry,
		rendered_percent,
		target_percent
	)
	if not scaled_entry.is_empty():
		_presenter.set_section_preview(section, scaled_entry)
		_refresh_preview_session_layout(session)
		_queue_pointer_reposition(session_id, request_serial, pointer_context)
	_pending_zoom_session_id = session_id
	if is_instance_valid(_zoom_timer):
		_zoom_timer.start(PREVIEW_ZOOM_DEBOUNCE_SECONDS)

# Produces a display-only size around an existing texture while the debounced
# render is pending. The following transient render replaces this scaled texture
# with pixels generated at the actual requested resolution.
func _scale_preview_entry(
	entry: Dictionary,
	rendered_percent: int,
	target_percent: int
) -> Dictionary:
	var texture := entry.get("texture", null) as Texture2D
	var size_value: Variant = entry.get("size", Vector2i.ZERO)
	if texture == null or not (size_value is Vector2i) or rendered_percent <= 0:
		return {}
	var size := size_value as Vector2i
	var ratio := float(target_percent) / float(rendered_percent)
	return {
		"texture": texture,
		"size": Vector2i(
			maxi(2, roundi(float(size.x) * ratio)),
			maxi(2, roundi(float(size.y) * ratio))
		),
		"bytes": int(entry.get("bytes", 0)),
	}

func _on_preview_zoom_timer_timeout() -> void:
	var session_id := _pending_zoom_session_id
	_pending_zoom_session_id = 0
	if session_id == 0 or not _preview_sessions.has(session_id):
		return
	var session := _preview_sessions[session_id] as Dictionary
	var request_serial := int(session.get("request_serial", 0))
	_start_transient_zoom_generation(session_id, request_serial)

# Non-awaiting wrapper used by the timer. The coroutine owns its temporary
# render tree and silently discards stale results when the pointer moves away or
# another wheel step supersedes the request.
func _start_transient_zoom_generation(
	session_id: int,
	request_serial: int
) -> void:
	_run_transient_zoom_generation(session_id, request_serial)

# Regenerates one preview at the wheel-selected size without reading or writing
# the add-on preview cache. ResourceLoader may still reuse Godot's normal loaded
# Resource object; only the generated tooltip image is intentionally transient.
func _run_transient_zoom_generation(
	session_id: int,
	request_serial: int
) -> void:
	if not _transient_request_is_current(session_id, request_serial):
		return
	var session := _preview_sessions[session_id] as Dictionary
	var module_id := String(session.get("module_id", ""))
	var path := String(session.get("path", ""))
	var module_entry := _get_module_entry(module_id)
	var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
	if plugin == null or path.is_empty() or _generator == null:
		return
	var requested_percent := int(session.get(
		"requested_percent",
		Settings.get_preview_size_percent()
	))
	var metadata := {
		Settings.PREVIEW_SCALE_METADATA_KEY: float(requested_percent) / 100.0,
		"source": "transient_wheel_zoom",
	}
	var safety_limit_ms := (
		0
		if Input.is_key_pressed(KEY_SHIFT)
		else Settings.get_preview_safety_limit_ms()
	)
	var current_callback := Callable(self, "_transient_request_is_current").bind(
		session_id,
		request_serial
	)
	var capture: Dictionary = await _generator.generate(
		plugin,
		path,
		metadata,
		safety_limit_ms,
		current_callback
	)
	if String(capture.get("status", PreviewGenerator.STATUS_CANCELLED)) != PreviewGenerator.STATUS_READY:
		return
	if not _transient_request_is_current(session_id, request_serial):
		return
	var texture := capture.get("texture", null) as Texture2D
	var image := capture.get("image", null) as Image
	var size_value: Variant = capture.get("size", Vector2i.ZERO)
	if texture == null or image == null or not (size_value is Vector2i):
		return
	var entry := {
		"texture": texture,
		"size": size_value as Vector2i,
		"bytes": image.get_data_size(),
	}
	session = _preview_sessions[session_id] as Dictionary
	var section := _get_preview_session_section(session)
	if section == null:
		return
	_presenter.set_section_preview(section, entry)
	session["display_entry"] = entry
	session["rendered_percent"] = requested_percent
	_preview_sessions[session_id] = session
	_refresh_preview_session_layout(session)
	Debug.log(
		String(module_entry.get("name", "Preview")),
		"transient wheel render %d%%: %s" % [requested_percent, path]
	)

func _transient_request_is_current(
	session_id: int,
	request_serial: int
) -> bool:
	if not _preview_sessions.has(session_id):
		return false
	var session := _preview_sessions[session_id] as Dictionary
	if int(session.get("request_serial", 0)) != request_serial:
		return false
	var module_id := String(session.get("module_id", ""))
	if module_id.is_empty() or _get_module_entry(module_id).is_empty():
		return false
	var section := _get_preview_session_section(session)
	return section != null and section.is_inside_tree() and section.is_visible_in_tree()

func _find_latest_visible_preview_session() -> int:
	_prune_preview_sessions()
	var best_id := 0
	var best_sequence := -1
	for session_id_value: Variant in _preview_sessions.keys():
		var session_id := int(session_id_value)
		var session := _preview_sessions[session_id] as Dictionary
		var section := _get_preview_session_section(session)
		if section == null or not section.is_visible_in_tree():
			continue
		var sequence := int(session.get("sequence", 0))
		if sequence > best_sequence:
			best_sequence = sequence
			best_id = session_id
	return best_id

func _prune_preview_sessions() -> void:
	var stale_ids: Array[int] = []
	for session_id_value: Variant in _preview_sessions.keys():
		var session_id := int(session_id_value)
		var session := _preview_sessions[session_id] as Dictionary
		var section := _get_preview_session_section(session)
		if section == null or not section.is_inside_tree():
			stale_ids.append(session_id)
	for session_id in stale_ids:
		_preview_sessions.erase(session_id)
		if _pending_zoom_session_id == session_id:
			_pending_zoom_session_id = 0
	_prune_tooltip_window_bindings()

func _prune_tooltip_window_bindings() -> void:
	var stale_ids: Array[int] = []
	for window_id_value: Variant in _tooltip_window_bindings.keys():
		var window_id := int(window_id_value)
		var binding_value: Variant = _tooltip_window_bindings.get(window_id, null)
		if not (binding_value is Dictionary):
			stale_ids.append(window_id)
			continue
		var window_ref: Variant = (binding_value as Dictionary).get("window", null)
		if not (window_ref is WeakRef) or not is_instance_valid((window_ref as WeakRef).get_ref()):
			stale_ids.append(window_id)
	for window_id in stale_ids:
		_tooltip_window_bindings.erase(window_id)

# Drops hover sessions owned by a module that is being disabled. This prevents a
# transient render already in flight from publishing into a tooltip after its
# preview module has been removed from the central pipeline.
func remove_sessions_for_module(module_id: String) -> void:
	var removed_pending_session := false
	var remove_ids: Array[int] = []
	for session_id_value: Variant in _preview_sessions.keys():
		var session_id := int(session_id_value)
		var session := _preview_sessions[session_id] as Dictionary
		if String(session.get("module_id", "")) != module_id:
			continue
		remove_ids.append(session_id)
		if _pending_zoom_session_id == session_id:
			removed_pending_session = true
	for session_id in remove_ids:
		_preview_sessions.erase(session_id)
	if remove_ids.is_empty():
		return
	_zoom_request_serial += 1
	if removed_pending_session:
		_pending_zoom_session_id = 0
		if is_instance_valid(_zoom_timer):
			_zoom_timer.stop()

# Applies the dynamic screen limit once the surrounding tooltip has a measurable
# size. A too-large configured default remains cached at its configured render
# resolution but is displayed downscaled for this hover only.
func _apply_initial_preview_screen_limit(session_id: int) -> void:
	if not _preview_sessions.has(session_id):
		return
	var session := _preview_sessions[session_id] as Dictionary
	var section := _get_preview_session_section(session)
	if section == null or not section.is_visible_in_tree():
		return
	var configured_percent := int(session.get(
		"configured_percent",
		Settings.get_preview_size_percent()
	))
	var maximum_percent := _get_session_max_zoom_percent(session)
	if configured_percent <= maximum_percent:
		return
	var original_entry := session.get("original_entry", {}) as Dictionary
	var limited_entry := _scale_preview_entry(
		original_entry,
		configured_percent,
		maximum_percent
	)
	if limited_entry.is_empty():
		return
	_presenter.set_section_preview(section, limited_entry)
	session["default_percent"] = maximum_percent
	session["requested_percent"] = maximum_percent
	session["rendered_percent"] = maximum_percent
	session["default_entry"] = limited_entry.duplicate()
	session["display_entry"] = limited_entry.duplicate()
	_preview_sessions[session_id] = session
	_refresh_preview_session_layout(session)

# Returns the largest zoom percentage that still leaves a meaningful amount of
# visible desktop around the tooltip. The budget includes the existing tooltip
# header/text/padding, so a large Code Editor help bit and a small FileSystem
# tooltip converge on the same final outer-screen constraints.
func _get_session_max_zoom_percent(session: Dictionary) -> int:
	var configured_percent := int(session.get(
		"configured_percent",
		Settings.get_preview_size_percent()
	))
	var original_entry := session.get("original_entry", {}) as Dictionary
	var original_size_value: Variant = original_entry.get("size", Vector2i.ZERO)
	if not (original_size_value is Vector2i):
		return PREVIEW_ZOOM_MAX_PERCENT
	var original_size := original_size_value as Vector2i
	if original_size.x <= 0 or original_size.y <= 0:
		return PREVIEW_ZOOM_MAX_PERCENT
	var tooltip_rect := _get_session_tooltip_rect(session)
	var preview_size := _get_session_preview_display_size(session)
	if tooltip_rect.size.x <= 0 or tooltip_rect.size.y <= 0 or preview_size.x <= 0.0 or preview_size.y <= 0.0:
		return PREVIEW_ZOOM_MAX_PERCENT
	var screen := _get_session_screen(session)
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		return PREVIEW_ZOOM_MAX_PERCENT
	var editor_scale := EditorInterface.get_editor_scale()
	var exit_margin := roundi(GRAPHICAL_TOOLTIP_EXIT_MARGIN * editor_scale)
	var max_tooltip_width := mini(
		roundi(float(usable_rect.size.x) * MAX_GRAPHICAL_TOOLTIP_WIDTH_FRACTION),
		maxi(2, usable_rect.size.x - exit_margin * 2)
	)
	var max_tooltip_height := mini(
		roundi(float(usable_rect.size.y) * MAX_GRAPHICAL_TOOLTIP_HEIGHT_FRACTION),
		maxi(2, usable_rect.size.y - exit_margin * 2)
	)
	var overhead_x := maxi(0, tooltip_rect.size.x - roundi(preview_size.x))
	var overhead_y := maxi(0, tooltip_rect.size.y - roundi(preview_size.y))
	var max_preview_width := maxi(2, max_tooltip_width - overhead_x)
	var max_preview_height := maxi(2, max_tooltip_height - overhead_y)
	var width_percent := floori(
		float(configured_percent) * float(max_preview_width) / float(original_size.x)
	)
	var height_percent := floori(
		float(configured_percent) * float(max_preview_height) / float(original_size.y)
	)
	return clampi(
		mini(PREVIEW_ZOOM_MAX_PERCENT, mini(width_percent, height_percent)),
		PREVIEW_ZOOM_MIN_PERCENT,
		PREVIEW_ZOOM_MAX_PERCENT
	)

func _get_session_preview_display_size(session: Dictionary) -> Vector2:
	var section := _get_preview_session_section(session)
	if section == null:
		return Vector2.ZERO
	var rect := section.get_node_or_null(
		"Background/Body/%s/%s" % [PREVIEW_FRAME_NAME, PREVIEW_TEXTURE_NAME]
	) as TextureRect
	if rect == null:
		return Vector2.ZERO
	return rect.custom_minimum_size

# Returns the screen-space bounds used for pointer-relative zoom. Explicit popup
# windows are preferred; otherwise the visible tooltip base control supplies a
# screen-space fallback for FileSystem tooltip implementations.
func _get_session_tooltip_rect(session: Dictionary) -> Rect2i:
	var base := _get_preview_session_node(session, "base") as Control
	var requested_target := _get_preview_session_node(session, "resize_target")
	var target := _presenter.resolve_tooltip_resize_target(base, requested_target) as Node
	if target is Window:
		var window := target as Window
		return Rect2i(window.position, window.size)
	if target is Control:
		var control := target as Control
		return Rect2i(Vector2i(control.get_screen_position()), Vector2i(control.size))
	if is_instance_valid(base):
		return Rect2i(Vector2i(base.get_screen_position()), Vector2i(base.size))
	return Rect2i()

func _get_session_screen(session: Dictionary) -> int:
	var base := _get_preview_session_node(session, "base") as Control
	var requested_target := _get_preview_session_node(session, "resize_target")
	var target := _presenter.resolve_tooltip_resize_target(base, requested_target) as Node
	if target is Window:
		var window := target as Window
		if window.current_screen >= 0:
			return window.current_screen
	var editor_window := EditorInterface.get_base_control().get_window()
	if editor_window != null and editor_window.current_screen >= 0:
		return editor_window.current_screen
	return DisplayServer.get_primary_screen()

# Captures the pointer's normalized location inside the visible tooltip before a
# zoom resize. Only the tiny corner zones are excluded, preserving an intentional
# escape point while keeping ordinary in-tooltip pointer semantics stable.
func _capture_pointer_resize_context(session: Dictionary) -> Dictionary:
	var tooltip_rect := _get_session_tooltip_rect(session)
	if tooltip_rect.size.x <= 0 or tooltip_rect.size.y <= 0:
		return {}
	var mouse_position := DisplayServer.mouse_get_position()
	if not tooltip_rect.has_point(mouse_position):
		return {}
	var local := mouse_position - tooltip_rect.position
	var guard := roundi(POINTER_CORNER_GUARD * EditorInterface.get_editor_scale())
	var near_horizontal_edge := local.x <= guard or local.x >= tooltip_rect.size.x - guard
	var near_vertical_edge := local.y <= guard or local.y >= tooltip_rect.size.y - guard
	if near_horizontal_edge and near_vertical_edge:
		return {}
	return {
		"relative": Vector2(
			float(local.x) / float(tooltip_rect.size.x),
			float(local.y) / float(tooltip_rect.size.y)
		),
	}

func _queue_pointer_reposition(
	session_id: int,
	request_serial: int,
	pointer_context: Dictionary
) -> void:
	if pointer_context.is_empty():
		return
	var relative_value: Variant = pointer_context.get("relative", Vector2.ZERO)
	if not (relative_value is Vector2):
		return
	call_deferred(
		"_reposition_pointer_after_layout",
		session_id,
		request_serial,
		relative_value as Vector2
	)

# Repositions the cursor to the same normalized point in the resized tooltip.
# This is especially important when shrinking: the tooltip cannot disappear from
# underneath the cursor merely because its dimensions changed around that cursor.
func _reposition_pointer_after_layout(
	session_id: int,
	request_serial: int,
	relative: Vector2
) -> void:
	if not _preview_sessions.has(session_id):
		return
	var session := _preview_sessions[session_id] as Dictionary
	if int(session.get("request_serial", 0)) != request_serial:
		return
	var tooltip_rect := _get_session_tooltip_rect(session)
	if tooltip_rect.size.x <= 0 or tooltip_rect.size.y <= 0:
		return
	var target := Vector2(tooltip_rect.position) + Vector2(
		float(tooltip_rect.size.x) * clampf(relative.x, 0.0, 1.0),
		float(tooltip_rect.size.y) * clampf(relative.y, 0.0, 1.0)
	)
	var inset := 2.0
	target.x = clampf(
		target.x,
		float(tooltip_rect.position.x) + inset,
		float(tooltip_rect.end.x) - inset
	)
	target.y = clampf(
		target.y,
		float(tooltip_rect.position.y) + inset,
		float(tooltip_rect.end.y) - inset
	)
	_warp_mouse_to_screen_position(Vector2i(roundi(target.x), roundi(target.y)))

# DisplayServer.warp_mouse() expects coordinates relative to the currently active
# window, while mouse_get_position() and tooltip geometry use screen coordinates.
# A visible PopupPanel can be the active window even with NO_FOCUS, so prefer its
# client-area origin and otherwise fall back to the main editor window.
func _warp_mouse_to_screen_position(screen_position: Vector2i) -> void:
	var editor_window := EditorInterface.get_base_control().get_window()
	var window_origin := Vector2i.ZERO
	if editor_window != null:
		var editor_window_id := editor_window.get_window_id()
		var active_popup_id := DisplayServer.window_get_active_popup()
		if active_popup_id >= 0:
			window_origin = DisplayServer.window_get_position(active_popup_id)
		else:
			window_origin = DisplayServer.window_get_position(editor_window_id)
	DisplayServer.warp_mouse(screen_position - window_origin)

func _get_preview_session_section(session: Dictionary) -> VBoxContainer:
	var section_ref: Variant = session.get("section", null)
	if section_ref is WeakRef:
		var section := (section_ref as WeakRef).get_ref() as VBoxContainer
		if is_instance_valid(section):
			return section
	return null

func _get_preview_session_node(session: Dictionary, key: String) -> Node:
	var reference_value: Variant = session.get(key, null)
	if reference_value is WeakRef:
		var node := (reference_value as WeakRef).get_ref() as Node
		if is_instance_valid(node):
			return node
	return null

func _refresh_preview_session_layout(session: Dictionary) -> void:
	var base := _get_preview_session_node(session, "base") as Control
	var resize_target := _get_preview_session_node(session, "resize_target")
	_presenter.refresh_tooltip_layout(base, resize_target)

# Replaces the section body with a readable pipeline-status message.
