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

const PREVIEW_WIDTH := 620.0
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

# Generic text uses the editor's source font but deliberately keeps the same
# document-size baseline as the rest of the tooltip. Preview-size settings are
# graphical-only and never shrink/enlarge text fonts.
static func _configure_plain_text_label(label: RichTextLabel) -> void:
	var renderer := DocumentationRenderer.new() as BTDocumentationRenderer
	renderer.refresh_theme()
	renderer.configure_label(label, false)
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

# Converts useful Markdown constructs into RichTextLabel BBCode. Base font size
# comes directly from Godot's EditorHelp theme; headings scale relative to that
# size, so FileSystem and Code/IDE tooltips render with identical typography.
static func _markdown_to_bbcode(markdown: String, base_font_size: int) -> String:
	var result := PackedStringArray()
	var in_code_block := false
	for source_line: String in markdown.split("\n", true):
		var stripped := source_line.strip_edges()
		if stripped.begins_with("```"):
			if in_code_block:
				result.append("[/code]")
			else:
				result.append("[code]")
			in_code_block = not in_code_block
			continue
		if in_code_block:
			result.append(_escape_bbcode(source_line))
			continue
		if stripped in ["---", "***", "___"]:
			result.append("──────────────────────────────")
			continue
		var heading_level := _heading_level(source_line)
		if heading_level > 0:
			var heading_text := stripped.substr(heading_level + 1).strip_edges()
			var heading_size := maxi(
				base_font_size,
				base_font_size + 8 - (heading_level - 1) * 2
			)
			result.append(
				"[font_size=%d][b]%s[/b][/font_size]" % [
					heading_size,
					_inline_markdown_to_bbcode(heading_text),
				]
			)
			continue
		if stripped.begins_with(">"):
			var quote := stripped.trim_prefix(">").strip_edges()
			result.append("[i]│ %s[/i]" % _inline_markdown_to_bbcode(quote))
			continue
		if (
			stripped.begins_with("- ")
			or stripped.begins_with("* ")
			or stripped.begins_with("+ ")
		):
			result.append(
				"• %s" % _inline_markdown_to_bbcode(stripped.substr(2))
			)
			continue
		result.append(_inline_markdown_to_bbcode(source_line))
	if in_code_block:
		result.append("[/code]")
	return "\n".join(result)

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
	result = _regex_replace(result, "`([^`\\n]+)`", "[code]$1[/code]")
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
