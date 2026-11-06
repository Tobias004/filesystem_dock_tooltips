# Better Tooltips

Better Tooltips is a Godot 4.7.2+ editor add-on that extends tooltips throughout the editor with project documentation, resource previews, Markdown/text previews and optional IDE integrations. Version 3.3.0 introduced **opt-in scene-component documentation** and theme-aware separation of `Implementation notes` in class documentation (even without `COMPONENT_CONTRACT`).

The project was originally released as **FileSystem Dock Tooltips**. The GitHub repository keeps its existing `filesystem_dock_tooltips` URL so published links continue to work.

For the current feature description, screenshots, compatibility information and installation details, please see the official Godot Asset Library page:

**[Better Tooltips on the Godot Asset Library](https://store.godotengine.org/asset/tobias-lawrenz/filesystem-dock-tooltips/)**

## Source code

This repository contains the source code of the add-on. For the feature list and setup instructions, see the [add-on README](addons/better_tooltips/README.md). The [module overview](MODULES.md) and [code-tooltip guide](CODE_TOOLTIP_FEATURES.md) provide additional implementation and usage details.

## Bug reports and feedback

If you encounter a bug or have feedback or a feature request, please use the GitHub issue tracker for this repository.

## Releases

For released versions of the add-on, see the GitHub Releases section or the Godot Asset Library page.

## Text-file previews

Markdown (.md / .markdown) and other Godot TextFile entries can be previewed directly from the FileSystem dock. The same live text renderer is used for statically resolvable res:// / uid:// paths in CodeEdit and Godot's open-file list. It also supports outline entries and file tabs in both Quill-IDE by Rayyan Aziz and Script-IDE by Marius Hanl. Long text scrolls inside the tooltip instead of using graphical zoom. Markdown and generic text previews can be enabled independently.

## Tooltip sizing

Graphical previews use one shared wheel-zoom/layout path in FileSystem and code tooltips, including wheel input received while the pointer is directly over the tooltip popup. The configured default size controls the cached render; wheel zoom is temporary and cache-free. The effective maximum is constrained by the usable screen area, graphical previews never scroll, and resizing under the pointer preserves its relative position inside the tooltip except at small corner escape zones. Text and code tooltips have independent settings for font scale, maximum width and maximum height. At 100% the text font is one point smaller than the Godot theme. Long text becomes scrollable within the size limits. These settings do not affect graphical preview zoom.

## Scene-component documentation (3.3.0)

This optional module is **disabled by default**. Turn on **Component documentation (opt-in)** under **Project > Tools > Better Tooltips > Settings...**; the `?` button beside the setting explains the contract format.

Scripts can declare a `COMPONENT_CONTRACT` version 1 constant to identify required and optional exported properties. Better Tooltips reads additional `##` documentation, signals and documented public methods automatically. The contract documents dependencies; it does not validate them or run scene code.

- Hover a `.tscn`/`.scn` scene with a documented root script in the **FileSystem** dock for its class description and Implementation notes, even without a contract. Contracted scene resources also show their saved component API when opt-in is enabled.
- Hover a node with an attached GDScript in the **Scene** dock for its normal class description and any `Implementation notes`, even without a contract. This uses the default-enabled **FileSystem GDScript documentation** setting.
- Enable the separate **Component documentation (opt-in)** setting to add contract properties, signals and methods when the node declares a contract; unsaved Inspector values are supported. The native node description remains the popup header.
- Scene file tooltips read the root node's script (including inherited scripts); the Scene dock also supports documented child nodes.
- With **Scene Dependency Explorer** installed, its compact saved-scene entries use the same rich documentation/contract renderer. This optional compatibility integration follows the existing documentation switches and reads saved files, not unsaved Inspector state.

The Scene-dock documentation and contract features were tested with **Godot 4.7.2** and **4.8-beta2**. The Scene dock has a version-selected NodePath resolver for these engine versions; the remaining documentation and rendering code is shared. This integration depends on internal editor controls and may require adjustments for future Godot releases.

Component documents are cached in RAM (up to **256 positive or negative results**) and invalidated when saved scene/script files or detected dependencies change. Scene-dock hovers reuse parsed documentation and refresh live values without reparsing on every timer tick. See the [add-on README](addons/better_tooltips/README.md) for cache details and limitations.

## Updating development versions

Replace the complete `addons/better_tooltips` directory rather than overlaying files.
Earlier internal builds contained experimental popup-transparency scripts
(`core/windows_text_popup_reveal.gd` and `core/text_popup_delayed_reveal.gd`).
Neither is used now. Delete any leftover `.gd` and `.gd.uid` files to avoid
stale scripts or duplicate script UID warnings.

Plugin diagnostics can be enabled per project in **Better Tooltips Settings → Show Better Tooltips diagnostics** (off by default). Only add-on messages emitted through `BTDebug` are controlled; Godot runtime/parse errors remain visible and should be fixed at their source.
