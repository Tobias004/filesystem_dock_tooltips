# FileSystem Dock Tooltips

Get useful information about your files **without opening them**.

FileSystem Dock Tooltips extends Godot's standard FileSystem tooltips with inline GDScript documentation and generated visual previews for common resource types.

Version 2.0 expands the original documentation tooltip into a modular FileSystem preview tool.

## GDScript documentation at a glance

Hover over a `.gd` file to see its `class_name` and `##` class documentation directly in the FileSystem dock.

The tooltip preserves source-style formatting such as:

* blank lines and indentation
* repeated spaces and tabs
* common BBCode formatting
* Godot class, method and member references
* long documentation lines with fallback wrapping

Both documentation below `class_name` / `extends` and documentation directly above `class_name` are supported.

Scripts are read as text and are not loaded or instantiated.

## Generated resource previews

Version 2.0 adds larger previews for resources where the standard FileSystem tooltip provides little or no visual information.

### Materials

`BaseMaterial3D` resources and spatial `ShaderMaterial` resources are rendered on a dedicated preview sphere with a generated studio environment.

The preview includes:

* PBR-friendly environment reflections
* neutral studio lighting
* transparency checkerboard
* reference pedestal
* anti-aliasing

This is a newly rendered preview — not an enlarged version of Godot's existing thumbnail.

### Meshes

Meshes are displayed as generated 3D previews with:

* automatic centering
* automatic camera distance based on the mesh bounds
* fixed preview lighting
* a neutral material for clearly showing geometry

No camera setup is required.

### Shaders

`.gdshader` files are previewed according to their shader type:

* `spatial` shaders are rendered on a 3D sphere
* `canvas_item` shaders are applied to a generated 2D test image
* unsupported shader types simply keep the normal Godot tooltip

### Fonts

Font resources display actual text samples in several sizes, including letters, numbers and symbols.

### SpriteFrames

`SpriteFrames` resources show a compact contact sheet with animation names, frame count, FPS and several frames from each animation.

### Themes

Theme resources are demonstrated using representative Godot controls such as:

* Button
* CheckBox
* LineEdit
* ProgressBar
* Slider

This gives a quick visual impression of a theme without opening it in the Inspector.

### StyleBoxes

StyleBox resources are displayed as a larger panel preview, making borders, corner radii, backgrounds and shadows immediately visible.

### Curves

The plugin generates visual previews for:

* `Curve`
* `Curve2D`
* `Curve3D`

2D curves are automatically fitted to the preview area. Curve3D resources use a fixed isometric projection, so no user-defined camera is required.

### Gradients

Gradient resources are displayed at a useful width over a checkerboard background, making both color transitions and transparency visible.

### Environments and Skies

Environment resources are rendered with a fixed reference scene containing materials with different surface properties.

Sky resources receive a wide preview of the sky itself.

## Modular by design

Each preview type is implemented as a separate module.

Individual modules can be disabled in `tooltip_settings.gd`, for example:

```gdscript
const ENABLE_MESH_PREVIEW := true
const ENABLE_THEME_PREVIEW := false
```

This keeps the add-on easy to maintain and allows individual preview features to be disabled if they are not needed.

## Graceful fallback

If a resource cannot be previewed or is not supported by a module, the plugin leaves Godot's normal FileSystem tooltip unchanged.

The release version does not output its own debug messages during normal fallback cases.

## What the plugin deliberately does not replace

Godot already provides useful FileSystem tooltip previews for textures and audio resources, so the plugin does not duplicate them.

Scenes are also not instantiated automatically for previews. Hovering a file should not unexpectedly execute scene or `@tool` behavior.

## Installation

Copy:

`addons/filesystem_dock_tooltips`

into the root of your Godot project.

Then enable **FileSystem Dock Tooltips** under:

**Project > Project Settings > Plugins**

The ZIP archive can be extracted directly into the project root.

## Compatibility

Designed for Godot 4.5 and newer.
