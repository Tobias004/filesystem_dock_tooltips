# Changelog


## 3.0.5

### Improvements
- Added scrollable source-code previews for `.gd` files. Scripts with class documentation show both the documentation and source code; undocumented scripts show the source directly.
- Added Markdown table support with formatted headers, aligned columns, cell borders and inline formatting.
- Improved Markdown formatting with clearer headings, styled quotes, code blocks, links and lists, inspired by VS Code.
- Made Markdown and plain-text previews more compact by reducing excessive line and paragraph spacing without changing font sizes.

### Fixes
- Improved keyboard handling: Escape closes tooltips immediately, while normal keys and function-key shortcuts are forwarded to Godot.
- Kept scrolling and text selection available inside interactive tooltips.
- Fixed oversized text tooltips by limiting their height and making long content scrollable.
- Fixed tooltip scrolling errors caused by an invalid screen-coordinate API call.

## 3.0.1
### Fixes

- Fixed Quill IDE and Script-IDE outline tooltips for constants referencing a GDScript with `preload()`/`load()`. The outline now displays the referenced script's class documentation, matching Code Editor tooltips (for example, `TargetScript` in the Code Tooltip showcase).
- Fixed long native Code Editor symbol/help tooltips extending beyond the usable screen area. Their text is now height-limited and scrollable, and the tooltip window is repositioned within the usable screen after layout.

## 3.0
### Better Tooltips

- Renamed the add-on from FileSystem Dock Tooltips to Better Tooltips to reflect that tooltip features now extend well beyond the FileSystem dock.
- Renamed the add-on directory to `addons/better_tooltips` and the public GDScript class prefix from `FSDT` to `BT`.
- Existing 2.x project-scoped settings are migrated automatically when first read. Generated preview caches start fresh under `.godot/better_tooltips/`.

### Code and documentation tooltips

- Added project documentation directly to GDScript symbol tooltips in the Code Editor while retaining Godot's native symbol title/signature and engine/API help.
- Added documentation for project classes, functions, properties, exported properties, signals, constants, enums, enum values and inner classes at declarations and supported use sites.
- Added cross-script documentation when Godot resolves a project `class_name` owner, plus source-only lookup for common script aliases declared with `preload()` or `load()`.
- Added optional single-`#` implementation documentation alongside normal Godot `##` documentation.
- Added a shared Godot-themed documentation renderer with preserved line breaks, formatting tags, code blocks, links, references and metadata such as tutorials, deprecation and experimental notices.
- Added contextual Code Editor tooltips for statically resolvable project resource references, Input/InputMap action names, scene-aware `$`/`%`/`get_node()` NodePaths and ProjectSettings keys.
- Long add-on documentation is height-limited and scrollable instead of growing beyond the usable editor area.

### Tooltips throughout the editor

- Added documentation tooltips to Godot's script/open-file navigation surfaces.
- Added optional Quill IDE and Script-IDE integration for script tabs and outline/navigation entries without modifying either third-party plugin.
- Added graphical resource previews to supported Quill/Script-IDE navigation entries when their source resolves to a supported resource.
- Added independent compatibility switches for Quill IDE and Script-IDE integration.

### Markdown and text previews

- Added formatted Markdown previews for `.md` and `.markdown` files.
- Added generic previews for other Godot text files.
- Markdown/text previews use the same live renderer in the FileSystem dock, Code Editor, Godot's open-file list and supported Quill/Script-IDE surfaces.
- Long text previews scroll inside the tooltip and do not use graphical preview zoom.
- Increased the text safety cap to 2 MiB / 8000 lines so truncation is limited to unusually large files.

### Resource previews and interaction

- Resource previews can now appear inside Code Editor and navigation tooltips in addition to the FileSystem dock.
- Added temporary mouse-wheel zoom for graphical previews without modifying the configured cached preview size.
- Graphical tooltips keep the pointer at a stable relative position while resizing and are constrained to the usable screen area.
- Unified graphical preview sizing, margins and layout across FileSystem and code/navigation tooltips.

### Caching and performance

- Added a persistent project-local preview cache so unchanged generated previews can be reused across editor sessions.
- Added a bounded 32 MiB RAM hot cache for repeated hovers.
- Cache invalidation follows the source resource and recursively discovered external dependencies.
- Holding Shift while hovering force-regenerates a preview and bypasses remembered cache/failure state for that attempt.
- Added a configurable preview-generation safety limit and cache-clearing controls.

### Settings and usability

- Expanded the settings dialog for module switches, code-documentation behavior, optional IDE integrations, preview size, safety limit and tooltip background contrast.
- Added a local Documentation Syntax... help dialog rendered by the same documentation renderer used by tooltips.
- Improved theme integration so add-on-owned documentation and preview sections follow Godot editor fonts, semantic colors and spacing.
- Added numerous fixes for tooltip startup/rebinding, popup layout, clipping, wheel input, cache invalidation and integration stability.

The minimum supported Godot version is now 4.7 (raised from 4.5).

## 2.1.1

- Refactored the add-on architecture without changing tooltip behavior.
- Reduced `plugin.gd` to the Godot `EditorPlugin` lifecycle and moved add-on orchestration into `filesystem_dock_tooltips.gd`.
- Moved the GDScript documentation tooltip into `modules/script_documentation_tooltip.gd` alongside the other tooltip modules.
- Added purpose and behavior comments to the refactored functions.
- Kept the add-on compatible with Godot 4.5 and newer.

## 2.1.0

- Added feedback option via GitHub ( Project -> Tools -> FileSystem Dock Tooltips -> Feedback ).
- Added a settings dialog that allows specific tooltips to be disabled ( Project -> Tools -> FileSystem Dock Tooltips -> Settings... ).

## 2.0.0

- Added central module enable/disable constants.
- Added `DEBUG_MESSAGES` source-code constant; release default is `false`.
- Added generated 3D previews for `BaseMaterial3D` and spatial `ShaderMaterial`.
- Added a generated studio panorama for broader PBR material reflections.
- Added Mesh previews with automatic AABB-based camera fitting.
- Added Font sample previews.
- Added `.gdshader` previews for spatial and canvas-item shaders.
- Added SpriteFrames contact-sheet previews.
- Added representative Theme previews.
- Added StyleBox previews.
- Added Curve, Curve2D and Curve3D previews.
- Added Gradient previews with transparency checkerboard.
- Added Environment previews with fixed reference objects.
- Added Sky previews.
- Kept all preview types as independent modules.
- Kept the original GDScript documentation tooltip as an independent module.
- Texture and audio previews remain handled by Godot itself.
- PackedScene auto-rendering remains intentionally excluded.
- Added explicit test-asset provenance/license documentation.
