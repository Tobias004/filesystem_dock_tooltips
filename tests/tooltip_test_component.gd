class_name TooltipTestComponent
extends Node

## Demonstrates Godot documentation formatting in the FileSystem tooltip.
##
## Uses [Node], [method Node.add_child], [member Node.owner],
## [signal Node.renamed], [constant Color.RED] and [param delta].
##
## [b]Bold[/b], [i]italic[/i], [u]underline[/u], [s]strikethrough[/s],
## [color=orange]colored text[/color], [code]inline_code()[/code] and
## [kbd]Ctrl + S[/kbd].[br]This line is kept with an explicit break.
##
## [codeblock lang=gdscript]
## func example(child: Node) -> void:
##     if child.get_parent() == null:
##         add_child(child)
## [/codeblock]
##
## Literal brackets: [lb]value[rb].
## [url=https://godotengine.org]Godot website[/url]
## @tutorial(GDScript documentation): https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_documentation_comments.html

const ExternalFixtureScript := preload(
	"res://tests/tooltip_external_fixture.gd"
)

## Emitted whenever the test value changes.
signal test_value_changed(value: int)

## Available states for member-tooltip tests.
enum TestState {
	## The test is waiting for input.
	WAITING,
	# The test is actively processing data.
	RUNNING,
}

## Maximum value used by the tooltip fixture.
const MAX_TEST_VALUE := 100

## Movement speed used by [method _process].
@export var speed: float = 200.0

# Direction used by this concrete test component.
@export var direction := Vector2.RIGHT

## Enables or disables movement processing.
@export var enabled := true

# Creates the local test component state when the node enters the tree.
# This deliberately documents an overridden engine callback with a single # block.
func _enter_tree() -> void:
	pass

## Moves the owner while processing is enabled.
## [param delta] is the elapsed frame time supplied by Godot.
func _process(delta: float) -> void:
	if enabled and owner is Node2D:
		owner.position += direction.normalized() * speed * delta

## Returns [param value] unchanged for a custom-method tooltip test.
func documented_custom_method(value: int) -> int:
	return value

## Small inner type used to verify class member documentation.
class TooltipInnerFixture:
	var value := 0

# Manual cross-script tooltip fixture. Hover the class and members below to
# verify that Godot's resolved TooltipExternalFixture owner leads back to the
# external source documentation rather than the current script.
func _cross_script_tooltip_examples() -> void:
	# Hover ExternalFixtureScript to verify preload-alias class documentation.
	var preloaded_fixture := ExternalFixtureScript.new()
	var fixture := TooltipExternalFixture.new()
	var value := preloaded_fixture.documented_method()
	value += fixture.documented_value
	value += fixture.implementation_value
	value += fixture.documented_method()
	value += fixture.implementation_method()
	if value < 0:
		print(value)
