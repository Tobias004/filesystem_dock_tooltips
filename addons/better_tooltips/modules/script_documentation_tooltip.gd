@tool
class_name BTScriptDocumentationTooltip
extends EditorResourceTooltipPlugin

## GDScript class-documentation tooltip module.
## Adds [code]class_name[/code] and script-level [code]##[/code] documentation
## to Godot's standard FileSystem tooltip. Formatting is delegated to
## [BTDocumentationRenderer], which mirrors Godot's EditorHelp presentation
## and is shared with the add-on's built-in documentation dialog.


const DocumentationRenderer := preload(
	"res://addons/better_tooltips/core/documentation_renderer.gd"
)
const TooltipAppearance := preload(
	"res://addons/better_tooltips/core/tooltip_appearance.gd"
)

const MIN_TOOLTIP_WIDTH := 420.0
const MAX_TOOLTIP_WIDTH := 760.0
const TOOLTIP_HORIZONTAL_PADDING := 28.0
const CONTENT_MARGIN_LEFT := 8
const CONTENT_MARGIN_RIGHT := 8
const CONTENT_MARGIN_TOP := 4
const CONTENT_MARGIN_BOTTOM := 6
const CLASS_NAME_KEYWORD := "class_name"

var _renderer: BTDocumentationRenderer = null

# Restricts this module to GDScript resources. The file extension is checked
# again while building the tooltip to avoid modifying unexpected resource paths.
func _handles(type: String) -> bool:
	return type == "GDScript"

# Appends class_name and script-level ## documentation to Godot's existing
# FileSystem tooltip. If no suitable documentation is found, the base tooltip
# is returned unchanged.
func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	if not path.ends_with(".gd"):
		return base
	var documentation := _read_script_documentation(path)
	if documentation.is_empty():
		return base
	var renderer := _get_renderer()
	renderer.refresh_theme()
	base.add_child(HSeparator.new())
	var tooltip_width := _calculate_tooltip_width(documentation, renderer)
	var editor_scale := EditorInterface.get_editor_scale()
	var margin_left := roundi(CONTENT_MARGIN_LEFT * editor_scale)
	var margin_right := roundi(CONTENT_MARGIN_RIGHT * editor_scale)
	var margin_top := roundi(CONTENT_MARGIN_TOP * editor_scale)
	var margin_bottom := roundi(CONTENT_MARGIN_BOTTOM * editor_scale)
	var background_panel := PanelContainer.new()
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TooltipAppearance.style_addon_panel(background_panel)
	base.add_child(background_panel)
	var content_margin := MarginContainer.new()
	content_margin.custom_minimum_size.x = (
		tooltip_width + margin_left + margin_right
	)
	content_margin.add_theme_constant_override("margin_left", margin_left)
	content_margin.add_theme_constant_override("margin_right", margin_right)
	content_margin.add_theme_constant_override("margin_top", margin_top)
	content_margin.add_theme_constant_override("margin_bottom", margin_bottom)
	background_panel.add_child(content_margin)
	# Keep a fixed content width. RichTextLabel needs it to calculate fitted
	# height correctly while autowrapping is enabled inside a tooltip.
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = tooltip_width
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content)
	var class_name_label := Label.new()
	class_name_label.text = documentation["class_name"]
	renderer.style_type_label(class_name_label)
	content.add_child(class_name_label)
	var description_label := RichTextLabel.new()
	description_label.fit_content = true
	description_label.scroll_active = false
	description_label.selection_enabled = false
	description_label.focus_mode = Control.FOCUS_NONE
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.autowrap_trim_flags = 0
	description_label.custom_minimum_size.x = tooltip_width
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	content.add_child(description_label)
	renderer.render_document(
		description_label,
		documentation,
		str(documentation["class_name"]),
		false
	)
	TooltipAppearance.limit_rich_text_height(description_label)
	return base

# Releases the shared renderer when Godot unregisters this tooltip module.
func cleanup() -> void:
	_renderer = null

