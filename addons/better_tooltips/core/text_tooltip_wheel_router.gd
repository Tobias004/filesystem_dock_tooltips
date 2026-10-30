@tool
class_name BTTextTooltipWheelRouter
extends RefCounted

## Routes mouse-wheel input to the text area belonging to a visible BT popup.
## Owns only the external-popup signal registrations, not popup lifetime.
## The pipeline retains its public registration facade so existing integrations
## do not need to depend on this component.

var _external_text_popups: Dictionary = {}

func register_external_text_popup(
	popup: PopupPanel, root: Control, trigger: Control, trigger_rect: Rect2i
) -> void:
	if not is_instance_valid(popup) or not is_instance_valid(root) or not is_instance_valid(trigger):
		return
	var popup_id := popup.get_instance_id()
	if _external_text_popups.has(popup_id):
		unregister_external_text_popup(popup)
	var callback := Callable(self, "_on_external_text_popup_window_input").bind(popup_id)
	popup.window_input.connect(callback)
	_external_text_popups[popup_id] = {
		"popup": weakref(popup),
		"root": weakref(root),
		"trigger": weakref(trigger),
		"trigger_rect": trigger_rect,
		"callback": callback,
	}

func unregister_external_text_popup(popup: PopupPanel) -> void:
	if not is_instance_valid(popup):
		return
	var popup_id := popup.get_instance_id()
	var entry: Dictionary = _external_text_popups.get(popup_id, {}) as Dictionary
	if entry.is_empty():
		return
	var callback: Callable = entry.get("callback", Callable())
	if callback.is_valid() and popup.window_input.is_connected(callback):
		popup.window_input.disconnect(callback)
	_external_text_popups.erase(popup_id)

func clear() -> void:
	for popup_id_value in _external_text_popups.keys():
		var entry: Dictionary = _external_text_popups[popup_id_value]
		var popup_ref := entry.get("popup", null) as WeakRef
		var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
		if is_instance_valid(popup):
			unregister_external_text_popup(popup)
	_external_text_popups.clear()

func _on_external_text_popup_window_input(event: InputEvent, popup_id: int) -> void:
	var entry: Dictionary = _external_text_popups.get(popup_id, {}) as Dictionary
	if entry.is_empty():
		return
	if route_to_session(event, entry):
		var popup_ref := entry.get("popup", null) as WeakRef
		var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
		if is_instance_valid(popup):
			popup.set_input_as_handled()

func route_external(event: InputEvent) -> bool:
	if not _is_wheel_press(event):
		return false
	for popup_id_value in _external_text_popups.keys():
		var popup_id := int(popup_id_value)
		var entry: Dictionary = _external_text_popups.get(popup_id, {}) as Dictionary
		var popup_ref := entry.get("popup", null) as WeakRef
		var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
		if not is_instance_valid(popup):
			_external_text_popups.erase(popup_id)
			continue
		if route_to_session(event, entry):
			return true
	return false

func route_to_session(event: InputEvent, session: Dictionary) -> bool:
	if not _is_wheel_press(event):
		return false
	var wheel := event as InputEventMouseButton
	var popup_ref := session.get("popup", null) as WeakRef
	var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
	if not is_instance_valid(popup) or not popup.visible:
		return false
	var pointer := DisplayServer.mouse_get_position()
	var popup_rect := Rect2i(popup.position, popup.size).grow(2)
	var trigger_value: Variant = session.get("trigger_rect", Rect2i())
	var trigger_rect := trigger_value as Rect2i if trigger_value is Rect2i else Rect2i()
	if not popup_rect.has_point(pointer) and not trigger_rect.has_point(pointer):
		return false
	var root_ref := session.get("root", null) as WeakRef
	var root := root_ref.get_ref() as Control if root_ref != null else null
	if not is_instance_valid(root):
		return false
	var label := find_scrollable_rich_text(root)
	if label == null:
		return false
	var bar := label.get_v_scroll_bar()
	if bar == null or not bar.visible:
		return false
	var direction := -1.0 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	var amount := maxf(36.0 * EditorInterface.get_editor_scale(), bar.page * 0.09)
	bar.value = clampf(
		bar.value + direction * amount * maxf(1.0, absf(wheel.factor)),
		bar.min_value,
		maxf(bar.min_value, bar.max_value - bar.page)
	)
	return true

func _is_wheel_press(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mouse_event := event as InputEventMouseButton
	return mouse_event.pressed and mouse_event.button_index in [
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	]

func find_scrollable_rich_text(root: Node) -> RichTextLabel:
	if root == null:
		return null
	# When a script shows both class documentation and its source, wheel and
	# navigation keys should scroll the section actually under the pointer.
	var pointer := Vector2(DisplayServer.mouse_get_position())
	for candidate: Node in root.find_children("*", "RichTextLabel", true, false):
		var hovered := candidate as RichTextLabel
		if hovered == null:
			continue
		var screen_rect := Rect2(hovered.get_screen_transform().origin, hovered.size)
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
	for preview_name: StringName in [&"MethodSourcePreview", &"MarkdownPreview", &"TextPreview"]:
		var named := root.find_child(String(preview_name), true, false) as RichTextLabel
		if named != null and named.scroll_active and not named.fit_content:
			return named
	for candidate: Node in root.find_children("*", "RichTextLabel", true, false):
		var label := candidate as RichTextLabel
		if label != null and label.scroll_active and not label.fit_content:
			return label
	return null

