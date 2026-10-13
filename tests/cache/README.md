# Tooltip pipeline / cache stress tests

These resources are original test assets written for this add-on. They are not copied from the external projects used by the earlier performance benchmark.

## What this test set should show

The normal FileSystem tooltip is returned immediately. For an uncached resource, the additional preview area first shows a generation message. The preview is then allowed to finish and is stored in the bounded RAM hot cache and persistently below `.godot/better_tooltips/`.

Later hovers should display the preview immediately. Unchanged previews should also remain available after restarting Godot.

The old short 20/80/200 ms timeout is no longer used. Better Tooltips 3.0 uses a generous **Preview safety limit** (default: `5000 ms`). Set it to `0` to disable the limit completely.

Hold **Shift while hovering** a resource to force a complete regeneration. This ignores both RAM and persistent preview caches, bypasses remembered failure states, and disables the safety limit for that one attempt. A successful forced preview replaces the previous cache entry.

## Shader compile stress and cache busting

The shader files in `tests/cache/shaders/` contain deliberately large vertex-stage expression chains. They are intended to make first-time shader/pipeline compilation visible even on fast hardware while still producing a clean preview.

Suggested order:

1. `heavy_ice_like.gdshader` - medium compile stress
2. `heavy_lava_like.gdshader` - heavy compile stress
3. `heavy_marble_like.gdshader` - extreme compile stress

Each shader contains a small `CACHE_BUSTER` constant near the top that participates in the shader calculation. Incrementing its value and saving the file creates a new shader variant, which is useful when testing compilation behavior without clearing the graphics driver's shader cache manually. This mechanism is vendor-independent.

Deleting the project's `.godot/shader_cache/` can still be useful when testing a complete Godot renderer cold start. In that case, expect first-time rendering to be slower because Godot may need to rebuild internal renderer pipelines.

## Generated texture stress

`noise_1024_material.tres` and `noise_2048_material.tres` stress generated texture work. Their cost is not pure shader compilation and varies significantly by hardware.

## Volumetric environment

`environments/volumetric_fog_heavy.tres` exercises the Environment preview path.

## Suggested manual test

1. Open **Project > Tools > Better Tooltips > Settings...**.
2. Leave **Preview safety limit** at `5000 ms` initially, or set it to `0` to disable the limit.
3. Press **Clear Tooltip Caches**.
4. Hover a font, a normal resource and then one of the stress shaders/materials. The generation message should be visible until the preview is ready.
5. Hover the same unchanged files again. Their previews should appear immediately from the RAM cache.
6. Close Godot normally and reopen the project without deleting `.godot/better_tooltips/`. The same unchanged previews should still appear without being regenerated.
7. Change a source shader or another external dependency and save it. A dependent material should regenerate on the next hover.
8. To test the force option, first generate any preview normally. Then hold **Shift** while hovering the same resource; the existing RAM/disk cache entry must be ignored and the preview generated again without the safety limit.
9. Press **Clear Tooltip Caches** and verify that both RAM and persistent disk entries are removed.
