# Better Tooltips

**Better Tooltips 3.3.1** extends Godot 4.7.2+ with richer tooltips throughout the editor.
( The project was originally released as **FileSystem Dock Tooltips** )

It adds project documentation, visual resource previews, Markdown/text previews and contextual information directly where you are already working - without opening additional files or inspectors.

## Highlights

- Rich GDScript documentation tooltips for classes, methods, properties, signals, constants, enums and inner classes
- Documentation at both declarations and use sites, including members from other project scripts
- Visual previews for materials, meshes, fonts, shaders, SpriteFrames, themes, StyleBoxes, curves, gradients, environments and skies
- Markdown (including pipe tables), generic text and GDScript source previews
- Contextual tooltips for NodePaths, Input actions and ProjectSettings keys
- Resource previews directly from `preload()`, `load()` and resource variables in GDScript
- Tooltips in Godot's FileSystem dock, Code Editor and script navigation
- Optional tooltip integration for **Quill-IDE by Rayyan Aziz** and **Script-IDE by Marius Hanl**
- Scrollable long documentation/text tooltips and mouse-wheel zoom for graphical previews
- Optional scene-component documentation via `COMPONENT_CONTRACT` (disabled by default)
- Persistent graphical-preview cache, RAM cache for component documentation and configurable modules

## Code Tooltips

Better Tooltips extends Godot's normal GDScript tooltips with project documentation and additional context.

```gdscript
## Enemy currently controlled by the player.
var enemy: Enemy

## Applies damage to this enemy.
func damage(amount: int) -> void:
    health -= amount

enemy.damage(10)
enemy.health -= 5
```

Hover `Enemy`, `damage` or `health` to see the corresponding project documentation.

Resource references can show visual previews directly in the Code Editor:

```gdscript
const MATERIAL := preload("res://materials/metal.tres")
const README := "res://README.md"
```

Hover `MATERIAL`, the resource path, `README` or the quoted project-file path.

Godot-specific strings and paths can also provide useful context:

```gdscript
var player := $Player

Input.is_action_pressed("ui_accept")

ProjectSettings.get_setting(
    "display/window/size/viewport_width"
)
```

Hover `$Player`, `"ui_accept"` or the ProjectSettings key.

## Standard Godot method overview

Hovering a function in the built-in **Filter Methods** outline shows its documentation (when available) followed by a scrollable source-code preview of that function. Undocumented functions show their source directly. The integration supports Godot 4.7's method list and Godot 4.8's grouped method tree. While a scrollable tooltip is open, the mouse wheel scrolls its text instead of moving the underlying method list.

## Quill-IDE and Script-IDE Integration

Better Tooltips optionally integrates with **Quill-IDE by Rayyan Aziz** and **Script-IDE by Marius Hanl**.

Their script tabs and outline entries can show the same class/member documentation and resource previews used elsewhere in the editor. Function entries also include a source-code preview, even when no documentation comment exists.

The third-party plugins are only observed at runtime and are not modified.

Integration can be enabled or disabled separately for each plugin.

## Resource Previews

Better Tooltips can generate visual previews for:

- Materials
- Meshes
- Fonts
- `.gdshader` files
- SpriteFrames
- Themes
- StyleBoxes
- `Curve`, `Curve2D` and `Curve3D`
- Gradients
- Environments
- Skies

The same preview system is used in the FileSystem dock, Code Editor and supported navigation/IDE integrations.

Texture and audio previews are not duplicated because Godot already provides dedicated previews for them.

Graphical previews can be resized temporarily with the mouse wheel while the tooltip is open.

## Markdown and Text Previews

Markdown (`.md` / `.markdown`), ordinary Godot `TextFile` entries and GDScript (`.gd`) source can be previewed directly from the FileSystem dock. Markdown pipe tables render with real cells, styled header rows, borders and column alignment.

GDScript files show their script-level documentation first when available, followed by the source text. This also works without `class_name` (the filename is used as the title). Undocumented scripts still show the source. Long descriptions and source text remain separately scrollable in one tooltip.

