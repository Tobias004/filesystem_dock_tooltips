# Tooltip modules

Module switches are available under **Project > Tools > Better Tooltips > Settings...**. Changes apply immediately and are stored per project in Godot editor metadata outside the project folder.

| Setting | Module | Preview |
| --- | --- | --- |
| Scene-component documentation (opt-in) | `component_documentation_tooltip.gd` + `scene_component_tooltip.gd` | `COMPONENT_CONTRACT`-marked `.gd` and root `.tscn`/`.scn` resources; rich component API in the FileSystem and local Scene dock, including live Inspector assignments |
| FileSystem GDScript documentation | `script_documentation_tooltip.gd` | Godot-formatted `##` documentation for `.gd` files and `.tscn`/`.scn` scene root scripts, even without `class_name` or a contract |
| Code editor / ScriptEditor navigation documentation | `code_editor_documentation_tooltip.gd` + `script_editor_navigation_tooltip.gd` | renders project class/member documentation in Godot symbol help, the stock script list, compatible script tabs and Quill-style member outlines |
| Markdown files | `markdown_preview_tooltip.gd` | shared live/scrollable Markdown preview for `.md` / `.markdown` TextFile entries |
| Text files | `text_file_preview_tooltip.gd` | shared live/scrollable source-text preview for other Godot `TextFile` entries |
| Materials | material | generated 3D sphere |
| Meshes | mesh | generated 3D geometry, automatic camera fit |
| Fonts | font | rendered text samples |
| Shaders | shader | spatial sphere / canvas-item test texture |
| SpriteFrames | SpriteFrames | contact sheet |
| Themes | theme | representative controls |
| StyleBoxes | StyleBox | representative panel |
| Curves | curve | graph / fitted 2D / projected 3D |
| Gradients | gradient | generated gradient over checkerboard |
| Environments | environment | fixed reference scene |
| Skies | sky | fixed wide-angle view |

The **Show Better Tooltips diagnostics** checkbox controls add-on logs, warnings and errors emitted through `BTDebug` (off by default). This cannot suppress parser or runtime errors generated directly by Godot.

The modules deliberately do not duplicate Godot's own texture and audio tooltip
previews. PackedScene auto-rendering is deliberately excluded.

By default, add-on diagnostics are hidden. All established tooltip modules are enabled by default; **Component documentation** is **disabled by default** and must be enabled explicitly. The `?` button beside the setting opens local usage help.


## Documentation rendering

Better Tooltips routes FileSystem, Code Editor and ScriptEditor navigation documentation through the reusable
`core/documentation_renderer.gd`. It uses Godot's `EditorHelp` theme values for
fonts, sizes, semantic colors and spacing and implements the documentation tags
listed in Godot's GDScript documentation-comment reference. The same renderer
drives **Project > Tools > Better Tooltips > Documentation Syntax...**
and is independent from source extraction. Code Editor tooltips therefore reuse the
same formatting while resolving the current unsaved script first and, when Godot's
own symbol title identifies another project `class_name` owner, the corresponding
project script as well. Top-level `.gd` constants declared through `preload()` or `load()` are also followed to the referenced script class documentation.

The same module also adds class/member documentation to ScriptEditor navigation controls. The stock Godot script list shows the hovered script's documented `class_name`. Optional Quill IDE and Script-IDE bridges add class documentation to their script tabs and member documentation to their outlines using the public control/item metadata each plugin already maintains; neither plugin is modified. Resource constants/properties in either outline are also resolved through the same GDScript Resource-reference parser and central graphical preview pipeline used by CodeEdit, so previews, caching and wheel zoom are not reimplemented by the integrations. Each compatibility bridge has its own project setting and can be disabled completely while the standard Godot CodeEdit/script-list integration remains active. Quill and Script-IDE are tested separately because the editor add-ons conflict when installed together. For script lists and script tabs, the native resource-path tooltip is preserved and documented class information is appended underneath in the same TooltipPanel. Undocumented scripts/items keep their native behavior. Outline member lists without a useful native tooltip continue to use the add-on popup.

The Code Editor module normally augments symbol help that Godot itself creates. It also
handles literal/code-context hovers for supported Resources/project files, Input/InputMap action names,
scene-aware NodePaths (including variables/short aliases initialized from them) and ProjectSettings keys. Resource/file previews reuse the central preview
pipeline and cache; the other contexts add lightweight textual information without creating
a second semantic type system. When Godot's description contains the same project `##` documentation, that native
description can be replaced by the shared add-on renderer while Godot's
title/signature is retained. For a documented project `class_name` token where Godot
creates no tooltip at all, a narrow add-on fallback resolves the class from Godot's
global class registry and displays the same shared documentation renderer without
replacing Godot's tooltip callback. This is enabled by default because the add-on preserves
source line breaks, uses the same formatting as FileSystem documentation and avoids
the compact native project-documentation tooltip being clipped. Godot's built-in API help and
distinct inherited/base-class help are not replaced. Ordinary single-`#` blocks
directly above supported project class/member declarations can optionally be treated
as implementation documentation. `##` display, single-`#` display and replacement of
duplicate Godot project documentation are separate settings. Injected Code Editor
documentation copies Godot's native help-content insets and add-on-owned tooltip
sections use the configurable theme-aware background contrast.

