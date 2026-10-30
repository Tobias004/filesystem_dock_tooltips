@tool
class_name BTTooltipLifetimeManager
extends RefCounted

## Owns the short-lived hover/drag sessions of add-on PopupPanels.
## Individual sources remain responsible for resolving their hovered item and
## for destroying their own popup. This manager never owns source integrations.

var _sessions: Dictionary = {}

func register_popup(
	popup: PopupPanel,
	trigger_rect: Rect2i,
	source_control: Control,
	source_hover_callback: Callable,
	exit_callback: Callable,
	grace_seconds: float = 0.30,
	poll_seconds: float = 0.04
) -> void:
	if not is_instance_valid(popup):
		return
	unregister_popup(popup)
	var popup_id := popup.get_instance_id()
	var timer := Timer.new()
	timer.name = &"BTTooltipLifetimeTimer"
	timer.wait_time = poll_seconds
	timer.one_shot = false
	popup.add_child(timer)
	var timer_callback := Callable(self, "_poll_popup").bind(popup_id)
	var input_callback := Callable(self, "_on_popup_input").bind(popup_id)
	timer.timeout.connect(timer_callback)
	popup.window_input.connect(input_callback)
	_sessions[popup_id] = {
		"popup": weakref(popup),
		"source": weakref(source_control) if is_instance_valid(source_control) else null,
		"trigger_rect": trigger_rect,
		"source_hover_callback": source_hover_callback,
		"exit_callback": exit_callback,
		"last_inside_msec": Time.get_ticks_msec(),
		"drag_active": false,
		"grace_msec": roundi(grace_seconds * 1000.0),
		"timer": weakref(timer),
		"timer_callback": timer_callback,
		"input_callback": input_callback,
	}
	timer.start()

func unregister_popup(popup: PopupPanel) -> void:
	if is_instance_valid(popup):
		_drop_session(popup.get_instance_id())

func clear() -> void:
	for popup_id in _sessions.keys():
		_drop_session(int(popup_id))

func has_popup(popup: PopupPanel) -> bool:
	return is_instance_valid(popup) and _sessions.has(popup.get_instance_id())

func touch_popup(popup: PopupPanel) -> void:
	if not is_instance_valid(popup):
		return
	var popup_id := popup.get_instance_id()
	if _sessions.has(popup_id):
		var session: Dictionary = _sessions[popup_id]
		session["last_inside_msec"] = Time.get_ticks_msec()
		_sessions[popup_id] = session

func _drop_session(popup_id: int) -> void:
	if not _sessions.has(popup_id):
		return
	var session: Dictionary = _sessions[popup_id]
	# Remove first: callbacks may close/recreate a popup recursively.
	_sessions.erase(popup_id)
	var popup_ref := session.get("popup", null) as WeakRef
	var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
	var input_callback: Callable = session.get("input_callback", Callable())
	if is_instance_valid(popup) and input_callback.is_valid() and popup.window_input.is_connected(input_callback):
		popup.window_input.disconnect(input_callback)
	var timer_ref := session.get("timer", null) as WeakRef
	var timer := timer_ref.get_ref() as Timer if timer_ref != null else null
	if is_instance_valid(timer):
		timer.stop()
		var timer_callback: Callable = session.get("timer_callback", Callable())
		if timer_callback.is_valid() and timer.timeout.is_connected(timer_callback):
			timer.timeout.disconnect(timer_callback)
		timer.queue_free()

func _on_popup_input(event: InputEvent, popup_id: int) -> void:
	if not _sessions.has(popup_id) or not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var session: Dictionary = _sessions[popup_id]
	session["drag_active"] = mouse_event.pressed
	session["last_inside_msec"] = Time.get_ticks_msec()
	_sessions[popup_id] = session

func _poll_popup(popup_id: int) -> void:
	if not _sessions.has(popup_id):
		return
	var session: Dictionary = _sessions[popup_id]
	var popup_ref := session.get("popup", null) as WeakRef
	var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
	if not is_instance_valid(popup) or not popup.visible:
		_expire_popup(popup_id, session)
		return
	var now := Time.get_ticks_msec()
	if bool(session.get("drag_active", false)):
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			session["last_inside_msec"] = now
			_sessions[popup_id] = session
			return
		session["drag_active"] = false
		session["last_inside_msec"] = now
	var pointer := DisplayServer.mouse_get_position()
	var popup_rect := Rect2i(popup.position, popup.size).grow(2)
	var in_popup := popup_rect.has_point(pointer)
	var in_source := false
	var source_ref := session.get("source", null) as WeakRef
	var source := source_ref.get_ref() as Control if source_ref != null else null
	if source_ref != null:
		# The source control can disappear when a third-party IDE rebuilds tabs.
		if not is_instance_valid(source) or not source.is_inside_tree():
			_expire_popup(popup_id, session)
			return
		var local_mouse := source.get_local_mouse_position()
		in_source = Rect2(Vector2.ZERO, source.size).has_point(local_mouse)
	else:
		var trigger_rect := session.get("trigger_rect", Rect2i()) as Rect2i
		in_source = trigger_rect.grow(2).has_point(pointer)
	if in_popup or in_source:
		session["last_inside_msec"] = now
		_sessions[popup_id] = session
		if in_source:
			var source_callback: Callable = session.get("source_hover_callback", Callable())
			if source_callback.is_valid():
				source_callback.call()
		return
	_sessions[popup_id] = session
	if now - int(session.get("last_inside_msec", now)) >= int(session.get("grace_msec", 300)):
		_expire_popup(popup_id, session)

func _expire_popup(popup_id: int, session: Dictionary) -> void:
	var exit_callback: Callable = session.get("exit_callback", Callable())
	_drop_session(popup_id)
	if exit_callback.is_valid():
		exit_callback.call()
