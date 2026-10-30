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
const TextWheelRouter := preload("res://addons/better_tooltips/core/text_tooltip_wheel_router.gd")
const TooltipLifetime := preload("res://addons/better_tooltips/core/tooltip_lifetime_manager.gd")
const PreviewGenerator := preload("res://addons/better_tooltips/core/preview_generator.gd")
const TooltipPresenter := preload("res://addons/better_tooltips/core/tooltip_presenter.gd")
# Zoom is optional: a broken or unavailable zoom component must not prevent
# text tooltips and cached graphical previews from loading.
const PREVIEW_ZOOM_SCRIPT_PATH := "res://addons/better_tooltips/core/preview_zoom_controller.gd"
const TooltipAppearance := preload(
	"res://addons/better_tooltips/core/tooltip_appearance.gd"
)

const LIVE_TEXT_POPUP_NAME := &"BTInteractiveTextTooltip"
const LIVE_TEXT_TOOLTIP_PANEL_VARIATION := &"TooltipPanel"
const LIVE_TEXT_EXIT_GRACE_SECONDS := 0.30
const LIVE_TEXT_POPUP_GAP := 10.0
const LIVE_TEXT_SCREEN_MARGIN := 8.0

var _cache: BTTooltipCache = null
var _preview_generator: Node = null
var _presenter: RefCounted = null
var _preview_zoom: Node = null
var _modules: Dictionary = {}
var _module_order: Array[String] = []
var _jobs: Dictionary = {}
var _generation_epoch := 0
var _live_text_session: Dictionary = {}
var _live_text_session_sequence := 0
# Navigation popups are created outside this pipeline but share its wheel router.
var _text_wheel_router: BTTextTooltipWheelRouter = null
var _tooltip_lifetime: RefCounted = null

# Initializes the pipeline facade and its independent helper components.
# Rendering, presentation, zoom interaction and tooltip lifetime each keep their
# own state so a change in one area does not have to be implemented here.
func setup(cache: BTTooltipCache, parent: Node) -> void:
	_cache = cache
	if _text_wheel_router == null:
		_text_wheel_router = TextWheelRouter.new()
	if _tooltip_lifetime == null:
		_tooltip_lifetime = TooltipLifetime.new()
	if _presenter == null:
		_presenter = TooltipPresenter.new()
	if _preview_generator == null:
		_preview_generator = PreviewGenerator.new()
		_preview_generator.setup(parent)
	if _preview_zoom == null and FileAccess.file_exists(PREVIEW_ZOOM_SCRIPT_PATH):
		var zoom_script := load(PREVIEW_ZOOM_SCRIPT_PATH) as Script
		if zoom_script != null and zoom_script.can_instantiate():
			var zoom_instance: Variant = zoom_script.new()
			if zoom_instance is Node:
				_preview_zoom = zoom_instance as Node
				_preview_zoom.setup(
					parent,
					_preview_generator,
					_presenter,
					Callable(self, "_get_module_entry")
				)

func cleanup() -> void:
	_generation_epoch += 1
	_remove_all_job_sections()
	_jobs.clear()
	_close_live_text_session()
	_clear_external_text_popups()
	if _tooltip_lifetime != null:
		_tooltip_lifetime.clear()
	_tooltip_lifetime = null
	_text_wheel_router = null
	if _preview_zoom != null:
		_preview_zoom.cleanup()
	_preview_zoom = null
	if _preview_generator != null:
		_preview_generator.cleanup()
	_preview_generator = null
	_presenter = null
	_modules.clear()
	_module_order.clear()
	_cache = null

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

func _get_module_entry(module_id: String) -> Dictionary:
	return _modules.get(module_id, {}) as Dictionary

# Removes one module and cancels jobs belonging to it. The shared successful and
# failure cache is intentionally retained so re-enabling a module in the same
# editor session can reuse already generated entries.
func remove_module(module_id: String) -> void:
	if not _modules.has(module_id):
		return
	_cancel_jobs_for_module(module_id)
	if _preview_zoom != null:
		_preview_zoom.remove_sessions_for_module(module_id)
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

