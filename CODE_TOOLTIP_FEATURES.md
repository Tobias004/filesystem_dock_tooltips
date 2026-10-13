# Code Tooltips

Better Tooltips extends Godot's project-code tooltips. It keeps Godot's native API documentation, while adding project documentation in places where Godot normally shows little or no information.

For project code, the add-on uses its own documentation renderer. This preserves formatting such as explicit line breaks and avoids some clipping seen in Godot's compact project-documentation tooltips.

> In the examples below, `^` marks the cursor position that triggers the tooltip.

## Where code tooltips can appear

### Inside the Code Editor

Hover documented project symbols directly in GDScript code.

Supported symbols include, where they can be resolved reliably:

- script classes (`class_name`)
- functions and methods
- properties and variables
- exported properties
- signals
- constants
- enums and enum values
- inner classes

Tooltips can appear both at declarations and at many use sites.

```gdscript
var enemy: Enemy
             ^

enemy.health -= 10
        ^

enemy.damage(10)
        ^
```

If `Enemy`, `health` or `damage()` are documented in `enemy.gd`, the add-on can resolve the owning project class and show that documentation without opening the source file first.

This is especially useful when working with typed project classes spread across several scripts.

### Project class names and script aliases

Project `class_name` types can show their class documentation when used as types, return values or parameters:

```gdscript
var controller: BTController
                     ^

func create_controller() -> BTController:
                                 ^
```

Script aliases created with `preload()` or `load()` can also resolve to the documentation of the referenced script:

```gdscript
const TooltipCache := preload("res://tooltip_cache.gd")
          ^

var cache := TooltipCache.new()
                 ^
```

### Resource and project-file previews in code

Supported resources referenced by a literal `preload()` or `load()` can use the same generated preview as the FileSystem dock. Hover the variable or constant that holds the resource:

```gdscript
const MATERIAL := preload("res://materials/metal.tres")
      ^

@export var ui_theme: Theme = preload(
            ^
    "res://ui/main_theme.tres"
)

func configure() -> void:
    var response_curve := load("res://curves/response.tres")
        ^
```

Script members and local variables are supported. Typed/exported declarations, multiline calls and `uid://` references are also resolved. If Godot already creates a native symbol tooltip, the preview is appended to it; otherwise a narrow add-on fallback can show the preview for a locally resolvable symbol.

The preview uses the same enabled resource modules and the same RAM/persistent cache as FileSystem previews. Holding **Shift while hovering** therefore also force-regenerates a Code Editor resource preview. Graphical Code Editor previews use the same wheel-zoom, symmetric padding and dynamic screen-size limit as FileSystem previews. Wheel zoom continues to work when the pointer is moved from the code onto the graphical tooltip itself because the popup window forwards its own input into the shared preview session. If the pointer is inside the tooltip while it is resized, its normalized position is preserved so shrinking does not strand the pointer outside the popup.

Resource paths can also be previewed directly by hovering the quoted path inside `preload()` or `load()`:

```gdscript
var material := preload("res://materials/metal.tres")
                               ^
```

Simple Resource aliases are followed when the assignment is only another identifier:

```gdscript
const ORIGINAL := preload("res://materials/metal.tres")
const ALIAS := ORIGINAL
      ^
const ALIAS_2 := ALIAS
      ^
```

Alias following is intentionally conservative: it is source-only, limited to a short chain and does not evaluate function calls, member access or computed expressions.

Only source references that can be resolved safely are followed. A variable assigned at runtime, an exported property whose value exists only in a scene/Inspector instance, or a dynamically constructed resource path is not guessed from source code.

Direct quoted project-file strings are also supported when an enabled preview module recognizes the referenced path. This includes Markdown and generic `TextFile` previews, so `const README_PATH := "res://README.md"` can be hovered as a symbol, direct literal, compatible Quill/Script-IDE outline member, Godot open-file entry, or compatible IDE top tab. Short alias chains use the same source-only resolver. Markdown/text previews stay as one shared live RichTextLabel-based UI in every host, use normal editor font sizing, scroll when tall, and never use graphical wheel zoom.

### Input actions

Hover action-name strings used by common `Input`/`InputMap` calls:

```gdscript
Input.is_action_just_pressed("ui_accept")
                              ^
InputMap.action_get_events("ui_cancel")
                            ^
```

The tooltip reports whether the action exists and lists its configured input events.

### Node paths and unique node names

When the currently edited scene provides an unambiguous base, hover `$` paths, `%UniqueName` references or literal paths passed to `get_node()`, `get_node_or_null()`, `has_node()` or `NodePath()`:

```gdscript
var camera := $Player/Camera2D
                         ^
var player := %Player
               ^
var hud := get_node("UI/HUD")
                         ^
```

Resolved nodes show their scene path, native type, attached script and project `class_name`. If that class has documentation, it is rendered in the same tooltip.

Variables and constants initialized from those expressions resolve to the same node information when hovering the symbol itself; explicit typing is not required:

```gdscript
var target: Node = $PreviewTarget
    ^
var alias: Node = target
    ^
var target_from_call = get_node("PreviewTarget")
    ^
```

As with Resource aliases, Node-reference aliases are source-only and limited to a short chain of bare identifiers. Dynamic assignments and arbitrary expressions are not evaluated.

