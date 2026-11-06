extends SceneTree

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const Debug := preload("res://addons/better_tooltips/tooltip_debug.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var original_state: bool = Settings.is_plugin_diagnostics_enabled()
	Settings.set_plugin_diagnostics_enabled(false)
	Debug.log("DiagnosticTest", "HIDDEN_TEST_MARKER")
	Settings.set_plugin_diagnostics_enabled(true)
	Debug.log("DiagnosticTest", "VISIBLE_TEST_MARKER")
	if not Settings.is_plugin_diagnostics_enabled():
		push_error("Diagnostics did not become enabled.")
		quit(1)
		return
	Settings.set_plugin_diagnostics_enabled(original_state)
	print("Plugin diagnostics state: PASS")
	quit(0)