The same live text renderer is used for statically resolvable `res://` / `uid://` paths in CodeEdit and Godot's open-file list.

It also supports outline entries and file tabs in both **Quill-IDE by Rayyan Aziz** and **Script-IDE by Marius Hanl**.

Long text scrolls inside the tooltip instead of using graphical zoom.

Markdown and generic text previews can be enabled independently.

## Implementation notes (3.3.0)

Better Tooltips can separate **architecture / integration notes** from the normal
GDScript class description. The script stays fully compatible with Godot's native
`##` documentation, and **no `COMPONENT_CONTRACT` is required**.

Write the following native BBCode wrapper inside the class documentation:

```gdscript
class_name OSCReceiver
extends Node

## Receives OSC messages and forwards valid addresses.
##
## [color=#888888][i]Implementation notes[/i][br]
## The UDP transport is intentionally kept separate from scene routing.
## Replace the transport adapter without changing consumer scenes.
## [/color]
```

The first paragraph remains normal, prominent class help. The implementation
notes appear below with a thin theme-colored left rule and muted typography.
The original BBCode is unchanged in the source and remains readable in Godot
without Better Tooltips. This also applies to classes with `COMPONENT_CONTRACT`.

Script help works through normal `.gd` FileSystem and Code Editor documentation.
In the live **Scene dock**, nodes with an attached GDScript now receive the same
rich class-description/Implementation-notes presentation when **FileSystem
GDScript documentation** (enabled by default) is active. No
`COMPONENT_CONTRACT` or `class_name` is necessary. Even undocumented scripts
show their script identity, while nodes without a script retain native help.

The separately enabled **Component documentation** module adds contract API
information to the same Scene-dock popup. When this module is enabled by itself,
notes-only scenes are also documented. For `.tscn` and `.scn` FileSystem resource
hovers, the optional component module remains necessary; ordinary `.gd` class
help keeps its existing independent toggle.

## Scene Component Documentation (3.3.0, opt-in)

Reusable scenes and scripts can expose an integration contract using a
`COMPONENT_CONTRACT` constant. The feature is **off by default**. Enable
**Component documentation (opt-in)** under `Project > Tools > Better Tooltips >
Settings...`; click the `?` button beside the option for a built-in guide and
example. No special configuration is required for ordinary scenes.

```gdscript
## Reusable status display that reads from a source node.
const COMPONENT_CONTRACT: Dictionary = {
    "version": 1,
    "required": [&"data_source"],
    "optional": [&"caption"],
}

## Source used by this display.
@export var data_source: Node

## Optional label above the status.
@export var caption: String = "Status"
```

The listed names must refer to exported properties. Their types, documented
signals and documented public methods are read automatically from the script.
`required` describes an expectation; the addon does **not** validate bindings or
create editor warnings. The scene root's `editor_description` provides optional
assembly guidance.

Hover a contracted `.tscn`, `.scn` or `.gd` file in the FileSystem dock (or a
supported resource reference in the Code Editor) to see the complete reference.
For scene files, the contract must belong to the **root node's script** or an
inherited script. The file tooltip reads saved assignments without instantiating
the scene. In the Scene dock, the node owning the contract uses the same rich
component presentation style as the FileSystem tooltip, while still showing the
native node text as a small header and including **unsaved Inspector values**.
Child nodes with their own contract are supported there too.

