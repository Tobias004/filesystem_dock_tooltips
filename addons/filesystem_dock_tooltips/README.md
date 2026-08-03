# FileSystem Dock Documentation Tooltips for .gd Scripts

Godot editor plugin for Godot 4.5 and newer. It extends the standard tooltip for GDScript files in the FileSystem dock with the script's `class_name` and class documentation.

## Installation

Copy `addons/filesystem_script_doc_tooltips` into the root of the Godot project, then enable **FileSystem Script Documentation Tooltips** under **Project > Project Settings > Plugins**.

The ZIP archive is structured so that it can be extracted directly into the project root.

## Supported documentation styles

Godot's documented style places script documentation after `class_name` and `extends`:

```gdscript
class_name TooltipTestComponent
extends Node

## Demonstrates the tooltip documentation features.
##
## [b]Bold text[/b]
## [i]Italic text[/i]
## [color=orange]Colored text[/color]
```

Documentation directly above `class_name` is also supported:

```gdscript
## Alternative documentation placement above [code]class_name[/code].
##
## This class can be used to test the second supported placement.
class_name TooltipTestResource
extends Resource
```

Only `.gd` files with a `class_name` and a non-empty `##` documentation block are extended.

## Source-like layout

The tooltip keeps the layout of the documentation comment:

```gdscript
## Parameters:
##     speed       Movement speed
##     direction   Normalized movement direction
##     enabled     Enables or disables movement
##
## This    line    contains    repeated    spaces.
```

The plugin removes only:

* indentation before `##`,
* the `##` prefix,
* one conventional space immediately after `##`.

Line breaks, blank lines, leading indentation, repeated spaces, tabs, and trailing spaces are otherwise retained. The editor's code font is used. Tooltip width follows the longest source line up to a maximum width; longer lines wrap as a fallback.

## Documentation markup

The tooltip uses `RichTextLabel` and supports its common BBCode formatting:

```gdscript
## [b]Bold text[/b]
## [i]Italic text[/i]
## [u]Underlined text[/u]
## [s]Strikethrough text[/s]
## [color=orange]Colored text[/color]
## [code]inline_code()[/code]
## [url=https://godotengine.org]Godot website[/url]
## First line[br]Second line
```

Godot-specific references such as `[Node2D]`, `[method Node.add_child]`, and `[member speed]` are shown in code formatting:

```gdscript
## Godot references:
##     Class:    [Node2D]
##     Method:   [method Node.add_child]
##     Member:   [member speed]
```

`[codeblock]` and `[kbd]` are approximated using `[code]` because `RichTextLabel` does not provide those exact tags:

```gdscript
## [codeblock]var value := 42[/codeblock]
## Press [kbd]Ctrl+S[/kbd] to save.
```

## Test scripts

The following scripts can be used to test the supported documentation positions, formatting tags, source layout, width calculation, and fallback wrapping.

### Documentation after `class_name` and `extends`

```gdscript
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
```

### Documentation before `class_name`

```gdscript
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
```

### Negative test

A script without `class_name` or without a `##` documentation block must retain the standard FileSystem tooltip:

```gdscript
extends Node

# This ordinary comment must not appear as class documentation.

func test() -> void:
	pass
```

## Implementation

The plugin uses the official `EditorResourceTooltipPlugin` API registered through `FileSystemDock`. It reads the hovered script as text and does not load or instantiate the script resource.
