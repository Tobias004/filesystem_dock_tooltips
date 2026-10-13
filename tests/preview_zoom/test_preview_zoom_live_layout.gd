extends SceneTree
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var popup := PopupPanel.new()
	popup.wrap_controls = true
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	EditorInterface.get_base_control().add_child(popup)
	var base := VBoxContainer.new()
	popup.add_child(base)
	var title := Label.new()
	title.text = "Title for test"
	base.add_child(title)
	var section := pipeline.call("_create_section", base) as VBoxContainer
	var image := Image.create(300, 300, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var entry := {"texture": texture, "size": Vector2i(300,300), "bytes": image.get_data_size()}
	pipeline.call("_set_section_preview", section, entry)
	pipeline.call("_register_preview_session", section, base, popup, "test", "res://tests/curves/ease_curve.tres", entry)
	popup.position = Vector2i(200,100)
	popup.reset_size()
	popup.popup()
	await process_frame
	await process_frame
	var session := pipeline.get("_preview_sessions")[section.get_instance_id()] as Dictionary
	var old_rect := pipeline.call("_get_session_tooltip_rect", session) as Rect2i
	var max_percent := int(pipeline.call("_get_session_max_zoom_percent", session))
	if max_percent <= 100 or max_percent > 250:
		push_error("Dynamic graphical zoom limit should stay above default and at/below hard maximum on the test screen.")
		quit(1)
		return
	var rel := Vector2(0.35,0.55)
	var mouse := Vector2(old_rect.position) + Vector2(float(old_rect.size.x)*rel.x,float(old_rect.size.y)*rel.y)
	pipeline.call("_warp_mouse_to_screen_position", Vector2i(mouse))
	await process_frame
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.factor = 1.0
	popup.window_input.emit(wheel_up)
	await process_frame
	await process_frame
	session = pipeline.get("_preview_sessions")[section.get_instance_id()] as Dictionary
	var new_rect := pipeline.call("_get_session_tooltip_rect", session) as Rect2i
	var new_mouse := DisplayServer.mouse_get_position()
	var new_rel := Vector2(float(new_mouse.x-new_rect.position.x)/float(new_rect.size.x), float(new_mouse.y-new_rect.position.y)/float(new_rect.size.y))
	if absf(new_rel.x-rel.x) > 0.03 or absf(new_rel.y-rel.y) > 0.03:
		push_error("Relative pointer position not preserved while growing.")
		quit(1)
		return

	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	wheel_down.factor = 1.0
	popup.window_input.emit(wheel_down)
	await process_frame
	await process_frame
	session = pipeline.get("_preview_sessions")[section.get_instance_id()] as Dictionary
	var shrink_rect := pipeline.call("_get_session_tooltip_rect", session) as Rect2i
	var shrink_mouse := DisplayServer.mouse_get_position()
	var shrink_rel := Vector2(
		float(shrink_mouse.x - shrink_rect.position.x) / float(shrink_rect.size.x),
		float(shrink_mouse.y - shrink_rect.position.y) / float(shrink_rect.size.y)
	)
	if shrink_rect.size.x >= new_rect.size.x or shrink_rect.size.y >= new_rect.size.y:
		push_error("Tooltip should shrink again after reversing one wheel step.")
		quit(1)
		return
	if absf(shrink_rel.x-rel.x) > 0.03 or absf(shrink_rel.y-rel.y) > 0.03:
		push_error("Relative pointer position not preserved while shrinking.")
		quit(1)
		return
	popup.queue_free()
	print("Live preview layout/pointer test: PASS")
	quit(0)
