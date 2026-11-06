extends SceneTree

# Long script previews must not expand a native Godot tooltip before the
# asynchronous text-height finalizer has had a chance to run.
const TextRenderer := preload("res://addons/better_tooltips/core/text_preview_renderer.gd")
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Presenter := preload("res://addons/better_tooltips/core/tooltip_presenter.gd")
const ScriptDocs := preload("res://addons/better_tooltips/modules/script_documentation_tooltip.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

const SOURCE := "res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd"

class CountingPresenter extends BTTooltipPresenter:
	var refreshes := 0
	func refresh_tooltip_layout(base: Control, resize_target: Node = null) -> void:
		refreshes += 1
		super.refresh_tooltip_layout(base, resize_target)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var native := TextRenderer.create_plain_preview(SOURCE, {"bt_code_editor_host": "native"})
	var label := native.find_child("TextPreview", true, false) as RichTextLabel
	if label == null or label.fit_content or label.custom_minimum_size.y > 500.0:
		_fail("Native long source preview is not bounded before first layout.")
		return
	var normal := TextRenderer.create_plain_preview(SOURCE, {})
	var original := normal.find_child("TextPreview", true, false) as RichTextLabel
	if original == null or not original.fit_content:
		_fail("Non-native text preview behavior changed.")
		return
	var pipeline := Pipeline.new() as BTTooltipPipeline
	var presenter := CountingPresenter.new()
	pipeline._presenter = presenter
	pipeline.add_module(Settings.MODULE_SCRIPT_DOCUMENTATION, "Script Documentation", ScriptDocs.new())
	var popup := PopupPanel.new()
	var base := VBoxContainer.new()
	root.add_child(popup)
	popup.add_child(base)
	popup.popup()
	pipeline._append_live_preview(Settings.MODULE_SCRIPT_DOCUMENTATION,
		pipeline._modules[Settings.MODULE_SCRIPT_DOCUMENTATION], SOURCE,
		{"source":"code_editor", "bt_code_editor_host":"native", "host_manages_popup":true},
		base, popup)
	for i in range(15):
		await process_frame
	if presenter.refreshes != 0:
		_fail("Native tooltip was resized by the shared presenter (%d)." % presenter.refreshes)
		return
	var final_label := base.find_child("TextPreview", true, false) as RichTextLabel
	if final_label == null or final_label.fit_content or not final_label.scroll_active:
		_fail("Long native source preview lost its scrollable final layout.")
		return
	popup.queue_free()
	native.free()
	normal.free()
	print("Native Code Editor initial height and no interim fit: PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
