# FileSystem Dock Tooltips
Get useful information about your project files **without opening them**.

FileSystem Dock Tooltips enhances tooltips in Godot's **FileSystem dock** with inline GDScript documentation and generated visual previews for common resource types.

Hover over supported files to quickly inspect class documentation, materials, meshes, shaders, fonts, SpriteFrames, themes, curves, gradients, environments, skies and more — directly from the FileSystem dock.

Individual tooltip and preview modules can be enabled or disabled from the plugin's settings menu under **Project > Tools > FileSystem Dock Tooltips**.

## GDScript documentation at a glance
Hover over a `.gd` file to see its `class_name` and `##` class documentation directly in the FileSystem dock.
The tooltip preserves source-style formatting such as:
- blank lines and indentation
- repeated spaces and tabs
- common BBCode formatting
- Godot class, method and member references
- long documentation lines with fallback wrapping
Both documentation below `class_name` / `extends` and documentation directly above `class_name` are supported.
Scripts are read as text and are not loaded or instantiated.

## Generated resource previews
Starting with version 2.0, larger previews for resources where the standard FileSystem tooltip provides little or no visual information are available.

### Materials
`BaseMaterial3D` resources and spatial `ShaderMaterial` resources are rendered on a dedicated preview sphere with a generated studio environment.
The preview includes:
- PBR-friendly environment reflections
- neutral studio lighting
- transparency checkerboard
- reference pedestal
- anti-aliasing
This is a newly rendered preview — not an enlarged version of Godot's existing thumbnail.

### Meshes
Meshes are displayed as generated 3D previews with:
- automatic centering
- automatic camera distance based on the mesh bounds
- fixed preview lighting
- a neutral material for clearly showing geometry
No camera setup is required.

### Shaders
`.gdshader` files are previewed according to their shader type:
- `spatial` shaders are rendered on a 3D sphere
- `canvas_item` shaders are applied to a generated 2D test image
- unsupported shader types simply keep the normal Godot tooltip

### Fonts
Font resources display actual text samples in several sizes, including letters, numbers and symbols.

### SpriteFrames
`SpriteFrames` resources show a compact contact sheet with animation names, frame count, FPS and several frames from each animation.

### Themes
Theme resources are demonstrated using representative Godot controls such as:
- Button
- CheckBox
- LineEdit
- ProgressBar
- Slider
This gives a quick visual impression of a theme without opening it in the Inspector.

### StyleBoxes
StyleBox resources are displayed as a larger panel preview, making borders, corner radii, backgrounds and shadows immediately visible.

### Curves
The plugin generates visual previews for:
- `Curve`
- `Curve2D`
- `Curve3D`
2D curves are automatically fitted to the preview area. Curve3D resources use a fixed isometric projection, so no user-defined camera is required.

### Gradients
Gradient resources are displayed at a useful width over a checkerboard background, making both color transitions and transparency visible.

### Environments and Skies
Environment resources are rendered with a fixed reference scene containing materials with different surface properties.
Sky resources receive a wide preview of the sky itself.

## Integrated editor menu and settings
Starting with version 2.1, a dedicated menu is available under:
**Project > Tools > FileSystem Dock Tooltips**
The menu provides:
- **Settings...**
- **Report a Bug**
- **Feedback / Feature Request**

### Settings
Open:
**Project > Tools > FileSystem Dock Tooltips > Settings...**
to individually enable or disable:
- GDScript documentation
- Materials
- Meshes
- Fonts
- Shaders
- SpriteFrames
- Themes
- StyleBoxes
- Curves
- Gradients
- Environments
- Skies
The dialog also provides **Enable All** and **Disable All** buttons.
Changes take effect immediately without restarting the editor.
The selected module states are stored per project, so different projects can use different FileSystem tooltip configurations.
All modules are enabled by default.

### Bug reports and feedback
The **Report a Bug** and **Feedback / Feature Request** entries open the corresponding GitHub issue pages in your browser.
A GitHub account is required to submit a bug report, feedback or feature request.

## Modular by design
Each tooltip and preview type is implemented as a separate module.

Starting with version 2.1, these modules can be managed through the integrated settings dialog, allowing individual tooltip types to be disabled if certain resource previews cause problems or are not needed in a particular project.

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