# Reads a script and extracts the class_name together with its script-level
# documentation. Godot's documented placement after class_name/extends is
# preferred, while documentation directly before class_name remains supported.
func _read_script_documentation(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var source := file.get_as_text()
	if source.begins_with("\uFEFF"):
		source = source.trim_prefix("\uFEFF")
	var lines := source.split("\n")
	var class_data := _find_class_name(lines)
	if class_data.is_empty():
		return {}
	var class_line: int = class_data["line"]
	var documentation_lines := _find_documentation_after_header(lines, class_line)
	# Godot's documented style places script documentation after class_name and
	# extends. Documentation directly above class_name remains a compatibility
	# fallback for projects authored against older versions of this add-on.
	if documentation_lines.is_empty():
		documentation_lines = _find_documentation_before_class_name(
			lines,
			class_line
		)
	var documentation := _parse_documentation(documentation_lines)
	if not _has_renderable_documentation(documentation):
		return {}
	documentation["class_name"] = class_data["name"]
	return documentation

# Finds the first valid class_name declaration and returns both its source line
# and declared name. Inline comments after the name are ignored.
func _find_class_name(lines: PackedStringArray) -> Dictionary:
	for index in range(lines.size()):
		var stripped := lines[index].strip_edges()
		if not _starts_with_keyword(stripped, CLASS_NAME_KEYWORD):
			continue
		var remainder := stripped.trim_prefix(CLASS_NAME_KEYWORD).strip_edges()
		if remainder.is_empty():
			continue
		var normalized := remainder.replace("\t", " ")
		var tokens := normalized.split(" ", false)
		if tokens.is_empty():
			continue
		var script_class_name: String = tokens[0]
		var comment_position := script_class_name.find("#")
		if comment_position >= 0:
			script_class_name = script_class_name.left(comment_position)
		if not script_class_name.is_empty():
			return {
				"line": index,
				"name": script_class_name,
			}
	return {}

# Locates a documentation block after class_name while skipping annotations,
# blank lines and the extends statement that may form the script header.
func _find_documentation_after_header(
	lines: PackedStringArray,
	class_line: int
) -> PackedStringArray:
	var index := class_line + 1
	while index < lines.size():
		var stripped := lines[index].strip_edges()
		if stripped.is_empty() or stripped.begins_with("@"):
			index += 1
			continue
		if _starts_with_keyword(stripped, "extends"):
			index += 1
			continue
		break
	return _collect_documentation_block(lines, index, 1)

# Locates the fallback documentation block before class_name. Script annotations
# and blank lines between documentation and class_name are skipped.
func _find_documentation_before_class_name(
	lines: PackedStringArray,
	class_line: int
) -> PackedStringArray:
	var index := class_line - 1
	while index >= 0:
		var stripped := lines[index].strip_edges()
		if stripped.is_empty() or stripped.begins_with("@"):
			index -= 1
			continue
		break
	return _collect_documentation_block(lines, index, -1)

# Collects one contiguous ## block in the requested direction while preserving
# the original top-to-bottom source order in the returned array.
func _collect_documentation_block(
	lines: PackedStringArray,
	start_index: int,
	direction: int
) -> PackedStringArray:
	var result := PackedStringArray()
	var index := start_index
	while index >= 0 and index < lines.size():
		var line := lines[index]
		if not _is_documentation_comment(line):
			break
		if direction > 0:
			result.append(line)
		else:
			result.insert(0, line)
		index += direction
	return result

# Parses one ## documentation block into display text plus Godot's line-level
# @tutorial, @deprecated and @experimental metadata. Those keys intentionally
# match what future member-documentation consumers need as well.
func _parse_documentation(lines: PackedStringArray) -> Dictionary:
	var documentation := {
		"description": "",
		"tutorials": [],
		"is_deprecated": false,
		"deprecated": "",
		"is_experimental": false,
		"experimental": "",
	}
	if lines.is_empty():
		return documentation
	var description_lines := PackedStringArray()
	var in_codeblock := false
	for source_line in lines:
		var line := _remove_documentation_prefix(source_line)
		var stripped := line.strip_edges()
		if not in_codeblock:
			if stripped.begins_with("[codeblock"):
				in_codeblock = true
			elif _parse_special_tag(stripped, documentation):
				continue
		description_lines.append(line)
		if in_codeblock and stripped == "[/codeblock]":
			in_codeblock = false
	documentation["description"] = _normalize_description(description_lines)
	return documentation

# Extracts one valid line-level documentation tag. Invalid spellings are left in
# the description instead of being silently consumed.
func _parse_special_tag(line: String, documentation: Dictionary) -> bool:
	if line == "@deprecated":
		documentation["is_deprecated"] = true
		return true
	if line.begins_with("@deprecated:"):
		documentation["is_deprecated"] = true
		documentation["deprecated"] = line.substr(12).strip_edges()
		return true
	if line == "@experimental":
		documentation["is_experimental"] = true
		return true
	if line.begins_with("@experimental:"):
		documentation["is_experimental"] = true
		documentation["experimental"] = line.substr(14).strip_edges()
		return true
	if line.begins_with("@tutorial:"):
		var tutorial_url := line.substr(10).strip_edges()
		if tutorial_url.is_empty():
			return false
		(documentation["tutorials"] as Array).append({
			"title": "",
			"url": tutorial_url,
		})
		return true
	if line.begins_with("@tutorial("):
		var separator := line.find("):")
		if separator < 10:
			return false
		var tutorial_title := line.substr(10, separator - 10).strip_edges()
		var tutorial_url := line.substr(separator + 2).strip_edges()
		if tutorial_url.is_empty():
			return false
		(documentation["tutorials"] as Array).append({
			"title": tutorial_title,
			"url": tutorial_url,
		})
		return true
	return false

# Normalizes ordinary documentation like Godot does: wrapped source lines are
# joined with spaces, blank ## lines separate paragraphs, [br] keeps an explicit
# line break, and codeblock contents retain their source line structure. A
# paragraph break is represented by one LF; EditorHelp's paragraph_separation
# theme value supplies the visual spacing, so an extra empty line would double it.
func _normalize_description(lines: PackedStringArray) -> String:
	var output := PackedStringArray()
	var paragraph := PackedStringArray()
	var in_codeblock := false
	for line in lines:
		var stripped := line.strip_edges()
		if in_codeblock:
			output.append(line)
			if stripped == "[/codeblock]":
				in_codeblock = false
			continue
		if stripped.begins_with("[codeblock"):
			_flush_paragraph(output, paragraph)
			output.append(stripped)
			in_codeblock = true
			continue
		if stripped.is_empty():
			_flush_paragraph(output, paragraph)
			continue
		paragraph.append(stripped)
	_flush_paragraph(output, paragraph)
	return "\n".join(output)

# Flushes one ordinary paragraph using a single separating space, matching
# GDScript's generated class documentation behavior.
func _flush_paragraph(
	output: PackedStringArray,
	paragraph: PackedStringArray
) -> void:
	if paragraph.is_empty():
		return
	output.append(" ".join(paragraph))
	paragraph.clear()

# Removes indentation before ##, the marker itself and at most one conventional
# space after it while preserving codeblock indentation after that first space.
func _remove_documentation_prefix(line: String) -> String:
	var content := line.strip_edges(true, false)
	if not content.begins_with("##"):
		return line.trim_suffix("\r")
	content = content.substr(2)
	if content.begins_with(" "):
		content = content.substr(1)
	return content.trim_suffix("\r")

# Returns whether a source line is a GDScript documentation comment after
# ignoring indentation before the comment marker.
func _is_documentation_comment(line: String) -> bool:
	return line.strip_edges(true, false).begins_with("##")

# Checks whether the parsed block has any content worth appending to a tooltip.
func _has_renderable_documentation(documentation: Dictionary) -> bool:
	return (
		not str(documentation.get("description", "")).strip_edges().is_empty()
		or bool(documentation.get("is_deprecated", false))
		or bool(documentation.get("is_experimental", false))
		or not (documentation.get("tutorials", []) as Array).is_empty()
	)

# Chooses a readable tooltip width from visible documentation text while using
# EditorHelp's document font and respecting the current editor-window width.
func _calculate_tooltip_width(
	documentation: Dictionary,
	renderer: Variant
) -> float:
	var editor_scale := EditorInterface.get_editor_scale()
	var minimum_width := MIN_TOOLTIP_WIDTH * editor_scale
	var maximum_width := MAX_TOOLTIP_WIDTH * editor_scale
	var available_width := EditorInterface.get_base_control().size.x * 0.65
	maximum_width = min(maximum_width, available_width)
	maximum_width = max(maximum_width, minimum_width)
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

# Checks a keyword at the start of a stripped source line without accepting
# longer identifiers that only share the same prefix.
func _starts_with_keyword(line: String, keyword: String) -> bool:
	if not line.begins_with(keyword):
		return false
	if line.length() == keyword.length():
		return true
	var next_character := line.substr(keyword.length(), 1)
	return next_character == " " or next_character == "\t"
