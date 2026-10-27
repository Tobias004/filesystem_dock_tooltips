@tool
class_name BTTooltipPipeline
extends EditorResourceTooltipPlugin

## [b]Central asynchronous preview pipeline[/b] for Better Tooltips.
## The normal FileSystem tooltip is returned immediately while uncached previews are generated afterwards and then stored as static [ImageTexture] entries.
## Ordinary slow previews are allowed to finish; only the generous safety limit can stop remaining work at safe checkpoints.
## [i]Cold-render note:[/i] first-time rendering can compile and cache Godot or driver shaders, so the first preview after clearing shader caches may be much slower than later previews.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const Debug := preload("res://addons/better_tooltips/tooltip_debug.gd")
const TooltipCache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const TooltipAppearance := preload(
	"res://addons/better_tooltips/core/tooltip_appearance.gd"
)

const STATUS_GENERATING := "GENERATING"
const STATUS_READY := "READY"
const STATUS_NO_PREVIEW := "NO_PREVIEW"
const STATUS_CANCELLED := "CANCELLED"
const CAPTURE_RENDER_FRAMES := 2
const STATUS_WIDTH := 360.0
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
const LIVE_TEXT_POPUP_NAME := &"BTInteractiveTextTooltip"
const LIVE_TEXT_TOOLTIP_PANEL_VARIATION := &"TooltipPanel"
const LIVE_TEXT_MONITOR_TIMER_NAME := &"BTLiveTextTooltipMonitor"
const LIVE_TEXT_MONITOR_INTERVAL_SECONDS := 0.04
const LIVE_TEXT_EXIT_GRACE_SECONDS := 0.30
const LIVE_TEXT_POPUP_GAP := 10.0
const LIVE_TEXT_SCREEN_MARGIN := 8.0

var _cache: BTTooltipCache = null
var _render_host: Node = null
var _modules: Dictionary = {}
var _module_order: Array[String] = []
var _jobs: Dictionary = {}
var _generation_epoch := 0
var _preview_sessions: Dictionary = {}
var _preview_session_sequence := 0
var _zoom_request_serial := 0
var _pending_zoom_session_id := 0
var _zoom_timer: Timer = null
var _tooltip_window_bindings: Dictionary = {}
var _live_text_session: Dictionary = {}
var _live_text_session_sequence := 0
var _live_text_monitor: Timer = null

# Creates the hidden editor-side host used only while a generated preview is
# being rendered and captured. Finished cache entries contain static textures,
# so their temporary render trees can be released immediately afterward.
func setup(cache: BTTooltipCache, parent: Node) -> void:
	_cache = cache
	if is_instance_valid(_render_host):
		return
	_render_host = Node.new()
	_render_host.name = "FileSystemDockTooltipPipeline"
	parent.add_child(_render_host)
	_zoom_timer = Timer.new()
	_zoom_timer.name = PREVIEW_ZOOM_TIMER_NAME
	_zoom_timer.one_shot = true
	_zoom_timer.wait_time = PREVIEW_ZOOM_DEBOUNCE_SECONDS
	_render_host.add_child(_zoom_timer)
	_zoom_timer.timeout.connect(_on_preview_zoom_timer_timeout)
	_live_text_monitor = Timer.new()
	_live_text_monitor.name = LIVE_TEXT_MONITOR_TIMER_NAME
	_live_text_monitor.one_shot = false
	_live_text_monitor.wait_time = LIVE_TEXT_MONITOR_INTERVAL_SECONDS
	_render_host.add_child(_live_text_monitor)
	_live_text_monitor.timeout.connect(_on_live_text_monitor_timeout)

# Cancels pending result publication, releases temporary render infrastructure
# and drops module references when the add-on is disabled.
func cleanup() -> void:
	_generation_epoch += 1
	_remove_all_job_sections()
	_jobs.clear()
	_preview_sessions.clear()
	_disconnect_tooltip_window_inputs()
	_close_live_text_session()
	_zoom_request_serial += 1
	_pending_zoom_session_id = 0
	_zoom_timer = null
	_live_text_monitor = null
	_modules.clear()
	_module_order.clear()
	if is_instance_valid(_render_host):
		_render_host.queue_free()
	_render_host = null
	_cache = null

# Adds one enabled resource-preview module to the pipeline. Modules keep their
# existing _handles() and _make_tooltip_for_path() implementations and therefore
# remain responsible only for resource-specific preview construction.
func add_module(
	module_id: String,
	module_name: String,
	plugin: EditorResourceTooltipPlugin
) -> void:
	if module_id.is_empty() or plugin == null:
		return
	if not _modules.has(module_id):
		_module_order.append(module_id)
	_modules[module_id] = {
		"name": module_name,
		"plugin": plugin,
	}

# Removes one module and cancels jobs belonging to it. The shared successful and
# failure cache is intentionally retained so re-enabling a module in the same
# editor session can reuse already generated entries.
func remove_module(module_id: String) -> void:
	if not _modules.has(module_id):
		return
	_cancel_jobs_for_module(module_id)
	_remove_preview_sessions_for_module(module_id)
	if String(_live_text_session.get("module_id", "")) == module_id:
		_close_live_text_session()
	_modules.erase(module_id)
	_module_order.erase(module_id)

# Clears successful/failure cache entries and invalidates all in-flight jobs so
# a generation that finishes after the clear action cannot silently repopulate
# the cache with an entry that the user explicitly requested to remove.
func clear_cache() -> void:
	_generation_epoch += 1
	_remove_all_job_sections()
	_jobs.clear()
	if _cache != null:
		_cache.clear()

# Reports support when any currently enabled preview module handles Godot's
# FileSystemDock dispatch type. Loadable Resources arrive with their resource
# type; ordinary text files arrive as an empty string and are resolved by path
# later. Godot therefore still registers only this one central tooltip plugin.
func _handles(type: String) -> bool:
	return not _matching_module_ids(type).is_empty()

# Adds cached results or a visible generating section immediately, then schedules
# uncached work for a later editor frame. This lets Godot display its normal
# tooltip and the status message before potentially expensive render work starts.
func _make_tooltip_for_path(
	path: String,
	metadata: Dictionary,
	base: Control
) -> Control:
	var preview_context := _get_path_preview_context(path)
	if preview_context.is_empty():
		return base
	var normalized_path := String(preview_context.get("path", path))
	var matching_ids := preview_context.get("module_ids", []) as Array[String]
	for module_id in matching_ids:
		var module_entry: Dictionary = _modules.get(module_id, {})
		if module_entry.is_empty():
			continue
		_serve_module(module_id, module_entry, normalized_path, metadata, base, base)
	return base

# Adds the same cached/generated preview used by FileSystem Dock tooltips to an
# arbitrary visible editor tooltip. Code Editor integration uses this entry point
# after resolving a source symbol to a literal preload()/load() resource path.
# No Resource is loaded for type detection; EditorFileSystem already knows it.
func append_preview_for_path(
	path: String,
	base: Control,
	resize_target: Node = null,
	metadata: Dictionary = {}
) -> bool:
	if not is_instance_valid(base):
		return false
	var preview_context := _get_path_preview_context(path)
	if preview_context.is_empty():
		return false
	var normalized_path := String(preview_context.get("path", ""))
	var matching_ids := preview_context.get("module_ids", []) as Array[String]
	var effective_resize_target := resize_target if is_instance_valid(resize_target) else base
	for module_id in matching_ids:
		var module_entry: Dictionary = _modules.get(module_id, {})
		if module_entry.is_empty():
			continue
		_serve_module(
			module_id,
			module_entry,
			normalized_path,
			metadata,
			base,
			effective_resize_target
		)
	return true

# Reports whether the currently enabled preview modules can render the supplied
# resource reference. This is used by Code Editor fallback logic before creating
# an add-on-owned popup when Godot itself did not provide a native help tooltip.
func supports_preview_path(path: String) -> bool:
	return not _get_path_preview_context(path).is_empty()

# Resolves a source resource reference to the filesystem path/type information
# required by the existing preview modules without loading the Resource itself.
func _get_path_preview_context(path: String) -> Dictionary:
	var normalized_path := _normalize_resource_path(path)
	if normalized_path.is_empty():
		return {}
	var resource_filesystem := EditorInterface.get_resource_filesystem()
	if resource_filesystem == null:
		return {}
	var resource_type := String(resource_filesystem.get_file_type(normalized_path))
	if resource_type.is_empty():
		return {}
	var matching_ids := _matching_module_ids(resource_type, normalized_path)
	if matching_ids.is_empty():
		return {}
	return {
		"path": normalized_path,
		"type": resource_type,
		"module_ids": matching_ids,
	}