## Scene-component documentation (3.3.0)

`core/component_documentation.gd` reads a `COMPONENT_CONTRACT` dictionary with `"version": 1` and optional `"required"` / `"optional"` lists naming exported properties. It uses GDScript reflection and existing `##` documentation comments for properties, signals and documented public methods. A scene resource is inspected through its saved `PackedScene` root state **without instantiating the scene or calling lifecycle or configuration-warning functions**. The contract describes dependencies but does not enforce assignments.

The component module remains **opt-in**. FileSystem `.tscn`/`.scn`/`.gd` hovers and supported Code Editor resource references use `modules/component_documentation_tooltip.gd` and the normal rich-text preview pipeline. In the local Scene dock, `modules/scene_component_tooltip.gd` is now registered whenever **either** the script documentation or the component documentation module is enabled. The default-enabled script module shows documentation for every node with an attached GDScript, including unnamed scripts and plain `##` descriptions without implementation notes. The optional component module enables full `COMPONENT_CONTRACT` API details. The native node description stays in the popup header; live Inspector assignments are shown for contracted components, including unsaved edits. Each module can be switched independently and no duplicate popup is registered.

An optional `modules/scene_dependency_explorer_tooltip.gd` bridge supports
[Scene Dependency Explorer](https://github.com/Tobias004/scene_dependency_explorer).
Its TreeItem metadata contains a **saved scene resource path** instead of the
native Scene dock's NodePath. The bridge reuses the same rich popup and overlay
protection, reads the saved scene/script documentation and component contract,
and checks file/dependency modification time and size for refreshes. Both
positive and negative answers are retained while the hovered entry is unchanged.
It does not activate at all if the explorer addon is not installed. Script
help and the opt-in component details follow the existing two module switches;
SDE itself requires no changes. Installing SDE while Better Tooltips is already
running requires reloading Better Tooltips to enable the bridge.

Godot's local Scene-dock Tree is an internal editor control. Two minimal NodePath resolver strategies are selected once at startup: `modules/scene_node_resolvers/scene_node_resolver_47.gd` for Godot 4.7's absolute paths and `scene_node_resolver_48.gd` for Godot 4.8's relative paths. Only the NodePath interpretation differs; parsing, caching, rich-text rendering and popup behavior are shared.

The Scene-dock integration checks the hovered node every **250 ms** but reparses script documentation only when the hovered node/script changes or an edit invalidates it. Inspector edits trigger a live refresh; other unsaved property changes are checked approximately once per second without reparsing the script. When the local Scene-dock Tree is unavailable, a new search is attempted every **two seconds** instead of every hover tick.

Component-documentation testing fixtures and scripts live under `tests/components/` in the development repository. See its README for instructions. That test directory is not required in the distributed add-on.

## Preview pipeline and cache

All enabled resource-preview modules are routed through one central `tooltip_pipeline.gd` plugin. The pipeline provides visible generation/failure states, duplicate in-flight suppression, persistent caching for graphical previews and a generous safety limit. FileSystem GDScript and component documentation are **live-text modules in this pipeline**, while Code Editor documentation attaches separately to Godot's `ScriptEditor`/`CodeEdit`. Code Editor resource hovers call back into the same pipeline; graphical previews therefore share generated images, cache entries, in-flight jobs, failure memory and Shift-forced regeneration.

Better Tooltips stores completed graphical previews as PNG files below `res://.godot/better_tooltips/`. A bounded 32 MiB RAM hot cache keeps recent previews fast while preventing memory use from growing without limit in large projects. Cache signatures include the source resource, recursively discovered dependencies, module id, cache format, Godot version, editor scale, configured default preview size and relevant theme settings.

The configured **Default preview size** (50-200%, default 100%) determines the cached render dimensions for every graphical preview module. Mouse-wheel resizing is centralized in the same pipeline for FileSystem and Code Editor previews. The nominal transient range is 50-250%, with a dynamic upper bound derived from the current usable screen and the tooltip's non-preview overhead so graphical tooltips stay fully manageable without becoming scrollable. Pointer-relative zoom keeps the cursor at the same normalized tooltip position when resizing under the mouse. The current texture scales immediately, then the Resource is regenerated after the debounce interval; transient renders never enter RAM/disk caches.

Changing a resource or one of its external dependencies invalidates the corresponding persistent graphical preview. Component documentation has a **separate, bounded RAM-only cache** in `core/tooltip_cache.gd` with up to **256 entries**, including **negative results** (scripts/scenes without a contract). Each entry tracks the saved file's modification time and size, plus detected scene/script dependencies. A stale entry is rebuilt using deep cache-ignoring resource loading so Godot does not silently return an outdated script. **Shift + hover** invalidates a component entry and forces a fresh read. On filesystems with coarse timestamp resolution, changing a file within the same timestamp interval without changing its size can require a forced refresh. Unsaved Scene-dock values are read from the live node instead of the file cache.

**Clear Tooltip Caches** removes both graphical RAM/disk entries, component-documentation RAM entries and remembered session failures. The button is disabled when there is currently nothing to clear. Persistent failures are intentionally not stored; only successful graphical previews survive an editor restart.
