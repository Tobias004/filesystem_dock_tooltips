@tool
class_name BTMarkdownPreviewTooltip
extends EditorResourceTooltipPlugin

## Markdown file preview module for Godot TextFile entries ending in .md/.markdown.
## Common Markdown structure is rendered into one shared live editor-themed preview.

const Debug := preload("res://addons/better_tooltips/tooltip_debug.gd")
const TextPreviewRenderer := preload(
	"res://addons/better_tooltips/core/text_preview_renderer.gd"
)
const MODULE := "Markdown"

func _handles(type: String) -> bool:
	# FileSystemDock asks tooltip plugins with ResourceLoader.get_resource_type().
	# Plain text files are not loadable Resources, so that API reports an empty
	# type even though EditorFileSystem indexes them as TextFile. Accept both; the
	# central pipeline resolves the real path/type and handles_path() then selects
	# exactly one of the Markdown/generic-text modules.
	return type == "TextFile" or type.is_empty()

# Text previews remain live Controls so long documents can scroll and keep the
# same editor typography in every tooltip host. The central pipeline detects this
# marker and deliberately bypasses bitmap generation/cache/zoom.
func is_live_preview() -> bool:
	return true

# Path-level filtering lets Markdown and generic text previews share Godot's
# TextFile type without both producing a tooltip for the same file.
func handles_path(path: String, type: String) -> bool:
	return type == "TextFile" and TextPreviewRenderer.is_markdown_path(path)

func _make_tooltip_for_path(
	path: String,
	metadata: Dictionary,
	base: Control
) -> Control:
	if not TextPreviewRenderer.is_markdown_path(path):
		return base
	var preview := TextPreviewRenderer.create_markdown_preview(path, metadata)
	if preview == null:
		return base
	base.add_child(preview)
	Debug.log(MODULE, "preview added: " + path)
	return base