# Returns all enabled preview modules whose existing _handles() implementation
# accepts the supplied EditorFileSystem resource type.
func _matching_module_ids(type: String, path: String = "") -> Array[String]:
	var result: Array[String] = []
	for module_id in _module_order:
		var module_entry: Dictionary = _modules.get(module_id, {})
		var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
		if plugin == null or not bool(plugin.call("_handles", type)):
			continue
		# Godot reports Markdown and ordinary text files with the same TextFile
		# resource type. Optional path-level filtering lets modules split that
		# type without duplicating previews, while existing modules remain unchanged.
		if (
			not path.is_empty()
			and plugin.has_method("handles_path")
			and not bool(plugin.call("handles_path", path, type))
		):
			continue
		result.append(module_id)
	return result

# Cache signatures and module loaders expect filesystem paths. Godot supports
# uid:// source references, so resolve those to their current res:// path
# before resource-type lookup and cache identity construction.
func _normalize_resource_path(path: String) -> String:
	if path.begins_with("uid://"):
		var resource_id := ResourceUID.text_to_id(path)
		if resource_id == ResourceUID.INVALID_ID or not ResourceUID.has_id(resource_id):
			return ""
		return ResourceUID.get_id_path(resource_id)
	return path if path.begins_with("res://") else ""

# Resolves one matching module through cache, remembered hard failure, existing
# job or a newly scheduled generation. Ordinary slow generations are never
# rejected merely because they took longer than a small responsiveness target.
func _serve_module(
	module_id: String,
	module_entry: Dictionary,
	path: String,
	metadata: Dictionary,
	base: Control,
	resize_target: Node
) -> void:
	var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
	if plugin == null:
		return
	# Text/Markdown previews stay as live Controls instead of entering the bitmap
	# cache. This is the single rendering path used by FileSystem, Code Editor and
	# navigation tooltips, and is what allows long documents to scroll naturally.
	if plugin.has_method("is_live_preview") and bool(plugin.call("is_live_preview")):
		# Older development builds stored text as PNGs. Remove that module/path entry lazily
		# the first time it is hovered after upgrading; live text never writes it back.
		if _cache != null:
			_cache.invalidate_preview(path, module_id)
		_append_live_preview(
			module_id,
			module_entry,
			path,
			metadata,
			base,
			resize_target
		)
		return
	if _cache == null:
		return
	# Shift + hover is a complete force-regenerate operation: successful RAM/disk
	# previews and remembered failures are discarded for this resource/module, and
	# the one forced generation attempt runs without the safety limit.
	var force_generation := Input.is_key_pressed(KEY_SHIFT)
	if force_generation:
		_cache.invalidate_preview(path, module_id)
	else:
		var cached_entry: Dictionary = _cache.get_preview(path, module_id)
		if not cached_entry.is_empty():
			_append_cached_preview(
				base,
				cached_entry,
				module_id,
				path,
				resize_target
			)
			_refresh_tooltip_layout(base, resize_target)
			Debug.log(String(module_entry.get("name", "Preview")), "cache hit: " + path)
			return
	var safety_limit_ms := 0 if force_generation else Settings.get_preview_safety_limit_ms()
	var failure_value: Dictionary = {}
	if not force_generation:
		failure_value = _cache.get_failure_entry(
			path,
			safety_limit_ms,
			module_id
		)
	if not failure_value.is_empty():
		_append_failure_status(base, failure_value)
		_refresh_tooltip_layout(base, resize_target)
		Debug.log(
			String(module_entry.get("name", "Preview")),
			"cache failure hit: %s (%s)" % [
				path,
				String(failure_value.get("status", "")),
			]
		)
		return

	# Keep Godot's built-in tooltip untouched while it is being created. The
	# generating section is attached only after the returned base Control is
	# actually visible; this avoids platform-dependent blank first tooltips.
	var waiter := {
		"base": weakref(base),
		"section": null,
		"resize_target": weakref(resize_target) if is_instance_valid(resize_target) else null,
	}
	var job_key := _cache.get_cache_key(path, module_id)
	if job_key.is_empty():
		var section := _create_status_section(base, "")
		_set_section_failure(section, TooltipCache.STATUS_FAILED, safety_limit_ms, 0)
		_refresh_tooltip_layout(base, resize_target)
		return
	if _jobs.has(job_key):
		var existing_job := _jobs[job_key] as Dictionary
		var waiters := existing_job.get("waiters", []) as Array
		waiters.append(waiter)
		existing_job["waiters"] = waiters
		_jobs[job_key] = existing_job
		return
	_jobs[job_key] = {
		"module_id": module_id,
		"path": path,
		"waiters": [waiter],
	}
	_start_generation.call_deferred(
		job_key,
		module_id,
		path,
		metadata.duplicate(true),
		safety_limit_ms,
		_generation_epoch
	)

# Starts the coroutine for one queued generation. This non-awaiting wrapper is
# used with call_deferred() so the FileSystem Dock callback can return its
# placeholder Control synchronously as required by Godot.
func _start_generation(
	job_key: String,
	module_id: String,
	path: String,
	metadata: Dictionary,
	safety_limit_ms: int,
	job_epoch: int
) -> void:
	_run_generation(
		job_key,
		module_id,
		path,
		metadata,
		safety_limit_ms,
		job_epoch
	)

# Executes one complete preview attempt only after Godot has attached and shown
# its own tooltip base. The add-on inserts the generating section only after this
# hand-off, avoiding platform-dependent blank popups during initial construction.
# Render capture explicitly requests draw work and then yields one process frame,
# so generation can progress even while the mouse remains stationary.
func _run_generation(
	job_key: String,
	module_id: String,
	path: String,
	metadata: Dictionary,
	safety_limit_ms: int,
	job_epoch: int
) -> void:
	var tooltip_visible := await _wait_until_job_tooltip_is_visible(job_key, job_epoch)
	if not tooltip_visible:
		if _jobs.has(job_key):
			_jobs.erase(job_key)
		return
	var module_entry: Dictionary = _modules.get(module_id, {})
	_ensure_job_status_sections(job_key, _generating_text(module_entry))
	# Give the already-visible tooltip one normal editor frame to draw the status
	# before resource or shader work can occupy the main/render thread.
	await EditorInterface.get_base_control().get_tree().process_frame
	if not _job_is_current(job_key, job_epoch):
		return
	var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
	if plugin == null:
		_finish_cancelled(job_key)
		return

	var generation_started_usec := Time.get_ticks_usec()
	metadata[Settings.PREVIEW_SCALE_METADATA_KEY] = (
		float(Settings.get_preview_size_percent()) / 100.0
	)
	var generated := VBoxContainer.new()
	generated.theme = EditorInterface.get_editor_theme()
	generated.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var result: Variant = plugin.call(
		"_make_tooltip_for_path",
		path,
		metadata,
		generated
	)
	_remove_generated_separators(generated)
	if result == null:
		generated.free()
		_finish_failure(
			job_key,
			module_id,
			path,
			safety_limit_ms,
			_elapsed_ms_int(generation_started_usec),
			job_epoch
		)
		return
	if generated.get_child_count() == 0:
		generated.free()
		_finish_no_preview(job_key)
		return
	if _safety_limit_exceeded(generation_started_usec, safety_limit_ms):
		generated.free()
		_finish_safety_limit(
			job_key,
			module_id,
			path,
			safety_limit_ms,
			_elapsed_ms_int(generation_started_usec),
			job_epoch
		)
		return
	var capture: Dictionary = await _render_and_capture(
		generated,
		generation_started_usec,
		safety_limit_ms,
		job_key,
		job_epoch
	)
	var capture_status := String(capture.get("status", STATUS_CANCELLED))
	match capture_status:
		STATUS_READY:
			if not _job_is_current(job_key, job_epoch):
				return
			if _cache.get_cache_key(path, module_id) != job_key:
				_finish_cancelled(job_key)
				return
			var texture := capture.get("texture", null) as Texture2D
			var image := capture.get("image", null) as Image
			var size_value: Variant = capture.get("size", Vector2i.ZERO)
			if texture == null or image == null or not (size_value is Vector2i):
				_finish_failure(
					job_key,
					module_id,
					path,
					safety_limit_ms,
					_elapsed_ms_int(generation_started_usec),
					job_epoch
				)
				return

			var stored_value: Dictionary = _cache.store_runtime_preview(
				path,
				image,
				texture,
				module_id
			)
			if not stored_value.is_empty():
				_finish_ready(job_key, stored_value)
				_persist_ready_preview.call_deferred(
					path,
					image,
					module_id,
					job_key,
					job_epoch
				)
				Debug.log(
					String(module_entry.get("name", "Preview")),
					"pipeline cached: " + path
				)
			else:
				_finish_failure(
					job_key,
					module_id,
					path,
					safety_limit_ms,
					_elapsed_ms_int(generation_started_usec),
					job_epoch
				)
		TooltipCache.STATUS_SAFETY_LIMIT:
			_finish_safety_limit(
				job_key,
				module_id,
				path,
				safety_limit_ms,
				_elapsed_ms_int(generation_started_usec),
				job_epoch
			)
		TooltipCache.STATUS_FAILED:
			_finish_failure(
				job_key,
				module_id,
				path,
				safety_limit_ms,
				_elapsed_ms_int(generation_started_usec),
				job_epoch
			)
		_:
			_finish_cancelled(job_key)

