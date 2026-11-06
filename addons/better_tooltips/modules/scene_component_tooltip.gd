@tool
class_name BTSceneComponentTooltip
extends RefCounted

## Adds the same rich component reference used by FileSystem tooltips to the
## local Scene dock. Godot exposes only a native plain-text Tree tooltip there,
## so this integration suppresses that text while showing its own PopupPanel.
## Existing TreeItem NodePath metadata is still resolved inside the edited scene
## only; there is no scene instantiation, remote-tree support or fixed dock path.

const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const ComponentTooltip := preload("res://addons/better_tooltips/modules/component_documentation_tooltip.gd")
const TooltipAppearance := preload("res://addons/better_tooltips/core/tooltip_appearance.gd")
const TooltipLifetime := preload("res://addons/better_tooltips/core/tooltip_lifetime_manager.gd")
const Resolver47 := preload("res://addons/better_tooltips/modules/scene_node_resolvers/scene_node_resolver_47.gd")
const Resolver48 := preload("res://addons/better_tooltips/modules/scene_node_resolvers/scene_node_resolver_48.gd")

const TOOLTIP_PANEL_VARIATION := &"TooltipPanel"
const HOVER_INTERVAL := 0.25
const TREE_SEARCH_RETRY_INTERVAL := 2.0
const LIVE_VALUE_CHECK_INTERVAL := 1.0
# Empty TreeItem tooltip text falls back to its label in Godot. A space
# suppresses that native fallback while the rich popup is visible.
const NATIVE_SCENE_TOOLTIP_PLACEHOLDER := " "

var _node_resolver: BTSceneNodeResolver
var _timer: Timer
var _tree: Tree
var _item: TreeItem
var _active_node: Node
var _active_script: Script
var _parsed_document: Dictionary = {}
var _document_dirty := true
var _elapsed_since_value_check := 0.0
var _original: String = ""
var _applied: String = ""
var _inspector: EditorInspector
var _popup: PopupPanel
var _popup_body: VBoxContainer
var _popup_signature: String = ""
var _popup_lifetime: BTTooltipLifetimeManager
var _show_contracts := true
var _show_script_docs := true

## The controller calls this when either Settings module changes. Never cache
## the toggle decision in a version Strategy; the resolver only handles NodePaths.
func set_documentation_modes(show_contracts: bool, show_scripts: bool) -> void:
	if _show_contracts == show_contracts and _show_script_docs == show_scripts:
		return
	_restore()
	_show_contracts = show_contracts
	_show_script_docs = show_scripts

func setup() -> void:
	# The Strategy choice only covers actual Godot 4.7/4.8 NodePath differences.
	var version := Engine.get_version_info()
	var major: int = int(version.get("major", 0))
	var minor: int = int(version.get("minor", 0))
	var uses_relative_paths := major > 4 or (major == 4 and minor >= 8)
	_node_resolver = Resolver48.new() if uses_relative_paths else Resolver47.new()
	_inspector = EditorInterface.get_inspector()
	if is_instance_valid(_inspector):
		_inspector.property_edited.connect(_on_property_edited)
	_popup_lifetime = TooltipLifetime.new() as BTTooltipLifetimeManager
	_timer = Timer.new()
	_timer.wait_time = HOVER_INTERVAL
	_timer.timeout.connect(_refresh_hover)
	EditorInterface.get_base_control().add_child(_timer)
	_timer.start()

func cleanup() -> void:
	_restore()
	if _popup_lifetime != null:
		_popup_lifetime.clear()
	_popup_lifetime = null
	if is_instance_valid(_inspector) and _inspector.property_edited.is_connected(_on_property_edited):
		_inspector.property_edited.disconnect(_on_property_edited)
	_inspector = null
	if is_instance_valid(_timer):
		_timer.stop()
		_timer.queue_free()
	_timer = null
	if is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null
	_popup_body = null
	_tree = null
	_node_resolver = null

