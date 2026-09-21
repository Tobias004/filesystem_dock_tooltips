@tool
extends EditorPlugin

const FileSystemDockTooltips := preload(
	"res://addons/filesystem_dock_tooltips/filesystem_dock_tooltips.gd"
)

var _file_system_dock_tooltips: Variant = null


# Creates the add-on controller when Godot enables the editor plugin.
# All add-on behavior is delegated to the controller so this script stays
# limited to the EditorPlugin lifecycle.
func _enter_tree() -> void:
	_file_system_dock_tooltips = FileSystemDockTooltips.new()
	_file_system_dock_tooltips.setup(self)


# Gives the controller a chance to unregister editor integrations before the
# plugin is disabled, then releases the controller instance.
func _exit_tree() -> void:
	if is_instance_valid(_file_system_dock_tooltips):
		_file_system_dock_tooltips.cleanup()
	_file_system_dock_tooltips = null
