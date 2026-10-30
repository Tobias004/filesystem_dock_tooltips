@tool
class_name BTTextPreviewRenderer
extends RefCounted

## Shared live renderer for Markdown and generic text-file tooltips.
## Unlike graphical Resource previews, text remains a real RichTextLabel instead
## of being captured into a bitmap. The same Control tree is therefore used in
## FileSystem, Code Editor and navigation tooltips, preserving editor font sizes
## and allowing long content to scroll naturally.

const TooltipAppearance := preload("res://addons/better_tooltips/core/tooltip_appearance.gd")
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
	content.custom_minimum_size.x = TooltipAppearance.text_content_width(PREVIEW_WIDTH * EditorInterface.get_editor_scale())
	outer.add_child(content)
	var text_label := RichTextLabel.new()
	text_label.name = &"TextPreview"
	text_label.bbcode_enabled = false
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.selection_enabled = true
	text_label.focus_mode = Control.FOCUS_NONE
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size.x = TooltipAppearance.text_content_width(PREVIEW_WIDTH * EditorInterface.get_editor_scale())
	text_label.text = str(data.get("text", ""))
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_plain_text_label(text_label)
	content.add_child(text_label)
	_append_truncation_hint(content, bool(data.get("truncated", false)))
	return outer

# Navigation outlines show only the hovered method, not the full script.
# The source font/spacing match the plain .gd preview while long methods are
# bounded and scroll independently from any documentation above them.
static func create_method_source_preview(source: String) -> Control:
	var outer := _create_outer()
	var content := VBoxContainer.new()
	var width := TooltipAppearance.text_content_width(PREVIEW_WIDTH * EditorInterface.get_editor_scale())
	content.custom_minimum_size.x = width
	outer.add_child(content)
	var label := RichTextLabel.new()
	label.name = &"MethodSourcePreview"
	label.bbcode_enabled = false
	label.fit_content = false
	label.scroll_active = true
	label.selection_enabled = true
	label.focus_mode = Control.FOCUS_NONE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = source
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	_configure_plain_text_label(label)
	var renderer := DocumentationRenderer.new() as BTDocumentationRenderer
	renderer.refresh_theme()
	var font := renderer.get_document_font()
	var font_height := float(font.get_height(renderer.get_document_font_size()))
	var scale := EditorInterface.get_editor_scale()
	var source_lines := source.count("\n") + 1
	# A content-length estimate is sufficient to size the initial popup; the
	# RichTextLabel itself handles extra wrapping and actual scroll extent.
	var estimated_height := maxf(54.0 * scale, source_lines * (font_height + scale) + 14.0 * scale)
	var ceiling := minf(360.0 * scale, TooltipAppearance.get_text_max_height_pixels() - 90.0 * scale)
	var window := EditorInterface.get_base_control().get_window()
	if window != null:
		ceiling = minf(ceiling, float(window.size.y) * 0.40)
	label.custom_minimum_size.y = minf(estimated_height, ceiling)
	content.add_child(label)
	return outer

static func create_markdown_preview(path: String, _metadata: Dictionary) -> Control:
	var data := read_preview_text(path)
	if data.is_empty():
		return null
	var outer := _create_outer()
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = TooltipAppearance.text_content_width(PREVIEW_WIDTH * EditorInterface.get_editor_scale())
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
	markdown.custom_minimum_size.x = TooltipAppearance.text_content_width(PREVIEW_WIDTH * EditorInterface.get_editor_scale())
	var anchors := {}
	markdown.text = _markdown_to_bbcode(
		str(data.get("text", "")),
		renderer.get_document_font_size(),
		anchors
	)
	# A link must receive pointer events even when the document is too short
	# to need its own scrollbar. The shared height limiter preserves this flag.
	markdown.set_meta("_bt_interactive_links", true)
	markdown.mouse_filter = Control.MOUSE_FILTER_STOP
	markdown.meta_underlined = true
	markdown.meta_clicked.connect(_on_markdown_link_clicked.bind(path, markdown, anchors))
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
# independent of text font scaling and never resize the preview via the wheel.
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
static func _markdown_to_bbcode(markdown: String, base_font_size: int, anchors: Dictionary = {}) -> String:
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
			var anchor := _heading_slug(heading_text)
			if not anchor.is_empty():
				var unique_anchor := anchor
				var duplicate_index := 1
				while anchors.has(unique_anchor):
					unique_anchor = "%s-%d" % [anchor, duplicate_index]
					duplicate_index += 1
				anchors[unique_anchor] = result.size()
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