# Renders a module-created Control tree in a temporary SubViewport and converts
# the final pixels to an ImageTexture. Each capture pass explicitly requests a
# draw and then yields one editor process frame. This avoids depending on mouse
# movement or unrelated editor redraws while still allowing nested SubViewports
# and shader/pipeline work to settle before readback.
func _render_and_capture(
	content: Control,
	generation_started_usec: int,
	safety_limit_ms: int,
	job_key: String,
	job_epoch: int
) -> Dictionary:
	if not is_instance_valid(_render_host):
		content.free()
		return {"status": TooltipCache.STATUS_FAILED}
	content.theme = EditorInterface.get_editor_theme()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2, 2)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_render_host.add_child(viewport)
	content.position = Vector2.ZERO
	viewport.add_child(content)

	# MarginContainer theme constants and several editor-theme minimum sizes are
	# not reflected by get_combined_minimum_size() while the generated root is
	# still outside the SceneTree. Measuring there cropped right/bottom margins:
	# left/top offsets were applied after insertion, but the capture viewport had
	# already been sized without the matching trailing margins. Give the root one
	# layout frame in-tree before deciding the final capture size.
	var tree := EditorInterface.get_base_control().get_tree()
	await tree.process_frame
	if not _job_is_current(job_key, job_epoch):
		viewport.queue_free()
		return {"status": STATUS_CANCELLED}
	content.reset_size()
	var minimum_size := content.get_combined_minimum_size()
	if minimum_size.x <= 0.0 or minimum_size.y <= 0.0:
		viewport.queue_free()
		return {"status": TooltipCache.STATUS_FAILED}
	var size := Vector2i(
		maxi(2, ceili(minimum_size.x)),
		maxi(2, ceili(minimum_size.y))
	)
	viewport.size = size
	content.position = Vector2.ZERO
	content.size = Vector2(size.x, size.y)
	for frame_index in range(CAPTURE_RENDER_FRAMES):
		RenderingServer.force_draw(false)
		await tree.process_frame
		if not _job_is_current(job_key, job_epoch):
			viewport.queue_free()
			return {"status": STATUS_CANCELLED}
		var more_render_work_remains := frame_index < CAPTURE_RENDER_FRAMES - 1
		if (
			more_render_work_remains
			and _safety_limit_exceeded(generation_started_usec, safety_limit_ms)
		):
			viewport.queue_free()
			return {"status": TooltipCache.STATUS_SAFETY_LIMIT}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"status": TooltipCache.STATUS_FAILED}
	var texture := ImageTexture.create_from_image(image)
	viewport.queue_free()
	if texture == null:
		return {"status": TooltipCache.STATUS_FAILED}
	return {
		"status": STATUS_READY,
		"texture": texture,
		"image": image,
		"size": size,
	}

# Writes a successful preview to disk after the visible tooltip was already
# updated. The generation epoch prevents Clear Tooltip Caches from being undone
# by a deferred write that had been queued immediately before the clear action.
func _persist_ready_preview(
	path: String,
	image: Image,
	module_id: String,
	expected_key: String,
	job_epoch: int
) -> void:
	if job_epoch != _generation_epoch or _cache == null:
		return
	_cache.persist_preview(
		path,
		image,
		module_id,
		expected_key
	)

# Finishes a successful job by replacing every still-visible generating section
# with the cached static preview texture.
func _finish_ready(job_key: String, entry: Dictionary) -> void:
	_ensure_job_status_sections(job_key, "")
	var job_value: Variant = _jobs.get(job_key, null)
	if not (job_value is Dictionary):
		return
	var job: Dictionary = job_value as Dictionary
	var module_id := String(job.get("module_id", ""))
	var path := String(job.get("path", ""))
	var waiters: Array = job.get("waiters", []) as Array
	for waiter_value: Variant in waiters:
		if not (waiter_value is Dictionary):
			continue
		var waiter: Dictionary = waiter_value as Dictionary
		var section_ref: Variant = waiter.get("section", null)
		if not (section_ref is WeakRef):
			continue
		var section := (section_ref as WeakRef).get_ref() as VBoxContainer
		if not is_instance_valid(section):
			continue
		var base_ref: Variant = waiter.get("base", null)
		var base: Control = null
		if base_ref is WeakRef:
			base = (base_ref as WeakRef).get_ref() as Control
		_set_section_preview(section, entry)
		_register_preview_session(
			section,
			base,
			_get_waiter_resize_target(waiter),
			module_id,
			path,
			entry
		)
	_refresh_job_layout(job_key)
	_jobs.erase(job_key)

# Records a generation stopped by the generous safety limit. Unlike the previous
# short timeout, ordinary slow previews never enter this state merely because
# they exceeded a responsiveness target.
func _finish_safety_limit(
	job_key: String,
	module_id: String,
	path: String,
	safety_limit_ms: int,
	elapsed_ms: int,
	job_epoch: int
) -> void:
	if _job_is_current(job_key, job_epoch):
		_ensure_job_status_sections(job_key, "")
		_cache.store_failure(
			path,
			TooltipCache.STATUS_SAFETY_LIMIT,
			safety_limit_ms,
			elapsed_ms,
			module_id
		)
		for section in _live_job_sections(job_key):
			_set_section_failure(
				section,
				TooltipCache.STATUS_SAFETY_LIMIT,
				safety_limit_ms,
				elapsed_ms
			)
		_refresh_job_layout(job_key)
	_jobs.erase(job_key)

# Records a real pipeline failure, such as an invalid render capture, and shows
# a distinct message so it cannot be confused with a safety-limit stop.
func _finish_failure(
	job_key: String,
	module_id: String,
	path: String,
	safety_limit_ms: int,
	elapsed_ms: int,
	job_epoch: int
) -> void:
	if _job_is_current(job_key, job_epoch):
		_ensure_job_status_sections(job_key, "")
		_cache.store_failure(
			path,
			TooltipCache.STATUS_FAILED,
			safety_limit_ms,
			elapsed_ms,
			module_id
		)
		for section in _live_job_sections(job_key):
			_set_section_failure(
				section,
				TooltipCache.STATUS_FAILED,
				safety_limit_ms,
				elapsed_ms
			)
		_refresh_job_layout(job_key)
	_jobs.erase(job_key)

# Removes the transient status entirely when a module intentionally produces no
# preview for a handled resource subtype, preserving the previous behavior for
# unsupported shader/material variants.
func _finish_no_preview(job_key: String) -> void:
	for section in _live_job_sections(job_key):
		section.queue_free()
	_refresh_job_layout(job_key)
	_jobs.erase(job_key)

# Removes visible transient sections for work invalidated by cache clearing,
# module changes or resource changes and forgets the corresponding job.
func _finish_cancelled(job_key: String) -> void:
	for section in _live_job_sections(job_key):
		section.queue_free()
	_refresh_job_layout(job_key)
	_jobs.erase(job_key)

