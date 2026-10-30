# Changelog

## 3.2.0 (2026-10-28)

Includes the improvements from the unreleased 3.1.0 development version.

### New and improved

- Added documentation and source-code previews for methods in Godot's **Filter Methods** list and compatible Quill-IDE / Script-IDE outlines. Undocumented methods show their source directly.
- Improved mouse-wheel scrolling, tooltip hover persistence and scrollbar dragging across FileSystem, editor navigation and supported IDE integrations.
- Added clickable links in Markdown previews, including web links, project file links and heading anchors.
- Added adjustable font scaling and maximum width/height for text and code tooltips. The default text font is one point smaller than the editor theme font. Graphical previews are unaffected.
- Added **Reset to Defaults** to the settings dialog, with confirmation.

### Fixes

- Reduced large navigation tooltip resizing/flickering by completing text layout before showing the existing popup.
- Fixed interactive text previews intercepting FileSystem dock clicks and double-clicks.
- Fixed several issues with navigation tooltip closing, scroll-wheel routing, Markdown links and large popup layout.

## 3.1.0 (unreleased development build; included in 3.2.0)

### Improvements

- Added documentation and method-source previews to Godot's built-in **Filter Methods** list and to function entries in Quill IDE and Script-IDE outlines. Methods without inline documentation show their source code directly.
- Added support for both Godot 4.7's method list and Godot 4.8's grouped method tree.
- Unified mouse-wheel scrolling for interactive text, Markdown and method-source tooltips across the FileSystem dock, Godot's script navigation, Quill IDE and Script-IDE. When a tooltip can scroll, the wheel scrolls the tooltip instead of the editor list behind it.
- Unified tooltip lifetime handling for FileSystem text previews, navigation popups and add-on-owned Code Editor fallback popups, including grace timing and protection while dragging scrollbars.
- Refactored the preview pipeline into separate generator, presenter, zoom, wheel-routing and lifetime components while keeping the pipeline as the public facade. This is an internal maintainability change with no intended feature loss.

### Fixes

- Fixed Quill IDE and Script-IDE outline tooltips closing while the pointer crosses a neighboring method on the way into the popup. A different method replaces the visible tooltip only after a stable hover; returning to the original entry or entering the popup cancels the pending switch.
- Preserved the original hovered item rectangle through the popup delay, also for Godot's built-in Filter Methods list.
- Fixed Markdown links displaying raw `[lb]`/BBCode fragments. HTTP(S), project-relative file links and in-document heading anchors are now rendered as interactive links, including links inside Markdown tables.
- Preserved mouse input for clickable links in short Markdown previews, without changing shared popup scrolling or lifetime handling.
- Included the `SUPPORT.md` referenced by the bundled README so its relative link has a valid target.
- Fixed detection of Godot 4.7.2's built-in Filter Methods list and Godot 4.8's method tree.
- Fixed wheel events scrolling the underlying Filter Methods, Quill IDE or Script-IDE list instead of a long open tooltip.
- Fixed an invalid `RichTextLabel.get_screen_rect()` call when selecting the scrollable text section under the pointer.
- Cleaned up navigation popups when their observed editor controls disappear, without affecting the other integrations.
- Fixed Code Editor fallback tooltips closing immediately when moving the pointer from the code into the popup; scrollable fallback text now uses the shared wheel routing.
- Prevented a visible graphical preview from consuming mouse-wheel input in unrelated editor areas.
- Made the optional graphical zoom controller load independently so text previews and cached graphical previews can still work if zoom is unavailable.

## 3.0.5
### Preview improvements

- Added Markdown pipe-table rendering with real RichTextLabel table cells, bold headers, borders, alternate row backgrounds, alignment and inline formatting.
- Added a scrollable source-text preview for `.gd` files, including scripts without class-level documentation. For documented scripts, existing class help appears above the source preview.
- Unified GDScript file tooltips with the existing live-text pipeline so the source and class help can remain interactive, scroll independently, and use the existing Escape/keyboard forwarding behavior.
- Limited the combined height of class help plus source to prevent multi-section tooltips from overflowing the screen.

### Fixes

- Matched generic plain-text (`.txt`/`TextFile`) preview line and paragraph spacing to the compact Markdown renderer without changing font size or whitespace in the source file.
- Fixed excessive vertical spacing in Markdown previews: compact theme line/paragraph separation, collapsed redundant blank lines, and removed extra paragraphs around headings, lists and fenced code blocks. The same Markdown file now fits substantially more content on screen without reducing the editor's document font size.
- Preserved the richer Markdown presentation introduced during testing (more distinct headings and separators, styled quotes, code spans/blocks, links and ordered lists), now with denser VS Code-inspired spacing.
- Improved keyboard handling for interactive text/Markdown tooltip popups: Escape closes the tooltip immediately; ordinary keys and function-key shortcuts close it and are forwarded to the Godot editor. Navigation/scroll keys and Ctrl+C for selected tooltip text remain handled by the tooltip.

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

The minimum supported Godot version is 4.7.2 (raised from 4.5).

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
