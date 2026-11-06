@tool
class_name BTDebug
extends RefCounted

## [b]Conditional debug logger[/b] shared by all tooltip modules.
## User-selectable project diagnostics are disabled by default; Godot engine errors cannot be suppressed by this logger.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

static func log(module: String, message: String) -> void:
	if Settings.is_plugin_diagnostics_enabled():
		print("[Better Tooltips][%s] %s" % [module, message])

static func warning(module: String, message: String) -> void:
	if Settings.is_plugin_diagnostics_enabled():
		push_warning("[Better Tooltips][%s] %s" % [module, message])

static func error(module: String, message: String) -> void:
	if Settings.is_plugin_diagnostics_enabled():
		push_error("[Better Tooltips][%s] %s" % [module, message])