# Inserts a text/Markdown module directly into the visible tooltip without
# capture or caching. The section structure and typography are therefore exactly
# the same regardless of whether the path came from FileSystem, Code Editor,
# Quill or Script-IDE. Live text sections never register wheel-zoom sessions.
func _append_live_preview(
	module_id: String,
	module_entry: Dictionary,
	path: String,
	metadata: Dictionary,
	base: Control,
	resize_target: Node
) -> void:
	if not is_instance_valid(base):
		return
	for child: Node in base.get_children():
		if (
			child is Control
			and child.has_meta("_bt_live_module")
			and str(child.get_meta("_bt_live_module")) == module_id
			and str(child.get_meta("_bt_live_path")) == path
		):
			return
	var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
	if plugin == null:
		return
	var section := _create_section(base)
	section.set_meta("_bt_live_module", module_id)
	section.set_meta("_bt_live_path", path)
	var background_panel := section.get_node_or_null("Background") as PanelContainer
	var body := section.get_node_or_null("Background/Body") as VBoxContainer
	if background_panel == null or body == null:
		section.queue_free()
		return
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	background_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var live_metadata := metadata.duplicate(true)
	live_metadata["source"] = str(live_metadata.get("source", "live_text"))
	var result: Variant = plugin.call(
		"_make_tooltip_for_path",
		path,
		live_metadata,
		body
	)
	_remove_generated_separators(body)
	if result == null or body.get_child_count() == 0:
		section.queue_free()
		return
	_refresh_tooltip_layout(base, resize_target)
	_finalize_live_text_section.call_deferred(
		weakref(section),
		weakref(base),
		weakref(resize_target) if is_instance_valid(resize_target) else null,
		module_id,
		path,
		live_metadata
	)
	Debug.log(String(module_entry.get("name", "Text Preview")), "live preview: " + path)

# Once the live RichTextLabel has entered the actual editor tree, Godot can
# measure its content height. Short files keep natural height; tall files receive
# the same bounded scroll behavior in every tooltip host.
func _finalize_live_text_section(
	section_ref: WeakRef,
	base_ref: WeakRef,
	resize_target_ref: WeakRef,
	module_id: String,
	path: String,
	metadata: Dictionary
) -> void:
	var section := section_ref.get_ref() as Control if section_ref != null else null
	var base := base_ref.get_ref() as Control if base_ref != null else null
	var resize_target := (
		resize_target_ref.get_ref() as Node
		if resize_target_ref != null else null
	)
	if not is_instance_valid(section):
		return
	# FileSystemDock asks for the tooltip Control before attaching it to the popup.
	# Wait briefly for that hand-off so RichTextLabel can report its real content
	# height; Code/IDE hosts usually enter the tree immediately and exit this loop.
	var editor_tree := EditorInterface.get_base_control().get_tree()
	for _frame: int in range(30):
		if not is_instance_valid(section):
			return
		if section.is_inside_tree():
			break
		await editor_tree.process_frame
	if not is_instance_valid(section) or not section.is_inside_tree():
		return
	await editor_tree.process_frame
	if not is_instance_valid(section):
		return
	for candidate: Node in section.find_children("*", "RichTextLabel", true, false):
		var label := candidate as RichTextLabel
		if label != null:
			TooltipAppearance.limit_rich_text_height(label)
	# The shared limiter may schedule one more layout pass. Apply the stricter
	# two-region budget afterward so it cannot be overwritten by that callback.
	if section.is_inside_tree():
		await editor_tree.process_frame
	if not is_instance_valid(section):
		return
	_limit_combined_script_preview_height(section)
	_refresh_tooltip_layout(base, resize_target)
	if section.is_inside_tree():
		await editor_tree.process_frame
	_promote_live_text_tooltip(
		module_id,
		path,
		metadata,
		section,
		base,
		resize_target
	)

# A script can have both a large class description and a long source file.
# The generic per-label limits are appropriate alone, but their sum could still
# extend past the monitor. Bound both regions independently so neither becomes
# inaccessible and each retains its own scrollbar when needed.
func _limit_combined_script_preview_height(section: Control) -> void:
	var documentation := section.find_child("ScriptDocumentation", true, false) as RichTextLabel
	var source := section.find_child("TextPreview", true, false) as RichTextLabel
	if documentation == null or source == null:
		return
	var screen := DisplayServer.get_primary_screen()
	var editor_window := EditorInterface.get_base_control().get_window()
	if editor_window != null and editor_window.current_screen >= 0:
		screen = editor_window.current_screen
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.y <= 0:
		return
	var scale := EditorInterface.get_editor_scale()
	# Leave room for Godot's native file header, separators and outer margins.
	_set_script_region_height(documentation, minf(usable.size.y * 0.22, 230.0 * scale))
	_set_script_region_height(source, minf(usable.size.y * 0.43, 460.0 * scale))

func _set_script_region_height(label: RichTextLabel, ceiling: float) -> void:
	if label.get_content_height() <= 0.0:
		return
	if label.get_content_height() <= ceiling:
		label.fit_content = true
		label.scroll_active = false
		label.custom_minimum_size.y = 0.0
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		label.fit_content = false
		label.scroll_active = true
		label.custom_minimum_size.y = ceiling
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.update_minimum_size()

# Converts a live Text/Markdown tooltip into an add-on-owned PopupPanel once its
# final RichTextLabel height is known. Native Godot tooltips intentionally vanish
# as soon as their source item loses hover, which makes their scrollbars
# unreachable. Adopting the already-built popup contents keeps the exact same
# renderer/layout while allowing the pointer to move from the source item into the
# tooltip itself. Graphical previews are never routed through this path.
func _promote_live_text_tooltip(
	module_id: String,
	path: String,
	metadata: Dictionary,
	section: Control,
	base: Control,
	requested_target: Node
) -> void:
	if not is_instance_valid(section) or not is_instance_valid(base):
		return
	var target := _resolve_tooltip_resize_target(base, requested_target)
	var original_popup := target as PopupPanel
	if (
		original_popup == null
		or original_popup.name == LIVE_TEXT_POPUP_NAME
		or original_popup.theme_type_variation != LIVE_TEXT_TOOLTIP_PANEL_VARIATION
	):
		return
	var popup_root := _find_popup_root_for_control(original_popup, base)
	if popup_root == null:
		return
	var trigger_control := _metadata_trigger_control(metadata)
	if trigger_control == null:
		trigger_control = original_popup.get_parent() as Control
	var pointer_position := DisplayServer.mouse_get_position()
	var trigger_rect := _capture_trigger_rect(trigger_control, pointer_position)
	if trigger_rect.size.x <= 0 or trigger_rect.size.y <= 0:
		trigger_rect = Rect2i(pointer_position - Vector2i(6, 6), Vector2i(12, 12))
	_close_live_text_session()
	var popup := PopupPanel.new()
	popup.name = LIVE_TEXT_POPUP_NAME
	popup.theme_type_variation = original_popup.theme_type_variation
	popup.wrap_controls = true
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	popup.mouse_passthrough = false
	if original_popup.theme != null:
		popup.theme = original_popup.theme
	var popup_parent := EditorInterface.get_base_control()
	if popup_parent == null:
		return
	popup_parent.add_child(popup)
	var original_position := original_popup.position
	var original_size := original_popup.size
	popup_root.reparent(popup)
	original_popup.hide()
	popup.position = original_position
	if original_size.x > 0 and original_size.y > 0:
		popup.size = original_size
	popup.popup()
	popup.reset_size()
	_position_live_text_popup(popup, pointer_position)
	_live_text_session_sequence += 1
	var sequence := _live_text_session_sequence
	_live_text_session = {
		"sequence": sequence,
		"module_id": module_id,
		"path": path,
		"popup": weakref(popup),
		"root": weakref(popup_root),
		"trigger_control": weakref(trigger_control) if is_instance_valid(trigger_control) else null,
		"trigger_rect": trigger_rect,
		"last_inside_msec": Time.get_ticks_msec(),
		"pointer_drag_active": false,
	}
	var input_callback := Callable(self, "_on_live_text_popup_window_input").bind(sequence)
	popup.window_input.connect(input_callback)
	_live_text_session["input_callback"] = input_callback
	if is_instance_valid(_live_text_monitor):
		_live_text_monitor.start(LIVE_TEXT_MONITOR_INTERVAL_SECONDS)
	# Reparenting the finished tooltip contents can change the PopupPanel minimum
	# size only after one layout pass. Schedule a second size/placement pass instead
	# of awaiting here: this keeps the pipeline safe if the add-on is disabled while
	# a tooltip is visible and avoids resuming a coroutine on a freed plugin object.
	var reposition_callback := Callable(
		self,
		"_reposition_live_text_popup_after_layout"
	).bind(sequence, pointer_position)
	popup.get_tree().process_frame.connect(reposition_callback, CONNECT_ONE_SHOT)

