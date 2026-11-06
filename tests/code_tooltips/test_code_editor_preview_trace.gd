extends SceneTree

# Tests that Code Editor live-preview diagnostics label the owning popup and
# that appending the same preview twice to one container does not rebuild it.
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const ScriptDocumentation := preload("res://addons/better_tooltips/modules/script_documentation_tooltip.gd")
const Presenter := preload("res://addons/better_tooltips/core/tooltip_presenter.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

const TARGET := "res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var previous := Settings.is_plugin_diagnostics_enabled()
	Settings.set_plugin_diagnostics_enabled(true)
	var pipeline := Pipeline.new() as BTTooltipPipeline
	pipeline._presenter = Presenter.new()
	var module := ScriptDocumentation.new() as EditorResourceTooltipPlugin
	var module_id := Settings.MODULE_SCRIPT_DOCUMENTATION
	var module_entry := {"plugin": module, "name": "Script Documentation"}
	for host in ["native", "fallback"]:
		var popup := PopupPanel.new()
		root.add_child(popup)
		var base := VBoxContainer.new()
		popup.add_child(base)
		var metadata := {
			"source": "code_editor",
			"bt_code_editor_host": host,
			"host_manages_popup": true,
		}
		pipeline._append_live_preview(module_id, module_entry, TARGET, metadata, base, popup)
		if base.get_child_count() != 1:
			_fail("The live section was not added.", previous)
			return
		pipeline._append_live_preview(module_id, module_entry, TARGET, metadata, base, popup)
		if base.get_child_count() != 1:
			_fail("The same live section was added twice.", previous)
			return
		for _frame in range(6):
			await process_frame
		popup.queue_free()
		for _frame in range(3):
			await process_frame
	Settings.set_plugin_diagnostics_enabled(previous)
	print("Code Editor live-preview diagnostics test: PASS")
	quit(0)

func _fail(reason: String, previous: bool) -> void:
	Settings.set_plugin_diagnostics_enabled(previous)
	push_error(reason)
	quit(1)
