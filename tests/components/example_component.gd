@tool
class_name BTExampleComponent
extends Node

## Example reusable instrument; configure its sources in the Inspector.
## A fixture for documentation extraction, not an aircraft implementation.

const COMPONENT_CONTRACT: Dictionary = {
	"version": 1,
	"required": [&"data_source"],
	"optional": [&"caption"],
}

## Required read-only data source. Subscribes to its updates internally.
@export var data_source: Node
## Optional label; changing it does not affect simulation.
@export var caption: String = "Example"
## Emitted when the user requests activation.
signal activated(identifier: StringName)

func _init() -> void:
	Engine.set_meta("bt_component_fixture_instantiated", true)

## Reset the local display without changing its source.
func reset_display(_scope: StringName = &"local") -> void:
	pass

func _get_configuration_warnings() -> PackedStringArray:
	Engine.set_meta("bt_component_fixture_warnings_called", true)
	return []
