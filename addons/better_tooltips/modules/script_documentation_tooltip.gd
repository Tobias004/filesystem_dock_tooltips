@tool
class_name BTScriptDocumentationTooltip
extends EditorResourceTooltipPlugin

## GDScript file-documentation tooltip module.
## Adds script-level [code]##[/code] documentation with or without
## [code]class_name[/code] to Godot's FileSystem tooltip. Formatting is delegated to
## [BTDocumentationRenderer], which mirrors Godot's EditorHelp presentation
## and is shared with the add-on's built-in documentation dialog.


const DocumentationRenderer := preload(
	"res://addons/better_tooltips/core/documentation_renderer.gd"
)
const DocumentationParser := preload("res://addons/better_tooltips/core/gdscript_documentation_parser.gd")
const TooltipAppearance := preload(
	"res://addons/better_tooltips/core/tooltip_appearance.gd"
)
const TextPreviewRenderer := preload(
	"res://addons/better_tooltips/core/text_preview_renderer.gd"
)
const ComponentReader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

const MIN_TOOLTIP_WIDTH := 420.0
const MAX_TOOLTIP_WIDTH := 760.0
const TOOLTIP_HORIZONTAL_PADDING := 28.0

var _renderer: BTDocumentationRenderer = null

# Scene root scripts use the same GDScript documentation pipeline as .gd files.
# The component module is independent and remains opt-in.
func _handles(type: String) -> bool:
	return type in ["GDScript", "PackedScene"]

# Keep source text live and scrollable even without a documented class. The
# central pipeline owns the popup and keyboard behavior for all text previews.
func is_live_preview() -> bool:
	return true

# Script documentation appears above its source, even without class_name.
# Undocumented scripts still get their source preview.
func _make_tooltip_for_path(
	path: String,
	metadata: Dictionary,
	base: Control
) -> Control:
	var is_script := path.ends_with(".gd")
	var is_scene := path.get_extension().to_lower() in ["tscn", "scn"]
	if not is_script and not is_scene:
		return base
	var documentation: Dictionary = {}
	if is_scene:
		# The standard module supplies class documentation for scene root scripts,
		# even without a contract. An enabled component module owns contracted
		# scene references, so the description is never displayed twice.
		var contracts_enabled := Settings.is_module_enabled(Settings.MODULE_COMPONENT_DOCUMENTATION)
		documentation = ComponentReader.for_path(path, true, contracts_enabled)
		if contracts_enabled and bool(documentation.get("has_contract", false)):
			return base
		if not documentation.is_empty():
			documentation["class_name"] = str(documentation.get("title", path.get_file()))
	else:
		documentation = _read_script_documentation(path)
	if not documentation.is_empty():
		var renderer := _get_renderer()
		renderer.refresh_theme()
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.custom_minimum_size.x = _calculate_tooltip_width(documentation, renderer)
		base.add_child(content)
		var class_name_label := Label.new()
		class_name_label.text = str(documentation["class_name"])
		renderer.style_type_label(class_name_label)
		content.add_child(class_name_label)
		var description_label := RichTextLabel.new()
		description_label.name = &"ScriptDocumentation"
		description_label.fit_content = true
		description_label.scroll_active = false
		description_label.selection_enabled = true
		description_label.focus_mode = Control.FOCUS_NONE
		description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.autowrap_trim_flags = 0
		description_label.custom_minimum_size.x = content.custom_minimum_size.x
		description_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		content.add_child(description_label)
		renderer.render_document(
			description_label,
			documentation,
			str(documentation["class_name"]),
			false
		)
		TooltipAppearance.limit_rich_text_height(description_label)
	if is_script:
		# Existing source preview behavior is unchanged for .gd resources.
		var preview := TextPreviewRenderer.create_plain_preview(path, metadata)
		if preview != null:
			if not documentation.is_empty():
				base.add_child(HSeparator.new())
			base.add_child(preview)
	return base

# Releases the shared renderer when Godot unregisters this tooltip module.
func cleanup() -> void:
	_renderer = null

# Reuses the same script-level documentation lookup as the Scene dock and
# component reader. A registered class_name is only a display title, not a
# prerequisite for documentation; unnamed scripts use their filename instead.
func _read_script_documentation(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var document := DocumentationParser.find_script_documentation(file.get_as_text())
	if document.is_empty():
		return {}
	document["class_name"] = str(document.get("member_name", path.get_file()))
	return document

# Chooses a readable tooltip width from visible documentation text while using
# EditorHelp's document font and respecting the current editor-window width.
func _calculate_tooltip_width(
	documentation: Dictionary,
	renderer: Variant
) -> float:
	var editor_scale := EditorInterface.get_editor_scale()
	var minimum_width := MIN_TOOLTIP_WIDTH * editor_scale
	var maximum_width := minf(MAX_TOOLTIP_WIDTH * editor_scale, TooltipAppearance.text_content_width(2000.0 * editor_scale))
	var available_width := EditorInterface.get_base_control().size.x * 0.65
	maximum_width = min(maximum_width, available_width)
	maximum_width = max(120.0 * editor_scale, maximum_width)
	minimum_width = min(minimum_width, maximum_width)
	var document_font: Font = renderer.get_document_font()
	var document_font_size: int = renderer.get_document_font_size()
	var plain_text: String = renderer.to_plain_text(
		str(documentation.get("description", ""))
	)
	var measured_width := 0.0
	for line in plain_text.split("\n"):
		var line_width := document_font.get_string_size(
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			document_font_size
		).x
		measured_width = max(measured_width, line_width)
	return clamp(
		measured_width + TOOLTIP_HORIZONTAL_PADDING * editor_scale,
		minimum_width,
		maximum_width
	)

# Lazily creates the shared formatting service so module construction remains
# cheap when script-documentation tooltips are disabled in project settings.
func _get_renderer() -> BTDocumentationRenderer:
	if _renderer == null:
		_renderer = DocumentationRenderer.new() as BTDocumentationRenderer
		_renderer.refresh_theme()
	return _renderer
