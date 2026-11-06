@tool
class_name BTSceneDependencyExplorerTooltip
extends "res://addons/better_tooltips/modules/scene_component_tooltip.gd"

## Compatibility with Scene Dependency Explorer's compact Tree. Its item
## metadata is a saved scene's res:// path (not a live Scene-Dock NodePath).
## Reuse the Scene-Dock popup, renderer, lifetime and overlay protection;
## do not modify or depend on SDE's plugin lifecycle.

## Godot Tree falls back to the cell label when its tooltip is an empty string.
## A single space suppresses that native fallback without showing a native popup.
## The saved path is restored when the rich tooltip closes or this module stops.
const SUPPRESSED_NATIVE_TOOLTIP := " "

var _active_scene_path := ""
var _watched_paths: PackedStringArray = []
var _watched_stamp := ""
var _elapsed_since_file_check := 0.0

## SDE opens a scene on Tree.item_activated (double-click). A PopupPanel has
## FLAG_POPUP by default: its exclusive mouse grab can consume the first click
## just to dismiss the tooltip. Use the same non-exclusive window behavior as
## the FileSystem live-text preview, without changing the native Scene dock.
func _ensure_popup() -> PopupPanel:
	var popup := super._ensure_popup()
	if popup.get_flag(Window.FLAG_POPUP):
		popup.set_flag(Window.FLAG_POPUP, false)
	return popup

func setup() -> void:
	# An optional integration must not scan the editor when SDE is absent.
	# If installed during a running editor session, reload Better Tooltips.
	if not FileAccess.file_exists("res://addons/scene_dependency_explorer/plugin.cfg"):
		return
	_popup_lifetime = TooltipLifetime.new() as BTTooltipLifetimeManager
	_timer = Timer.new()
	_timer.wait_time = HOVER_INTERVAL
	_timer.timeout.connect(_refresh_hover)
	EditorInterface.get_base_control().add_child(_timer)
	_timer.start()

## Recognize precisely the Tree constructed by Scene Dependency Explorer.
## Name and script identity are stable in its 1.0 source. Never capture other
## Trees (native Scene dock, FileSystem, node pickers, etc.).
static func find_explorer_tree(base: Node) -> Tree:
	for candidate: Node in base.find_children("*", "Tree", true, false):
		if not candidate is Tree:
			continue
		var dock := candidate.get_parent()
		if not dock is VBoxContainer or dock.name != &"Scene Dependencies":
			continue
		var dock_script := dock.get_script() as Script
		if dock_script != null and dock_script.resource_path.get_file() == "scene_explorer_dock.gd":
			return candidate as Tree
	return null

## SDE stores saved scene paths in TreeItem metadata, unlike Godot's own
## Scene-Dock, which stores NodePaths with version-dependent semantics.
static func scene_path_for_item(item: TreeItem) -> String:
	if not is_instance_valid(item):
		return ""
	var metadata: Variant = item.get_metadata(0)
	if not metadata is String:
		return ""
	var path := metadata as String
	if not path.begins_with("res://") or not path.get_extension().to_lower() in ["tscn", "scn"]:
		return ""
	return path

func _refresh_hover() -> void:
	if not is_instance_valid(_tree) or not _tree.is_visible_in_tree():
		var candidate := find_explorer_tree(EditorInterface.get_base_control())
		_tree = candidate if is_instance_valid(candidate) and candidate.is_visible_in_tree() else null
		if is_instance_valid(_timer):
			_timer.wait_time = HOVER_INTERVAL if is_instance_valid(_tree) else TREE_SEARCH_RETRY_INTERVAL
	if not is_instance_valid(_tree):
		if not _scene_popup_active():
			_restore()
		return
	_hide_native_tree_tooltip()
	# Applying the existing overlay guard here is essential: the SDE Tree can
	# be underneath a Project/context menu just like the native Scene dock.
	if has_blocking_editor_window(_tree, _popup):
		_restore()
		return
	var hovered := _tree.get_viewport().gui_get_hovered_control()
	if is_instance_valid(hovered) and hovered != _tree and not _tree.is_ancestor_of(hovered):
		if _scene_popup_active() and _popup_contains_mouse():
			return
		_restore()
		return
	var position := _tree.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, _tree.size).has_point(position):
		if not _scene_popup_active():
			_restore()
		return
	var item := _tree.get_item_at_position(position)
	var path := scene_path_for_item(item)
	if path.is_empty():
		_restore()
		return
	if item != _item or path != _active_scene_path:
		update_path_item(item, path)
		return
	_elapsed_since_file_check += HOVER_INTERVAL
	if _elapsed_since_file_check >= LIVE_VALUE_CHECK_INTERVAL:
		_elapsed_since_file_check = 0.0
		var stamp := _file_stamp(_watched_paths)
		if stamp != _watched_stamp:
			update_path_item(item, path, true)

