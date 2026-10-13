class_name TooltipExternalFixture
extends RefCounted

## Project class used to verify documentation tooltips at cross-script use sites.
##
## The Code Editor should render this block with the add-on when the class name is
## hovered from another script, while keeping Godot's own symbol title/signature.

## Public value documented with Godot's normal documentation comment syntax.
var documented_value: int = 42

# Local implementation note exposed only when single-# tooltips are enabled.
var implementation_value: int = 7

## Returns [member documented_value] unchanged.
func documented_method() -> int:
	return documented_value

# Returns the implementation-only value for single-# cross-script tooltip tests.
func implementation_method() -> int:
	return implementation_value
