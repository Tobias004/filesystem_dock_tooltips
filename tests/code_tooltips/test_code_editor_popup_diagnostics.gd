extends SceneTree

# Focused regression for optional Code Editor popup lifecycle diagnostics.
# Uses a synthetic native-help-bit structure without running the full editor GUI.
const CodeDocumentation := preload("res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var prior_diagnostics := Settings.is_plugin_diagnostics_enabled()
	Settings.set_plugin_diagnostics_enabled(true)
	var documentation := CodeDocumentation.new()
	var code_edit := CodeEdit.new()
	root.add_child(code_edit)
	documentation._watch_code_edit(code_edit)
	var editor_id := code_edit.get_instance_id()
	var entry: Dictionary = documentation._watched_editors[editor_id]
	entry["hover_key"] = "Script:3:"
	entry["fallback_symbol"] = "Script"
	documentation._watched_editors[editor_id] = entry
	var native_delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	if documentation._get_fallback_delay_seconds(true) < native_delay + 0.8:
		_fail("Native symbol grace period is too short.", prior_diagnostics, code_edit)
		return
	var popup := PopupPanel.new()
	popup.theme_type_variation = &"TooltipPanel"
	code_edit.add_child(popup)
	var container := VBoxContainer.new()
	popup.add_child(container)
	var title := RichTextLabel.new()
	title.theme_type_variation = &"EditorHelpBitTitle"
	container.add_child(title)
	var content := RichTextLabel.new()
	content.theme_type_variation = &"EditorHelpBitContent"
	container.add_child(content)
	documentation._on_code_edit_child_entered(popup, code_edit)
	entry = documentation._watched_editors[editor_id]
	if not bool(entry.get("native_seen_for_hover", false)):
		_fail("A native popup should suppress the fallback for this hover.", prior_diagnostics, code_edit)
		return
	var has_callback := false
	for connection in popup.popup_hide.get_connections():
		var callback := connection.get("callable", Callable()) as Callable
		if callback.get_method() == "_on_native_popup_hidden":
			has_callback = true
	if not has_callback:
		_fail("Native tooltip hide callback was not registered.", prior_diagnostics, code_edit)
		return
	popup.popup_hide.emit()
	popup.queue_free()
	await process_frame
	documentation._disconnect_watched_editor(editor_id)
	Settings.set_plugin_diagnostics_enabled(prior_diagnostics)
	code_edit.queue_free()
	print("Code Editor popup diagnostics test: PASS")
	quit(0)

func _fail(message: String, prior_diagnostics: bool, editor: CodeEdit) -> void:
	Settings.set_plugin_diagnostics_enabled(prior_diagnostics)
	editor.queue_free()
	push_error(message)
	quit(1)