func _reposition_live_text_popup_after_layout(
	sequence: int,
	pointer_position: Vector2i
) -> void:
	if int(_live_text_session.get("sequence", 0)) != sequence:
		return
	var popup := _get_live_text_popup()
	if popup == null:
		return
	popup.reset_size()
	_position_live_text_popup(popup, pointer_position)

# Returns the direct PopupPanel child that owns the supplied tooltip base. Moving
# this root preserves native path/help headers and every add-on section instead of
# rebuilding a second, visually different text tooltip.
func _find_popup_root_for_control(popup: PopupPanel, control: Control) -> Control:
	if popup == null or not is_instance_valid(control):
		return null
	var current: Control = control
	while is_instance_valid(current) and current.get_parent() != popup:
		current = current.get_parent() as Control
	return current if is_instance_valid(current) and current.get_parent() == popup else null

func _metadata_trigger_control(metadata: Dictionary) -> Control:
	var value: Variant = metadata.get("trigger_control", null)
	if value is Control and is_instance_valid(value):
		return value as Control
	if value is WeakRef:
		var control := (value as WeakRef).get_ref() as Control
		if is_instance_valid(control):
			return control
	return null

# Captures the actual hovered row/tab whenever the source control exposes that
# geometry. Falling back to a small pointer hot spot is preferable to treating an
# entire CodeEdit/Tree as the trigger, because moving to another item should close
# the old text preview rather than keeping it alive indefinitely.
func _capture_trigger_rect(control: Control, pointer_position: Vector2i) -> Rect2i:
	if not is_instance_valid(control):
		return Rect2i()
	var local_mouse := control.get_local_mouse_position()
	var local_rect := Rect2()
	if control is Tree:
		var tree := control as Tree
		var item := tree.get_item_at_position(local_mouse)
		if item != null:
			var column := tree.get_column_at_position(local_mouse)
			if column < 0:
				column = 0
			local_rect = tree.get_item_area_rect(item, column)
	elif control is ItemList:
		var item_list := control as ItemList
		var index := item_list.get_item_at_position(local_mouse, true)
		if index >= 0:
			local_rect = item_list.get_item_rect(index)
	elif control is TabBar:
		var tab_bar := control as TabBar
		var tab_index := tab_bar.get_tab_idx_at_point(local_mouse)
		if tab_index >= 0:
			local_rect = tab_bar.get_tab_rect(tab_index)
	elif control is Button:
		local_rect = Rect2(Vector2.ZERO, control.size)
	if local_rect.size.x > 0.0 and local_rect.size.y > 0.0:
		return Rect2i(
			Vector2i(control.get_screen_position() + local_rect.position),
			Vector2i(local_rect.size)
		)
	return Rect2i(pointer_position - Vector2i(8, 8), Vector2i(16, 16))

# Positions the interactive text popup from the final size, not from the tiny
# native tooltip size Godot knew before the live text was appended. The cursor is
# the placement anchor, matching Godot's ordinary tooltip behaviour more closely;
# using the full Tree/Tab item rectangle here can otherwise leave a conspicuously
# large horizontal gap when the pointer is near the item's left side.
func _position_live_text_popup(
	popup: PopupPanel,
	pointer_position: Vector2i
) -> void:
	if popup == null:
		return
	var popup_size := popup.size
	if popup_size.x <= 0 or popup_size.y <= 0:
		return
	var screen := popup.current_screen
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var scale := EditorInterface.get_editor_scale()
	var gap := roundi(LIVE_TEXT_POPUP_GAP * scale)
	var margin := roundi(LIVE_TEXT_SCREEN_MARGIN * scale)
	# Prefer the same small cursor-relative offset as an ordinary tooltip. If that
	# side does not fit, flip across the cursor before falling back to clamping.
	var right_x := pointer_position.x + gap
	var left_x := pointer_position.x - popup_size.x - gap
	var x := right_x
	if right_x + popup_size.x > usable.end.x - margin:
		x = left_x
	if x < usable.position.x + margin:
		x = clampi(
			right_x,
			usable.position.x + margin,
			maxi(usable.position.x + margin, usable.end.x - popup_size.x - margin)
		)
	var below_y := pointer_position.y + gap
	var above_y := pointer_position.y - popup_size.y - gap
	var y := below_y
	if below_y + popup_size.y > usable.end.y - margin:
		y = above_y
	if y < usable.position.y + margin:
		# Very tall previews may fit neither wholly above nor below the pointer. Keep
		# them inside the usable screen; horizontal placement still leaves the cursor
		# outside the popup whenever the screen width permits it.
		y = clampi(
			pointer_position.y - popup_size.y / 2,
			usable.position.y + margin,
			maxi(usable.position.y + margin, usable.end.y - popup_size.y - margin)
		)
	popup.position = Vector2i(x, y)
# Keeps an interactive text tooltip alive while the pointer is over either the
# original source item or the popup. A short gap grace lets the pointer cross the
# few pixels between both rectangles without the tooltip disappearing mid-flight.
# A left-button drag that started inside the popup temporarily suspends closing,
# so overshooting a scrollbar thumb does not destroy the tooltip mid-drag.
func _on_live_text_monitor_timeout() -> void:
	if _live_text_session.is_empty():
		if is_instance_valid(_live_text_monitor):
			_live_text_monitor.stop()
		return
	var popup := _get_live_text_popup()
	if popup == null or not popup.visible:
		_close_live_text_session()
		return
	var now := Time.get_ticks_msec()
	if bool(_live_text_session.get("pointer_drag_active", false)):
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			# Keep refreshing the grace origin for the complete drag, even when the
			# cursor temporarily leaves both the tooltip and its source item.
			_live_text_session["last_inside_msec"] = now
			return
		# A release outside the popup may not be delivered to this subwindow. The
		# global button state therefore also terminates the drag reliably. Start the
		# normal exit grace only after the drag has actually ended.
		_live_text_session["pointer_drag_active"] = false
		_live_text_session["last_inside_msec"] = now
	var pointer := DisplayServer.mouse_get_position()
	var popup_rect := Rect2i(popup.position, popup.size).grow(2)
	var trigger_value: Variant = _live_text_session.get("trigger_rect", Rect2i())
	var trigger_rect := trigger_value as Rect2i if trigger_value is Rect2i else Rect2i()
	var inside := popup_rect.has_point(pointer) or trigger_rect.grow(2).has_point(pointer)
	if inside:
		_live_text_session["last_inside_msec"] = now
		return
	var last_inside := int(_live_text_session.get("last_inside_msec", now))
	if float(now - last_inside) / 1000.0 >= LIVE_TEXT_EXIT_GRACE_SECONDS:
		_close_live_text_session()

