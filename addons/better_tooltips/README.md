# Better Tooltips

**Better Tooltips** extends Godot 4.7.2+ with richer tooltips throughout the editor.
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
- Persistent preview cache and configurable modules

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

GDScript files show their class documentation first when available, followed by the source text. Files without `class_name` or class documentation still show the source. Long descriptions and source text remain separately scrollable in one tooltip.

The same live text renderer is used for statically resolvable `res://` / `uid://` paths in CodeEdit and Godot's open-file list.

It also supports outline entries and file tabs in both **Quill-IDE by Rayyan Aziz** and **Script-IDE by Marius Hanl**.

Long text scrolls inside the tooltip instead of using graphical zoom.

Markdown and generic text previews can be enabled independently.

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

- enable or disable individual tooltip modules
- configure Code Editor documentation behavior
- enable or disable Quill-IDE and Script-IDE integration
- set text/code tooltip font scaling and maximum width/height (independently of graphical previews)
- adjust graphical preview size
- adjust tooltip background contrast
- configure the preview safety limit
- clear generated tooltip caches

Changes apply immediately.

## Preview Cache

Generated graphical previews are cached persistently per project under:

`res://.godot/better_tooltips/`

A RAM cache is also used for recently displayed previews.

Changed resources and detected dependencies invalidate their cached previews automatically.

Hold **Shift while hovering** a supported resource to force the preview to be regenerated.

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
