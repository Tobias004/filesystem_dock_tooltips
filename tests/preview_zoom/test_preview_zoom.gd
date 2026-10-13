extends SceneTree

## Regression checks for graphical-preview sizing and transient wheel zoom.
## Run with Godot's editor context because project-local add-on settings use
## EditorInterface.get_editor_settings().

const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const CurveModule := preload("res://addons/better_tooltips/modules/curve_preview_tooltip.gd")
const TooltipAppearance := preload("res://addons/better_tooltips/core/tooltip_appearance.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_metadata_scale_helper()
	_test_default_size_changes_cache_identity()
	_test_curve_module_renders_requested_scale()
	_test_wheel_resizes_visible_session_without_cache_setup()
	await _test_graphical_preview_has_symmetric_padding()
	await _test_popup_window_input_uses_same_zoom_path()
	await _test_long_documentation_becomes_scrollable()
	if _failures.is_empty():
		print("Preview zoom tests: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_metadata_scale_helper() -> void:
	var default_scale := Settings.get_preview_scale_from_metadata({})
	_expect(is_equal_approx(default_scale, 1.0), "Default metadata scale should be 1.0.")
	var scaled := Settings.get_preview_scale_from_metadata({
		Settings.PREVIEW_SCALE_METADATA_KEY: 1.5,
	})
	_expect(is_equal_approx(scaled, 1.5), "Metadata scale 1.5 should be preserved.")




func _test_default_size_changes_cache_identity() -> void:
	var original_percent := Settings.get_preview_size_percent()
	var alternate_percent := 110 if original_percent != 110 else 120
	var cache := Cache.new() as BTTooltipCache
	var original_key := cache.get_cache_key(
		"res://tests/curves/ease_curve.tres",
		Settings.MODULE_CURVE_PREVIEW
	)
	Settings.set_preview_size_percent(alternate_percent)
	var alternate_key := cache.get_cache_key(
		"res://tests/curves/ease_curve.tres",
		Settings.MODULE_CURVE_PREVIEW
	)
	Settings.set_preview_size_percent(original_percent)
	_expect(not original_key.is_empty(), "Default-size cache identity should not be empty.")
	_expect(not alternate_key.is_empty(), "Changed-size cache identity should not be empty.")
	_expect(
		original_key != alternate_key,
		"Changing Default preview size must change the cached preview identity."
	)


func _test_curve_module_renders_requested_scale() -> void:
	var module := CurveModule.new() as BTCurvePreviewTooltip
	var base_100 := VBoxContainer.new()
	root.add_child(base_100)
	module.call(
		"_make_tooltip_for_path",
		"res://tests/curves/ease_curve.tres",
		{Settings.PREVIEW_SCALE_METADATA_KEY: 1.0},
		base_100
	)
	var preview_100 := base_100.get_child(1) as Control
	var size_100 := preview_100.get_combined_minimum_size()

	var base_150 := VBoxContainer.new()
	root.add_child(base_150)
	module.call(
		"_make_tooltip_for_path",
		"res://tests/curves/ease_curve.tres",
		{Settings.PREVIEW_SCALE_METADATA_KEY: 1.5},
		base_150
	)
	var preview_150 := base_150.get_child(1) as Control
	var size_150 := preview_150.get_combined_minimum_size()
	_expect(
		size_150.x > size_100.x * 1.45,
		"Curve preview should rasterize near the requested 150% width."
	)
	_expect(
		size_150.y > size_100.y * 1.45,
		"Curve preview should rasterize near the requested 150% height."
	)
	base_100.queue_free()
	base_150.queue_free()


func _test_wheel_resizes_visible_session_without_cache_setup() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var base := VBoxContainer.new()
	root.add_child(base)
	var section := pipeline.call("_create_section", base) as VBoxContainer
	var image := Image.create(100, 50, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var entry := {
		"texture": texture,
		"size": Vector2i(100, 50),
		"bytes": image.get_data_size(),
	}
	pipeline.call("_set_section_preview", section, entry)
	pipeline.call(
		"_register_preview_session",
		section,
		base,
		null,
		"test_preview",
		"res://tests/curves/ease_curve.tres",
		entry
	)
	var default_percent := Settings.get_preview_size_percent()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.factor = 1.0
	var consumed := pipeline.handle_input(event)
	_expect(consumed, "Wheel input should be consumed while a graphical preview is visible.")
	var rect := section.get_node_or_null(
		"Background/Body/PreviewFrame/PreviewTexture"
	) as TextureRect
	_expect(rect != null, "Graphical preview TextureRect should exist at the shared pipeline path.")
	if rect == null:
		base.queue_free()
		return
	var expected_ratio := float(default_percent + 10) / float(default_percent)
	_expect(
		is_equal_approx(rect.custom_minimum_size.x, 100.0 * expected_ratio),
		"Wheel-up should resize the displayed preview by one 10% step."
	)
	_expect(
		is_equal_approx(rect.custom_minimum_size.y, 50.0 * expected_ratio),
		"Wheel zoom should preserve the preview aspect ratio."
	)
	base.queue_free()


func _test_graphical_preview_has_symmetric_padding() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var base := VBoxContainer.new()
	base.custom_minimum_size.x = 420.0
	root.add_child(base)
	var section := pipeline.call("_create_section", base) as VBoxContainer
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var entry := {
		"texture": texture,
		"size": Vector2i(64, 64),
		"bytes": image.get_data_size(),
	}
	pipeline.call("_set_section_preview", section, entry)
	await process_frame
	var frame := section.get_node_or_null("Background/Body/PreviewFrame") as MarginContainer
	var rect := section.get_node_or_null("Background/Body/PreviewFrame/PreviewTexture") as TextureRect
	var panel := section.get_node_or_null("Background") as PanelContainer
	_expect(frame != null, "Graphical preview should use the shared symmetric MarginContainer.")
	_expect(rect != null, "Graphical preview TextureRect should exist.")
	_expect(panel != null, "Graphical preview panel should exist.")
	if frame != null and rect != null and panel != null:
		var left := rect.position.x
		var top := rect.position.y
		var right := frame.size.x - (rect.position.x + rect.size.x)
		var bottom := frame.size.y - (rect.position.y + rect.size.y)
		_expect(is_equal_approx(left, right), "Rendered graphical left/right padding must match.")
		_expect(is_equal_approx(top, bottom), "Rendered graphical top/bottom padding must match.")
		_expect(is_equal_approx(left, top), "Rendered graphical padding should match on all sides.")
		_expect(is_equal_approx(panel.size.x, frame.size.x), "Preview panel should shrink to the framed image width.")
		_expect(panel.size.x < base.size.x, "A wider native tooltip must not stretch the dark graphical panel.")
		_expect(is_equal_approx(section.size.x, base.size.x), "The graphical section must span the tooltip width so its separator aligns with native content.")
		var separator := section.get_child(0) as HSeparator
		_expect(separator != null, "Graphical preview section should own its separator.")
		if separator != null:
			_expect(is_equal_approx(separator.size.x, section.size.x), "Graphical preview separator must span the full tooltip width.")
	base.queue_free()


func _test_popup_window_input_uses_same_zoom_path() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var popup := PopupPanel.new()
	popup.wrap_controls = true
	root.add_child(popup)
	var base := VBoxContainer.new()
	popup.add_child(base)
	var section := pipeline.call("_create_section", base) as VBoxContainer
	var image := Image.create(100, 50, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var entry := {
		"texture": texture,
		"size": Vector2i(100, 50),
		"bytes": image.get_data_size(),
	}
	pipeline.call("_set_section_preview", section, entry)
	pipeline.call(
		"_register_preview_session",
		section,
		base,
		popup,
		"test_preview",
		"res://tests/curves/ease_curve.tres",
		entry
	)
	popup.popup()
	await process_frame
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.factor = 1.0
	popup.window_input.emit(event)
	await process_frame
	var rect := section.get_node_or_null(
		"Background/Body/PreviewFrame/PreviewTexture"
	) as TextureRect
	_expect(rect != null, "Popup graphical preview TextureRect should survive wheel zoom.")
	if rect != null:
		_expect(rect.custom_minimum_size.x > 100.0, "Wheel input emitted by the tooltip PopupPanel must zoom the same preview session.")
	popup.queue_free()


func _test_long_documentation_becomes_scrollable() -> void:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size.x = 280.0
	var lines := PackedStringArray()
	for index: int in range(120):
		lines.append("Documentation line %d with enough text to require vertical space." % index)
	label.text = "\n".join(lines)
	root.add_child(label)
	TooltipAppearance.limit_rich_text_height(label)
	await process_frame
	await process_frame
	_expect(label.scroll_active, "Very long documentation should become vertically scrollable.")
	_expect(not label.fit_content, "Scrollable documentation must stop expanding to full content height.")
	_expect(label.custom_minimum_size.y > 0.0, "Scrollable documentation should receive a bounded height.")
	label.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
