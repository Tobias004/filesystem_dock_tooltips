extends SceneTree

const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const StyleBoxModule := preload("res://addons/better_tooltips/modules/stylebox_preview_tooltip.gd")
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
		Settings.MODULE_STYLEBOX_PREVIEW,
		"StyleBox",
		StyleBoxModule.new() as EditorResourceTooltipPlugin
	)

	var first := await _show_preview(pipeline)
	if first.is_empty():
		_fail("First StyleBox preview did not appear.", pipeline)
		return
	var first_rect := first.get("rect") as TextureRect
	if not _margins_are_symmetric(_alpha_margins(first_rect.texture)):
		_fail("Fresh StyleBox capture is clipped/asymmetric.", pipeline)
		return
	var first_popup := first.get("popup") as PopupPanel
	first_popup.queue_free()
	await process_frame

	var second := await _show_preview(pipeline)
	if second.is_empty():
		_fail("Cached StyleBox preview did not appear.", pipeline)
		return
	var second_rect := second.get("rect") as TextureRect
	if not _margins_are_symmetric(_alpha_margins(second_rect.texture)):
		_fail("Cached StyleBox capture is clipped/asymmetric.", pipeline)
		return
	var second_section := second.get("section") as VBoxContainer
	if not _outer_padding_is_symmetric(second_section):
		_fail("Cached StyleBox outer padding is asymmetric.", pipeline)
		return
	var second_popup := second.get("popup") as PopupPanel
	second_popup.queue_free()
	pipeline.cleanup()
	print("Live StyleBox cache/capture test: PASS")
	quit(0)

func _show_preview(pipeline: BTTooltipPipeline) -> Dictionary:
	var popup := PopupPanel.new()
	popup.wrap_controls = true
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	EditorInterface.get_base_control().add_child(popup)
	var base := VBoxContainer.new()
	base.custom_minimum_size.x = 600.0
	popup.add_child(base)
	var title := Label.new()
	title.text = "StyleBox header deliberately wider than preview"
	base.add_child(title)
	popup.position = Vector2i(180, 100)
	popup.popup()
	pipeline.append_preview_for_path(
		"res://tests/styleboxes/rounded_panel.tres",
		base,
		popup,
		{"source": "live_stylebox_cache_test"}
	)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		for child: Node in base.get_children():
			if child is VBoxContainer:
				var rect := child.get_node_or_null("Background/Body/PreviewFrame/PreviewTexture") as TextureRect
				if rect != null:
					await process_frame
					await process_frame
					return {"popup": popup, "base": base, "section": child, "rect": rect}
	popup.queue_free()
	return {}

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
	return Vector4i(min_x, min_y, image.get_width() - 1 - max_x, image.get_height() - 1 - max_y)

func _margins_are_symmetric(margins: Vector4i) -> bool:
	return margins.x >= 0 and margins.x == margins.z and margins.y == margins.w and margins.x == margins.y

func _outer_padding_is_symmetric(section: VBoxContainer) -> bool:
	var frame := section.get_node_or_null("Background/Body/PreviewFrame") as MarginContainer
	var rect := section.get_node_or_null("Background/Body/PreviewFrame/PreviewTexture") as TextureRect
	if frame == null or rect == null:
		return false
	var left := rect.position.x
	var top := rect.position.y
	var right := frame.size.x - (rect.position.x + rect.size.x)
	var bottom := frame.size.y - (rect.position.y + rect.size.y)
	return is_equal_approx(left, right) and is_equal_approx(top, bottom) and is_equal_approx(left, top)

func _fail(message: String, pipeline: BTTooltipPipeline) -> void:
	push_error(message)
	pipeline.cleanup()
	quit(1)