# Reports whether a path is handled by a live text module, not by a graphical
# preview. Navigational hosts use this to wait for text layout before opening
# their already-owned popup window.
func supports_live_text_preview_path(path: String) -> bool:
	var preview_context := _get_path_preview_context(path)
	for module_id in preview_context.get("module_ids", []) as Array[String]:
		var module_entry: Dictionary = _modules.get(module_id, {})
		var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
		if plugin != null and plugin.has_method("is_live_preview") and bool(plugin.call("is_live_preview")):
			return true
	return false

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
			_presenter.refresh_tooltip_layout(base, resize_target)
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
		_presenter.refresh_tooltip_layout(base, resize_target)
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
		var section := _presenter.create_status_section(base, "") as VBoxContainer
		_presenter.set_section_failure(section, TooltipCache.STATUS_FAILED, safety_limit_ms, 0)
		_presenter.refresh_tooltip_layout(base, resize_target)
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
	_ensure_job_status_sections(job_key, _presenter.generating_text(module_entry))
	# Give the already-visible tooltip one normal editor frame to draw the status
	# before resource or shader work can occupy the main/render thread.
	await EditorInterface.get_base_control().get_tree().process_frame
	if not _job_is_current(job_key, job_epoch):
		return
	var plugin := module_entry.get("plugin", null) as EditorResourceTooltipPlugin
	if plugin == null or _preview_generator == null:
		_finish_cancelled(job_key)
		return

	metadata[Settings.PREVIEW_SCALE_METADATA_KEY] = (
		float(Settings.get_preview_size_percent()) / 100.0
	)
	var current_callback := Callable(self, "_job_is_current").bind(job_key, job_epoch)
	var capture: Dictionary = await _preview_generator.generate(
		plugin,
		path,
		metadata,
		safety_limit_ms,
		current_callback
	)
	var capture_status := String(capture.get("status", PreviewGenerator.STATUS_CANCELLED))
	var elapsed_ms := int(capture.get("elapsed_ms", 0))
	match capture_status:
		PreviewGenerator.STATUS_READY:
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
					job_key, module_id, path, safety_limit_ms, elapsed_ms, job_epoch
				)
				return
			var stored_value: Dictionary = _cache.store_runtime_preview(
				path, image, texture, module_id
			)
			if not stored_value.is_empty():
				_finish_ready(job_key, stored_value)
				_persist_ready_preview.call_deferred(
					path, image, module_id, job_key, job_epoch
				)
				Debug.log(
					String(module_entry.get("name", "Preview")),
					"pipeline cached: " + path
				)
			else:
				_finish_failure(
					job_key, module_id, path, safety_limit_ms, elapsed_ms, job_epoch
				)
		TooltipCache.STATUS_SAFETY_LIMIT:
			_finish_safety_limit(
				job_key, module_id, path, safety_limit_ms, elapsed_ms, job_epoch
			)
		TooltipCache.STATUS_FAILED:
			_finish_failure(
				job_key, module_id, path, safety_limit_ms, elapsed_ms, job_epoch
			)
		PreviewGenerator.STATUS_NO_PREVIEW:
			_finish_no_preview(job_key)
		_:
			_finish_cancelled(job_key)

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
		_presenter.set_section_preview(section, entry)
		_register_graphical_preview_session(
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
			_presenter.set_section_failure(
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
			_presenter.set_section_failure(
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
	var section := _presenter.create_section(base) as VBoxContainer
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
	_presenter.remove_generated_separators(body)
	if result == null or body.get_child_count() == 0:
		section.queue_free()
		return
	# A native popup may already be visible while text layout is deferred.
	# Keep its contents hidden until transfer to the fully measured popup.
	if not (resize_target is PopupPanel):
		base.modulate.a = 0.0
	_presenter.refresh_tooltip_layout(base, resize_target)
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
		if is_instance_valid(base):
			base.modulate.a = 1.0
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
	_presenter.refresh_tooltip_layout(base, resize_target)
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
	# An already-owned navigation popup can now be shown at its final size.
	# This callback runs only after the text heights have stabilized in-tree.
	var ready_callback: Variant = metadata.get("layout_ready_callback", null)
	if ready_callback is Callable and (ready_callback as Callable).is_valid():
		(ready_callback as Callable).call()

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
	var budget := TooltipAppearance.get_text_max_height_pixels() - 100.0 * scale
	_set_script_region_height(documentation, minf(budget * 0.33, 230.0 * scale))
	_set_script_region_height(source, minf(budget * 0.60, 460.0 * scale))

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
	# Some integrations create and monitor their own interactive PopupPanel.
	# Never replace such a window: reparenting it into a second popup can
	# trigger multiple visible resizing/blank frames on first hover.
	if bool(metadata.get("host_manages_popup", false)):
		base.modulate.a = 1.0
		return
	var target := _presenter.resolve_tooltip_resize_target(base, requested_target) as Node
	var original_popup := target as PopupPanel
	if (
		original_popup == null
		or original_popup.name == LIVE_TEXT_POPUP_NAME
		or original_popup.theme_type_variation != LIVE_TEXT_TOOLTIP_PANEL_VARIATION
	):
		base.modulate.a = 1.0
		return
	var popup_root := _find_popup_root_for_control(original_popup, base)
	if popup_root == null:
		base.modulate.a = 1.0
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
	# A PopupPanel defaults to FLAG_POPUP, which exclusively grabs mouse input.
	# On some platforms the first click on a FileSystemDock item is then used
	# only to dismiss the preview, breaking the editor's double-click action.
	# The shared lifetime manager already closes our non-exclusive tooltip.
	popup.set_flag(Window.FLAG_POPUP, false)
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	popup.mouse_passthrough = false
	if original_popup.theme != null:
		popup.theme = original_popup.theme
	var popup_parent := EditorInterface.get_base_control()
	if popup_parent == null:
		return
	popup_parent.add_child(popup)
	popup_root.reparent(popup)
	original_popup.hide()
	# The original content was hidden during layout; reveal it only in the
	# replacement window after final sizing and placement.
	base.modulate.a = 1.0
	popup.reset_size()
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
	}
	var input_callback := Callable(self, "_on_live_text_popup_window_input").bind(sequence)
	popup.window_input.connect(input_callback)
	_live_text_session["input_callback"] = input_callback
	if _tooltip_lifetime != null:
		_tooltip_lifetime.register_popup(
			popup, trigger_rect, null, Callable(),
			Callable(self, "_close_live_text_session"), LIVE_TEXT_EXIT_GRACE_SECONDS
		)
	# Reparenting the finished tooltip contents can change the PopupPanel minimum
	# size only after one layout pass. Schedule a second size/placement pass instead
	# of awaiting here: this keeps the pipeline safe if the add-on is disabled while
	# a tooltip is visible and avoids resuming a coroutine on a freed plugin object.
	_reposition_live_text_popup_after_layout(sequence, pointer_position)

func _reposition_live_text_popup_after_layout(
	sequence: int,
	pointer_position: Vector2i
) -> void:
	if int(_live_text_session.get("sequence", 0)) != sequence:
		return
	var popup := _get_live_text_popup()
	if popup == null:
		return
	await popup.get_tree().process_frame
	if int(_live_text_session.get("sequence", 0)) != sequence:
		return
	popup = _get_live_text_popup()
	if popup == null:
		return
	var prepared_size := TooltipAppearance.prepared_text_popup_size(popup)
	popup.size = prepared_size
	_position_live_text_popup(popup, pointer_position)
	popup.popup(Rect2i(popup.position, prepared_size))

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
# Scrolls the live RichTextLabel and consumes wheel events. The shared
# lifetime manager independently observes left-button drags.
func _on_live_text_popup_window_input(event: InputEvent, sequence: int) -> void:
	if int(_live_text_session.get("sequence", 0)) != sequence:
		return
	if event is InputEventKey:
		if _handle_live_text_popup_key(event as InputEventKey, true):
			var key_popup := _get_live_text_popup()
			if key_popup != null:
				key_popup.set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if _route_live_text_wheel(mouse_event):
		var popup := _get_live_text_popup()
		if popup != null:
			popup.set_input_as_handled()

# The same key handling works for regular editor input (non-exclusive
# text windows) and for a native popup Window. In the former case normal
# editor shortcuts are delivered directly, without synthesizing key events.
func _handle_live_text_popup_key(key_event: InputEventKey, from_popup: bool) -> bool:
	if not key_event.pressed or key_event.echo:
		return false
	var popup := _get_live_text_popup()
	if popup == null or not popup.visible:
		return false
	var root := _get_live_text_root()
	var label := _text_wheel_router.find_scrollable_rich_text(root) if root != null and _text_wheel_router != null else null
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
			return true
	if key_event.keycode == KEY_C and key_event.ctrl_pressed:
		var selected := _find_selected_rich_text(root)
		if selected != null:
			DisplayServer.clipboard_set(selected.get_selected_text())
			return true
	_close_live_text_session()
	if from_popup and key_event.keycode != KEY_ESCAPE:
		# A real popup receives the key instead of the editor. Forward it only
		# in that case, never when the event already reached the editor.
		call_deferred("_forward_closed_tooltip_key", key_event.duplicate())
	return from_popup or key_event.keycode == KEY_ESCAPE

# Facade for text-popup wheel routing. Navigation integrations continue to
# register through BTTooltipPipeline; only the router owns wheel input hooks.
# Central input facade: text scrolling has priority over graphical preview zoom.
# Returning true lets the EditorPlugin consume the wheel event before the editor
# control underneath the tooltip can act on it.
func handle_input(event: InputEvent) -> bool:
	# Non-exclusive tooltip windows no longer receive the editor's key input.
	# Route those keys through the same handler used by native popup windows.
	if event is InputEventKey:
		var text_popup := _get_live_text_popup()
		if text_popup != null and not text_popup.get_flag(Window.FLAG_POPUP):
			return _handle_live_text_popup_key(event as InputEventKey, false)
	# Close our non-exclusive text preview on a click outside its bounds.
	# Do not consume or synthesize the event: the FileSystemDock must receive
	# both genuine clicks of a double-click unchanged.
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var text_popup := _get_live_text_popup()
			if text_popup != null and text_popup.visible:
				var pointer := DisplayServer.mouse_get_position()
				if not Rect2i(text_popup.position, text_popup.size).has_point(pointer):
					_close_live_text_session()
	if _route_live_text_wheel(event):
		return true
	return _preview_zoom != null and _preview_zoom.handle_input(event)

func register_external_text_popup(popup: PopupPanel, root: Control, trigger: Control) -> void:
	if _text_wheel_router == null or not is_instance_valid(trigger):
		return
	_text_wheel_router.register_external_text_popup(
		popup, root, trigger,
		_capture_trigger_rect(trigger, DisplayServer.mouse_get_position())
	)

func unregister_external_text_popup(popup: PopupPanel) -> void:
	if _text_wheel_router != null:
		_text_wheel_router.unregister_external_text_popup(popup)

func _clear_external_text_popups() -> void:
	if _text_wheel_router != null:
		_text_wheel_router.clear()

func _route_live_text_wheel(event: InputEvent) -> bool:
	if _text_wheel_router == null:
		return false
	if not _live_text_session.is_empty() and _text_wheel_router.route_to_session(event, _live_text_session):
		if _tooltip_lifetime != null:
			_tooltip_lifetime.touch_popup(_get_live_text_popup())
		return true
	return _text_wheel_router.route_external(event)

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
		return
	var popup := _get_live_text_popup()
	var callback_value: Variant = _live_text_session.get("input_callback", null)
	if popup != null:
		if _tooltip_lifetime != null:
			_tooltip_lifetime.unregister_popup(popup)
		if callback_value is Callable and popup.window_input.is_connected(callback_value as Callable):
			popup.window_input.disconnect(callback_value as Callable)
		popup.hide()
		popup.queue_free()
	_live_text_session.clear()

# Registers graphical interaction only when the optional zoom controller is
# available. Preview display itself remains usable if that controller is absent.
func _register_graphical_preview_session(
	section: Control,
	base: Control,
	resize_target: Node,
	module_id: String,
	path: String,
	entry: Dictionary
) -> void:
	if _preview_zoom == null:
		return
	_preview_zoom.register_session(
		section, base, resize_target, module_id, path, entry
	)

# Adds one cached static texture below Godot's built-in tooltip content and
# registers it as a wheel-zoom session for as long as this tooltip stays visible.
func _append_cached_preview(
	base: Control,
	entry: Dictionary,
	module_id: String,
	path: String,
	resize_target: Node
) -> void:
	var section := _presenter.create_section(base) as VBoxContainer
	_presenter.set_section_preview(section, entry)
	_register_graphical_preview_session(
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
	var section := _presenter.create_status_section(base, "") as VBoxContainer
	_presenter.set_section_failure(
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
			section = _presenter.create_status_section(base, message)
			waiter["section"] = weakref(section)
			waiters[index] = waiter
			var resize_target: Node = _get_waiter_resize_target(waiter)
			_presenter.refresh_tooltip_layout(base, resize_target)
	job["waiters"] = waiters
	_jobs[job_key] = job

# Recalculates the base container and, when supplied, the surrounding popup after
# an asynchronous section changes size. FileSystem tooltips simply use their base
# control; Code Editor help bits additionally pass their PopupPanel window.
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
		_presenter.refresh_tooltip_layout(
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