# Scrolls the live RichTextLabel inside the popup directly and marks wheel events
# handled so they never leak through to the FileSystem/CodeEdit control behind the
# tooltip. Left-button state is observed separately to keep scrollbar drags alive
# if the pointer overshoots the popup while the thumb is being dragged.
func _on_live_text_popup_window_input(event: InputEvent, sequence: int) -> void:
	if int(_live_text_session.get("sequence", 0)) != sequence:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var popup := _get_live_text_popup()
		if popup == null:
			return
		# Keep actual tooltip commands inside the popup: scrolling and copying
		# selected text should not close a long document.
		var root := _get_live_text_root()
		var label := _find_scrollable_rich_text(root) if root != null else null
		if label != null and key_event.keycode in [KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END] and not key_event.ctrl_pressed and not key_event.alt_pressed:
			var bar := label.get_v_scroll_bar()
			if bar != null:
				var delta := bar.page * 0.85 if key_event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] else 40.0 * EditorInterface.get_editor_scale()
				if key_event.keycode == KEY_HOME:
					bar.value = bar.min_value
				elif key_event.keycode == KEY_END:
					bar.value = bar.max_value - bar.page
				else:
					bar.value += delta * (-1.0 if key_event.keycode in [KEY_UP, KEY_PAGEUP] else 1.0)
				popup.set_input_as_handled()
				return
		if key_event.keycode == KEY_C and key_event.ctrl_pressed:
			var selected := _find_selected_rich_text(root)
			if selected != null:
				DisplayServer.clipboard_set(selected.get_selected_text())
				popup.set_input_as_handled()
				return
		popup.set_input_as_handled()
		_close_live_text_session()
		# Return the key to the main editor Viewport after the popup is gone.
		# In particular, F-keys and keyboard shortcuts must not be swallowed.
		if key_event.keycode != KEY_ESCAPE:
			call_deferred("_forward_closed_tooltip_key", key_event.duplicate())
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if mouse_event.pressed:
			_live_text_session["pointer_drag_active"] = true
			_live_text_session["last_inside_msec"] = Time.get_ticks_msec()
		elif bool(_live_text_session.get("pointer_drag_active", false)):
			_live_text_session["pointer_drag_active"] = false
			_live_text_session["last_inside_msec"] = Time.get_ticks_msec()
		return
	if not mouse_event.pressed or mouse_event.button_index not in [
		MOUSE_BUTTON_WHEEL_UP,
		MOUSE_BUTTON_WHEEL_DOWN,
	]:
		return
	var popup := _get_live_text_popup()
	if popup == null:
		return
	# Consume wheel input for the text popup even when the current document is too
	# short to scroll, and also when an already-scrollable document is at either
	# limit. The FileSystem/CodeEdit control underneath must never receive it.
	popup.set_input_as_handled()
	var root := _get_live_text_root()
	if root == null:
		return
	var label := _find_scrollable_rich_text(root)
	if label == null:
		return
	var scroll_bar := label.get_v_scroll_bar()
	if scroll_bar == null:
		return
	var direction := -1.0 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	var steps := maxf(1.0, absf(mouse_event.factor))
	var amount := maxf(36.0 * EditorInterface.get_editor_scale(), scroll_bar.page * 0.09)
	scroll_bar.value = clampf(
		scroll_bar.value + direction * amount * steps,
		scroll_bar.min_value,
		maxf(scroll_bar.min_value, scroll_bar.max_value - scroll_bar.page)
	)


# Re-inject once after closing the separate tooltip Window. The live popup is
# destroyed first, so the event cannot be handled by it a second time.
func _forward_closed_tooltip_key(event: InputEventKey) -> void:
	var editor := EditorInterface.get_base_control()
	if editor != null and editor.is_inside_tree():
		editor.get_viewport().push_input(event, true)

func _find_selected_rich_text(root: Node) -> RichTextLabel:
	if root == null:
		return null
	for candidate: Node in root.find_children("*", "RichTextLabel", true, false):
		var label := candidate as RichTextLabel
		if label != null and label.has_selection():
			return label
	return null

func _find_scrollable_rich_text(root: Node) -> RichTextLabel:
	if root == null:
		return null
	# When a script shows both class documentation and its source, wheel and
	# navigation keys should scroll the section actually under the pointer.
	var pointer := Vector2(DisplayServer.mouse_get_position())
	for candidate: Node in root.find_children("*", "RichTextLabel", true, false):
		var hovered := candidate as RichTextLabel
		if ( hovered != null ):
			var screen_rect := Rect2(hovered.get_screen_transform().origin,hovered.size)
			if (
				hovered.scroll_active
				and not hovered.fit_content
				and screen_rect.has_point(pointer)
			):
				return hovered
	if root is RichTextLabel:
		var direct := root as RichTextLabel
		if direct.scroll_active and not direct.fit_content:
			return direct
	# A code/documentation tooltip may contain more than one RichTextLabel. Prefer
	# the file-preview label explicitly so wheel input never scrolls an unrelated
	# documentation block above it.
	for preview_name: StringName in [&"MarkdownPreview", &"TextPreview"]:
		var named := root.find_child(String(preview_name), true, false) as RichTextLabel
		if named != null and named.scroll_active and not named.fit_content:
			return named
	for candidate: Node in root.find_children("*", "RichTextLabel", true, false):
		var label := candidate as RichTextLabel
		if label != null and label.scroll_active and not label.fit_content:
			return label
	return null

func _get_live_text_popup() -> PopupPanel:
	var popup_ref: Variant = _live_text_session.get("popup", null)
	if popup_ref is WeakRef:
		var popup := (popup_ref as WeakRef).get_ref() as PopupPanel
		if is_instance_valid(popup):
			return popup
	return null

func _get_live_text_root() -> Control:
	var root_ref: Variant = _live_text_session.get("root", null)
	if root_ref is WeakRef:
		var root := (root_ref as WeakRef).get_ref() as Control
		if is_instance_valid(root):
			return root
	return null

func _close_live_text_session() -> void:
	if _live_text_session.is_empty():
		if is_instance_valid(_live_text_monitor):
			_live_text_monitor.stop()
		return
	var popup := _get_live_text_popup()
	var callback_value: Variant = _live_text_session.get("input_callback", null)
	if popup != null:
		if callback_value is Callable and popup.window_input.is_connected(callback_value as Callable):
			popup.window_input.disconnect(callback_value as Callable)
		popup.hide()
		popup.queue_free()
	_live_text_session.clear()
	if is_instance_valid(_live_text_monitor):
		_live_text_monitor.stop()

# Adds one cached static texture below Godot's built-in tooltip content and
# registers it as a wheel-zoom session for as long as this tooltip stays visible.
func _append_cached_preview(
	base: Control,
	entry: Dictionary,
	module_id: String,
	path: String,
	resize_target: Node
) -> void:
	var section := _create_section(base)
	_set_section_preview(section, entry)
	_register_preview_session(
		section,
		base,
		resize_target,
		module_id,
		path,
		entry
	)

# Adds an immediate remembered failure explanation. Ordinary slow previews are
# successful cache entries, so this is reserved for true failures or safety stops.
func _append_failure_status(base: Control, entry: Dictionary) -> void:
	var section := _create_status_section(base, "")
	_set_section_failure(
		section,
		String(entry.get("status", TooltipCache.STATUS_FAILED)),
		int(entry.get(
			"safety_limit_ms",
			Settings.get_preview_safety_limit_ms()
		)),
		int(entry.get("elapsed_ms", 0))
	)

# Creates one self-contained preview section including its separator. Keeping
# the separator inside the section allows an unsupported/cancelled preview to
# disappear cleanly without leaving an empty line in the normal tooltip.
func _create_section(base: Control) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(HSeparator.new())
	var background_panel := PanelContainer.new()
	background_panel.name = "Background"
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TooltipAppearance.style_graphical_preview_panel(background_panel)
	section.add_child(background_panel)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_panel.add_child(body)
	base.add_child(section)
	return section

# Creates a text status section used while generating and for remembered
# SAFETY_LIMIT / FAILED results.
func _create_status_section(base: Control, message: String) -> VBoxContainer:
	var section := _create_section(base)
	_set_section_text(section, message)
	return section

# Replaces the section body with one static cached preview texture.
func _set_section_preview(section: VBoxContainer, entry: Dictionary) -> void:
	if not is_instance_valid(section):
		return
	var texture := entry.get("texture", null) as Texture2D
	var size_value: Variant = entry.get("size", Vector2i.ZERO)
	if texture == null or not (size_value is Vector2i):
		_set_section_text(section, "Preview could not be displayed.")
		return
	var background_panel := section.get_node_or_null("Background") as PanelContainer
	var body := section.get_node_or_null("Background/Body") as VBoxContainer
	if background_panel == null or body == null:
		return
	# Keep the separator aligned to the full tooltip width, but center the actual
	# dark preview panel at its own natural width. This makes Code Editor and
	# FileSystem graphic previews visually match even when the text/header above
	# is much wider than the preview itself.
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	background_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_free_children(body)
	var size := size_value as Vector2i
	var frame := MarginContainer.new()
	frame.name = PREVIEW_FRAME_NAME
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame_padding := roundi(
		TooltipAppearance.GRAPHICAL_PREVIEW_PADDING * EditorInterface.get_editor_scale()
	)
	for side: String in ["left", "top", "right", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, frame_padding)
	body.add_child(frame)
	var rect := TextureRect.new()
	rect.name = PREVIEW_TEXTURE_NAME
	rect.custom_minimum_size = Vector2(size.x, size.y)
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Native Code Editor tooltips can be much wider than the cached preview.
	# Keep the rendered preview at its own aspect ratio instead of stretching it
	# to the width assigned by the surrounding VBoxContainer.
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(rect)
	section.reset_size()

