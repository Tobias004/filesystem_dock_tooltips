@tool
extends RefCounted

const Settings := preload("res://addons/filesystem_dock_tooltips/tooltip_settings.gd")


static func log(module: String, message: String) -> void:
	if Settings.DEBUG_MESSAGES:
		print("[FileSystem Dock Tooltips][%s] %s" % [module, message])


static func warning(module: String, message: String) -> void:
	if Settings.DEBUG_MESSAGES:
		push_warning("[FileSystem Dock Tooltips][%s] %s" % [module, message])


static func error(module: String, message: String) -> void:
	if Settings.DEBUG_MESSAGES:
		push_error("[FileSystem Dock Tooltips][%s] %s" % [module, message])
