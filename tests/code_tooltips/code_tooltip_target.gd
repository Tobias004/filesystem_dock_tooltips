class_name CodeTooltipTarget
extends Node2D

## Scene node used by the Code Tooltip showcase.
##
## Hover [code]%PreviewTarget[/code] or a path resolving to this node to verify
## that the NodePath tooltip can also include the target script's class docs.
## [b]Expected:[/b] node type, resolved scene path, script path, class name and
## this documentation block are displayed.

## Example property used for ordinary cross-script member documentation.
var documented_value: int = 42


## Returns [member documented_value].
func documented_method() -> int:
	return documented_value
