# Better Tooltips

Better Tooltips extends Godot's editor tooltips with project documentation, visual resource previews, Markdown/text previews and additional context directly where you work.

( Note: The project was originally released as **FileSystem Dock Tooltips.** -> Attention: Note the [upgrading section](#attention-upgrading-from-filesystem-dock-tooltips-2x) )

Instead of opening a file or resource just to inspect it, hover it in the FileSystem dock, Code Editor or supported navigation controls.

## Code tooltips

Better Tooltips adds project documentation to Godot's existing GDScript symbol tooltips while keeping Godot's native title/signature and engine API documentation.

Supported project symbols include, where Godot can resolve them reliably:

- `class_name` classes
- functions and methods
- properties and variables
- exported properties
- signals
- constants
- enums and enum values
- inner classes

Documentation works at declarations and at many use sites, including cross-script project classes. The add-on uses a shared Godot-themed renderer for `##` documentation and can optionally show contiguous single-`#` implementation documentation.

The Code Editor can also show additional context for supported project resource references, Input/InputMap action names, scene-aware NodePaths (`$`, `%`, `get_node()`) and ProjectSettings keys.

## Resource previews

Generated visual previews are available for resource types where Godot's normal tooltip provides little visual information:

- 3D materials and supported ShaderMaterials
- meshes
- fonts
- spatial and canvas-item shaders
- SpriteFrames
- themes
- StyleBoxes
- Curve, Curve2D and Curve3D
- gradients
- environments
- skies

The same graphical preview pipeline can be reused in FileSystem, Code Editor and supported navigation tooltips. Texture and audio previews are intentionally left to Godot itself. PackedScene auto-rendering is intentionally excluded because hovering should not instantiate arbitrary scenes or execute `@tool` behavior.

Graphical previews support temporary mouse-wheel zoom. The configured default size remains unchanged; wheel zoom affects only the current hover. Previews are constrained to the usable screen area.

## Markdown and text previews

Markdown (`.md`, `.markdown`) and other supported text files can be previewed directly in tooltips. Markdown keeps common formatting such as headings, emphasis, lists, quotes, code and links. Long files scroll inside the tooltip instead of using graphical zoom.

The same text renderer is used in FileSystem, Code Editor, Godot's open-file list and compatible Quill/Script-IDE navigation surfaces.

## Tooltips throughout the editor

Better Tooltips integrates with:

- FileSystem dock
- GDScript Code Editor
- Godot's script/open-file navigation controls
- Quill IDE script tabs and outline (optional)
- Script-IDE script tabs and outline/navigation controls (optional)

## Quill-IDE and Script-IDE Integration

Better Tooltips optionally integrates with **Quill-IDE** by Rayyan Aziz and **Script-IDE** by Marius Hanl.

Their script tabs and outline entries can show the same class/member documentation and resource previews used elsewhere in the editor.
The third-party plugins are only observed at runtime and are not modified.

Integration can be enabled or disabled separately for each plugin.
Third-party editor plugins are observed at runtime and are not modified. Quill IDE and Script-IDE integrations can be disabled independently.

## Cache and performance

Generated previews use a bounded RAM hot cache plus a persistent project-local cache under `.godot/better_tooltips/`. Cache keys include the source resource and relevant dependencies, so changed resources regenerate automatically.

Hold **Shift while hovering** to force-regenerate a graphical preview and bypass the current cache/failure state for that attempt.

## Settings

Open:

**Project > Tools > Better Tooltips > Settings...**

Settings include:

- individual tooltip/preview modules
- Code Editor documentation behavior
- Quill IDE / Script-IDE compatibility switches
- default graphical preview size
- preview-generation safety limit
- tooltip background contrast
- cache clearing

A local documentation syntax reference is available under:

**Project > Tools > Better Tooltips > Documentation Syntax...**

## Installation

Copy:

`addons/better_tooltips`

into the project root and enable **Better Tooltips** under:

**Project > Project Settings > Plugins**

# ATTENTION: Upgrading from FileSystem Dock Tooltips 2.x

Version 3.0 changes the add-on directory. Disable the old plugin and close Godot, **delete** `addons/filesystem_dock_tooltips`, then copy `addons/better_tooltips` into the project and enable **Better Tooltips**. Do not keep both add-on directories installed at the same time.Compatibility

Godot 4.7 and newer are supported.