func _refresh_hover() -> void:
	if not is_instance_valid(_tree) or not _tree.is_visible_in_tree():
		var candidate := find_scene_tree(EditorInterface.get_base_control())
		_tree = candidate if is_instance_valid(candidate) and candidate.is_visible_in_tree() else null
		# On unsupported/hidden/rebuilt layouts search only every two seconds.
		# This also allows replacing a dock that still exists but is hidden.
		if is_instance_valid(_timer):
			_timer.wait_time = HOVER_INTERVAL if is_instance_valid(_tree) else TREE_SEARCH_RETRY_INTERVAL
	if not is_instance_valid(_tree):
		if _scene_popup_active():
			return
		_restore()
		return
	_hide_native_tree_tooltip()
	# A screen position inside the dock does not mean the dock is receiving
	# input. In particular, an open Project/context menu can cover this Tree.
	# Opening our PopupPanel then dismisses Godot's active menu.
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
		if _scene_popup_active():
			return
		_restore()
		return
	var item := _tree.get_item_at_position(position)
	if item == null:
		_restore()
		return
	var metadata: Variant = item.get_metadata(0)
	if not metadata is NodePath:
		_restore()
		return
	var edited := EditorInterface.get_edited_scene_root()
	var node := _node_resolver.resolve(_tree, edited, metadata)
	if node == null or edited == null or (node != edited and not edited.is_ancestor_of(node)):
		_restore()
		return
	var script := node.get_script() as Script
	# Reparse only when identity/script changes or an edit signal invalidates it.
	if item != _item or node != _active_node or script != _active_script or _document_dirty:
		update_item(item, node)
		return
	_elapsed_since_value_check += HOVER_INTERVAL
	if _elapsed_since_value_check >= LIVE_VALUE_CHECK_INTERVAL:
		# Fallback for programmatic/unsaved changes outside the Inspector.
		# Re-read assignments only, never parse GDScript again.
		update_item(item, node)

func _on_property_edited(_property_name: StringName) -> void:
	if is_instance_valid(_active_node) and is_instance_valid(_item):
		if not has_blocking_editor_window(_tree, _popup):
			update_item(_item, _active_node)

## Ignore the Scene dock while another editor popup, submenu or dialog has
## priority. The hovered Tree can still be under the pointer geometrically,
## even though an overlapping window is receiving the mouse input. Only the
## existing addon tooltip is exempted, so its interactive hover stays intact.
static func has_blocking_editor_window(tree: Tree, own_popup: PopupPanel) -> bool:
	if not is_instance_valid(tree) or not tree.is_inside_tree():
		return false
	var editor_window := tree.get_window()
	var focused := Window.get_focused_window()
	if is_instance_valid(focused) and focused != editor_window and focused != own_popup:
		return true
	var active_popup_id := DisplayServer.window_get_active_popup()
	if active_popup_id != DisplayServer.INVALID_WINDOW_ID:
		if not is_instance_valid(own_popup) or not own_popup.visible:
			return true
		if active_popup_id != own_popup.get_window_id():
			return true
	# Non-popup dialogs can be separate native windows without becoming the
	# active popup or taking focus (e.g. with NO_FOCUS). Inspect the short list
	# of actual application windows rather than scanning the editor Node tree.
	var pointer := DisplayServer.mouse_get_position()
	for window_id: int in DisplayServer.get_window_list():
		if window_id == editor_window.get_window_id():
			continue
		if is_instance_valid(own_popup) and own_popup.visible and window_id == own_popup.get_window_id():
			continue
		var window := instance_from_id(DisplayServer.window_get_attached_instance_id(window_id)) as Window
		if is_instance_valid(window) and window.visible and _window_blocks_hover(window, pointer):
			return true
	# Some Godot configurations embed transient windows. They have no native
	# DisplayServer window ID, so check the embedded windows as well.
	for window in editor_window.get_embedded_subwindows():
		if window != own_popup and window.visible:
			return true
	return false

static func _window_blocks_hover(window: Window, pointer: Vector2i) -> bool:
	# A menu/modal dialog takes precedence even when its rectangle does not
	# intersect the Scene dock. Non-modal windows only block the area they cover.
	if window is Popup or window is AcceptDialog or window.exclusive:
		return true
	return Rect2i(window.position, window.size).has_point(pointer)

## With a non-exclusive popup, Godot can also create its own blank/label
## TreeItem tooltip (notably in 4.8). Hide only that generated native window;
## menus and other editor/addon popups must remain untouched.
func _hide_native_tree_tooltip() -> void:
	if not is_instance_valid(_tree) or not _scene_popup_active():
		return
	for child in _tree.get_children():
		if (
			child is PopupPanel
			and child.visible
			and child.name.begins_with("@PopupPanel@")
			and child.get_child_count() == 1
			and child.get_child(0) is Label
		):
			child.hide()

