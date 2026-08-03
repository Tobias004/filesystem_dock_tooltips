@tool
extends EditorResourceTooltipPlugin

const MIN_TOOLTIP_WIDTH := 420.0
const MAX_TOOLTIP_WIDTH := 760.0
const TOOLTIP_HORIZONTAL_PADDING := 28.0
const CONTENT_MARGIN_LEFT := 8
const CONTENT_MARGIN_RIGHT := 8
const CONTENT_MARGIN_TOP := 4
const CONTENT_MARGIN_BOTTOM := 6
const CLASS_NAME_KEYWORD := "class_name"

func _handles(type: String) -> bool:
	return type == "GDScript"

func _make_tooltip_for_path(path: String,_metadata: Dictionary,base: Control) -> Control:
	if not path.ends_with(".gd"):
		return base
	var documentation := _read_script_documentation(path)
	if documentation.is_empty():
		return base
	base.add_child(HSeparator.new())
	var tooltip_width := _calculate_tooltip_width(documentation["description"])
	var editor_scale := EditorInterface.get_editor_scale()
	var margin_left := roundi(CONTENT_MARGIN_LEFT * editor_scale)
	var margin_right := roundi(CONTENT_MARGIN_RIGHT * editor_scale)
	var margin_top := roundi(CONTENT_MARGIN_TOP * editor_scale)
	var margin_bottom := roundi(CONTENT_MARGIN_BOTTOM * editor_scale)
	var content_margin := MarginContainer.new()
	content_margin.custom_minimum_size.x = (
		tooltip_width + margin_left + margin_right
	)
	content_margin.add_theme_constant_override("margin_left", margin_left)
	content_margin.add_theme_constant_override("margin_right", margin_right)
	content_margin.add_theme_constant_override("margin_top", margin_top)
	content_margin.add_theme_constant_override("margin_bottom", margin_bottom)
	base.add_child(content_margin)
	# Keep the original fixed content width. RichTextLabel needs this width to
	# calculate its fitted height correctly while autowrapping is enabled.
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = tooltip_width
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content)
	var class_name_label := Label.new()
	class_name_label.text = documentation["class_name"]
	class_name_label.add_theme_font_size_override(
		"font_size",
		class_name_label.get_theme_font_size("font_size") + 1
	)
	content.add_child(class_name_label)
	var description_label := RichTextLabel.new()
	description_label.bbcode_enabled = true
	description_label.text = _convert_godot_documentation_markup(
		documentation["description"]
	)
	description_label.fit_content = true
	description_label.scroll_active = false
	description_label.selection_enabled = false
	description_label.focus_mode = Control.FOCUS_NONE
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Do not remove indentation at the beginning or end of wrapped lines.
	description_label.autowrap_trim_flags = 0
	description_label.custom_minimum_size.x = tooltip_width
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_apply_editor_code_font(description_label)
	content.add_child(description_label)
	return base


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
	# Godot's documented style places the script documentation after
	# class_name and extends. Documentation directly above class_name is
	# supported as a fallback.
	if documentation_lines.is_empty():
		documentation_lines = _find_documentation_before_class_name(
			lines,
			class_line
		)
	var description := _format_documentation(documentation_lines)
	if description.strip_edges().is_empty():
		return {}
	return {
		"class_name": class_data["name"],
		"description": description,
	}

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

func _find_documentation_after_header(lines: PackedStringArray, class_line: int) -> PackedStringArray:
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

func _find_documentation_before_class_name(lines: PackedStringArray,class_line: int) -> PackedStringArray:
	var index := class_line - 1
	# Script annotations may sit between the documentation and class_name.
	while index >= 0:
		var stripped := lines[index].strip_edges()
		if stripped.is_empty() or stripped.begins_with("@"):
			index -= 1
			continue
		break
	return _collect_documentation_block(lines, index, -1)

func _collect_documentation_block(lines: PackedStringArray,start_index: int,direction: int) -> PackedStringArray:
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

func _format_documentation(lines: PackedStringArray) -> String:
	if lines.is_empty():
		return ""
	var result := PackedStringArray()
	for line in lines:
		result.append(_remove_documentation_prefix(line))
	# Keep source line breaks, blank lines, leading whitespace, repeated spaces,
	# and trailing whitespace. Only the indentation before ##, the ## itself,
	# and one conventional space directly after ## are removed.
	return "\n".join(result)

