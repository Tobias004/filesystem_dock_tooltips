@tool
class_name BTTooltipCache
extends RefCounted

## [b]Shared persistent tooltip cache[/b] used by the preview pipeline.
## Generated previews are stored as PNG files below [code]res://.godot/better_tooltips/[/code] and survive editor restarts.
## A bounded RAM hot cache keeps recently used [ImageTexture] objects fast without allowing large projects to grow memory use without limit.
## Cache signatures include the resource, recursively discovered dependencies, module id, cache format and relevant editor/runtime context.


const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

const STATUS_FAILED := "FAILED"
const STATUS_SAFETY_LIMIT := "SAFETY_LIMIT"
const CACHE_FORMAT_VERSION := 2
const CACHE_ROOT := "res://.godot/better_tooltips"
const CACHE_PREVIEWS_DIR := CACHE_ROOT + "/previews"
const CACHE_INDEX_PATH := CACHE_ROOT + "/cache_index.cfg"
const CACHE_INDEX_SECTION := "cache"
const RAM_CACHE_MAX_BYTES := 32 * 1024 * 1024

var _preview_cache: Dictionary = {}
var _failure_cache: Dictionary = {}
var _path_keys: Dictionary = {}
var _lru_keys: Array[String] = []
var _ram_cache_bytes := 0
var _index := ConfigFile.new()


# Initializes the persistent cache directory and metadata index. The parent is
# intentionally unused; Better Tooltips 3.0 does not keep hidden live preview Controls.
func setup(_parent: Node) -> void:
	_ensure_persistent_storage()
	_load_persistent_index()


# Releases only transient RAM state when the add-on is disabled. Persistent PNG
# previews intentionally remain on disk so they can be reused after a restart.
func cleanup() -> void:
	_clear_memory_cache()
	_failure_cache.clear()
	_path_keys.clear()


# Removes RAM entries, remembered failures and every persistent preview written
# by this add-on. The following hover therefore regenerates the resource preview.
func clear() -> void:
	_clear_memory_cache()
	_failure_cache.clear()
	_path_keys.clear()
	_reset_persistent_storage()


# Reports whether there is anything meaningful for Clear Tooltip Caches to
# remove. The cache-format metadata section by itself does not count as content.
func has_entries() -> bool:
	if not _preview_cache.is_empty() or not _failure_cache.is_empty():
		return true
	for section in _index.get_sections():
		if section != CACHE_INDEX_SECTION:
			return true
	return false


# Returns the exact key for one module and the current resource/dependency state.
# The pipeline also uses this key to deduplicate in-flight generation work.
func get_cache_key(path: String, module_id: String = "") -> String:
	var identity := _prepare_current_identity(path, module_id)
	return String(identity.get("key", ""))


# Removes the cached state for one resource/module scope from RAM, transient
# failure memory and persistent storage. Shift + hover uses this to guarantee a
# genuine regeneration instead of reusing any previously successful preview.
func invalidate_preview(path: String, module_id: String = "") -> void:
	var identity := _prepare_current_identity(path, module_id)
	var key := String(identity.get("key", ""))
	if key.is_empty():
		return
	_erase_ram_key(key)
	_failure_cache.erase(key)
	_erase_persistent_scope(String(identity.get("scope_hash", "")))


# Returns the current preview from the bounded RAM cache or, on a RAM miss, from
# the persistent PNG cache.
func get_preview(path: String, module_id: String = "") -> Dictionary:
	var identity := _prepare_current_identity(path, module_id)
	var key := String(identity.get("key", ""))
	if key.is_empty():
		return {}

	var entry_value: Variant = _preview_cache.get(key, null)
	if entry_value is Dictionary:
		_touch_ram_key(key)
		return entry_value as Dictionary

	var disk_entry := _load_persistent_preview(identity)
	if disk_entry.is_empty():
		return {}
	_store_ram_entry(key, disk_entry)
	return disk_entry


# Returns a remembered transient failure for the current resource version. A
# SAFETY_LIMIT stop is retried when the configured limit is raised or disabled.
# Failures are deliberately not persisted across editor restarts.
func get_failure_entry(
	path: String,
	current_safety_limit_ms: int,
	module_id: String = ""
) -> Dictionary:
	var identity := _prepare_current_identity(path, module_id)
	var key := String(identity.get("key", ""))
	if key.is_empty():
		return {}
	var entry_value: Variant = _failure_cache.get(key, null)
	if not (entry_value is Dictionary):
		return {}
	var entry := entry_value as Dictionary
	var status := String(entry.get("status", ""))
	if status == STATUS_SAFETY_LIMIT:
		var previous_limit_ms := int(entry.get("safety_limit_ms", 0))
		if current_safety_limit_ms == 0 or current_safety_limit_ms > previous_limit_ms:
			_failure_cache.erase(key)
			return {}
	return entry