func _popup_contains_mouse() -> bool:
	if not is_instance_valid(_popup) or not _popup.visible:
		return false
	return Rect2i(_popup.position, _popup.size).has_point(DisplayServer.mouse_get_position())

func _on_script_changed() -> void:
	_document_dirty = true
	# The Script may still be reloading; let the next hover tick rebuild it.

func _on_property_list_changed() -> void:
	_document_dirty = true

func _track_node(node: Node) -> void:
	if is_instance_valid(_active_node) and _active_node.property_list_changed.is_connected(_on_property_list_changed):
		_active_node.property_list_changed.disconnect(_on_property_list_changed)
	if is_instance_valid(_active_script) and _active_script.changed.is_connected(_on_script_changed):
		_active_script.changed.disconnect(_on_script_changed)
	_active_node = node
	_active_script = node.get_script() as Script if is_instance_valid(node) else null
	if is_instance_valid(_active_node):
		_active_node.property_list_changed.connect(_on_property_list_changed)
	if is_instance_valid(_active_script):
		_active_script.changed.connect(_on_script_changed)
	_document_dirty = true

## Narrow capability check: distinguish the local tree from node pickers, remote
## debugger trees, Filesystem and unrelated addon controls. No fixed node paths.
static func find_scene_tree(base: Node) -> Tree:
	for candidate: Node in base.find_children("*", "Tree", true, false):
		if candidate.get_parent().get_class() != "SceneTreeEditor":
			continue
		var parent: Node = candidate.get_parent()
		while parent != null and parent != base:
			if parent.get_class() == "SceneTreeDock":
				return candidate as Tree
			parent = parent.get_parent()
	return null

## Test seam and event-driven refresh. Script parsing happens only on changes;
## regular live updates reuse reflection and compare the resulting tooltip.
func update_item(item: TreeItem, node: Node) -> void:
	if not is_instance_valid(item) or not is_instance_valid(node):
		_restore()
		return
	if not is_instance_valid(_item) or item != _item or node != _active_node:
		_restore()
		_item = item
		_original = item.get_tooltip_text(0)
		_track_node(node)
	elif item.get_tooltip_text(0) not in ["", NATIVE_SCENE_TOOLTIP_PLACEHOLDER, _original]:
		# Godot/another addon replaced the native tooltip while ours was inactive.
		_original = item.get_tooltip_text(0)
	if node.get_script() != _active_script:
		_track_node(node)
	if _document_dirty:
		_parsed_document = Reader.for_scene_script(
			_active_script, _show_contracts, _show_script_docs
		)
		_document_dirty = false
	_elapsed_since_value_check = 0.0
	if _parsed_document.is_empty():
		_hide_popup()
		if is_instance_valid(_item) and _item.get_tooltip_text(0) in ["", NATIVE_SCENE_TOOLTIP_PLACEHOLDER]:
			_item.set_tooltip_text(0, _original)
		_applied = ""
		return
	var document := Reader.for_node(node, _parsed_document)
	var signature := _original + "\n---\n" + var_to_str(document)
	if signature != _popup_signature:
		_rebuild_popup(document, signature)
	if is_instance_valid(_item) and not _original.is_empty():
		_item.set_tooltip_text(0, NATIVE_SCENE_TOOLTIP_PLACEHOLDER)
	_applied = signature
	_show_popup()

static func summary(document: Dictionary) -> String:
	# Kept as a test/debug helper even though the Scene dock now uses the shared
	# rich-text popup. The FileSystem tooltip remains the canonical full view.
	var lines: PackedStringArray = ["Component: " + str(document.get("title", ""))]
	var purpose := str(document.get("description", "")).replace("\n", " ")
	if not purpose.is_empty():
		lines.append(purpose.left(240) + ("…" if purpose.length() > 240 else ""))
	for entry: Dictionary in document.get("properties", []):
		lines.append("%s — %s: %s = %s" % [entry.requirement, entry.name, entry.type, str(entry.get("assignment", "Unassigned"))])
	for section: String in ["signals", "commands"]:
		var entries: Array = document.get(section, [])
		lines.append(("Emitted signals: " if section == "signals" else "Documented public methods: ") + ("None" if entries.is_empty() else ""))
		for entry: Dictionary in entries:
			lines.append(str(entry.signature))
	var text := "\n".join(lines)
	return _wrap(text.left(2200) + ("\n… Full component reference in the FileSystem tooltip." if text.length() > 2200 else ""))

