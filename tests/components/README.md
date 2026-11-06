# Component scene tooltip regression tests

These tests belong in a Godot **project root** alongside `addons/better_tooltips/`.
They are developer fixtures; do not copy the `tests/` directory to the addon
folder. The scene tooltip module is **off by default**; tests call it directly.
For the feature's GDScript contract see
[COMPONENT_DOCUMENTATION.md](../../COMPONENT_DOCUMENTATION.md).

## Automated (Godot 4.7.2 and 4.8-beta2)

Run each command from the project root, using the matching Godot executable
(`godot` below is a placeholder for its name/path). Import the project first:

```sh
godot --headless --editor --path . --import
godot --headless --editor --path . --script res://tests/components/test_component_documentation.gd
godot --headless --editor --path . --script res://tests/components/test_component_tooltip_live.gd
godot --headless --editor --path . --script res://tests/components/test_component_cache.gd
godot --headless --editor --path . --script res://tests/components/test_dependency_hot_reload.gd
godot --headless --editor --path . --script res://tests/components/test_scene_component_refresh.gd
godot --headless --editor --path . --script res://tests/components/test_scene_popup_initial_size.gd
godot --headless --editor --path . --script res://tests/components/test_scene_dock_editor_tree.gd
godot --headless --editor --path . --script res://tests/components/test_implementation_notes.gd
godot --headless --editor --path . --script res://tests/components/test_osc_repository_scene_scripts.gd
godot --headless --editor --path . --script res://tests/components/test_filesystem_scene_documentation.gd
```

Each test prints `PASS` on success and exits with a nonzero code on assertion
failure. The dependency test creates and removes temporary `.tscn` and `.gd`
files. Run the suite with **both** Godot 4.7.2 and Godot 4.8-beta2 when verifying
compatibility. The Scene-dock integration test inspects the *real editor tree*
and its version-specific NodePath metadata; it is not a substitute for visually
checking tooltip placement.

## Manual scene tests

1. In `Project > Tools > Better Tooltips > Settings...`, enable **Component
   documentation (opt-in)** (normally disabled). Open the adjacent `?` help
   and confirm the sample contract appears.
2. Hover `tests/components/scenes/component_root.tscn` in the FileSystem dock.
   Confirm `Required` and `Optional`, saved `caption` and the root description.
3. Hover `tests/components/scenes/ordinary_root.tscn`: the component section
   must **not** appear, despite a child node declaring `COMPONENT_CONTRACT`.
4. Open `component_root.tscn`; hover the scene root in the Scene dock. Verify
   the scene popup uses the same rich component presentation as the FileSystem
   tooltip and still includes the native node text above it. The popup must
   open at its final width and height immediately, without a delayed jump after
   approximately one second; remaining on the same node must not reopen it.
5. Change `caption` in the Inspector **without saving**. Move the mouse away
   and back; the tooltip must show the unsaved value. Changing values without
   the Inspector is checked every second while hovering.
6. Hover the child `Source`: no component summary should be appended.
7. Edit the component script's `##` comments and save; verify that saved-file
   tooltips change, and that Scene dock reflection updates for edited scripts.
8. Rename/move/remove the scene or its script, then restore it; verify the
   FileSystem tooltip cache invalidates appropriately (mtime + size).
9. Toggle component documentation off. Contract API details must disappear,
   but ordinary class help remains in the Scene dock when the independent
   GDScript documentation module is still enabled. Disable that too to return
   fully to the native Scene-dock tooltip; the FileSystem contract section
   must also be gone.
10. Re-enable, open Settings and press **Clear Tooltip Caches**; verify no
    old component data is retained. With a changed saved file, Shift + Hover
    should also force a fresh result if a coarse timestamp hid the modification.
11. Repeat under Godot 4.7.2 and Godot 4.8-beta2 (different NodePath strategy).

Note: file timestamps are second-granular on some filesystems; in an automated
edit/same-size rewrite within the same second, an mtime+size cache cannot know
that contents changed. The Scene dock deliberately reads unsaved Inspector data
from live nodes instead of the file cache.

## OSC implementation-note fixtures

`osc_with_contract.gd` and `osc_without_contract.gd`, together with the matching
`.tscn` roots under `scenes/`, exercise the notes separator in both contract and
non-contract paths. These are **representative OSC fixtures**, not copies of the
OSC project itself (these older fixtures remain deliberately self-contained).

For both scenes, hover the `.tscn` in the FileSystem dock and the root in the
Scene dock with component documentation enabled. Check that the ordinary
class description appears first and the technical details follow with a narrow
subtle vertical stripe and reduced text intensity. Hover the `.gd` files with
standard script documentation enabled to confirm the same separation there.
Disable the component module and confirm `.gd` class help still shows notes.
Check a light editor theme as well as a dark theme.

## OSC repository-derived Scene-dock coverage

