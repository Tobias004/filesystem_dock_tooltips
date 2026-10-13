# Preview Size / Wheel Zoom Tests

These checks cover the shared graphical-preview sizing behavior added after the
Code Tooltip resource integration.

## Automated wheel/layout test

Run in editor context because the add-on stores project-local settings through
`EditorInterface.get_editor_settings()`:

```sh
Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path . \
  --script tests/preview_zoom/test_preview_zoom.gd
```

The test verifies that:

- absent preview-scale metadata means 100%,
- explicit preview-scale metadata is preserved,
- changing **Default preview size** changes the normal cached-preview identity,
- mouse-wheel input is consumed only for a visible graphical preview session,
- one wheel step changes the displayed preview by 10 percentage points, and
- the temporary resize preserves aspect ratio,
- graphical preview padding is symmetric on all four sides, and
- unusually long add-on documentation switches to a bounded scrollable text area.

The test intentionally does not require an actual GPU capture. Headless Godot
uses the dummy renderer, which cannot exercise the final SubViewport readback
used by a live editor tooltip.

## Settings dialog test

```sh
Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path . \
  --script tests/preview_zoom/test_settings_dialog_scene.gd
```

This verifies that the Settings scene loads and contains the default preview-size
control at the expected path.

## Manual live-render check

1. Open any supported graphical Resource in the FileSystem dock or hover a
   supported Resource reference in GDScript.
2. Let its normal cached preview appear.
3. Roll the mouse wheel while keeping the pointer on the same hovered source, then repeat with the pointer directly over the graphical tooltip. Both routes should resize the same preview session.
4. The tooltip should resize immediately. After a short pause, the preview should
   be replaced by a freshly rendered sharp version at that size.
5. Move the mouse away and hover the same Resource again. It should return to the
   configured **Default preview size** rather than keeping the temporary zoom.
6. Confirm that repeated temporary sizes do not create additional persistent PNG
   cache variants. Only the configured default size is part of the cache signature.


## Live popup geometry / pointer test

This test requires a real windowing backend because it checks screen geometry and mouse warping. On Linux it can run under Xvfb:

```sh
xvfb-run -a -s '-screen 0 1280x720x24' \
  Godot_v4.7.2-stable_linux.x86_64 --editor --path . \
  --script tests/preview_zoom/test_preview_zoom_live_layout.gd
```

It verifies that the graphical zoom ceiling is reduced by the available screen area, that popup-owned wheel input reaches the shared zoom path, and that growing and shrinking a popup keeps a pointer already inside the tooltip at the same normalized position.

## Live real-preview capture/input test

The real Mesh capture test requires a rendering/window backend. On Linux:

```sh
xvfb-run -a -s '-screen 0 1280x720x24' \
  Godot_v4.7.2-stable_linux.x86_64 --rendering-method gl_compatibility \
  --editor --path . --script tests/preview_zoom/test_preview_capture_live.gd
```

It renders the actual `box_mesh.tres` preview, checks that the captured bitmap has equal transparent margins on all four sides, verifies the visible pipeline padding, sends wheel input through the tooltip PopupPanel itself, waits for the transient high-resolution render, and repeats the margin checks after zoom.


## Live StyleBox cache/capture regression test

This test specifically guards against the right/bottom clipping bug that could
appear only on the cached default-size preview while transient wheel renders
looked correct:

```sh
xvfb-run -a -s '-screen 0 1280x720x24' \
  Godot_v4.7.2-stable_linux.x86_64 --rendering-method gl_compatibility \
  --editor --path . --script tests/preview_zoom/test_stylebox_cache_capture_live.gd
```

It clears the preview cache, generates a real StyleBox preview, checks equal
transparent capture margins on all four sides, then reopens the same Resource
from the persistent/RAM cache and repeats the symmetry check.