## Godot 4.8 may still create its own (blank) tooltip window for a
## whitespace TreeItem tooltip. Suppress only the Tree's own generated native
## tooltip, never another addon/menu/dialog window.
func _hide_native_tree_tooltip() -> void:
	if not is_instance_valid(_tree) or not _scene_popup_active():
		return
	for child in _tree.get_children():
		# Godot's generated Tree tooltip has a single Label child. Never
		# dismiss arbitrary addon popups or context menus attached to the Tree.
		if (
			child is PopupPanel
			and child.visible
			and child.name.begins_with("@PopupPanel@")
			and child.get_child_count() == 1
			and child.get_child(0) is Label
		):
			child.hide()

## Test seam: updates a single explorer row without requiring the SDE plugin.
## Only saved data can be reflected here; SDE displays a file dependency tree,
## not the actual edited Node instances (which may be from another scene).
func update_path_item(item: TreeItem, path: String, force_reload: bool = false) -> void:
	if not is_instance_valid(item) or path.is_empty():
		_restore()
		return
	var new_item := item != _item or path != _active_scene_path
	if new_item:
		_restore()
		_item = item
		_original = item.get_tooltip_text(0)
		_active_scene_path = path
	elif (
		item.get_tooltip_text(0) != SUPPRESSED_NATIVE_TOOLTIP
		and not item.get_tooltip_text(0).is_empty()
		and item.get_tooltip_text(0) != _original
	):
		_original = item.get_tooltip_text(0)
	if new_item or force_reload:
		_watched_paths = _scene_dependencies(path)
		_watched_stamp = _file_stamp(_watched_paths)
		_parsed_document = Reader.for_path(path, true, _show_contracts)
		# Match the native Scene-Dock module switches: contract-only mode
		# must not expose arbitrary plain script descriptions.
		if not _show_script_docs and not bool(_parsed_document.get("has_contract", false)):
			if str(_parsed_document.get("implementation_notes", "")).is_empty():
				_parsed_document = {}
	_elapsed_since_file_check = 0.0
	if _parsed_document.is_empty():
		_hide_popup()
		if is_instance_valid(_item) and _item.get_tooltip_text(0) in ["", SUPPRESSED_NATIVE_TOOLTIP]:
			_item.set_tooltip_text(0, _original)
		return
	var signature := _original + "\n---\n" + var_to_str(_parsed_document)
	if signature != _popup_signature:
		_rebuild_popup(_parsed_document, signature)
	if is_instance_valid(_item) and not _original.is_empty():
		# Empty would trigger Tree's fallback-to-label native popup a moment later.
		_item.set_tooltip_text(0, SUPPRESSED_NATIVE_TOOLTIP)
	_show_popup()

## Track direct scene and Script resources. Positive and negative answers are
## both kept until the hovered item or its saved file/dependency stamp changes.
static func _scene_dependencies(path: String) -> PackedStringArray:
	var paths := PackedStringArray([path])
	if not FileAccess.file_exists(path):
		return paths
	for dependency: String in ResourceLoader.get_dependencies(path):
		var resource_path := dependency.substr(dependency.rfind("::") + 2) if dependency.contains("::") else dependency
		if resource_path.begins_with("res://") and resource_path.get_extension().to_lower() in ["gd", "tscn", "scn"]:
			if not paths.has(resource_path):
				paths.append(resource_path)
	return paths

static func _file_stamp(paths: PackedStringArray) -> String:
	var stamps := PackedStringArray()
	for path: String in paths:
		var size := -1
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			size = file.get_length()
		stamps.append("%s:%s:%s" % [path, FileAccess.get_modified_time(path), size])
	return "|".join(stamps)

func _restore() -> void:
	var previous_item := _item
	var previous_tooltip := _original
	super._restore()
	# The base Scene-Dock integration restores only empty native tooltips.
	# SDE deliberately uses a space to prevent Tree's label fallback.
	if is_instance_valid(previous_item) and previous_item.get_tooltip_text(0) == SUPPRESSED_NATIVE_TOOLTIP:
		previous_item.set_tooltip_text(0, previous_tooltip)
	_active_scene_path = ""
	_watched_paths.clear()
	_watched_stamp = ""
	_elapsed_since_file_check = 0.0
