extends SceneTree

# A live GDScript tooltip can contain script docs and component docs. Wait for
# both to settle and perform only one final native popup fit.
const CodeDocumentation := preload("res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd")
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const Presenter := preload("res://addons/better_tooltips/core/tooltip_presenter.gd")
const ScriptDocs := preload("res://addons/better_tooltips/modules/script_documentation_tooltip.gd")
const ComponentDocs := preload("res://addons/better_tooltips/modules/component_documentation_tooltip.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

const SOURCE := "res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd"
const PENDING := &"_bt_code_native_live_layout_pending"

class CountingCodeDocumentation extends BTCodeEditorDocumentationTooltip:
	var fit_calls := 0
	func _schedule_native_tooltip_fit(_popup: PopupPanel, _content: RichTextLabel) -> void:
		fit_calls += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem != null and filesystem.is_scanning():
		await process_frame
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline._presenter = Presenter.new()
	pipeline.add_module(Settings.MODULE_SCRIPT_DOCUMENTATION, "Script Documentation", ScriptDocs.new())
	pipeline.add_module(Settings.MODULE_COMPONENT_DOCUMENTATION, "Component Documentation", ComponentDocs.new())
	if pipeline.count_live_text_preview_modules(SOURCE) != 2:
		_fail("Expected two independent live documentation modules.")
		return
	var controller := CountingCodeDocumentation.new()
	controller._preview_pipeline = pipeline
	var code_edit := CodeEdit.new()
	root.add_child(code_edit)
	var popup := PopupPanel.new()
	code_edit.add_child(popup)
	var base := VBoxContainer.new()
	popup.add_child(base)
	var content := RichTextLabel.new()
	base.add_child(content)
	popup.popup()
	if not controller._append_native_resource_preview(SOURCE, base, popup, content, code_edit, "code_editor"):
		_fail("The native script preview was not accepted.")
		return
	var pending: Dictionary = popup.get_meta(PENDING, {})
	if int(pending.get(SOURCE, 0)) != 2 or controller.fit_calls != 0:
		_fail("Native popup was fitted before its live sections finished.")
		return
	# Even when the common presenter refreshes its base, it must not resize
	# the native popup while async RichText content is still being laid out.
	pipeline._presenter.refresh_tooltip_layout(base, popup)
	if controller.fit_calls != 0:
		_fail("Intermediate layout requested a premature final fit.")
		return
	for frame in range(40):
		if not popup.has_meta(PENDING):
			break
		await process_frame
	if popup.has_meta(PENDING) or controller.fit_calls != 1:
		_fail("Native popup must receive exactly one final fit after both sections.")
		return
	popup.queue_free()
	code_edit.queue_free()
	print("Code Editor native single-fit regression: PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
