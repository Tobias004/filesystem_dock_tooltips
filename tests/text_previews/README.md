# Text preview tests

`showcase.md` demonstrates Markdown rendering, `showcase.txt` generic text, and `long_showcase.md` is intentionally over 200 KiB to prevent regressions to the old 64 KiB limit.

The automated tests verify that:

- Godot classifies the fixtures as `TextFile`.
- Markdown and generic text modules split that shared type by path.
- both modules create live `RichTextLabel` content rather than cached bitmap previews.
- Markdown uses the same EditorHelp base font size as code documentation.
- long Markdown is not truncated at ordinary file sizes and switches to internal scrolling instead of graphical zoom.
- direct `res://` strings and aliases resolve to the same renderer.
- FileSystemDock's empty ResourceLoader dispatch type is accepted before path/type resolution.
- Godot's open-file list, Quill-style TabBars and Script-IDE-style custom tab buttons can expose `.md`/text paths to the same navigation resolver.

## FileSystem Dock dispatch regression

Godot 4.7's FileSystem Dock asks `EditorResourceTooltipPlugin` using the ResourceLoader type, not the type shown by EditorFileSystem. Plain text files therefore reach tooltip plugins with an empty type string. `test_text_previews.gd` explicitly verifies that the central pipeline accepts this empty dispatch before resolving the actual path back to `TextFile`.
