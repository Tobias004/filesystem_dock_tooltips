extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var scene := load("res://addons/better_tooltips/settings_dialog.tscn") as PackedScene
	if scene == null:
		push_error("Settings dialog scene failed to load.")
		quit(1)
		return
	var dialog := scene.instantiate()
	if dialog == null:
		push_error("Settings dialog scene failed to instantiate.")
		quit(1)
		return
	root.add_child(dialog)
	var size_spin := dialog.get_node_or_null("MarginContainer/Columns/PreviewColumn/PreviewSizeRow/spnPreviewSize") as SpinBox
	if size_spin == null:
		push_error("Default preview-size SpinBox is missing.")
		quit(1)
		return
	var diagnostics := dialog.get_node_or_null(
		"MarginContainer/Columns/PreviewColumn/chkbPluginDiagnostics"
	) as CheckBox
	if diagnostics == null:
		push_error("Plugin diagnostics checkbox is missing.")
		quit(1)
		return
	var settings := load("res://addons/better_tooltips/tooltip_settings.gd")
	var original_value: bool = settings.is_plugin_diagnostics_enabled()
	settings.set_plugin_diagnostics_enabled(false)
	dialog.refresh()
	if diagnostics.button_pressed:
		push_error("Plugin diagnostics should be off by default.")
		quit(1)
		return
	diagnostics.button_pressed = true
	if not settings.is_plugin_diagnostics_enabled():
		push_error("Plugin diagnostics checkbox did not persist its state.")
		quit(1)
		return
	diagnostics.button_pressed = false
	if settings.is_plugin_diagnostics_enabled():
		push_error("Disabling diagnostics did not persist its state.")
		quit(1)
		return
	settings.set_plugin_diagnostics_enabled(original_value)
	print("Settings dialog diagnostics toggle: PASS")
	print("Settings dialog preview-size control: PASS")
	dialog.queue_free()
	quit(0)
