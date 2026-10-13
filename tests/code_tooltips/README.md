# Code Tooltip Tests

This directory contains both manual editor fixtures and a small headless parser test.

## Manual showcase

1. Open `code_tooltip_showcase.tscn` in Godot.
2. Open `code_tooltip_showcase.gd` in the Script editor.
3. Hover the documented declarations and the expressions described by the comments.
4. For Resource previews, hover both the variable/constant and a literal `res://...` string inside `preload()` / `load()`.
5. Hold **Shift** while hovering a Resource to verify forced regeneration through the shared preview cache pipeline.
6. With a graphical Resource preview visible, use the mouse wheel to verify temporary resizing and sharp debounced regeneration; move away and hover again to confirm the configured default size is restored.

The showcase covers:

- `class_name`, `##` documentation and optional single-`#` member documentation
- project-class member documentation across scripts
- direct Resource variables/constants
- typed and exported Resource declarations
- local Resource declarations
- direct Resource-path strings in `preload()` / `load()`
- one- and two-step Resource aliases
- InputMap/Input action strings and their configured events
- `$Node`, `$Parent/Child`, `%UniqueName`, `get_node()`, `get_node_or_null()` and `NodePath()` paths
- variables initialized from those node references, including short local/member alias chains
- ProjectSettings keys with current value and Variant type

Resource examples cover Material, Theme, Mesh, Font, StyleBox, Gradient, Environment, Sky, SpriteFrames, Shader and Curve previews using the existing test assets.

## Automated parser test

Run from the project root:

```sh
Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script tests/code_tooltips/test_code_tooltip_parser.gd
```

The script exits with a non-zero status when Resource resolution, Node-reference variable resolution, multiline handling, alias following, local-scope resolution or documentation parsing regresses.

A second test exercises source-position detection for direct Resource path strings, Input action strings, ProjectSettings keys and `$`/`%` NodePath tokens:

```sh
Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script tests/code_tooltips/test_code_tooltip_context.gd
```

Full NodePath resolution depends on the currently edited scene and is therefore exercised by the manual showcase. The whole project should additionally be opened or scanned with the editor binary to catch parse/compile errors in the editor-only integration.

### Quill / Script-IDE graphical outline regression

`test_navigation_resource_preview.gd` runs in editor context and mirrors the public outline metadata used by Quill (`Tree`) and Script-IDE (`ItemList`). It verifies that a Resource alias resolves through the same source parser as CodeEdit, that a shared Material preview is actually inserted into the navigation popup, and that popup-window mouse-wheel zoom uses the central preview pipeline. Run it with a graphical backend (X11/Xvfb is sufficient).
