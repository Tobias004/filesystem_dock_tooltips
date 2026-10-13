# Better Tooltips

Better Tooltips is a Godot 4.7+ editor add-on that extends tooltips throughout the editor with project documentation, resource previews, Markdown/text previews and optional IDE integrations.

The project was originally released as **FileSystem Dock Tooltips**. The GitHub repository keeps its existing `filesystem_dock_tooltips` URL so published links continue to work.

For the current feature description, screenshots, compatibility information and installation details, please see the official Godot Asset Library page:

**[Better Tooltips on the Godot Asset Library](https://store.godotengine.org/asset/tobias-lawrenz/filesystem-dock-tooltips/)**

## Source code

This repository contains the source code of the add-on.

## Bug reports and feedback

If you encounter a bug or have feedback or a feature request, please use the GitHub issue tracker for this repository.

## Releases

For released versions of the add-on, see the GitHub Releases section or the Godot Asset Library page.

## Text-file previews

Markdown (.md / .markdown) and other Godot TextFile entries can be previewed directly from the FileSystem dock. The same live text renderer is used for statically resolvable res:// / uid:// paths in CodeEdit and Godot's open-file list. It also supports outline entries and file tabs in both Quill-IDE by Rayyan Aziz and Script-IDE by Marius Hanl. Long text scrolls inside the tooltip instead of using graphical zoom. Markdown and generic text previews can be enabled independently.

## Tooltip sizing

Graphical previews use one shared wheel-zoom/layout path in FileSystem and code tooltips, including wheel input received while the pointer is directly over the tooltip popup. The configured default size controls the cached render; wheel zoom is temporary and cache-free. The effective maximum is constrained by the usable screen area, graphical previews never scroll, and resizing under the pointer preserves its relative position inside the tooltip except at small corner escape zones. Very long add-on documentation is height-limited and becomes vertically scrollable instead of growing indefinitely.
