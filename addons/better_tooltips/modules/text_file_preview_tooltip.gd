@tool
class_name BTTextFilePreviewTooltip
extends EditorResourceTooltipPlugin

## Generic text-file preview module for Godot TextFile entries except Markdown.
## Shows live source text with preserved line breaks/wrapping and scrolls when tall.

const Debug := preload("res://addons/better_tooltips/tooltip_debug.gd")
const TextPreviewRenderer := preload(
	"res://addons/better_tooltips/core/text_preview_renderer.gd"
)
const MODULE := "Text File"

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

func handles_path(path: String, type: String) -> bool:
	return type == "TextFile" and not TextPreviewRenderer.is_markdown_path(path)

func _make_tooltip_for_path(
	path: String,
	metadata: Dictionary,
	base: Control
) -> Control:
	if TextPreviewRenderer.is_markdown_path(path):
		return base
	var preview := TextPreviewRenderer.create_plain_preview(path, metadata)
	if preview == null:
		return base
	base.add_child(preview)
	Debug.log(MODULE, "preview added: " + path)
	return base
