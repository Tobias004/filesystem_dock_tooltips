# FileSystem Dock Tooltips

Godot editor plugin for Godot 4.5 and newer. It extends FileSystem dock
tooltips with GDScript documentation and generated visual previews for
resource types where a larger hover preview provides additional information.

## Version 2.0 preview modules

Each feature is implemented as a separate `EditorResourceTooltipPlugin`
module and registered independently.

Supported modules:

- GDScript class documentation
- 3D material preview (`BaseMaterial3D`, spatial `ShaderMaterial`)
- Mesh preview with automatic AABB-based camera fitting
- Font sample preview
- `.gdshader` preview for `spatial` and `canvas_item` shaders
- `SpriteFrames` contact-sheet preview
- Theme preview using representative Godot controls
- StyleBox preview
- `Curve`, `Curve2D` and `Curve3D` previews
- Gradient preview
- Environment preview using fixed reference objects
- Sky preview

Texture and audio previews are intentionally not duplicated because Godot
already provides dedicated FileSystem tooltip previews for them.

PackedScene previews are intentionally not generated automatically. Rendering
arbitrary scenes on hover would require instantiation and could execute
`@tool` code. A future user-defined scene screenshot feature can remain
separate from this release.

## Modular configuration

All modules can be enabled or disabled in:

`tooltip_settings.gd`

For example:

```gdscript
const ENABLE_MESH_PREVIEW := true
const ENABLE_THEME_PREVIEW := false
```

`plugin.gd` loads enabled module scripts dynamically. A disabled module script
is not loaded at all, which makes experimental features easy to isolate.

## Debug messages

Debug output is also controlled only by a source-code constant:

```gdscript
const DEBUG_MESSAGES := false
```

The release configuration sets it to `false`.

No Project Setting is created.

## Robust fallback behavior

A module adds content only when:

- the hovered resource type is supported,
- the resource exists and can be loaded,
- required data is present,
- the preview can be built with sensible bounds.

Otherwise it returns Godot's standard tooltip unchanged.

The add-on does not intentionally emit its own warnings/errors when
`DEBUG_MESSAGES` is `false`.

Engine-level diagnostics cannot be suppressed from GDScript. In particular,
an invalid user shader can still make Godot report a shader compile error when
that shader is loaded. The shader module reads `shader_type` from the source
first and does not load unsupported particle/fog/texture-blit shaders.

## Installation

Copy:

`addons/filesystem_dock_tooltips`

into the root of a Godot project and enable **FileSystem Dock Tooltips** under
**Project > Project Settings > Plugins**.