func _remove_documentation_prefix(line: String) -> String:
	var content := line.strip_edges(true, false)
	if not content.begins_with("##"):
		return line.trim_suffix("\r")
	content = content.substr(2)
	if content.begins_with(" "):
		content = content.substr(1)
	return content.trim_suffix("\r")

func _is_documentation_comment(line: String) -> bool:
	return line.strip_edges(true, false).begins_with("##")

func _apply_editor_code_font(label: RichTextLabel) -> void:
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme.has_font("source", "EditorFonts"):
		var source_font := editor_theme.get_font("source", "EditorFonts")
		label.add_theme_font_override("normal_font", source_font)
		label.add_theme_font_override("mono_font", source_font)
	if editor_theme.has_font_size("source_size", "EditorFonts"):
		var source_font_size := editor_theme.get_font_size(
			"source_size",
			"EditorFonts"
		)
		label.add_theme_font_size_override("normal_font_size", source_font_size)
		label.add_theme_font_size_override("mono_font_size", source_font_size)

func _calculate_tooltip_width(description: String) -> float:
	var editor_scale := EditorInterface.get_editor_scale()
	var minimum_width := MIN_TOOLTIP_WIDTH * editor_scale
	var maximum_width := MAX_TOOLTIP_WIDTH * editor_scale
	var available_width := EditorInterface.get_base_control().size.x * 0.65
	maximum_width = min(maximum_width, available_width)
	maximum_width = max(maximum_width, minimum_width)
	var editor_theme := EditorInterface.get_editor_theme()
	if not editor_theme.has_font("source", "EditorFonts"):
		return minimum_width
	var source_font := editor_theme.get_font("source", "EditorFonts")
	var source_font_size := editor_theme.get_font_size(
		"source_size",
		"EditorFonts"
	)
	var plain_text := _strip_markup_for_measurement(
		_convert_godot_documentation_markup(description)
	)
	var measured_width := 0.0
	for line in plain_text.split("\n"):
		var line_width := source_font.get_string_size(
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			source_font_size
		).x
		measured_width = max(measured_width, line_width)
	return clamp(
		measured_width + TOOLTIP_HORIZONTAL_PADDING * editor_scale,
		minimum_width,
		maximum_width
	)

func _convert_godot_documentation_markup(text: String) -> String:
	var converted := text
	# RichTextLabel has no codeblock or kbd tags. Their visual meaning is
	# approximated with its built-in monospace code tag.
	var codeblock_pattern := RegEx.new()
	codeblock_pattern.compile("\\[codeblock(?:\\s+lang=[^\\]]+)?\\]")
	converted = codeblock_pattern.sub(converted, "[code]", true)
	converted = converted.replace("[/codeblock]", "[/code]")
	converted = converted.replace("[kbd]", "[code]")
	converted = converted.replace("[/kbd]", "[/code]")
	# Godot class-reference links are not RichTextLabel BBCode tags. Display
	# their target as code instead of letting the RichTextLabel parser hide it.
	var reference_pattern := RegEx.new()
	reference_pattern.compile(
		"\\[(?:class|method|member|signal|constant|enum|annotation|param)\\s+([^\\]]+)\\]"
	)
	var references := reference_pattern.search_all(converted)
	for index in range(references.size() - 1, -1, -1):
		var reference_match := references[index]
		var reference_before := converted.left(reference_match.get_start())
		var reference_replacement := (
			"[code]" + reference_match.get_string(1) + "[/code]"
		)
		var reference_after := converted.substr(reference_match.get_end())
		converted = reference_before + reference_replacement + reference_after
	# The short class-reference form, for example [Node2D].
	var class_pattern := RegEx.new()
	class_pattern.compile("\\[([A-Z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_@]+)*)\\]")
	var classes := class_pattern.search_all(converted)
	for index in range(classes.size() - 1, -1, -1):
		var class_match := classes[index]
		var class_before := converted.left(class_match.get_start())
		var class_replacement := (
			"[code]" + class_match.get_string(1) + "[/code]"
		)
		var class_after := converted.substr(class_match.get_end())
		converted = class_before + class_replacement + class_after
	return converted

func _strip_markup_for_measurement(text: String) -> String:
	var without_tags := text
	var tag_pattern := RegEx.new()
	tag_pattern.compile("\\[.*?\\]")
	without_tags = tag_pattern.sub(without_tags, "", true)
	return without_tags

func _starts_with_keyword(line: String, keyword: String) -> bool:
	if not line.begins_with(keyword):
		return false
	if line.length() == keyword.length():
		return true
	var next_character := line.substr(keyword.length(), 1)
	return next_character == " " or next_character == "\t"