# Compatibility wrapper for callers that only require the failure status string.
func get_failure_status(
	path: String,
	current_safety_limit_ms: int,
	module_id: String = ""
) -> String:
	var entry := get_failure_entry(path, current_safety_limit_ms, module_id)
	return String(entry.get("status", ""))


# Stores the already captured image and texture in the bounded RAM hot cache.
# Persistent PNG writing is scheduled separately so it cannot delay tooltip display.
func store_runtime_preview(
	path: String,
	image: Image,
	texture: Texture2D,
	module_id: String = ""
) -> Dictionary:
	if image == null or image.is_empty():
		return {}
	if texture == null:
		texture = ImageTexture.create_from_image(image)
	if texture == null:
		return {}

	var identity := _prepare_current_identity(path, module_id)
	var key := String(identity.get("key", ""))
	if key.is_empty():
		return {}
	var size := image.get_size()
	if size.x <= 0 or size.y <= 0:
		return {}
	var entry := {
		"texture": texture,
		"size": size,
		"bytes": image.get_data_size(),
	}
	_store_ram_entry(key, entry)
	_failure_cache.erase(key)
	return entry


# Persists a completed preview after the visible tooltip has already been updated.
# The expected key prevents a deferred write from publishing an image after the
# resource or one of its dependencies changed in the meantime.
func persist_preview(
	path: String,
	image: Image,
	module_id: String,
	expected_key: String
) -> void:
	if image == null or image.is_empty() or expected_key.is_empty():
		return
	var identity := _prepare_current_identity(path, module_id)
	if String(identity.get("key", "")) != expected_key:
		return
	_store_persistent_preview(identity, image)


# Stores a failed generation only for this editor session. Persistent failure
# caching could otherwise make a transient driver/render problem survive restart.
func store_failure(
	path: String,
	status: String,
	safety_limit_ms: int,
	elapsed_ms: int = 0,
	module_id: String = ""
) -> void:
	var identity := _prepare_current_identity(path, module_id)
	var key := String(identity.get("key", ""))
	if key.is_empty():
		return
	_erase_ram_key(key)
	_failure_cache[key] = {
		"status": status,
		"safety_limit_ms": safety_limit_ms,
		"elapsed_ms": elapsed_ms,
	}


# Builds a stable identity from the resource scope and a signature of the source,
# recursively discovered dependencies, cache format and relevant editor context.
func _prepare_current_identity(path: String, module_id: String = "") -> Dictionary:
	if path.is_empty():
		return {}
	var scope := "%s|%s" % [module_id, path]
	var signature := _build_signature(path, module_id)
	if signature.is_empty():
		return {}
	var key := "%s|%s" % [scope, signature]
	var scope_hash := scope.sha256_text()
	var previous_key := String(_path_keys.get(scope, ""))
	if not previous_key.is_empty() and previous_key != key:
		_erase_ram_key(previous_key)
		_failure_cache.erase(previous_key)
	_path_keys[scope] = key

	# If a persistent entry exists for the same resource/module scope but belongs
	# to an older source/dependency signature, discard it immediately.
	if _index.has_section(scope_hash):
		var stored_signature := String(_index.get_value(scope_hash, "signature", ""))
		if stored_signature != signature:
			_erase_persistent_scope(scope_hash)

	return {
		"scope": scope,
		"scope_hash": scope_hash,
		"signature": signature,
		"key": key,
		"path": path,
		"module_id": module_id,
	}


# Computes a persistent signature. Recursive dependency mtimes/sizes ensure that
# changing an external shader/texture invalidates a material even when the .tres
# file itself was not modified.
func _build_signature(path: String, module_id: String) -> String:
	var parts: Array[String] = []
	parts.append("cache_format=%d" % CACHE_FORMAT_VERSION)
	parts.append("module=%s" % module_id)
	parts.append("godot=%s" % String(Engine.get_version_info().get("string", "")))
	parts.append("editor_scale=%.4f" % EditorInterface.get_editor_scale())
	parts.append("preview_size_percent=%d" % Settings.get_preview_size_percent())
	parts.append("theme=%s" % _editor_theme_signature())
	var visited: Dictionary = {}
	_append_resource_signature(path, parts, visited)
	return "\n".join(parts).sha256_text()


