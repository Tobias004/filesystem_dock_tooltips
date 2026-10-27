@tool
class_name BTTextPreviewRenderer
extends RefCounted

## Shared live renderer for Markdown and generic text-file tooltips.
## Unlike graphical Resource previews, text remains a real RichTextLabel instead
## of being captured into a bitmap. The same Control tree is therefore used in
## FileSystem, Code Editor and navigation tooltips, preserving editor font sizes
## and allowing long content to scroll naturally.

const DocumentationRenderer := preload(
	"res://addons/better_tooltips/core/documentation_renderer.gd"
)

const PREVIEW_WIDTH := 760.0
const INNER_MARGIN := 10.0
# Text tooltips are intentionally much less aggressively truncated than the old
# bitmap previews. This cap exists only to keep pathological multi-megabyte files
# from turning one hover into an unbounded editor allocation/layout operation.
const MAX_READ_BYTES := 2 * 1024 * 1024
const MAX_PREVIEW_LINES := 8000
const MARKDOWN_EXTENSIONS: Array[String] = ["md", "markdown"]

static func is_markdown_path(path: String) -> bool:
	return path.get_extension().to_lower() in MARKDOWN_EXTENSIONS

# Reads a generous UTF-8 prefix and applies a high independent line cap. Normal
# source/docs files should therefore be shown completely; truncation is reserved
# for genuinely very large files rather than ordinary README/changelog content.
static func read_preview_text(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var total_bytes := file.get_length()
	var read_bytes := mini(total_bytes, MAX_READ_BYTES)
	var buffer := file.get_buffer(read_bytes)
	file.close()
	var text := buffer.get_string_from_utf8()
	if text.begins_with("\uFEFF"):
		text = text.trim_prefix("\uFEFF")
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	var lines := text.split("\n", true)
	var truncated := total_bytes > read_bytes
	if lines.size() > MAX_PREVIEW_LINES:
		lines = lines.slice(0, MAX_PREVIEW_LINES)
		truncated = true
	return {
		"text": "\n".join(lines),
		"truncated": truncated,
		"total_bytes": total_bytes,
		"read_bytes": read_bytes,
	}

static func create_plain_preview(path: String, _metadata: Dictionary) -> Control:
	var data := read_preview_text(path)
	if data.is_empty():
		return null
	var outer := _create_outer()
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = PREVIEW_WIDTH * EditorInterface.get_editor_scale()
	outer.add_child(content)
	var text_label := RichTextLabel.new()
	text_label.name = &"TextPreview"
	text_label.bbcode_enabled = false
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.selection_enabled = true
	text_label.focus_mode = Control.FOCUS_NONE
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size.x = PREVIEW_WIDTH * EditorInterface.get_editor_scale()
	text_label.text = str(data.get("text", ""))
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_plain_text_label(text_label)
	content.add_child(text_label)
	_append_truncation_hint(content, bool(data.get("truncated", false)))
	return outer

static func create_markdown_preview(path: String, _metadata: Dictionary) -> Control:
	var data := read_preview_text(path)
	if data.is_empty():
		return null
	var outer := _create_outer()
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = PREVIEW_WIDTH * EditorInterface.get_editor_scale()
	outer.add_child(content)
	var renderer := DocumentationRenderer.new() as BTDocumentationRenderer
	renderer.refresh_theme()
	var markdown := RichTextLabel.new()
	markdown.name = &"MarkdownPreview"
	renderer.configure_label(markdown, false)
	# Use the same compact paragraph and line spacing for Markdown and plain
	# text previews. Full Godot/code documentation retains its native spacing.
	_configure_compact_text_spacing(markdown)
	markdown.bbcode_enabled = true
	markdown.fit_content = true
	markdown.scroll_active = false
	markdown.selection_enabled = true
	markdown.focus_mode = Control.FOCUS_NONE
	markdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	markdown.custom_minimum_size.x = PREVIEW_WIDTH * EditorInterface.get_editor_scale()
	markdown.text = _markdown_to_bbcode(
		str(data.get("text", "")),
		renderer.get_document_font_size()
	)
	markdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(markdown)
	_append_truncation_hint(content, bool(data.get("truncated", false)))
	return outer

static func _create_outer() -> MarginContainer:
	var outer := MarginContainer.new()
	outer.name = &"LiveTextPreview"
	var margin := roundi(INNER_MARGIN * EditorInterface.get_editor_scale())
	for side: String in ["left", "top", "right", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return outer

static func _append_truncation_hint(content: VBoxContainer, truncated: bool) -> void:
	if not truncated:
		return
	var hint := Label.new()
	hint.text = "… preview truncated (file exceeds the tooltip safety limit)"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_color("font_disabled_color", "Label"):
		hint.add_theme_color_override(
			"font_color",
			theme.get_color("font_disabled_color", "Label")
		)
	content.add_child(hint)

# RichTextLabel inherits EditorHelp's relatively large paragraph and line
# separation. Plain .txt previews should be just as compact as .md previews.
static func _configure_compact_text_spacing(label: RichTextLabel) -> void:
	var spacing := roundi(EditorInterface.get_editor_scale())
	label.add_theme_constant_override("paragraph_separation", spacing)
	label.add_theme_constant_override("line_separation", spacing)

# Generic text uses the editor's source font but deliberately keeps the same
# document-size baseline as the rest of the tooltip. Preview-size settings are
# graphical-only and never shrink/enlarge text fonts.
static func _configure_plain_text_label(label: RichTextLabel) -> void:
	var renderer := DocumentationRenderer.new() as BTDocumentationRenderer
	renderer.refresh_theme()
	renderer.configure_label(label, false)
	_configure_compact_text_spacing(label)
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_font("source", "EditorFonts"):
		label.add_theme_font_override(
			"normal_font",
			theme.get_font("source", "EditorFonts")
		)
	label.add_theme_font_size_override(
		"normal_font_size",
		renderer.get_document_font_size()
	)

# Convert Markdown to BBCode with at most one empty line between source
# blocks. The RichTextLabel's paragraph spacing is compact, so adjacent list
# items and code lines stay close while blank lines remain visually distinct.
static func _markdown_to_bbcode(markdown: String, base_font_size: int) -> String:
	var result := PackedStringArray()
	var in_code_block := false
	var pending_blank := false
	var list_number := 0
	var last_was_heading_ruler := false
	var ordered := RegEx.create_from_string("^([0-9]+)\\.\\s+(.*)$")
	var source_lines := markdown.split("\n", true)
	var line_index := 0
	while line_index < source_lines.size():
		var source_line: String = source_lines[line_index]
		var stripped := source_line.strip_edges()
		# GitHub/VS Code pipe tables: the separator row distinguishes a table
		# from ordinary text containing | characters. Code fences take priority.
		if not in_code_block and line_index + 1 < source_lines.size():
			var header_cells := _split_table_cells(source_line)
			var separator_cells := _split_table_cells(source_lines[line_index + 1])
			if _is_table_separator(header_cells, separator_cells):
				if pending_blank and not result.is_empty():
					result.append("")
				pending_blank = false
				last_was_heading_ruler = false
				var rows: Array[PackedStringArray] = [header_cells]
				line_index += 2
				while line_index < source_lines.size():
					var row_cells := _split_table_cells(source_lines[line_index])
					if row_cells.is_empty() or row_cells.size() != header_cells.size():
						break
					rows.append(row_cells)
					line_index += 1
				result.append(_table_to_bbcode(rows, separator_cells))
				list_number = 0
				continue
		line_index += 1
		if stripped.begins_with("```"):
			if in_code_block:
				# Keep closing tags on the final code line. Separate tag-only
				# lines would create empty paragraphs in RichTextLabel.
				if not result.is_empty():
					result[result.size() - 1] += "[/code][/bgcolor]"
				else:
					result.append("[bgcolor=#151515][code][/code][/bgcolor]")
				in_code_block = false
			else:
				if pending_blank and not result.is_empty():
					result.append("")
				pending_blank = false
				in_code_block = true
				# The opening tags are attached to the first actual code line.
				result.append("[bgcolor=#151515][code]")
			continue
		if in_code_block:
			var code_text := _escape_bbcode(source_line)
			if result.is_empty():
				result.append("[bgcolor=#151515][code]" + code_text)
			elif result[result.size() - 1] == "[bgcolor=#151515][code]":
				result[result.size() - 1] += code_text
			else:
				result.append(code_text)
			continue
		if stripped.is_empty():
			# Heading rules already provide the necessary visual separation.
			# Do not add a whole empty line after them as well.
			if last_was_heading_ruler:
				last_was_heading_ruler = false
				continue
			# A Markdown blank line separates blocks, not every line in a
			# multi-line source section. Collapse repeated source blanks and
			# avoid stacking them with synthetic heading/code-block blanks.
			pending_blank = true
			list_number = 0
			continue
		if pending_blank and not result.is_empty():
			result.append("")
		pending_blank = false
		last_was_heading_ruler = false
		if stripped in ["---", "***", "___"]:
			result.append("[color=#555555]────────────────────────────────────────────────────[/color]")
			continue
		var heading_level := _heading_level(source_line)
		if heading_level > 0:
			var heading_text := stripped.substr(heading_level + 1).strip_edges()
			var heading_size := maxi(base_font_size, base_font_size + 12 - (heading_level - 1) * 3)
			result.append("[font_size=%d][b]%s[/b][/font_size]" % [heading_size, _inline_markdown_to_bbcode(heading_text)])
			if heading_level <= 2:
				result.append("[color=#555555]────────────────────────────────────────────────────[/color]")
				last_was_heading_ruler = true
			list_number = 0
			continue
		if stripped.begins_with(">"):
			var quote := stripped.trim_prefix(">").strip_edges()
			result.append("[color=#318bcc]▏[/color]  [bgcolor=#262626]%s[/bgcolor]" % _inline_markdown_to_bbcode(quote))
			continue
		var depth := source_line.length() - source_line.lstrip(" ").length()
		if stripped.begins_with("- ") or stripped.begins_with("* ") or stripped.begins_with("+ "):
			result.append("%s•  %s" % ["  ".repeat(depth / 2), _inline_markdown_to_bbcode(stripped.substr(2))])
			continue
		var match_ordered := ordered.search(stripped)
		if match_ordered != null:
			list_number = int(match_ordered.get_string(1))
			result.append("%s%d.  %s" % ["  ".repeat(depth / 2), list_number, _inline_markdown_to_bbcode(match_ordered.get_string(2))])
			continue
		result.append(_inline_markdown_to_bbcode(source_line))
	if in_code_block and not result.is_empty():
		result[result.size() - 1] += "[/code][/bgcolor]"
	return "\n".join(result)

# Only pipe tables with a valid Markdown separator are interpreted as tables.
# Escaped pipes and pipes inside inline code belong to the cell, not its border.
static func _split_table_cells(line: String) -> PackedStringArray:
	if not line.contains("|"):
		return PackedStringArray()
	var stripped := line.strip_edges()
	var cells := PackedStringArray()
	var cell := ""
	var escaped := false
	var in_code := false
	var index := 0
	while index < stripped.length():
		var character := stripped.substr(index, 1)
		if escaped:
			cell += character if character == "|" else "\\" + character
			escaped = false
		elif character == "\\":
			escaped = true
		elif character == "`":
			in_code = not in_code
			cell += character
		elif character == "|" and not in_code:
			cells.append(cell.strip_edges())
			cell = ""
		else:
			cell += character
		index += 1
	if escaped:
		cell += "\\"
	cells.append(cell.strip_edges())
	if stripped.begins_with("|") and not cells.is_empty():
		cells.remove_at(0)
	if stripped.ends_with("|") and not cells.is_empty():
		cells.remove_at(cells.size() - 1)
	return cells

static func _is_table_separator(header: PackedStringArray, separators: PackedStringArray) -> bool:
	if header.size() < 2 or header.size() > 12 or header.size() != separators.size():
		return false
	var syntax := RegEx.create_from_string("^:?-{3,}:?$")
	for separator: String in separators:
		if syntax.search(separator) == null:
			return false
	return true

static func _table_to_bbcode(rows: Array[PackedStringArray], separators: PackedStringArray) -> String:
	var output := "[table=%d]" % separators.size()
	for row_index in range(rows.size()):
		var row := rows[row_index]
		var background := "#292929" if row_index == 0 else ("#202020" if row_index % 2 == 1 else "#252525")
		for column in range(separators.size()):
			var alignment := ""
			if separators[column].begins_with(":") and separators[column].ends_with(":"):
				alignment = "center"
			elif separators[column].ends_with(":"):
				alignment = "right"
			var cell_text := _inline_markdown_to_bbcode(row[column])
			if row_index == 0:
				cell_text = "[b]" + cell_text + "[/b]"
			if not alignment.is_empty():
				cell_text = "[" + alignment + "]" + cell_text + "[/" + alignment + "]"
			output += "[cell shrink=false expand=1 border=#494949 bg=%s padding=8,4,8,4]%s[/cell]" % [background, cell_text]
	output += "[/table]"
	return output

static func _heading_level(line: String) -> int:
	var stripped := line.strip_edges()
	var level := 0
	while level < stripped.length() and level < 6 and stripped.substr(level, 1) == "#":
		level += 1
	if level == 0 or level >= stripped.length():
		return 0
	return level if stripped.substr(level, 1) == " " else 0

static func _inline_markdown_to_bbcode(text: String) -> String:
	var result := _escape_bbcode(text)
	result = _regex_replace(result, "`([^`\\n]+)`", "[bgcolor=#303030][color=#e4bd78][code]$1[/code][/color][/bgcolor]")
	result = _regex_replace(result, "\\[lb\\]([^\\n]+?)\\[rb\\]\\((https?://[^ )]+)\\)", "[url=$2][color=#4ea1ff]$1[/color][/url]")
	result = _regex_replace(result, "\\*\\*([^*\\n]+)\\*\\*", "[b]$1[/b]")
	result = _regex_replace(result, "__([^_\\n]+)__", "[b]$1[/b]")
	result = _regex_replace(result, "\\*([^*\\n]+)\\*", "[i]$1[/i]")
	return result

static func _regex_replace(text: String, pattern: String, replacement: String) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return text
	return regex.sub(text, replacement, true)

static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")