# Registers one displayed graphical preview as a short-lived hover session. The
# session keeps the cached/default texture only as its reset point; temporary
# wheel renders are deliberately retained only by the currently visible tooltip.
func _register_preview_session(
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
	var session_id := _find_latest_visible_preview_session()
	if session_id == 0:
		return false
	return _handle_input_for_session(event, session_id)

# Handles one wheel event for an explicitly selected visible preview session.
# This common path is used both by the main editor viewport and by tooltip popup
# windows, which own a separate Viewport and therefore do not forward their
# input through EditorPlugin._input().
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
	var target := _resolve_tooltip_resize_target(base, requested_target)
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
		var target := _resolve_tooltip_resize_target(base, requested_target)
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
			_set_section_preview(section, default_entry)
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
		_set_section_preview(section, scaled_entry)
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
	var module_entry: Dictionary = _modules.get(module_id, {})
	var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
	if plugin == null or path.is_empty():
		return
	var requested_percent := int(session.get(
		"requested_percent",
		Settings.get_preview_size_percent()
	))
	var metadata := {
		Settings.PREVIEW_SCALE_METADATA_KEY: float(requested_percent) / 100.0,
		"source": "transient_wheel_zoom",
	}
	var generation_started_usec := Time.get_ticks_usec()
	var safety_limit_ms := (
		0
		if Input.is_key_pressed(KEY_SHIFT)
		else Settings.get_preview_safety_limit_ms()
	)
	var generated := VBoxContainer.new()
	generated.theme = EditorInterface.get_editor_theme()
	generated.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var result: Variant = plugin.call(
		"_make_tooltip_for_path",
		path,
		metadata,
		generated
	)
	_remove_generated_separators(generated)
	if result == null or generated.get_child_count() == 0:
		generated.free()
		return
	if _safety_limit_exceeded(generation_started_usec, safety_limit_ms):
		generated.free()
		return
	var capture: Dictionary = await _render_and_capture_transient(
		generated,
		generation_started_usec,
		safety_limit_ms,
		session_id,
		request_serial
	)
	if String(capture.get("status", STATUS_CANCELLED)) != STATUS_READY:
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
	_set_section_preview(section, entry)
	session["display_entry"] = entry
	session["rendered_percent"] = requested_percent
	_preview_sessions[session_id] = session
	_refresh_preview_session_layout(session)
	Debug.log(
		String(module_entry.get("name", "Preview")),
		"transient wheel render %d%%: %s" % [requested_percent, path]
	)

# Capture variant for temporary wheel renders. It has the same draw settling as
# normal generation but is keyed to the hover request serial rather than a cache job.
func _render_and_capture_transient(
	content: Control,
	generation_started_usec: int,
	safety_limit_ms: int,
	session_id: int,
	request_serial: int
) -> Dictionary:
	if not is_instance_valid(_render_host):
		content.free()
		return {"status": TooltipCache.STATUS_FAILED}
	content.theme = EditorInterface.get_editor_theme()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2, 2)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_render_host.add_child(viewport)
	content.position = Vector2.ZERO
	viewport.add_child(content)
	var tree := EditorInterface.get_base_control().get_tree()
	await tree.process_frame
	if not _transient_request_is_current(session_id, request_serial):
		viewport.queue_free()
		return {"status": STATUS_CANCELLED}
	content.reset_size()
	var minimum_size := content.get_combined_minimum_size()
	if minimum_size.x <= 0.0 or minimum_size.y <= 0.0:
		viewport.queue_free()
		return {"status": TooltipCache.STATUS_FAILED}
	var size := Vector2i(
		maxi(2, ceili(minimum_size.x)),
		maxi(2, ceili(minimum_size.y))
	)
	viewport.size = size
	content.position = Vector2.ZERO
	content.size = Vector2(size.x, size.y)
	for frame_index in range(CAPTURE_RENDER_FRAMES):
		RenderingServer.force_draw(false)
		await tree.process_frame
		if not _transient_request_is_current(session_id, request_serial):
			viewport.queue_free()
			return {"status": STATUS_CANCELLED}
		if (
			frame_index < CAPTURE_RENDER_FRAMES - 1
			and _safety_limit_exceeded(generation_started_usec, safety_limit_ms)
		):
			viewport.queue_free()
			return {"status": TooltipCache.STATUS_SAFETY_LIMIT}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"status": TooltipCache.STATUS_FAILED}
	var texture := ImageTexture.create_from_image(image)
	viewport.queue_free()
	if texture == null:
		return {"status": TooltipCache.STATUS_FAILED}
	return {
		"status": STATUS_READY,
		"texture": texture,
		"image": image,
		"size": size,
	}

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
	if module_id.is_empty() or not _modules.has(module_id):
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
func _remove_preview_sessions_for_module(module_id: String) -> void:
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
	_set_section_preview(section, limited_entry)
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
	var target := _resolve_tooltip_resize_target(base, requested_target)
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
	var target := _resolve_tooltip_resize_target(base, requested_target)
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
	_refresh_tooltip_layout(base, resize_target)

