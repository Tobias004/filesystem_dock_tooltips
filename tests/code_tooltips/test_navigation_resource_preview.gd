extends SceneTree

## Editor-side regression coverage for Quill/Script-IDE graphical outline hovers.
## It opens the Code Tooltip showcase as the current script, creates outline
## controls with the same metadata shape used by both plugins and verifies that
## the navigation integration resolves the hovered Resource symbol to the shared
## preview pipeline and actually inserts a graphical preview into its popup.

const NavigationTooltip := preload(
	"res://addons/better_tooltips/modules/script_editor_navigation_tooltip.gd"
)
const Pipeline := preload(
	"res://addons/better_tooltips/core/tooltip_pipeline.gd"
)
const Cache := preload(
	"res://addons/better_tooltips/core/tooltip_cache.gd"
)
const MaterialModule := preload(
	"res://addons/better_tooltips/modules/material_preview_tooltip.gd"
)
const Settings := preload(
	"res://addons/better_tooltips/tooltip_settings.gd"
)

const SHOWCASE_PATH := "res://tests/code_tooltips/code_tooltip_showcase.gd"
const EXPECTED_RESOURCE := "res://tests/materials/blue_metal_material_3d.tres"
const SYMBOL := "MATERIAL_ALIAS_2"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var filesystem := EditorInterface.get_resource_filesystem()
	var scan_deadline := Time.get_ticks_msec() + 10000
	while filesystem != null and filesystem.is_scanning() and Time.get_ticks_msec() < scan_deadline:
		await process_frame
	var script := load(SHOWCASE_PATH) as Script
	if script == null:
		_fail("Could not load Code Tooltip showcase script.")
		return
	EditorInterface.edit_script(script)
	for _frame: int in range(4):
		await process_frame

	var cache := Cache.new() as BTTooltipCache
	cache.setup(EditorInterface.get_base_control())
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.setup(cache, EditorInterface.get_base_control())
	pipeline.add_module(
		Settings.MODULE_MATERIAL_PREVIEW,
		"Material",
		MaterialModule.new() as EditorResourceTooltipPlugin
	)

	var navigation := NavigationTooltip.new() as BTScriptEditorNavigationTooltip
	navigation.setup(EditorInterface.get_script_editor(), pipeline)
	var direct := navigation.call(
		"_resolve_member_from_source",
		script.source_code,
		SHOWCASE_PATH,
		SYMBOL
	) as Dictionary
	if str(direct.get("resource_path", "")) != EXPECTED_RESOURCE:
		_fail("Navigation resolver did not resolve the Resource alias.", navigation, pipeline)
		return

	var undocumented := navigation.call(
		"_resolve_member_from_source",
		"class_name NavigationResourceFixture\nconst GRAPHIC: Material = preload(\"%s\")\n" % EXPECTED_RESOURCE,
		"res://tests/code_tooltips/navigation_resource_fixture.gd",
		"GRAPHIC"
	) as Dictionary
	if (
		str(undocumented.get("resource_path", "")) != EXPECTED_RESOURCE
		or (undocumented.get("documentation", {}) as Dictionary).size() != 0
		or str(undocumented.get("title", "")).is_empty()
	):
		_fail("Undocumented graphical outline members should still resolve to a titled preview.", navigation, pipeline)
		return

	var quill_tree := Tree.new()
	quill_tree.hide_root = true
	quill_tree.custom_minimum_size = Vector2(320, 100)
	EditorInterface.get_base_control().add_child(quill_tree)
	var quill_root := quill_tree.create_item()
	var quill_item := quill_tree.create_item(quill_root)
	quill_item.set_text(0, SYMBOL)
	quill_item.set_metadata(0, {&"type": &"const", &"modifier": &""})

	var script_ide_outline := ItemList.new()
	script_ide_outline.custom_minimum_size = Vector2(320, 100)
	EditorInterface.get_base_control().add_child(script_ide_outline)
	script_ide_outline.add_item(SYMBOL)
	script_ide_outline.set_item_metadata(0, {&"type": &"const", &"modifier": &""})
	await process_frame
	var quill_symbol := quill_item.get_text(0)
	var script_ide_symbol := navigation.call(
		"_outline_symbol_from_label",
		script_ide_outline.get_item_text(0),
		"const"
	) as String
	if quill_symbol != SYMBOL or script_ide_symbol != SYMBOL:
		_fail("Quill/Script-IDE outline symbol extraction changed unexpectedly.", navigation, pipeline)
		return
	var quill_hover := _find_tree_hover(navigation, quill_tree)
	if str((quill_hover.get("resolved", {}) as Dictionary).get("resource_path", "")) != EXPECTED_RESOURCE:
		_fail("Quill-shaped outline hover did not resolve the graphical Resource.", navigation, pipeline)
		return
	var script_ide_hover := _find_item_list_hover(navigation, script_ide_outline)
	if str((script_ide_hover.get("resolved", {}) as Dictionary).get("resource_path", "")) != EXPECTED_RESOURCE:
		_fail("Script-IDE-shaped outline hover did not resolve the graphical Resource.", navigation, pipeline)
		return

	# Verify the custom outline popup really reuses the central graphical pipeline.
	navigation.call("_watch_control", quill_tree, &"quill_outline_tree")
	quill_tree.warp_mouse(Vector2(30, 20))
	await process_frame
	var watched := navigation.get("_watched_controls") as Dictionary
	var entry := watched[quill_tree.get_instance_id()] as Dictionary
	entry["hover_key"] = str(quill_hover.get("hover_key", ""))
	entry["resolved"] = quill_hover.get("resolved", {})
	watched[quill_tree.get_instance_id()] = entry
	navigation.set("_watched_controls", watched)
	navigation.call(
		"_show_documentation_popup",
		quill_tree,
		entry,
		quill_hover.get("resolved", {}) as Dictionary
	)

	var deadline := Time.get_ticks_msec() + 8000
	var preview_found := false
	var popup: PopupPanel = null
	var preview: TextureRect = null
	while Time.get_ticks_msec() < deadline:
		await process_frame
		watched = navigation.get("_watched_controls") as Dictionary
		entry = watched.get(quill_tree.get_instance_id(), {}) as Dictionary
		var popup_ref := entry.get("popup_reference", null) as WeakRef
		popup = popup_ref.get_ref() as PopupPanel if popup_ref != null else null
		if is_instance_valid(popup):
			preview = popup.find_child("PreviewTexture", true, false) as TextureRect
			if preview != null and preview.texture != null:
				preview_found = true
				break
	if not preview_found or popup == null or preview == null:
		_fail("Navigation popup did not receive the shared graphical Resource preview.", navigation, pipeline)
		return
	var initial_width := preview.custom_minimum_size.x
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.factor = 1.0
	popup.window_input.emit(wheel_up)
	await create_timer(0.8).timeout
	preview = popup.find_child("PreviewTexture", true, false) as TextureRect
	if preview == null or preview.custom_minimum_size.x <= initial_width:
		_fail("Navigation graphical popup did not reuse shared wheel zoom.", navigation, pipeline)
		return

	navigation.cleanup()
	pipeline.cleanup()
	cache.cleanup()
	quill_tree.queue_free()
	script_ide_outline.queue_free()
	print("Navigation graphical Resource preview tests: PASS")
	quit(0)


func _find_tree_hover(navigation: BTScriptEditorNavigationTooltip, tree: Tree) -> Dictionary:
	for y: int in range(2, 96, 2):
		var result := navigation.call("_resolve_outline_hover", tree, Vector2(30, y)) as Dictionary
		if not result.is_empty():
			return result
	return {}


func _find_item_list_hover(
	navigation: BTScriptEditorNavigationTooltip,
	item_list: ItemList
) -> Dictionary:
	for y: int in range(2, 96, 2):
		var result := navigation.call(
			"_resolve_script_ide_outline_hover",
			item_list,
			Vector2(30, y)
		) as Dictionary
		if not result.is_empty():
			return result
	return {}


func _fail(
	message: String,
	navigation: BTScriptEditorNavigationTooltip = null,
	pipeline: BTTooltipPipeline = null
) -> void:
	push_error(message)
	if navigation != null:
		navigation.cleanup()
	if pipeline != null:
		pipeline.cleanup()
	quit(1)