static func _wrap(text: String) -> String:
	var wrapped: PackedStringArray = []
	for line: String in text.split("\n"):
		while line.length() > 88:
			var split_at := line.rfind(" ", 88)
			if split_at <= 0:
				split_at = 88
			wrapped.append(line.left(split_at))
			line = line.substr(split_at).strip_edges()
		wrapped.append(line)
	return "\n".join(wrapped)

func _ensure_popup() -> PopupPanel:
	if is_instance_valid(_popup):
		return _popup
	_popup = PopupPanel.new()
	_popup.name = &"BTSceneComponentTooltipPopup"
	_popup.theme_type_variation = TOOLTIP_PANEL_VARIATION
	_popup.wrap_controls = true
	_popup.set_flag(Window.FLAG_NO_FOCUS, true)
	# Native PopupPanel grabs outside mouse presses by default. A context-menu
	# right-click over the Scene tree must reach Godot rather than dismissing BT.
	_popup.set_flag(Window.FLAG_POPUP, false)
	EditorInterface.get_base_control().add_child(_popup)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TooltipAppearance.style_addon_panel(panel)
	_popup.add_child(panel)
	_popup_body = VBoxContainer.new()
	_popup_body.name = &"Body"
	_popup_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_popup_body)
	return _popup

func _rebuild_popup(document: Dictionary, signature: String) -> void:
	var popup := _ensure_popup()
	if not is_instance_valid(popup) or _popup_body == null:
		return
	for child in _popup_body.get_children():
		_popup_body.remove_child(child)
		child.queue_free()
	if not _original.is_empty():
		var native_header := Label.new()
		native_header.text = _original
		native_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# The PopupPanel starts hidden. Without an explicit content width the
		# native Label is measured at ~one character wide, so its wrapped
		# height is drastically wrong until the first visible layout pass.
		native_header.custom_minimum_size.x = TooltipAppearance.text_content_width(
			640.0 * EditorInterface.get_editor_scale()
		)
		native_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		native_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_popup_body.add_child(native_header)
		_popup_body.add_child(HSeparator.new())
	var content := ComponentTooltip.create_content(document)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_popup_body.add_child(content)
	_popup_signature = signature
	popup.reset_size()

func _show_popup() -> void:
	var popup := _ensure_popup()
	if not is_instance_valid(popup):
		return
	if _popup_lifetime != null:
		if _popup_lifetime.has_popup(popup):
			_popup_lifetime.touch_popup(popup)
		else:
			_popup_lifetime.register_popup(
				popup,
				Rect2i(),
				_tree,
				Callable(),
				Callable(self, "_on_popup_expired"),
				0.30,
				0.04
			)
	# A repeated popup() call during the one-second unsaved-value polling
	# restarts native window layout/placement, even when nothing changed.
	# Keep an already-visible window untouched; update_item() only rebuilds
	# its contents when the document signature actually changes.
	if not popup.visible:
		_position_popup(popup, DisplayServer.mouse_get_position())

func _position_popup(popup: PopupPanel, pointer: Vector2i) -> void:
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

func _hide_popup() -> void:
	if not is_instance_valid(_popup):
		return
	if _popup_lifetime != null and _popup_lifetime.has_popup(_popup):
		_popup_lifetime.unregister_popup(_popup)
	_popup.hide()
	_popup_signature = ""

func _scene_popup_active() -> bool:
	return is_instance_valid(_popup) and _popup.visible and _popup_lifetime != null and _popup_lifetime.has_popup(_popup)

func _on_popup_expired() -> void:
	_restore()

func _restore() -> void:
	_hide_popup()
	if is_instance_valid(_item) and _item.get_tooltip_text(0) in ["", NATIVE_SCENE_TOOLTIP_PLACEHOLDER]:
		_item.set_tooltip_text(0, _original)
	_track_node(null)
	_item = null
	_parsed_document.clear()
	_elapsed_since_value_check = 0.0
	_original = ""
	_applied = ""