# Appends one file and its recursively discoverable external dependencies to the
# signature input while preventing cycles in dependency graphs.
func _append_resource_signature(
	path: String,
	parts: Array[String],
	visited: Dictionary
) -> void:
	if path.is_empty() or visited.has(path):
		return
	visited[path] = true
	parts.append("%s|%d|%d" % [
		path,
		FileAccess.get_modified_time(path),
		FileAccess.get_size(path),
	])
	for dependency_value in ResourceLoader.get_dependencies(path):
		var dependency_path := _extract_dependency_path(String(dependency_value))
		if dependency_path.begins_with("res://"):
			_append_resource_signature(dependency_path, parts, visited)


# Extracts the fallback resource path from Godot dependency descriptors such as
# uid::type::res://path while also accepting plain res:// dependency strings.
func _extract_dependency_path(dependency: String) -> String:
	if dependency.begins_with("res://"):
		return dependency
	var parts := dependency.split("::", false)
	for index in range(parts.size() - 1, -1, -1):
		var part := String(parts[index])
		if part.begins_with("res://"):
			return part
	return ""


# Includes stable editor-theme choices that can materially change Control-based
# previews. Missing settings simply contribute an empty/default value.
func _editor_theme_signature() -> String:
	var settings := EditorInterface.get_editor_settings()
	var values: Array[String] = []
	for setting_name in [
		"interface/theme/preset",
		"interface/theme/custom_theme",
		"interface/theme/base_color",
		"interface/theme/accent_color",
		"interface/theme/contrast",
	]:
		if settings.has_setting(setting_name):
			values.append("%s=%s" % [setting_name, str(settings.get_setting(setting_name))])
	return ";".join(values)


# Loads one validated PNG from disk and recreates the static ImageTexture used by
# the tooltip. Corrupt or missing files are removed from the persistent index.
func _load_persistent_preview(identity: Dictionary) -> Dictionary:
	var scope_hash := String(identity.get("scope_hash", ""))
	var signature := String(identity.get("signature", ""))
	if scope_hash.is_empty() or not _index.has_section(scope_hash):
		return {}
	if String(_index.get_value(scope_hash, "signature", "")) != signature:
		return {}
	var file_name := String(_index.get_value(scope_hash, "file", scope_hash + ".png"))
	var file_path := _absolute_path(CACHE_PREVIEWS_DIR + "/" + file_name)
	if not FileAccess.file_exists(file_path):
		_erase_persistent_scope(scope_hash)
		return {}
	var image := Image.new()
	if image.load(file_path) != OK or image.is_empty():
		_erase_persistent_scope(scope_hash)
		return {}
	var texture := ImageTexture.create_from_image(image)
	if texture == null:
		return {}
	return {
		"texture": texture,
		"size": image.get_size(),
		"bytes": image.get_data_size(),
	}


# Writes one PNG and updates the compact index. One filename is reused per
# module/resource scope, so changing a resource does not accumulate old versions.
func _store_persistent_preview(identity: Dictionary, image: Image) -> void:
	if not _ensure_persistent_storage():
		return
	var scope_hash := String(identity.get("scope_hash", ""))
	if scope_hash.is_empty():
		return
	var file_name := scope_hash + ".png"
	var file_path := _absolute_path(CACHE_PREVIEWS_DIR + "/" + file_name)
	if image.save_png(file_path) != OK:
		return
	_index.set_value(scope_hash, "signature", String(identity.get("signature", "")))
	_index.set_value(scope_hash, "file", file_name)
	_index.set_value(scope_hash, "path", String(identity.get("path", "")))
	_index.set_value(scope_hash, "module_id", String(identity.get("module_id", "")))
	_save_persistent_index()


# Stores one texture in the bounded RAM LRU and evicts least-recently-used
# entries until the configured memory budget is satisfied.
func _store_ram_entry(key: String, entry: Dictionary) -> void:
	_erase_ram_key(key)
	var stored := entry.duplicate()
	var bytes := int(stored.get("bytes", 0))
	if bytes <= 0:
		var size_value: Variant = stored.get("size", Vector2i.ZERO)
		if size_value is Vector2i:
			var size := size_value as Vector2i
			bytes = maxi(0, size.x * size.y * 4)
	stored["bytes"] = bytes
	_preview_cache[key] = stored
	_ram_cache_bytes += bytes
	_lru_keys.append(key)
	_prune_ram_cache()


