class_name TooltipTestComponent
extends Node

## Demonstrates all supported tooltip features.
##
## [b]Bold text[/b]
## [i]Italic text[/i]
## [u]Underlined text[/u]
## [s]Strikethrough text[/s]
## [color=orange]Colored text[/color]
## [code]inline_code()[/code]
## [url=https://godotengine.org]Godot website[/url]
## First line[br]Second line
##
## Godot references:
##     Class:    [Node2D]
##     Method:   [method Node.add_child]
##     Member:   [member speed]
##
## Approximated tags:
##     [codeblock]var value := 42[/codeblock]
##     Press [kbd]Ctrl+S[/kbd] to save.
##
## Parameters:
##     speed       Movement speed
##     direction   Normalized movement direction
##     enabled     Enables or disables movement
##
## Source layout:
##         This line has leading indentation.
##     This    line    contains    repeated    spaces.
##	This line begins with a tab.
##
## Blank lines above and below should remain visible.
##
## A very long line for testing the maximum tooltip width and fallback wrapping behavior when the source line is wider than the configured maximum width of the tooltip control.
##
## Trailing spaces follow this line.    
## End of documentation.

@export var speed: float = 200.0
@export var direction := Vector2.RIGHT
@export var enabled := true


func _process(delta: float) -> void:
	if enabled and owner is Node2D:
		owner.position += direction.normalized() * speed * delta
		
# This ordinary comment must not appear as class documentation.
func test() -> void:
	pass
