@tool
class_name BTPlugin
extends EditorPlugin

## [b]Godot editor-plugin entry point[/b] for Better Tooltips.
## Creates and releases [code]BTController[/code] and deliberately contains no resource-specific tooltip logic.
## See [method EditorPlugin._enter_tree] and [method EditorPlugin._exit_tree] for the lifecycle hooks used by this class.

const BetterTooltipsController := preload(
	"res://addons/better_tooltips/better_tooltips.gd"
)

var _better_tooltips: BTController = null


# Creates the add-on controller when Godot enables the editor plugin.
# All add-on behavior is delegated to the controller so this script stays
# limited to the EditorPlugin lifecycle.
func _enter_tree() -> void:
	_better_tooltips = BetterTooltipsController.new() as BTController
	_better_tooltips.setup(self)


# Gives the central preview pipeline first refusal on mouse-wheel events while a
# graphical tooltip is visible. Consumed wheel input resizes only that transient
# hover session instead of scrolling the editor control underneath it.
func _input(event: InputEvent) -> void:
	if not is_instance_valid(_better_tooltips):
		return
	if _better_tooltips.handle_input(event):
		get_viewport().set_input_as_handled()


# Gives the controller a chance to unregister editor integrations before the
# plugin is disabled, then releases the controller instance.
func _exit_tree() -> void:
	if is_instance_valid(_better_tooltips):
		_better_tooltips.cleanup()
	_better_tooltips = null
