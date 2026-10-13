@tool
class_name BTDebug
extends RefCounted

## [b]Conditional debug logger[/b] shared by all tooltip modules.
## Output is emitted only when [code]BTSettings.DEBUG_MESSAGES[/code] is enabled, keeping release builds quiet by default.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

static func log(module: String, message: String) -> void:
	if Settings.DEBUG_MESSAGES:
		print("[Better Tooltips][%s] %s" % [module, message])

static func warning(module: String, message: String) -> void:
	if Settings.DEBUG_MESSAGES:
		push_warning("[Better Tooltips][%s] %s" % [module, message])

static func error(module: String, message: String) -> void:
	if Settings.DEBUG_MESSAGES:
		push_error("[Better Tooltips][%s] %s" % [module, message])
