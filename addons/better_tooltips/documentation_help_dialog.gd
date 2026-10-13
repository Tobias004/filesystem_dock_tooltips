@tool
class_name BTDocumentationHelpDialog
extends AcceptDialog

## Displays the add-on's local GDScript documentation syntax reference.
## The help body is rendered by [BTDocumentationRenderer], so the same
## formatting and theme behavior is shared with FileSystem tooltips and future
## symbol-level documentation surfaces.

const DocumentationRenderer := preload(
	"res://addons/better_tooltips/core/documentation_renderer.gd"
)
const HELP_PATH := (
	"res://addons/better_tooltips/DOCUMENTATION_SYNTAX.txt"
)

@onready var _help_text: RichTextLabel = %HelpText

var _renderer: BTDocumentationRenderer = null
var _help_source := ""

# Loads the bundled reference once the dialog controls are ready. Rendering is
# triggered by the controller after the current editor theme has been applied.
func _ready() -> void:
	get_ok_button().text = "Close"
	_load_help_source()

# Re-applies the current editor theme and re-renders the local help source.
# This keeps the dialog synchronized with theme/font changes made while the
# editor is open.
func refresh() -> void:
	if not is_node_ready():
		return
	theme = EditorInterface.get_editor_theme()
	var renderer := _get_renderer()
	renderer.refresh_theme()
	renderer.style_help_surface(_help_text)
	renderer.render_markup(_help_text, _help_source, "", true)
	_help_text.scroll_to_line(0)

# Reads the bundled reference as plain text. The file intentionally contains
# Godot documentation markup rather than Markdown, allowing it to exercise the
# same renderer that users see in documentation tooltips.
func _load_help_source() -> void:
	var file := FileAccess.open(HELP_PATH, FileAccess.READ)
	if file == null:
		_help_source = (
			"[b]Documentation syntax help could not be loaded.[/b][br]"
			+ "Expected: [code]%s[/code]" % HELP_PATH
		)
		return
	_help_source = file.get_as_text()

# Creates the shared documentation renderer lazily so the help dialog has no
# formatting overhead until the user opens it.
func _get_renderer() -> BTDocumentationRenderer:
	if _renderer == null:
		_renderer = DocumentationRenderer.new() as BTDocumentationRenderer
	return _renderer