# Parse links before escaping brackets: escaping first used to leave literal
# [lb] fragments in the result when a URL failed the regular expression.
# A small scanner also handles parentheses within URLs, escaped punctuation and
# ordinary Markdown emphasis on either side of a link.
static func _inline_markdown_to_bbcode(text: String) -> String:
	var output := ""
	var pending := ""
	var index := 0
	var in_inline_code := false
	while index < text.length():
		if text.substr(index, 1) == "\\" and index + 1 < text.length():
			var escaped := text.substr(index + 1, 1)
			if escaped in ["[", "]", "(", ")", "*", "_", "`", "\\"]:
				pending += escaped
				index += 2
				continue
		if text.substr(index, 1) == "`":
			in_inline_code = not in_inline_code
		if in_inline_code or text.substr(index, 1) != "[":
			pending += text.substr(index, 1)
			index += 1
			continue
		var closing := text.find("](", index + 1)
		if closing < 0 or text.substr(index + 1, closing - index - 1).contains("\n"):
			pending += "["
			index += 1
			continue
		var target_start := closing + 2
		var cursor := target_start
		var depth := 1
		while cursor < text.length():
			var character := text.substr(cursor, 1)
			if character == "\\" and cursor + 1 < text.length():
				cursor += 2
				continue
			if character == "(":
				depth += 1
			elif character == ")":
				depth -= 1
				if depth == 0:
					break
			cursor += 1
		if depth != 0:
			pending += "["
			index += 1
			continue
		var target := text.substr(target_start, cursor - target_start).replace("\\)", ")").replace("\\(", "(")
		var label := text.substr(index + 1, closing - index - 1)
		# Only emit metadata for supported targets. Never turn local schemes,
		# unknown protocols or BBCode brackets into click actions.
		if _is_supported_link_target(target):
			output += _format_inline_text(pending)
			pending = ""
			var safe_meta := "bt-md:" + target.uri_encode()
			output += "[url=%s][color=#4ea1ff]%s[/color][/url]" % [safe_meta, _format_inline_text(label)]
			index = cursor + 1
		else:
			pending += text.substr(index, cursor - index + 1)
			index = cursor + 1
	return output + _format_inline_text(pending)

static func _format_inline_text(text: String) -> String:
	var formatted := _escape_bbcode(text)
	formatted = _regex_replace(formatted, "`([^`\\n]+)`", "[bgcolor=#303030][color=#e4bd78][code]$1[/code][/color][/bgcolor]")
	formatted = _regex_replace(formatted, "\\*\\*([^*\\n]+)\\*\\*", "[b]$1[/b]")
	formatted = _regex_replace(formatted, "__([^_\\n]+)__", "[b]$1[/b]")
	formatted = _regex_replace(formatted, "\\*([^*\\n]+)\\*", "[i]$1[/i]")
	return formatted

static func _is_supported_link_target(target: String) -> bool:
	if target.is_empty() or target.contains("[") or target.contains("]"):
		return false
	if target.contains("\n") or target.contains("\r") or target.contains(" "):
		return false
	var normalized := target.to_lower()
	if normalized.begins_with("https://") or normalized.begins_with("http://"):
		return target.length() > normalized.find("://") + 3
	if target.begins_with("#"):
		return target.length() > 1
	# Only paths within the project are allowed. No other URI schemes, absolute
	# disk paths or Windows drive letters are accepted.
	return not target.contains(":") and not target.begins_with("/") and not target.begins_with("\\")

static func _heading_slug(text: String) -> String:
	var plain := text.strip_edges().to_lower()
	plain = _regex_replace(plain, "`([^`]+)`", "$1")
	plain = _regex_replace(plain, "\\[([^]]+)\\]\\([^)]*\\)", "$1")
	plain = _regex_replace(plain, "[^\\p{L}\\p{N}_ -]", "")
	plain = _regex_replace(plain, "\\s+", "-")
	return plain.strip_edges().trim_prefix("-").trim_suffix("-")

# URLs are deliberately handled only when clicked, never during rendering.
# Relative files are confined to res:// and selected in the FileSystem Dock;
# scripts/scenes can also be opened directly using the public editor APIs.
static func _on_markdown_link_clicked(meta: Variant, source_path: String, label: RichTextLabel, anchors: Dictionary) -> void:
	var value := str(meta)
	if not value.begins_with("bt-md:"):
		return
	var target := value.trim_prefix("bt-md:").uri_decode()
	if not _is_supported_link_target(target):
		return
	var normalized := target.to_lower()
	if normalized.begins_with("https://") or normalized.begins_with("http://"):
		OS.shell_open(target)
		return
	if target.begins_with("#"):
		var anchor := target.substr(1).uri_decode().to_lower()
		if is_instance_valid(label) and anchors.has(anchor):
			label.scroll_to_paragraph(int(anchors[anchor]))
		return
	var path_part := target.get_slice("#", 0).uri_decode()
	if path_part.is_empty():
		return
	var resolved := source_path.get_base_dir().path_join(path_part).simplify_path()
	if not resolved.begins_with("res://") or not FileAccess.file_exists(resolved):
		return
	var dock := EditorInterface.get_file_system_dock()
	if dock != null:
		dock.navigate_to_path(resolved)
	var ext := resolved.get_extension().to_lower()
	if ext == "gd":
		var script := ResourceLoader.load(resolved) as Script
		if script != null:
			EditorInterface.edit_script(script)
	elif ext in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(resolved)
static func _regex_replace(text: String, pattern: String, replacement: String) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return text
	return regex.sub(text, replacement, true)

static func _escape_bbcode(text: String) -> String:
	# Do not chain replace("[", ...) and replace("]", ...): the second
	# replacement also rewrites the closing bracket of the first tag.
	var escaped := ""
	for character in text:
		if character == "[":
			escaped += "[lb]"
		elif character == "]":
			escaped += "[rb]"
		else:
			escaped += character
	return escaped
