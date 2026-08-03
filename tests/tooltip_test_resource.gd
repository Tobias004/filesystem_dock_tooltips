## Alternative documentation placement above [code]class_name[/code].
##
## This class tests the same formatting in a shorter documentation block.
##
## [b]Formatting:[/b] [i]italic[/i], [u]underline[/u], [s]strike[/s]
## [color=cyan]Colored text[/color]
## [url=https://docs.godotengine.org]Godot documentation[/url]
##
## References:
##     [Resource]
##     [method Object.get]
##     [member resource_name]
##
## Alignment:
##     name        Description
##     count       Number of entries
##     active      Current state
##
## Repeated  spaces  should  remain.
##     Leading indentation should remain.
##
## [codeblock]
## var example := TooltipTestResource.new()
## example.count = 10
## [/codeblock]
##
## Keyboard shortcut: [kbd]Ctrl+Shift+S[/kbd]
class_name TooltipTestResource
extends Resource

@export var name: String
@export var count: int
@export var active: bool

# This ordinary comment must not appear as class documentation.
func test() -> void:
	pass
