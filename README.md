# FileSystem Dock Tooltips 2.0

Development and validation project for the Godot editor add-on.

Version 2.0 adds modular generated FileSystem tooltip previews for materials,
meshes, fonts, shaders, SpriteFrames, themes, StyleBoxes, curves, gradients,
environments and skies while retaining the original GDScript documentation
tooltip.

This project is configured exactly like the release add-on:

```gdscript
const DEBUG_MESSAGES := false
```

All optional modules are enabled. Individual modules can be disabled in:

`addons/filesystem_dock_tooltips/tooltip_settings.gd`

Test resources are documented in:

`tests/TEST_ASSETS.md`
