@tool
extends EditorPlugin

const TOOLTIP_PLUGIN_SCRIPT := preload("res://addons/filesystem_dock_tooltips/filesystem_dock_tooltips.gd")

var _tooltip_plugin: EditorResourceTooltipPlugin


func _enter_tree() -> void:
	_tooltip_plugin = TOOLTIP_PLUGIN_SCRIPT.new()
	EditorInterface.get_file_system_dock().add_resource_tooltip_plugin(_tooltip_plugin)


func _exit_tree() -> void:
	if _tooltip_plugin == null:
		return

	EditorInterface.get_file_system_dock().remove_resource_tooltip_plugin(_tooltip_plugin)
	_tooltip_plugin = null
