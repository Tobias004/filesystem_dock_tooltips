extends SceneTree

## Live UI regression for Markdown/TextFile previews. Text is deliberately not
## captured into images: the real RichTextLabel must remain in the tooltip so
## mouse-wheel scrolling and editor typography work in every host.

const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const MarkdownModule := preload(
	"res://addons/better_tooltips/modules/markdown_preview_tooltip.gd"
)
const TextModule := preload(
	"res://addons/better_tooltips/modules/text_file_preview_tooltip.gd"
)
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

const MARKDOWN_PATH := "res://tests/text_previews/showcase.md"
const TEXT_PATH := "res://tests/text_previews/showcase.txt"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(0.5).timeout
	var filesystem := EditorInterface.get_resource_filesystem()
	var deadline := Time.get_ticks_msec() + 10000
	while filesystem != null and filesystem.is_scanning() and Time.get_ticks_msec() < deadline:
		await process_frame
	var cache := Cache.new() as BTTooltipCache
	cache.setup(EditorInterface.get_base_control())
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline.setup(cache, EditorInterface.get_base_control())
	pipeline.add_module(
		Settings.MODULE_MARKDOWN_PREVIEW,
		"Markdown",
		MarkdownModule.new() as EditorResourceTooltipPlugin
	)
	pipeline.add_module(
		Settings.MODULE_TEXT_FILE_PREVIEW,
		"Text File",
		TextModule.new() as EditorResourceTooltipPlugin
	)
	if not await _test_one_path(pipeline, MARKDOWN_PATH):
		pipeline.cleanup()
		quit(1)
		return
	if not await _test_one_path(pipeline, TEXT_PATH):
		pipeline.cleanup()
		quit(1)
		return
	pipeline.cleanup()
	cache.cleanup()
	print("Live text preview UI test: PASS")
	quit(0)


func _test_one_path(pipeline: BTTooltipPipeline, path: String) -> bool:
	var popup := PopupPanel.new()
	popup.wrap_controls = true
	popup.set_flag(Window.FLAG_NO_FOCUS, true)
	EditorInterface.get_base_control().add_child(popup)
	var base := VBoxContainer.new()
	popup.add_child(base)
	var title := Label.new()
	title.text = path.get_file()
	base.add_child(title)
	popup.position = Vector2i(240, 140)
	popup.popup()
	if not pipeline.append_preview_for_path(path, base, popup, {"source": "live_text_test"}):
		push_error("Pipeline rejected text preview path: " + path)
		popup.queue_free()
		return false
	for _frame: int in range(5):
		await process_frame
	var rich := popup.find_child("MarkdownPreview", true, false) as RichTextLabel
	if rich == null:
		rich = popup.find_child("TextPreview", true, false) as RichTextLabel
	if rich == null:
		push_error("Text preview did not remain a live RichTextLabel: " + path)
		popup.queue_free()
		return false
	if popup.find_child("PreviewTexture", true, false) != null:
		push_error("Text preview was unexpectedly converted to a graphical TextureRect: " + path)
		popup.queue_free()
		return false
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	if pipeline.handle_input(wheel):
		push_error("Text preview unexpectedly consumed wheel input as graphical zoom: " + path)
		popup.queue_free()
		return false
	popup.queue_free()
	await process_frame
	return true
