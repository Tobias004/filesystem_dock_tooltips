# Changelog

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