`test_osc_repository_scene_scripts.gd` exercises additional independent fixtures
under `tests/components/osc_repo_*.gd` and `tests/components/scenes/osc_repo_*.tscn`.
The header documentation was checked against the actual OSC repository
`Tobias004/OSC-private` (branch `dev`, tree `3ed4e38423c85b2cd80b0f5e7f55728e045c0649`),
including `game/scripts/main.gd`, `game/scripts/ui/cockpit_view.gd`, and
`game/scripts/ui/head_up_display.gd`. The fixture bodies are minimal substitutes:
the entire private OSC project and its GDScript dependencies are not bundled.
The test covers unnamed script headers, ordinary descriptions, notes with and
without contracts, opt-in contract details, independent Settings toggles,
native tooltip restoration and the actual Scene-dock popup renderer.

For a manual check, leave the **FileSystem GDScript documentation** module on
and **Component documentation (opt-in)** off. Open `osc_repo_main.tscn` and
`osc_repo_cockpit_view.tscn`, hover their roots in the Scene dock and verify
ordinary class/help text and the muted left-rule Implementation notes block.
Switch on component documentation and open `osc_repo_hud.tscn` to verify
Required/Optional API details; all popup text should retain the rich layout.

## FileSystem scene documentation (3.3.0)

`test_filesystem_scene_documentation.gd` covers ordinary root-script help and
Implementation notes for `.tscn` files while the component feature is off,
and verifies that enabling it adds only one component API view. It also checks
that `##` member descriptions remain visible inside the single continuous
left-rule contract section and that the local contract help explains the original BBCode markers.

In the FileSystem dock, hover `osc_repo_cockpit_view.tscn` with GDScript
Documentation enabled and Component Documentation disabled: the normal class
help and the architecture notes should appear. Enable Component Documentation,
then hover `osc_repo_hud.tscn`: the API details should be shown once and member
the entire contract section (properties, signals and methods) should have
one continuous subtle left rule, while Implementation notes have their own
separate rule.

## Scene-dock overlay safety (3.3.0)

Run `godot --headless --editor --path . --script res://tests/components/test_scene_popup_overlay_guard.gd`.
The targeted regression verifies that an open Godot popup menu or editor dialog
prevents the Scene-dock timer from opening its own popup, while the add-on's own
tooltip remains exempt. For a manual check, open **Project > Version Control**
and move the mouse downward over the Scene dock without clicking: the menu must
remain open. Repeat with a context menu or another overlapping editor dialog.

## Scene Dependency Explorer integration (3.3.0)

Run the targeted regression (requires no actual SDE plugin):

```sh
godot --headless --editor --path . --script res://tests/components/test_scene_dependency_explorer_tooltip.gd
```

Graphical hover stability test (run without `--headless`):

```sh
godot --editor --path . --script res://tests/components/test_scene_dependency_explorer_hover_stability.gd
```

This test holds the pointer over one row long enough to catch competing native
Tree tooltips and checks that the rich popup stays open, the non-exclusive
window flag remains set, and the original path is restored at cleanup.

The stand-in dock `tests/components/scene_explorer_dock.gd` mirrors SDE's
`Scene Dependencies` Tree identity, and items use the same saved `res://`
scene-path metadata as the upstream addon. The test checks the shared rich
component renderer, Implementation notes without a contract, contract
sections, saved file/dependency fingerprints, module toggles and restoration of
the original path tooltip. No SDE code is bundled into Better Tooltips.

For a manual integration check, enable both addons, open a saved scene and
hover its rows in the **Scene Dependencies** dock. Normal script documentation
should appear with default documentation enabled; opt-in Component documentation
adds Required/Optional API sections. Compare to the native Scene dock and
FileSystem tooltips. SDE entries use saved data only. Moving the pointer under
an open Project/context menu must not open another popup or close the menu.
If SDE was installed after Better Tooltips initialized, reload Better Tooltips.

## Native Scene-dock right-click safety (3.3.0)

Run the focused tests with the affected Godot editor version:

```sh
godot --headless --editor --path . --script res://tests/components/test_scene_component_refresh.gd
godot --editor --path . --script res://tests/components/test_scene_dock_rightclick.gd
```

The graphical test opens a rich Scene-dock popup and sends a right-click event
through the editor GUI to its source Tree. It verifies that the popup does not
grab the click, that the native label fallback stays suppressed and that the
original node tooltip is restored. It also checks suppression of an additional
native Tree tooltip (seen with Godot 4.8). The Scene Dependency Explorer uses
this shared popup base and must continue to allow double-click navigation.

Manual check: hover a documented node in the native Scene dock, wait until the
rich tooltip opens, then right-click the node. The normal Godot node context
menu must open on the first click. Recheck with the mouse resting on the node,
with Project/context menus open, and under both Godot 4.7 and 4.8.