### ProjectSettings keys

Hover literal setting keys used by common `ProjectSettings` calls:

```gdscript
ProjectSettings.get_setting("application/config/name")
                                      ^
```

The tooltip shows whether the setting exists, its current Variant type and its current value.

### Godot's Script list

Hover a GDScript in Godot's standard Script list to see the documented class description for that script.

This is useful when several scripts are open and the filename alone does not describe their purpose.

### Quill IDE

When the optional Quill IDE integration is enabled:

- hovering a script tab can show the class documentation while keeping Quill's normal `res://...` path information
- hovering members in Quill's outline can show their documentation
- Resource constants/properties in the outline can show the same graphical preview as the normal Code Editor, including aliases and mouse-wheel zoom

Graphical outline previews do not require a documentation comment; supported Resources without docs get a compact symbol title above the preview. The integration does not modify Quill itself and can be disabled independently.

### Script-IDE

Script-IDE is supported in the same way:

- script tabs can show class documentation
- outline entries can show documentation for supported members
- supported Resource constants/properties in the outline use the shared graphical preview/cache/zoom pipeline

Script-IDE support can also be disabled independently.

> Quill IDE and Script-IDE are alternative editor-layout plugins. Better Tooltips supports either integration separately.

## Differences from standard Godot

| Feature | Standard Godot | Better Tooltips |
| --- | --- | --- |
| Optional ordinary `#` comment blocks as local docs | No | Yes |
| Class documentation in the Script list | No | Yes |
| Quill IDE tabs and outline | No | Yes |
| Script-IDE tabs and outline | No | Yes |
| Resolve documented members from another typed project class | Limited by native tooltip behavior | Yes |
| Project `class_name` tooltip fallback | Limited | Yes |
| Resolve `preload()` / `load()` script aliases | Limited | Yes |
| Visual previews for supported resource references in code and compatible IDE outlines | No | Yes |
| Direct preview on `preload()` / `load()` path strings | No | Yes |
| Follow simple Resource aliases | No | Yes |
| Input action details on action strings | No | Yes |
| Scene-aware NodePath details, including variables/aliases | No | Yes |
| ProjectSettings value/type on key strings | No | Yes |
| Preserve explicit documentation line breaks | Limited | Yes |
| Avoid compact project-doc tooltip clipping | Limited | Improved rendering |
| Same project-doc formatting across editor locations | No | Yes |
| Project `##` documentation in code | Yes | Can be rendered by the add-on |
| Godot engine/API documentation | Yes | Kept native |

Comparison based on Godot 4.7 without the add-on.

## `##` documentation comments

Standard Godot documentation comments remain the main documentation source:

```gdscript
## Applies damage to this enemy.
##
## Returns [code]true[/code] when the hit was fatal.
func damage(amount: int) -> bool:
       ^
```

When Godot's native tooltip already contains the same project documentation, the add-on can replace only that description while keeping Godot's native symbol header and signature.

For example, Godot can still provide:

```text
Method Enemy.damage(amount: int) -> bool
```

while the descriptive part is rendered by Better Tooltips.

## Optional single-`#` comments

Ordinary comments directly above a declaration can optionally be treated as local editor documentation:

```gdscript
# Creates the controller used by this editor plugin.
# The controller owns the add-on modules.
func _enter_tree() -> void:
         ^
```

This is useful for implementation notes that should be visible while navigating code but should not become part of Godot's official `##` API documentation.

Single-`#` support can be disabled separately.

## Local project documentation plus Godot API documentation

For overridden Godot methods, both kinds of information can be useful.

```gdscript
# Registers this add-on's controller.
func _enter_tree() -> void:
         ^
```

The tooltip can show:

1. the local project comment explaining what this implementation does
2. Godot's native documentation explaining what `EditorPlugin._enter_tree()` does in general

Godot's engine/API documentation therefore remains available where it provides additional information.

## Consistent formatting

Code tooltips use the same documentation renderer as the add-on's GDScript documentation tooltips.

Supported documentation includes Godot-style references and common formatting:

```gdscript
## Uses [Node], [method Node.add_child] and [member Node.owner].
##
## [b]Important:[/b] Call [code]setup()[/code] before use.
##
## [codeblock lang=gdscript]
## var cache := TooltipCache.new()
## cache.setup(self)
## [/codeblock]
```

For the complete supported documentation syntax, see `DOCUMENTATION_SYNTAX.txt`.

## Settings

The Code Editor documentation features can be adjusted independently:

- show Godot-style `##` documentation comments
- show ordinary single-`#` comment blocks
- replace Godot-rendered project documentation with the add-on renderer
- enable or disable Quill IDE integration
- enable or disable Script-IDE integration
- adjust the background contrast of add-on tooltip sections

The resource-preview module switches also control which generated previews may appear in Code Editor tooltips.

The external IDE integrations can be disabled separately if a future version of Quill IDE or Script-IDE changes its editor layout.

## Resolution limits

The add-on only shows project documentation when it can resolve the hovered symbol with sufficient confidence.

Typed values are therefore more reliable:

```gdscript
var enemy: Enemy
enemy.damage(10)
        ^
```

For completely untyped or ambiguous values, the add-on does not guess. In those cases Godot's normal tooltip behavior is left unchanged.
