extends SceneTree

## Integration regression for a script-preload constant, a Sky Resource constant,
## and Godot's native help content being taller than the available screen.
const Navigation = preload("res://addons/better_tooltips/modules/script_editor_navigation_tooltip.gd")
const CodeTooltips = preload("res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd")
const Pipeline = preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Cache = preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const SkyModule = preload("res://addons/better_tooltips/modules/sky_preview_tooltip.gd")
const Settings = preload("res://addons/better_tooltips/tooltip_settings.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await create_timer(0.5).timeout
	var filesystem := EditorInterface.get_resource_filesystem()
	var scan_deadline := Time.get_ticks_msec() + 12000
	while filesystem != null and filesystem.is_scanning() and Time.get_ticks_msec() < scan_deadline:
		await process_frame
	var script_path := "res://tests/code_tooltips/code_tooltip_showcase.gd"
	var source := FileAccess.get_file_as_string(script_path)
	EditorInterface.edit_script(load(script_path) as Script)
	for _frame in range(8):
		await process_frame
	var cache: BTTooltipCache = Cache.new()
	cache.setup(EditorInterface.get_base_control())
	var pipeline: BTTooltipPipeline = Pipeline.new()
	pipeline.setup(cache, EditorInterface.get_base_control())
	pipeline.add_module(Settings.MODULE_SKY_PREVIEW, "Sky", SkyModule.new())
	var navigation: BTScriptEditorNavigationTooltip = Navigation.new()
	navigation.setup(EditorInterface.get_script_editor(), pipeline)
	var target := navigation._resolve_member_from_source(source, script_path, "TargetScript")
	if str(target.get("title", "")).is_empty() or (target.get("documentation", {}) as Dictionary).is_empty():
		_finish_failure("Script-preload constant did not return referenced class documentation.", navigation, pipeline, cache)
		return
	var sky := navigation._resolve_member_from_source(source, script_path, "TEST_SKY")
	print("TEST sky context ", pipeline._get_path_preview_context("res://tests/skies/sunset_sky.tres"), "  resolved ", sky)
	if str(sky.get("resource_path", "")) != "res://tests/skies/sunset_sky.tres":
		_finish_failure("Sky constant did not return its resource path.", navigation, pipeline, cache)
		return
	var outline := Tree.new()
	outline.hide_root = true
	outline.custom_minimum_size = Vector2(400, 140)
	EditorInterface.get_base_control().add_child(outline)
	var root := outline.create_item()
	var item := outline.create_item(root)
	item.set_text(0, "TEST_SKY")
	item.set_metadata(0, {&"type": &"const", &"modifier": &""})
	navigation._watch_control(outline, &"quill_outline_tree")
	await process_frame
	var found := false
	var hover := {}
	for y in range(2, 130, 2):
		hover = navigation._resolve_outline_hover(outline, Vector2(35, y))
		if not hover.is_empty():
			found = true
			break
	if not found:
		_finish_failure("The Tree outline did not resolve TEST_SKY.", navigation, pipeline, cache)
		return
	var entry := (navigation.get("_watched_controls") as Dictionary)[outline.get_instance_id()] as Dictionary
	navigation._show_documentation_popup(outline, entry, sky)
	var popup: PopupPanel = null
	var image_ready := false
	var until := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < until:
		await process_frame
		entry = (navigation.get("_watched_controls") as Dictionary).get(outline.get_instance_id(), {}) as Dictionary
		var ref := entry.get("popup_reference", null) as WeakRef
		popup = ref.get_ref() as PopupPanel if ref != null else null
		if popup != null:
			var preview := popup.find_child("PreviewTexture", true, false) as TextureRect
			if preview != null and preview.texture != null:
				image_ready = true
				break
	if not image_ready:
		_finish_failure("Sky outline did not produce a rendered preview.", navigation, pipeline, cache)
		return
	navigation.cancel_active_tooltips()
	await process_frame
	var code: BTCodeEditorDocumentationTooltip = CodeTooltips.new()
	var tall_popup := PopupPanel.new()
	tall_popup.theme_type_variation = &"TooltipPanel"
	EditorInterface.get_base_control().add_child(tall_popup)
	var long_text := RichTextLabel.new()
	long_text.theme_type_variation = &"EditorHelpBitContent"
	long_text.custom_minimum_size.x = 460
	long_text.fit_content = true
	long_text.text = ("A long tooltip line for scrolling.\n").repeat(120)
	tall_popup.add_child(long_text)
	tall_popup.position = Vector2i(200, 650)
	tall_popup.popup()
	await process_frame
	code._schedule_native_tooltip_fit(tall_popup, long_text)
	for i in range(4): await process_frame
	var usable := DisplayServer.screen_get_usable_rect(tall_popup.current_screen)
	print("LONG sizes ",long_text.get_content_height(), " fit ",long_text.fit_content," scroll ",long_text.scroll_active," label_size ",long_text.size," popup ",tall_popup.size," pos ", tall_popup.position, " usable ", usable, " visible ",tall_popup.visible)
	if long_text.fit_content or not long_text.scroll_active or tall_popup.position.y + tall_popup.size.y > usable.end.y:
		_finish_failure("Tall help popup is not scrollable and screen-clamped.", navigation, pipeline, cache)
		return
	tall_popup.queue_free()
	outline.queue_free()
	navigation.cleanup()
	pipeline.cleanup()
	cache.cleanup()
	print("Navigation script/Sky and native long-text UI tests: PASS")
	quit(0)

func _finish_failure(message: String, navigation: BTScriptEditorNavigationTooltip, pipeline: BTTooltipPipeline, cache: BTTooltipCache) -> void:
	push_error(message)
	navigation.cleanup()
	pipeline.cleanup()
	cache.cleanup()
	quit(1)