If [Scene Dependency Explorer](https://github.com/Tobias004/scene_dependency_explorer)
is installed, its compact scene hierarchy also displays the same rich
class documentation, Implementation notes and optional component API on hover.
The explorer entries represent **saved scene files**, so their tooltips show
saved assignments rather than unsaved Inspector values. Its original scene-path
tooltip is preserved/restored, and Godot's menus/dialogs continue to take
priority. The integration uses the existing documentation settings and starts
only if the other addon is installed. No modifications to the explorer are needed.

Godot 4.7.2 and 4.8-beta2 were tested. The Scene-dock bridge uses separate,
version-selected NodePath resolver strategies for their different metadata
formats; all other component-documentation logic is shared. The bridge relies
on Godot's internal local Scene-dock tree, so future engine changes may require
adaptation.

For details and limitations see the repository's
[component documentation](../../COMPONENT_DOCUMENTATION.md), also available in
[German](../../COMPONENT_DOCUMENTATION_de.md). Test fixtures and instructions
are in [tests/components/README.md](../../tests/components/README.md).

## Documentation Syntax

GDScript documentation uses Godot's normal `##` documentation-comment syntax.

Common Godot documentation tags such as class references, method references, member references, inline code, code blocks, formatting and links are rendered using the editor's own fonts, sizes and colors.

Better Tooltips can optionally also interpret ordinary `#` comment blocks directly above supported declarations as documentation.

For examples, open:

`Project > Tools > Better Tooltips > Documentation Syntax...`

The dialog uses the same renderer as the actual tooltips.

## Updating an existing installation

Replace the entire `addons/better_tooltips` folder instead of copying files over an older installation. This prevents leftover scripts and duplicate GDScript UID warnings.

## Settings

Open:

`Project > Tools > Better Tooltips > Settings...`

The settings dialog lets you:

- enable or disable individual tooltip modules (component documentation is off by default)
- configure Code Editor documentation behavior
- enable or disable Quill-IDE and Script-IDE integration
- set text/code tooltip font scaling and maximum width/height (independently of graphical previews)
- adjust graphical preview size
- adjust tooltip background contrast
- configure the preview safety limit
- clear graphical-preview and component-documentation caches
- optionally show Better Tooltips diagnostic messages in Godot Output (off by default; engine errors remain visible)

Changes apply immediately.

## Preview and Component Caches

Generated **graphical** previews are cached persistently per project under:

`res://.godot/better_tooltips/`

A RAM cache is also used for recently displayed previews.

Changed resources and detected dependencies invalidate their cached previews automatically.

Hold **Shift while hovering** a supported resource to force the preview to be regenerated.

Component documentation is handled separately in the shared cache: up to
**256 positive or negative scene/script lookup results** are retained in RAM
only (no component-documentation PNGs or disk files). Saved files are rechecked
when their modification time or size changes, including tracked scene/script
dependencies. Shift-hover forces a fresh component read; **Clear Tooltip Caches**
also removes these RAM entries. Edits not yet saved to disk are reflected from
the live Scene-dock node instead of from the file cache. On filesystems with
coarse timestamp resolution, a same-size rewrite within the same timestamp
interval may require a forced refresh.

The Scene-dock hover timer only identifies the hovered node every 250 ms;
script documentation is not reparsed on every tick. Inspector edits refresh
live values, with a one-second fallback for other changes. When the local
Scene-dock tree is unavailable, the tree search is retried every two seconds.

## Installation

Copy:

`addons/better_tooltips`

into the root of a Godot project.

Then enable **Better Tooltips** under:

`Project > Project Settings > Plugins`

Better Tooltips requires **Godot 4.7.2 or newer**.

## Upgrading from FileSystem Dock Tooltips 2.x

Version 3.0 renames the add-on directory.

Before installing Better Tooltips:

1. Disable the old plugin.
2. Close Godot.
3. Delete:

   `addons/filesystem_dock_tooltips`
4. Copy:

   `addons/better_tooltips`

   into the project.
5. Reopen the project and enable **Better Tooltips**.

Do not keep both add-on directories installed at the same time.

Existing project-specific Better Tooltips preferences are migrated from the old metadata namespace when first read.

Generated 2.x preview caches are not migrated.

## Support and Feedback

Found a bug or have an idea?

- [Report a bug](https://github.com/Tobias004/filesystem_dock_tooltips/issues/new?template=bug_report.yml)
- [Send feedback / request a feature](https://github.com/Tobias004/filesystem_dock_tooltips/issues/new?template=feedback.yml)

When the add-on is enabled, the same links are also available from **Project > Tools** in Godot.

See [SUPPORT.md](SUPPORT.md) for additional support information.