# Replaces the section body with a readable pipeline-status message.
func _set_section_text(section: VBoxContainer, message: String) -> void:
	if not is_instance_valid(section):
		return
	var body := section.get_node_or_null("Background/Body") as VBoxContainer
	if body == null:
		return
	_free_children(body)
	var label := Label.new()
	var scale := EditorInterface.get_editor_scale()
	label.custom_minimum_size = Vector2(STATUS_WIDTH * scale, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = message
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(label)
	section.reset_size()

# Replaces the section body with a failure/safety explanation. The safety-limit
# message is intentionally distinct from an ordinary slow-but-successful preview.
func _set_section_failure(
	section: VBoxContainer,
	status: String,
	safety_limit_ms: int,
	elapsed_ms: int
) -> void:
	if status == TooltipCache.STATUS_SAFETY_LIMIT:
		var measured := ""
		if elapsed_ms > 0:
			measured = " Work had reached about %d ms." % elapsed_ms
		_set_section_text(
			section,
			"Preview stopped at the %d ms safety limit.%s\nHold Shift while hovering to force regeneration without the safety limit." % [
				safety_limit_ms,
				measured,
			]
		)
		return
	_set_section_text(section, "Preview could not be generated.")

# Returns the compact text shown while a newly scheduled preview is generated.
# This intentionally matches the simple status layout proven to work reliably in
# the earlier pipeline test.
func _generating_text(module_entry: Dictionary) -> String:
	var module_name := String(module_entry.get("name", "Preview"))
	return "Generating %s preview..." % module_name.to_lower()

# Removes separators inserted by existing modules because the pipeline owns the
# separator surrounding its entire status/preview section.
func _remove_generated_separators(container: Control) -> void:
	for child in container.get_children():
		if child is HSeparator:
			container.remove_child(child)
			child.free()

# Frees every child of a status body before replacing text with a preview or
# vice versa.
func _free_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()

# Returns whether the configured safety limit has been reached. A value of zero
# explicitly disables the limit.
func _safety_limit_exceeded(started_usec: int, safety_limit_ms: int) -> bool:
	return (
		safety_limit_ms > 0
		and float(Time.get_ticks_usec() - started_usec) / 1000.0 >= float(safety_limit_ms)
	)

# Returns elapsed generation time in whole milliseconds for remembered failure
# messages and safety-limit bookkeeping.
func _elapsed_ms_int(started_usec: int) -> int:
	return ceili(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	
func _job_is_current(job_key: String, job_epoch: int) -> bool:
	return job_epoch == _generation_epoch and _jobs.has(job_key)

# Returns all still-alive tooltip base controls waiting for one in-flight job.
func _live_job_bases(job_key: String) -> Array[Control]:
	var result: Array[Control] = []
	var job_value: Variant = _jobs.get(job_key, null)
	if not (job_value is Dictionary):
		return result
	var waiters: Array = (job_value as Dictionary).get("waiters", []) as Array
	for waiter_value: Variant in waiters:
		if waiter_value is Dictionary:
			var base_ref: Variant = (waiter_value as Dictionary).get("base", null)
			if base_ref is WeakRef:
				var base_value: Control = (base_ref as WeakRef).get_ref() as Control
				if is_instance_valid(base_value):
					result.append(base_value)
	return result

# Returns all still-alive add-on sections already attached to visible tooltip bases.
func _live_job_sections(job_key: String) -> Array[VBoxContainer]:
	var result: Array[VBoxContainer] = []
	var job_value: Variant = _jobs.get(job_key, null)
	if not (job_value is Dictionary):
		return result
	var waiters: Array = (job_value as Dictionary).get("waiters", []) as Array
	for waiter_value: Variant in waiters:
		if waiter_value is Dictionary:
			var section_ref: Variant = (waiter_value as Dictionary).get("section", null)
			if section_ref is WeakRef:
				var section_value: VBoxContainer = (section_ref as WeakRef).get_ref() as VBoxContainer
				if is_instance_valid(section_value):
					result.append(section_value)
	return result

# Attaches the generating section only after Godot has displayed its own tooltip.
# The base Control itself is resized, never any FileSystem Dock parent.
func _ensure_job_status_sections(job_key: String, message: String) -> void:
	var job_value: Variant = _jobs.get(job_key, null)
	if not (job_value is Dictionary):
		return
	var job: Dictionary = job_value as Dictionary
	var waiters := job.get("waiters", []) as Array
	for index: int in range(waiters.size()):
		var waiter_value: Variant = waiters[index]
		if not (waiter_value is Dictionary):
			continue
		var waiter: Dictionary = waiter_value as Dictionary
		var base_ref: Variant = waiter.get("base", null)
		if not (base_ref is WeakRef):
			continue
		var base: Control = (base_ref as WeakRef).get_ref() as Control
		if not is_instance_valid(base):
			continue
		if not base.is_inside_tree() or not base.is_visible_in_tree():
			continue
		var section_ref: Variant = waiter.get("section", null)
		var section: VBoxContainer = null
		if section_ref is WeakRef:
			var existing: VBoxContainer = (section_ref as WeakRef).get_ref() as VBoxContainer
			if is_instance_valid(existing):
				section = existing
		if section == null:
			section = _create_status_section(base, message)
			waiter["section"] = weakref(section)
			waiters[index] = waiter
			var resize_target: Node = _get_waiter_resize_target(waiter)
			_refresh_tooltip_layout(base, resize_target)
	job["waiters"] = waiters
	_jobs[job_key] = job

# Recalculates the base container and, when supplied, the surrounding popup after
# an asynchronous section changes size. FileSystem tooltips simply use their base
# control; Code Editor help bits additionally pass their PopupPanel window.
func _refresh_tooltip_layout(base: Control, resize_target: Node = null) -> void:
	var effective_target := _resolve_tooltip_resize_target(base, resize_target)
	_refresh_tooltip_layout_pass(base, effective_target)
	var base_ref: WeakRef = weakref(base) if is_instance_valid(base) else null
	var target_ref: WeakRef = weakref(effective_target) if is_instance_valid(effective_target) else null
	call_deferred("_refresh_tooltip_layout_deferred", base_ref, target_ref)

# Runs one immediate and one deferred tooltip relayout pass. The deferred pass
# lets Godot propagate fresh minimum sizes after asynchronous preview content
# arrives, allowing popups to shrink again and to clamp themselves back onto the
# visible screen area after late growth.
func _refresh_tooltip_layout_deferred(base_ref: WeakRef, target_ref: WeakRef) -> void:
	var base := base_ref.get_ref() as Control if base_ref != null else null
	var requested_target := target_ref.get_ref() as Node if target_ref != null else null
	var resize_target := _resolve_tooltip_resize_target(base, requested_target)
	_refresh_tooltip_layout_pass(base, resize_target)

func _refresh_tooltip_layout_pass(base: Control, resize_target: Node = null) -> void:
	if is_instance_valid(base):
		base.update_minimum_size()
		base.reset_size()
		if base.has_method("queue_sort"):
			base.call("queue_sort")
	if not is_instance_valid(resize_target) or resize_target == base:
		return
	if resize_target is Control:
		var resize_control := resize_target as Control
		resize_control.update_minimum_size()
		resize_control.reset_size()
		if resize_control.has_method("queue_sort"):
			resize_control.call("queue_sort")
	elif resize_target.has_method("reset_size"):
		resize_target.call("reset_size")
	_clamp_resize_target_to_screen(resize_target)

# Resolves the actual tooltip window when possible so Code Editor and FileSystem
# previews use the same resize/clamp path. The explicit Code Editor PopupPanel
# still wins; FileSystem tooltips are discovered through the base's ancestors.
func _resolve_tooltip_resize_target(base: Control, requested_target: Node) -> Node:
	if requested_target is Window:
		return requested_target
	var current: Node = base
	while is_instance_valid(current):
		if current is PopupPanel:
			return current
		current = current.get_parent()
	return requested_target if is_instance_valid(requested_target) else base

# Native tooltip windows are positioned for the size known at creation time.
# Late preview growth or wheel resizing can change that size substantially, so
# keep the complete window inside the usable screen rect after each relayout.
func _clamp_resize_target_to_screen(resize_target: Node) -> void:
	var window := resize_target as Window
	if window == null:
		return
	var size: Vector2i = window.size
	if size.x <= 0 or size.y <= 0:
		return
	var screen := window.current_screen
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var max_x := usable_rect.position.x + maxi(0, usable_rect.size.x - size.x)
	var max_y := usable_rect.position.y + maxi(0, usable_rect.size.y - size.y)
	window.position = Vector2i(
		clampi(window.position.x, usable_rect.position.x, max_x),
		clampi(window.position.y, usable_rect.position.y, max_y)
	)

func _get_waiter_resize_target(waiter: Dictionary) -> Node:
	var target_ref: Variant = waiter.get("resize_target", null)
	if target_ref is WeakRef:
		var target_value: Node = (target_ref as WeakRef).get_ref() as Node
		if is_instance_valid(target_value):
			return target_value
	return null

# Refreshes all still-live tooltip layouts attached to one shared generation job.
func _refresh_job_layout(job_key: String) -> void:
	var job_value: Variant = _jobs.get(job_key, null)
	if not (job_value is Dictionary):
		return
	var waiters: Array = (job_value as Dictionary).get("waiters", []) as Array
	for waiter_value: Variant in waiters:
		if not (waiter_value is Dictionary):
			continue
		var waiter: Dictionary = waiter_value as Dictionary
		var base_ref: Variant = waiter.get("base", null)
		if not (base_ref is WeakRef):
			continue
		var base_value: Control = (base_ref as WeakRef).get_ref() as Control
		if not is_instance_valid(base_value):
			continue
		_refresh_tooltip_layout(
			base_value,
			_get_waiter_resize_target(waiter)
		)

# Returns whether at least one tooltip base is still alive for an in-flight job.
func _job_has_live_waiters(job_key: String) -> bool:
	return not _live_job_bases(job_key).is_empty()

# Waits until Godot's own tooltip base is attached and visible. Only then is the
# add-on status section inserted, so initial tooltip construction stays untouched.
func _wait_until_job_tooltip_is_visible(job_key: String, job_epoch: int) -> bool:
	var tree := EditorInterface.get_base_control().get_tree()
	while _job_is_current(job_key, job_epoch):
		var bases := _live_job_bases(job_key)
		if bases.is_empty():
			return false
		for base in bases:
			if base.is_inside_tree() and base.is_visible_in_tree():
				return true
		await tree.process_frame
	return false

# Cancels all in-flight jobs owned by one module when that module is disabled.
func _cancel_jobs_for_module(module_id: String) -> void:
	var keys_to_remove: Array[String] = []
	for job_key_value in _jobs.keys():
		var job_key := String(job_key_value)
		var job := _jobs[job_key] as Dictionary
		if String(job.get("module_id", "")) == module_id:
			for section in _live_job_sections(job_key):
				section.queue_free()
			keys_to_remove.append(job_key)
	for job_key in keys_to_remove:
		_jobs.erase(job_key)

# Removes every live status section when the cache is explicitly cleared or the
# pipeline is shut down.
func _remove_all_job_sections() -> void:
	for job_key_value in _jobs.keys():
		for section in _live_job_sections(String(job_key_value)):
			section.queue_free()
