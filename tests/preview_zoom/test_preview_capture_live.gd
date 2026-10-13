extends SceneTree

## Live graphical regression test for a real Mesh preview. This requires a real
## window/rendering backend (X11/Xvfb is sufficient) so SubViewport pixels can be
## inspected. It verifies both capture-edge symmetry and PopupPanel wheel routing.

const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const MeshModule := preload("res://addons/better_tooltips/modules/mesh_preview_tooltip.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(1.0).timeout
	var cache := Cache.new() as BTTooltipCache
	cache.setup(EditorInterface.get_base_control())
	cache.clear()
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.setup(cache, EditorInterface.get_base_control())
	pipeline.add_module(
		Settings.MODULE_MESH_PREVIEW,
		"Mesh",
		MeshModule.new() as EditorResourceTooltipPlugin
	)

	var popup := PopupPanel.new()
	popup.wrap_controls = true
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	EditorInterface.get_base_control().add_child(popup)
	var base := VBoxContainer.new()
	popup.add_child(base)
	var title := Label.new()
	title.text = "box_mesh.tres\nType: BoxMesh"
	base.add_child(title)
	popup.position = Vector2i(250, 120)
	popup.popup()
	pipeline.append_preview_for_path(
		"res://tests/meshes/box_mesh.tres",
		base,
		popup,
		{"source": "live_capture_test"}
	)

	var section: VBoxContainer = null
	var rect: TextureRect = null
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		for child: Node in base.get_children():
			if child is VBoxContainer:
				var candidate := child.get_node_or_null(
					"Background/Body/PreviewFrame/PreviewTexture"
				) as TextureRect
				if candidate != null:
					section = child as VBoxContainer
					rect = candidate
					break
		if rect != null:
			break
	if rect == null or section == null:
		_fail("Real Mesh preview did not appear.", popup, pipeline)
		return

	await process_frame
	await process_frame
	var initial_width := rect.custom_minimum_size.x
	if not _margins_are_symmetric(_alpha_margins(rect.texture)):
		_fail("Initial captured Mesh preview margins are not symmetric.", popup, pipeline)
		return
	if not _outer_padding_is_symmetric(section):
		_fail("Initial visible pipeline padding is not symmetric.", popup, pipeline)
		return

	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.factor = 1.0
	popup.window_input.emit(wheel_up)
	await create_timer(0.8).timeout
	rect = section.get_node_or_null(
		"Background/Body/PreviewFrame/PreviewTexture"
	) as TextureRect
	if rect == null or rect.custom_minimum_size.x <= initial_width:
		_fail("Popup-owned wheel input did not enlarge the Mesh preview.", popup, pipeline)
		return
	if not _margins_are_symmetric(_alpha_margins(rect.texture)):
		_fail("Transient zoomed Mesh capture margins are not symmetric.", popup, pipeline)
		return
	if not _outer_padding_is_symmetric(section):
		_fail("Visible pipeline padding changed asymmetrically after zoom.", popup, pipeline)
		return

	popup.queue_free()
	pipeline.cleanup()
	print("Live preview capture/input test: PASS")
	quit(0)


func _alpha_margins(texture: Texture2D) -> Vector4i:
	if texture == null:
		return Vector4i(-1, -1, -1, -1)
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Vector4i(-1, -1, -1, -1)
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.1:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0 or max_y < 0:
		return Vector4i(-1, -1, -1, -1)
	return Vector4i(
		min_x,
		min_y,
		image.get_width() - 1 - max_x,
		image.get_height() - 1 - max_y
	)


func _margins_are_symmetric(margins: Vector4i) -> bool:
	return (
		margins.x >= 0
		and margins.x == margins.z
		and margins.y == margins.w
		and margins.x == margins.y
	)


func _outer_padding_is_symmetric(section: VBoxContainer) -> bool:
	var frame := section.get_node_or_null("Background/Body/PreviewFrame") as MarginContainer
	var rect := section.get_node_or_null(
		"Background/Body/PreviewFrame/PreviewTexture"
	) as TextureRect
	if frame == null or rect == null:
		return false
	var left := rect.position.x
	var top := rect.position.y
	var right := frame.size.x - (rect.position.x + rect.size.x)
	var bottom := frame.size.y - (rect.position.y + rect.size.y)
	return (
		is_equal_approx(left, right)
		and is_equal_approx(top, bottom)
		and is_equal_approx(left, top)
	)


func _fail(message: String, popup: PopupPanel, pipeline: BTTooltipPipeline) -> void:
	push_error(message)
	if is_instance_valid(popup):
		popup.queue_free()
	pipeline.cleanup()
	quit(1)
