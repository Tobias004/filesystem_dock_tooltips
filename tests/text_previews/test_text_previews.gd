extends SceneTree

## Regression checks for Markdown and generic text-file previews.
## Run in editor context so EditorFileSystem and project-local tooltip settings
## are available exactly as they are during normal hover handling.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const Parser := preload(
	"res://addons/better_tooltips/core/gdscript_documentation_parser.gd"
)
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const TooltipCache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const MarkdownModule := preload(
	"res://addons/better_tooltips/modules/markdown_preview_tooltip.gd"
)
const TextModule := preload(
	"res://addons/better_tooltips/modules/text_file_preview_tooltip.gd"
)
const CodeTooltip := preload(
	"res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd"
)
const NavigationTooltip := preload(
	"res://addons/better_tooltips/modules/script_editor_navigation_tooltip.gd"
)
const TextPreviewRenderer := preload(
	"res://addons/better_tooltips/core/text_preview_renderer.gd"
)
const DocumentationRenderer := preload(
	"res://addons/better_tooltips/core/documentation_renderer.gd"
)

const MARKDOWN_PATH := "res://tests/text_previews/showcase.md"
const TEXT_PATH := "res://tests/text_previews/showcase.txt"
const LONG_MARKDOWN_PATH := "res://tests/text_previews/long_showcase.md"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _wait_for_filesystem_scan()
	_test_editor_file_types()
	_test_filesystem_dock_dispatch_type()
	_test_module_path_split()
	await _test_rendered_controls()
	await _test_long_live_scroll()
	await _test_interactive_live_text_popup()
	_test_direct_path_parser()
	_test_pipeline_path_routing()
	await _test_filesystem_dispatch_pipeline_render()
	_test_code_literal_hover()
	_test_navigation_resolution()
	_test_navigation_file_locations()
	await _test_native_navigation_live_preview()
	if _failures.is_empty():
		print("Text preview tests: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_editor_file_types() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	_expect(filesystem != null, "EditorFileSystem should be available.")
	if filesystem == null:
		return
	_expect(
		filesystem.get_file_type(MARKDOWN_PATH) == "TextFile",
		"Godot should classify the Markdown fixture as TextFile."
	)
	_expect(
		filesystem.get_file_type(TEXT_PATH) == "TextFile",
		"Godot should classify the .txt fixture as TextFile."
	)


# FileSystemDock dispatches non-Resource text files to tooltip plugins with an
# empty resource type. The central pipeline must accept that dispatch and defer
# the real TextFile/path split until _make_tooltip_for_path().
func _test_filesystem_dock_dispatch_type() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var markdown := MarkdownModule.new() as BTMarkdownPreviewTooltip
	var text := TextModule.new() as BTTextFilePreviewTooltip
	pipeline.add_module(Settings.MODULE_MARKDOWN_PREVIEW, "Markdown", markdown)
	pipeline.add_module(Settings.MODULE_TEXT_FILE_PREVIEW, "Text File", text)
	_expect(
		bool(pipeline.call("_handles", "")),
		"Pipeline must accept the empty ResourceLoader type used by FileSystemDock for text files."
	)


func _test_module_path_split() -> void:
	var markdown := MarkdownModule.new() as BTMarkdownPreviewTooltip
	var text := TextModule.new() as BTTextFilePreviewTooltip
	_expect(markdown.call("_handles", "TextFile"), "Markdown module should handle TextFile.")
	_expect(text.call("_handles", "TextFile"), "Text module should handle TextFile.")
	_expect(markdown.call("_handles", ""), "Markdown module should accept FileSystemDock's empty text-file dispatch type.")
	_expect(text.call("_handles", ""), "Text module should accept FileSystemDock's empty text-file dispatch type.")
	_expect(
		markdown.handles_path(MARKDOWN_PATH, "TextFile"),
		"Markdown module should accept .md paths."
	)
	_expect(
		not markdown.handles_path(TEXT_PATH, "TextFile"),
		"Markdown module should reject generic .txt paths."
	)
	_expect(
		text.handles_path(TEXT_PATH, "TextFile"),
		"Generic text module should accept .txt paths."
	)
	_expect(
		not text.handles_path(MARKDOWN_PATH, "TextFile"),
		"Generic text module should reject Markdown paths."
	)


func _test_rendered_controls() -> void:
	var markdown := MarkdownModule.new() as BTMarkdownPreviewTooltip
	var markdown_base := VBoxContainer.new()
	root.add_child(markdown_base)
	markdown.call("_make_tooltip_for_path", MARKDOWN_PATH, {}, markdown_base)
	var text := TextModule.new() as BTTextFilePreviewTooltip
	var text_base := VBoxContainer.new()
	root.add_child(text_base)
	text.call("_make_tooltip_for_path", TEXT_PATH, {}, text_base)
	await process_frame
	_expect(markdown_base.get_child_count() == 1, "Markdown module should add one live preview Control.")
	_expect(text_base.get_child_count() == 1, "Text module should add one live preview Control.")
	if markdown_base.get_child_count() == 1:
		var markdown_preview := markdown_base.get_child(0) as Control
		var rich := _find_rich_text(markdown_preview)
		_expect(rich != null, "Markdown preview should contain a RichTextLabel.")
		if rich != null:
			_expect(
				rich.get_parsed_text().contains("Markdown Preview Showcase"),
				"Markdown heading should be present in the rendered text."
			)
			var renderer := DocumentationRenderer.new() as BTDocumentationRenderer
			renderer.refresh_theme()
			_expect(
				rich.get_theme_font_size("normal_font_size") == renderer.get_document_font_size(),
				"Markdown base text should use the same EditorHelp font size as code documentation."
			)
	if text_base.get_child_count() == 1:
		var text_preview := text_base.get_child(0) as Control
		var rich := _find_rich_text(text_preview)
		_expect(rich != null, "Generic text preview should contain a RichTextLabel.")
		if rich != null:
			_expect(
				rich.text.contains("Generic Text Preview Showcase"),
				"Generic text content should be preserved."
			)
	markdown_base.queue_free()
	text_base.queue_free()


func _test_long_live_scroll() -> void:
	var data := TextPreviewRenderer.read_preview_text(LONG_MARKDOWN_PATH)
	_expect(not data.is_empty(), "Long Markdown fixture should be readable.")
	_expect(
		not bool(data.get("truncated", true)),
		"A ~200 KiB Markdown file should no longer be truncated by the old 64 KiB limit."
	)
	_expect(
		str(data.get("text", "")).contains("END_OF_LONG_MARKDOWN"),
		"The complete long Markdown fixture should reach the renderer."
	)

	var cache := TooltipCache.new() as BTTooltipCache
	cache.setup(root)
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.setup(cache, root)
	pipeline.add_module(
		Settings.MODULE_MARKDOWN_PREVIEW,
		"Markdown",
		MarkdownModule.new() as EditorResourceTooltipPlugin
	)
	var popup := PopupPanel.new()
	popup.wrap_controls = true
	root.add_child(popup)
	var base := VBoxContainer.new()
	popup.add_child(base)
	popup.popup_centered(Vector2i(760, 700))
	pipeline.append_preview_for_path(LONG_MARKDOWN_PATH, base, popup, {"source": "scroll_test"})
	for _frame: int in range(5):
		await process_frame
	var rich := _find_rich_text(base)
	_expect(rich != null, "Long Markdown pipeline preview should stay as live RichTextLabel content.")
	if rich != null:
		_expect(rich.scroll_active, "Long Markdown tooltip should enable internal scrolling.")
		_expect(not rich.fit_content, "Long Markdown tooltip should stop growing once it reaches its height limit.")
		_expect(rich.mouse_filter == Control.MOUSE_FILTER_STOP, "Scrollable text should receive wheel input itself.")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_expect(
		not pipeline.handle_input(wheel),
		"Live text previews must not enter the graphical wheel-zoom path."
	)
	_expect(_find_texture_rect(base) == null, "Live text previews must not be converted to cached TextureRects.")
	popup.hide()
	popup.queue_free()
	pipeline.cleanup()
	cache.cleanup()


# A native TooltipPanel is promoted into an add-on-owned popup for live text so
# the pointer can leave the source item, reach the scrollbar and consume wheel
# input without sending it to the editor behind the tooltip.
func _test_interactive_live_text_popup() -> void:
	var cache := TooltipCache.new() as BTTooltipCache
	cache.setup(root)
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.setup(cache, root)
	pipeline.add_module(
		Settings.MODULE_MARKDOWN_PREVIEW,
		"Markdown",
		MarkdownModule.new() as EditorResourceTooltipPlugin
	)

	var trigger := Button.new()
	trigger.position = Vector2(40, 40)
	trigger.size = Vector2(220, 36)
	root.add_child(trigger)
	var native_popup := PopupPanel.new()
	native_popup.theme_type_variation = &"TooltipPanel"
	native_popup.wrap_controls = true
	trigger.add_child(native_popup)
	var base := VBoxContainer.new()
	native_popup.add_child(base)
	native_popup.popup()

	pipeline.append_preview_for_path(
		LONG_MARKDOWN_PATH,
		base,
		native_popup,
		{"source": "interactive_text_test", "trigger_control": trigger}
	)
	for _frame: int in range(8):
		await process_frame

	var session := pipeline.get("_live_text_session") as Dictionary
	_expect(not session.is_empty(), "Long live text should be promoted into an interactive tooltip popup.")
	var popup_ref := session.get("popup", null) as WeakRef
	var popup := popup_ref.get_ref() as PopupPanel if popup_ref != null else null
	_expect(is_instance_valid(popup), "Interactive text tooltip popup should remain alive after promotion.")
	_expect(not native_popup.visible, "The original native tooltip should be hidden after promotion.")
	if is_instance_valid(popup):
		_expect(popup.visible, "Interactive text tooltip popup should be visible.")
		_expect(base.get_parent() == popup, "The existing tooltip root should be re-used rather than rebuilt.")
		var rich := _find_rich_text(popup)
		_expect(rich != null, "Interactive popup should keep the live RichTextLabel preview.")
		if rich != null:
			_expect(rich.scroll_active and not rich.fit_content, "Promoted long text must remain internally scrollable.")
			var scroll_bar := rich.get_v_scroll_bar()
			if scroll_bar != null:
				scroll_bar.value = scroll_bar.min_value
				var wheel := InputEventMouseButton.new()
				wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
				wheel.pressed = true
				wheel.factor = 1.0
				pipeline.call(
					"_on_live_text_popup_window_input",
					wheel,
					int(session.get("sequence", 0))
				)
				_expect(scroll_bar.value > scroll_bar.min_value, "Mouse wheel should scroll the live text preview.")

	pipeline.call("_close_live_text_session")
	trigger.queue_free()
	pipeline.cleanup()
	cache.cleanup()


func _test_direct_path_parser() -> void:
	var source := """
const README_PATH: String = "res://tests/text_previews/showcase.md"
const README_ALIAS := README_PATH
var notes_path: String = "res://tests/text_previews/showcase.txt"
"""
	var markdown := Parser.find_resource_reference(source, "README_ALIAS", -1)
	var text := Parser.find_resource_reference(source, "notes_path", -1)
	_expect(
		str(markdown.get("path", "")) == MARKDOWN_PATH,
		"Direct Markdown string aliases should resolve to the project file."
	)
	_expect(
		str(text.get("path", "")) == TEXT_PATH,
		"Direct text-file string properties should resolve to the project file."
	)


func _test_pipeline_path_routing() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var markdown := MarkdownModule.new() as BTMarkdownPreviewTooltip
	var text := TextModule.new() as BTTextFilePreviewTooltip
	pipeline.add_module(Settings.MODULE_MARKDOWN_PREVIEW, "Markdown", markdown)
	pipeline.add_module(Settings.MODULE_TEXT_FILE_PREVIEW, "Text File", text)
	_expect(pipeline.supports_preview_path(MARKDOWN_PATH), "Pipeline should support Markdown paths.")
	_expect(pipeline.supports_preview_path(TEXT_PATH), "Pipeline should support text paths.")
	var markdown_context := pipeline.call("_get_path_preview_context", MARKDOWN_PATH) as Dictionary
	var text_context := pipeline.call("_get_path_preview_context", TEXT_PATH) as Dictionary
	var markdown_ids: Array = markdown_context.get("module_ids", []) as Array
	var text_ids: Array = text_context.get("module_ids", []) as Array
	_expect(markdown_ids == [Settings.MODULE_MARKDOWN_PREVIEW], "Markdown path should route to exactly the Markdown module.")
	_expect(text_ids == [Settings.MODULE_TEXT_FILE_PREVIEW], "Text path should route to exactly the generic text module.")


# Mirrors FileSystemDock after its _handles("") dispatch: the plugin has already
# been selected for an untyped text file, and the central pipeline receives the
# real path plus Godot's default tooltip base. The async generation must replace
# its status section with a captured static preview while that popup is visible.
func _test_filesystem_dispatch_pipeline_render() -> void:
	var cache := TooltipCache.new() as BTTooltipCache
	cache.setup(root)
	cache.clear()
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.setup(cache, root)
	var markdown := MarkdownModule.new() as BTMarkdownPreviewTooltip
	var text_module := TextModule.new() as BTTextFilePreviewTooltip
	pipeline.add_module(Settings.MODULE_MARKDOWN_PREVIEW, "Markdown", markdown)
	pipeline.add_module(Settings.MODULE_TEXT_FILE_PREVIEW, "Text File", text_module)
	_expect(bool(pipeline.call("_handles", "")), "FileSystemDock empty-type dispatch must select the central pipeline.")

	var popup := PopupPanel.new()
	root.add_child(popup)
	# Mirror Godot's real FileSystem callback order: the plugin receives the base
	# before that Control is attached to the native TooltipPanel.
	var base := VBoxContainer.new()
	pipeline.call("_make_tooltip_for_path", MARKDOWN_PATH, {}, base)
	popup.add_child(base)
	popup.popup_centered(Vector2i(720, 520))
	for _frame: int in range(4):
		await process_frame
	var rich := _find_rich_text(base)
	_expect(
		rich != null and rich.get_parsed_text().contains("Markdown Preview Showcase"),
		"FileSystem-style Markdown dispatch should insert the same live text renderer used elsewhere."
	)
	_expect(_find_texture_rect(base) == null, "FileSystem Markdown should no longer be rasterized into a bitmap.")
	popup.hide()
	popup.queue_free()
	pipeline.cleanup()
	cache.cleanup()


func _find_texture_rect(node: Node) -> TextureRect:
	if node is TextureRect:
		return node as TextureRect
	for child: Node in node.get_children():
		var found := _find_texture_rect(child)
		if found != null:
			return found
	return null


func _test_code_literal_hover() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var markdown := MarkdownModule.new() as BTMarkdownPreviewTooltip
	pipeline.add_module(Settings.MODULE_MARKDOWN_PREVIEW, "Markdown", markdown)
	var integration := CodeTooltip.new() as BTCodeEditorDocumentationTooltip
	integration.set("_preview_pipeline", pipeline)
	var code := CodeEdit.new()
	root.add_child(code)
	code.text = 'const README_PATH := "res://tests/text_previews/showcase.md"'
	var column := code.get_line(0).find("res://") + 4
	var context := integration.call(
		"_resolve_special_hover",
		code,
		{"line": 0, "column": column}
	) as Dictionary
	_expect(
		str(context.get("resource_path", "")) == MARKDOWN_PATH,
		"Code Editor should preview a direct project-file string literal."
	)
	code.queue_free()


func _test_navigation_resolution() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var text := TextModule.new() as BTTextFilePreviewTooltip
	pipeline.add_module(Settings.MODULE_TEXT_FILE_PREVIEW, "Text File", text)
	var navigation := NavigationTooltip.new() as BTScriptEditorNavigationTooltip
	navigation.set("_preview_pipeline", pipeline)
	var source := 'const NOTES_PATH: String = "res://tests/text_previews/showcase.txt"'
	var resolved := navigation.call(
		"_resolve_member_from_source",
		source,
		"res://tests/text_previews/fixture.gd",
		"NOTES_PATH"
	) as Dictionary
	_expect(
		str(resolved.get("resource_path", "")) == TEXT_PATH,
		"Quill/Script-IDE navigation resolution should expose direct text-file paths."
	)


func _test_navigation_file_locations() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.add_module(
		Settings.MODULE_MARKDOWN_PREVIEW,
		"Markdown",
		MarkdownModule.new() as EditorResourceTooltipPlugin
	)
	var navigation := NavigationTooltip.new() as BTScriptEditorNavigationTooltip
	navigation.set("_preview_pipeline", pipeline)
	var resolved := navigation.call("_resolve_navigation_path", MARKDOWN_PATH) as Dictionary
	_expect(
		str(resolved.get("resource_path", "")) == MARKDOWN_PATH,
		"Navigation resolver should accept Markdown files, not only .gd scripts."
	)

	var list := ItemList.new()
	list.add_item("showcase.md")
	list.set_item_tooltip(0, MARKDOWN_PATH)
	_expect(
		navigation.call("_get_item_list_navigation_path", list, 0) == MARKDOWN_PATH,
		"Godot open-file list tooltips should expose Markdown paths."
	)
	_expect(
		bool(navigation.call("_looks_like_script_list", list)),
		"A stock open-file list containing Markdown should still be discovered as a navigation surface."
	)

	var tabs := TabContainer.new()
	var page := Control.new()
	page.name = "showcase.md"
	tabs.add_child(page)
	var tab_bar := tabs.get_tab_bar()
	tab_bar.set_tab_tooltip(0, MARKDOWN_PATH)
	_expect(
		navigation.call("_get_tab_navigation_path", tabs, tab_bar, 0) == MARKDOWN_PATH,
		"Quill-style TabBar tooltips should expose Markdown paths."
	)

	var script_ide_button := Button.new()
	script_ide_button.size = Vector2(240, 32)
	script_ide_button.tooltip_text = MARKDOWN_PATH
	var script_ide_hover := navigation.call(
		"_resolve_script_ide_tab_hover",
		script_ide_button,
		{},
		Vector2(12, 12)
	) as Dictionary
	_expect(
		str((script_ide_hover.get("resolved", {}) as Dictionary).get("resource_path", "")) == MARKDOWN_PATH,
		"Script-IDE custom tabs should resolve Markdown paths from their native tooltip."
	)


func _test_native_navigation_live_preview() -> void:
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.add_module(
		Settings.MODULE_MARKDOWN_PREVIEW,
		"Markdown",
		MarkdownModule.new() as EditorResourceTooltipPlugin
	)
	var navigation := NavigationTooltip.new() as BTScriptEditorNavigationTooltip
	navigation.set("_preview_pipeline", pipeline)
	var list := ItemList.new()
	root.add_child(list)
	list.add_item("showcase.md")
	list.set_item_tooltip(0, MARKDOWN_PATH)
	navigation.call("_watch_control", list, &"script_list")
	var watched := navigation.get("_watched_controls") as Dictionary
	var entry := watched.get(list.get_instance_id(), {}) as Dictionary
	entry["resolved"] = navigation.call("_resolve_navigation_path", MARKDOWN_PATH) as Dictionary
	entry["hover_key"] = "file:0:%s" % MARKDOWN_PATH
	watched[list.get_instance_id()] = entry
	navigation.set("_watched_controls", watched)

	var popup := PopupPanel.new()
	popup.theme_type_variation = &"TooltipPanel"
	list.add_child(popup)
	var native_label := Label.new()
	native_label.theme_type_variation = &"TooltipLabel"
	native_label.text = MARKDOWN_PATH
	popup.add_child(native_label)
	popup.popup()
	navigation.call(
		"_finish_native_navigation_tooltip",
		weakref(popup),
		weakref(list)
	)
	for _frame: int in range(4):
		await process_frame
	var rich := _find_rich_text(popup)
	if rich == null:
		var live_session := pipeline.get("_live_text_session") as Dictionary
		var popup_ref := live_session.get("popup", null) as WeakRef
		var interactive_popup := (
			popup_ref.get_ref() as PopupPanel if popup_ref != null else null
		)
		if is_instance_valid(interactive_popup):
			rich = _find_rich_text(interactive_popup)
	_expect(
		rich != null and rich.get_parsed_text().contains("Markdown Preview Showcase"),
		"Native open-file/tab tooltips should promote the same live Markdown renderer into the interactive popup."
	)
	pipeline.call("_close_live_text_session")
	navigation.cleanup()
	list.queue_free()


func _wait_for_filesystem_scan() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem == null:
		return
	var frames := 0
	while filesystem.is_scanning() and frames < 300:
		await process_frame
		frames += 1
	await process_frame


func _find_rich_text(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node as RichTextLabel
	for child: Node in node.get_children():
		var found := _find_rich_text(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