# Marks a RAM entry as most recently used.
func _touch_ram_key(key: String) -> void:
	_lru_keys.erase(key)
	_lru_keys.append(key)


# Evicts the least recently used textures until RAM usage is within the fixed
# 32 MiB hot-cache budget. A single oversized preview may be evicted immediately.
func _prune_ram_cache() -> void:
	while _ram_cache_bytes > RAM_CACHE_MAX_BYTES and not _lru_keys.is_empty():
		_erase_ram_key(_lru_keys.front())


# Removes one RAM entry and updates the approximate memory accounting.
func _erase_ram_key(key: String) -> void:
	var entry_value: Variant = _preview_cache.get(key, null)
	if entry_value is Dictionary:
		_ram_cache_bytes = maxi(
			0,
			_ram_cache_bytes - int((entry_value as Dictionary).get("bytes", 0))
		)
	_preview_cache.erase(key)
	_lru_keys.erase(key)


# Clears only the bounded in-memory hot cache, preserving persistent PNG files.
func _clear_memory_cache() -> void:
	_preview_cache.clear()
	_lru_keys.clear()
	_ram_cache_bytes = 0


# Creates the cache directories if required.
func _ensure_persistent_storage() -> bool:
	var root_path := _absolute_path(CACHE_ROOT)
	var previews_path := _absolute_path(CACHE_PREVIEWS_DIR)
	if DirAccess.make_dir_recursive_absolute(root_path) != OK and not DirAccess.dir_exists_absolute(root_path):
		return false
	if DirAccess.make_dir_recursive_absolute(previews_path) != OK and not DirAccess.dir_exists_absolute(previews_path):
		return false
	return true


# Loads the persistent index and invalidates the whole on-disk cache when its
# explicit format version changes in a future add-on version.
func _load_persistent_index() -> void:
	_index = ConfigFile.new()
	var index_path := _absolute_path(CACHE_INDEX_PATH)
	if not FileAccess.file_exists(index_path):
		_initialize_empty_index()
		return
	if _index.load(index_path) != OK:
		_reset_persistent_storage()
		return
	if int(_index.get_value(CACHE_INDEX_SECTION, "format_version", -1)) != CACHE_FORMAT_VERSION:
		_reset_persistent_storage()


# Initializes metadata for an empty persistent cache.
func _initialize_empty_index() -> void:
	_index = ConfigFile.new()
	_index.set_value(CACHE_INDEX_SECTION, "format_version", CACHE_FORMAT_VERSION)
	_save_persistent_index()


# Saves the current persistent index. A failed metadata write leaves the PNG on
# disk harmlessly unreachable and therefore cannot return a stale preview.
func _save_persistent_index() -> void:
	if not _ensure_persistent_storage():
		return
	_index.set_value(CACHE_INDEX_SECTION, "format_version", CACHE_FORMAT_VERSION)
	_index.save(_absolute_path(CACHE_INDEX_PATH))


# Removes one obsolete/corrupt persistent preview and its index section.
func _erase_persistent_scope(scope_hash: String) -> void:
	if scope_hash.is_empty() or scope_hash == CACHE_INDEX_SECTION:
		return
	var file_name := String(_index.get_value(scope_hash, "file", scope_hash + ".png"))
	var file_path := _absolute_path(CACHE_PREVIEWS_DIR + "/" + file_name)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	if _index.has_section(scope_hash):
		_index.erase_section(scope_hash)
		_save_persistent_index()


# Deletes every persistent preview owned by the add-on and recreates an empty
# index. Other data below .godot is never touched.
func _reset_persistent_storage() -> void:
	var previews_path := _absolute_path(CACHE_PREVIEWS_DIR)
	_remove_directory_contents(previews_path)
	var index_path := _absolute_path(CACHE_INDEX_PATH)
	if FileAccess.file_exists(index_path):
		DirAccess.remove_absolute(index_path)
	_ensure_persistent_storage()
	_initialize_empty_index()


# Recursively removes files from one cache directory. This helper is scoped to
# the add-on's own .godot folder and is never called on the project root.
func _remove_directory_contents(directory_path: String) -> void:
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child_path := directory_path.path_join(name)
			if dir.current_is_dir():
				_remove_directory_contents(child_path)
				DirAccess.remove_absolute(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		name = dir.get_next()
	dir.list_dir_end()


# Converts a project-relative cache path to an OS path for Image/ConfigFile I/O.
func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)
