@tool
class_name BTDocumentationRenderer
extends RefCounted

## Renders Godot class-reference documentation markup into a [RichTextLabel].
## The renderer deliberately mirrors [code]EditorHelp[/code] theme fonts, sizes,
## colors and spacing so every documentation surface can share one visual style.
## It is independent from source extraction and is shared by FileSystem class
## documentation, Code Editor member documentation and the local syntax help.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const EDITOR_HELP_THEME_TYPE := "EditorHelp"
const EDITOR_THEME_TYPE := "Editor"
const EDITOR_FONTS_THEME_TYPE := "EditorFonts"
const EDITOR_ICONS_THEME_TYPE := "EditorIcons"
const CODEBLOCK_PADDING := 10.0

const REFERENCE_TAGS := {
	"method": "class_method",
	"constructor": "class_method",
	"operator": "class_method",
	"member": "class_property",
	"signal": "class_signal",
	"enum": "class_enum",
	"constant": "class_constant",
	"annotation": "class_annotation",
	"theme_item": "class_theme_item",
}

const BUILTIN_DOCUMENTATION_TYPES := {
	"@GlobalScope": true,
	"@GDScript": true,
	"Nil": true,
	"bool": true,
	"int": true,
	"float": true,
	"AABB": true,
	"Array": true,
	"Basis": true,
	"Callable": true,
	"Color": true,
	"Dictionary": true,
	"NodePath": true,
	"PackedByteArray": true,
	"PackedColorArray": true,
	"PackedFloat32Array": true,
	"PackedFloat64Array": true,
	"PackedInt32Array": true,
	"PackedInt64Array": true,
	"PackedStringArray": true,
	"PackedVector2Array": true,
	"PackedVector3Array": true,
	"PackedVector4Array": true,
	"Plane": true,
	"Projection": true,
	"Quaternion": true,
	"Rect2": true,
	"Rect2i": true,
	"RID": true,
	"Signal": true,
	"String": true,
	"StringName": true,
	"Transform2D": true,
	"Transform3D": true,
	"Variant": true,
	"Vector2": true,
	"Vector2i": true,
	"Vector3": true,
	"Vector3i": true,
	"Vector4": true,
	"Vector4i": true,
}

var use_tooltip_font_settings := true
var _theme: Theme
var _global_classes: Dictionary = {}

# Captures the current editor theme and user-defined global classes. A renderer
# can be kept alive and reused; refresh_theme() may be called after a theme change.
func refresh_theme() -> void:
	_theme = EditorInterface.get_editor_theme()
	_global_classes.clear()
	for class_data in ProjectSettings.get_global_class_list():
		var class_name_value := str(class_data.get("class", ""))
		if not class_name_value.is_empty():
			_global_classes[class_name_value] = true

# Applies the same document font, size and spacing entries used by EditorHelp.
# Interactive labels additionally receive link/copy handling through metadata.
func configure_label(label: RichTextLabel, interactive: bool = false) -> void:
	_ensure_theme()
	label.bbcode_enabled = false
	label.meta_underlined = true
	label.add_theme_font_override("normal_font", _get_font("doc"))
	label.add_theme_font_override("bold_font", _get_font("doc_bold"))
	label.add_theme_font_override("italics_font", _get_font("doc_italic"))
	label.add_theme_font_override("bold_italics_font", _get_font("doc_bold"))
	label.add_theme_font_override("mono_font", _get_font("doc_source"))
	label.add_theme_font_size_override("normal_font_size", _get_font_size("doc_size"))
	label.add_theme_font_size_override("bold_font_size", _get_font_size("doc_size"))
	label.add_theme_font_size_override("italics_font_size", _get_font_size("doc_size"))
	label.add_theme_font_size_override("bold_italics_font_size", _get_font_size("doc_size"))
	label.add_theme_font_size_override("mono_font_size", _get_font_size("doc_source_size"))
	label.add_theme_color_override("default_color", _get_color("text_color"))
	for constant_name in [
		"line_separation",
		"paragraph_separation",
		"table_h_separation",
		"table_v_separation",
		"text_highlight_h_padding",
		"text_highlight_v_padding",
	]:
		if _theme.has_constant(constant_name, EDITOR_HELP_THEME_TYPE):
			label.add_theme_constant_override(
				constant_name,
				_theme.get_constant(constant_name, EDITOR_HELP_THEME_TYPE)
			)
	var meta_callable := Callable(self, "_on_meta_clicked")
	if interactive:
		if not label.meta_clicked.is_connected(meta_callable):
			label.meta_clicked.connect(meta_callable)
	else:
		if label.meta_clicked.is_connected(meta_callable):
			label.meta_clicked.disconnect(meta_callable)

# Applies EditorHelp's document background and minimum horizontal reading margin.
# This is intended for full help surfaces; hover tooltips keep their existing
# tooltip panel and only reuse EditorHelp typography/colors.
func style_help_surface(label: RichTextLabel) -> void:
	_ensure_theme()
	if not _theme.has_stylebox("background", EDITOR_HELP_THEME_TYPE):
		return
	var background := _theme.get_stylebox(
		"background",
		EDITOR_HELP_THEME_TYPE
	).duplicate()
	var display_margin := 15.0 * EditorInterface.get_editor_scale()
	background.content_margin_left = max(
		background.content_margin_left,
		display_margin
	)
	background.content_margin_right = max(
		background.content_margin_right,
		display_margin
	)
	label.add_theme_stylebox_override("normal", background)
	label.add_theme_stylebox_override("focused", background)

# Renders a documentation data dictionary. The common keys are description,
# deprecated, experimental and tutorials, which also map cleanly to future
# member-level documentation tooltips.
func render_document(
	label: RichTextLabel,
	documentation: Dictionary,
	context_class: String = "",
	interactive: bool = false
) -> void:
	configure_label(label, interactive)
	label.clear()
	var wrote_content := false
	var deprecated_message := str(documentation.get("deprecated", ""))
	if bool(documentation.get("is_deprecated", false)):
		_append_status(label, "Deprecated", deprecated_message, true, interactive)
		wrote_content = true
	var experimental_message := str(documentation.get("experimental", ""))
	if bool(documentation.get("is_experimental", false)):
		if wrote_content:
			label.newline()
		_append_status(label, "Experimental", experimental_message, false, interactive)
		wrote_content = true
	var description := str(documentation.get("description", ""))
	if not description.strip_edges().is_empty():
		if wrote_content:
			label.newline()
		_append_markup(label, description, context_class, interactive)
		wrote_content = true
	var tutorials: Array = documentation.get("tutorials", [])
	if not tutorials.is_empty():
		if wrote_content:
			label.newline()
		_append_tutorials(label, tutorials, interactive)

# Renders standalone Godot documentation markup. This is used by the built-in
# syntax help dialog and is intentionally the same code path as tooltip content.
func render_markup(
	label: RichTextLabel,
	markup: String,
	context_class: String = "",
	interactive: bool = false
) -> void:
	configure_label(label, interactive)
	label.clear()
	_append_markup(label, markup, context_class, interactive)

# Returns a display-only approximation of the markup for tooltip width
# measurement. It removes formatting tags but preserves their visible targets.
func to_plain_text(markup: String) -> String:
	var text := markup
	var code_tags := RegEx.new()
	code_tags.compile("\\[(?:code|kbd)(?:\\s+[^\\]]*)?\\](.*?)\\[/(?:code|kbd)\\]")
	text = code_tags.sub(text, "$1", true)
	var codeblock_tags := RegEx.new()
	codeblock_tags.compile("(?s)\\[codeblock(?:\\s+[^\\]]*)?\\](.*?)\\[/codeblock\\]")
	text = codeblock_tags.sub(text, "$1", true)
	var reference_tags := RegEx.new()
	reference_tags.compile(
		"\\[(?:class|method|constructor|operator|member|signal|enum|constant|annotation|theme_item|param)\\s+([^\\]]+)\\]"
	)
	text = reference_tags.sub(text, "$1", true)
	text = text.replace("[br]", "\n")
	text = text.replace("[lb]", "[")
	text = text.replace("[rb]", "]")
	var image_tags := RegEx.new()
	image_tags.compile("(?s)\\[img(?:\\s+[^\\]]*)?\\].*?\\[/img\\]")
	text = image_tags.sub(text, "", true)
	var remaining_tags := RegEx.new()
	remaining_tags.compile("\\[/?(?:b|i|u|s|center|color(?:=[^\\]]+)?|font(?:=[^\\]]+)?|url(?:=[^\\]]+)?)\\]")
	text = remaining_tags.sub(text, "", true)
	return text

# Exposes the EditorHelp document font used by width calculations without
# duplicating theme lookups in every tooltip consumer.
func get_document_font() -> Font:
	_ensure_theme()
	return _get_font("doc")

# Exposes the EditorHelp document font size used by width calculations.
func get_document_font_size() -> int:
	_ensure_theme()
	return _get_font_size("doc_size")

# Applies the monospace type style Godot uses for class references to a Label.
func style_type_label(label: Label) -> void:
	_ensure_theme()
	label.add_theme_font_override("font", _get_font("doc_source"))
	label.add_theme_font_size_override("font_size", _get_font_size("doc_source_size"))
	label.add_theme_color_override("font_color", _get_color("type_color"))

# Parses Godot's class-reference markup directly into RichTextLabel's tag stack.
# Code, keyboard and codeblock contents are consumed as literal text, matching
# the rule that BBCode is disabled inside those official documentation tags.
func _append_markup(
	label: RichTextLabel,
	markup: String,
	context_class: String,
	interactive: bool
) -> void:
	_ensure_theme()
	var text := _collapse_empty_paragraphs(
		markup.dedent().replace("\r", "").strip_edges()
	)
	var stack: Array[Dictionary] = []
	var position := 0
	while position < text.length():
		var bracket_position := text.find("[", position)
		if bracket_position < 0:
			label.add_text(text.substr(position))
			break
		if bracket_position > position:
			label.add_text(text.substr(position, bracket_position - position))
		var bracket_end := text.find("]", bracket_position + 1)
		if bracket_end < 0:
			label.add_text(text.substr(bracket_position))
			break
		var tag := text.substr(
			bracket_position + 1,
			bracket_end - bracket_position - 1
		)
		if tag.begins_with("/"):
			var closing_tag := tag.substr(1)
			if stack.is_empty() or str(stack[stack.size() - 1]["tag"]) != closing_tag:
				label.add_text("[")
				position = bracket_position + 1
				continue
			var stack_entry: Dictionary = stack.pop_back()
			for pop_index in range(int(stack_entry["pop_count"])):
				label.pop()
			if closing_tag == "url" and bool(stack_entry.get("external_icon", false)):
				_append_external_link_icon(label)
			position = bracket_end + 1
			continue
		if _is_reference_tag(tag):
			_append_reference(label, tag, context_class, interactive)
			position = bracket_end + 1
			continue
		if tag.begins_with("param "):
			_append_parameter(label, tag.substr(6).strip_edges())
			position = bracket_end + 1
			continue
		if tag.begins_with("class "):
			# Compatibility alias retained for documentation authored for older
			# versions of this add-on. Godot's official spelling is [ClassName].
			_append_class_reference(
				label,
				tag.substr(6).strip_edges(),
				context_class,
				interactive
			)
			position = bracket_end + 1
			continue
		if _is_documentation_class(tag):
			_append_class_reference(label, tag, context_class, interactive)
			position = bracket_end + 1
			continue
		if tag == "b":
			label.push_font(_get_font("doc_bold"))
			stack.append({"tag": "b", "pop_count": 1})
			position = bracket_end + 1
			continue
		if tag == "i":
			label.push_font(_get_font("doc_italic"))
			stack.append({"tag": "i", "pop_count": 1})
			position = bracket_end + 1
			continue
		if tag == "u":
			label.push_underline()
			stack.append({"tag": "u", "pop_count": 1})
			position = bracket_end + 1
			continue
		if tag == "s":
			label.push_strikethrough()
			stack.append({"tag": "s", "pop_count": 1})
			position = bracket_end + 1
			continue
		if tag == "center":
			label.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
			stack.append({"tag": "center", "pop_count": 1})
			position = bracket_end + 1
			continue
		if tag == "br":
			label.add_text("\r")
			position = bracket_end + 1
			continue
		if tag == "lb":
			label.add_text("[")
			position = bracket_end + 1
			continue
		if tag == "rb":
			label.add_text("]")
			position = bracket_end + 1
			continue
		if tag == "code" or tag.begins_with("code "):
			position = _append_literal_span(
				label,
				text,
				bracket_end,
				"code",
				_get_font("doc_source"),
				_get_font_size("doc_source_size"),
				_get_color("code_bg_color"),
				_get_inline_code_color()
			)
			continue
		if tag == "kbd":
			position = _append_literal_span(
				label,
				text,
				bracket_end,
				"kbd",
				_get_font("doc_keyboard"),
				_get_font_size("doc_keyboard_size"),
				_get_color("kbd_bg_color"),
				_get_color("kbd_color")
			)
			continue
		if tag == "codeblock" or tag.begins_with("codeblock "):
			position = _append_codeblock(
				label,
				text,
				bracket_end,
				tag,
				interactive
			)
			continue
		if tag == "url" or tag.begins_with("url="):
			var url := _get_url_target(text, tag, bracket_end)
			label.push_color(_get_color("link_color"))
			label.push_meta(
				{"kind": "url", "target": url, "interactive": interactive},
				RichTextLabel.META_UNDERLINE_ON_HOVER,
				url
			)
			stack.append({
				"tag": "url",
				"pop_count": 2,
				"external_icon": true,
			})
			position = bracket_end + 1
			continue
		if tag.begins_with("color="):
			label.push_color(Color.from_string(tag.substr(6), _get_color("text_color")))
			stack.append({"tag": "color", "pop_count": 1})
			position = bracket_end + 1
			continue
		if tag.begins_with("font="):
			var font_resource := load(tag.substr(5)) as Font
			label.push_font(font_resource if font_resource != null else _get_font("doc"))
			stack.append({"tag": "font", "pop_count": 1})
			position = bracket_end + 1
			continue
		if tag == "img" or tag.begins_with("img "):
			position = _append_image(label, text, bracket_end, tag)
			continue
		label.add_text("[")
		position = bracket_position + 1
	for stack_index in range(stack.size() - 1, -1, -1):
		var stack_entry: Dictionary = stack[stack_index]
		for pop_index in range(int(stack_entry["pop_count"])):
			label.pop()

# Collapses empty paragraphs outside code blocks. RichTextLabel applies the
# EditorHelp paragraph_separation theme value to each LF, so a source blank line
# must become one paragraph break rather than an additional empty paragraph.
# Code-block contents are preserved verbatim and handle line spacing separately.
func _collapse_empty_paragraphs(markup: String) -> String:
	var result := ""
	var position := 0
	var in_codeblock := false
	var previous_was_newline := false
	while position < markup.length():
		if not in_codeblock and markup.substr(position, 10) == "[codeblock":
			in_codeblock = true
			previous_was_newline = false
		elif in_codeblock and markup.substr(position, 12) == "[/codeblock]":
			in_codeblock = false
			previous_was_newline = false
		var character := markup.substr(position, 1)
		if character == "\n" and not in_codeblock:
			if previous_was_newline:
				position += 1
				continue
			previous_was_newline = true
		else:
			previous_was_newline = false
		result += character
		position += 1
	return result

# Renders one reference tag with Godot's semantic reference colors and source
# font. Metadata is retained even for noninteractive surfaces for visual parity.
func _append_reference(
	label: RichTextLabel,
	tag: String,
	context_class: String,
	interactive: bool
) -> void:
	var split_position := tag.find(" ")
	if split_position < 0:
		return
	var reference_kind := tag.left(split_position)
	var target := tag.substr(split_position + 1).strip_edges()
	if target.is_empty():
		return
	var target_color := _get_color("link_color")
	var underline_mode := RichTextLabel.META_UNDERLINE_ON_HOVER
	if reference_kind in ["method", "constructor", "operator"]:
		target_color = _get_editor_color("accent_color")
	elif reference_kind in ["member", "signal", "theme_item"]:
		target_color = _get_color("link_color").lerp(
			_get_editor_color("accent_color"),
			0.25
		)
	elif reference_kind == "annotation":
		target_color = _get_color("link_color").lerp(
			_get_editor_color("accent_color"),
			0.5
		)
	else:
		underline_mode = RichTextLabel.META_UNDERLINE_ALWAYS
	label.push_font(_get_font("doc_source"))
	label.push_font_size(_get_font_size("doc_source_size"))
	label.push_color(target_color)
	label.push_meta(
		{
			"kind": "reference",
			"reference_kind": reference_kind,
			"target": target,
			"context_class": context_class,
			"interactive": interactive,
		},
		underline_mode
	)
	var visible_target := target
	if reference_kind == "method":
		visible_target += "()"
	label.add_text(visible_target)
	label.pop()
	label.pop()
	label.pop()
	label.pop()

# Renders [param] using the same source font and parameter background color as
# EditorHelp, without making it a navigation link.
func _append_parameter(label: RichTextLabel, parameter_name: String) -> void:
	label.push_font(_get_font("doc_source"))
	label.push_font_size(_get_font_size("doc_source_size"))
	label.push_bgcolor(_get_color("param_bg_color"))
	label.push_color(_get_color("code_color"))
	label.add_text(parameter_name)
	label.pop()
	label.pop()
	label.pop()
	label.pop()

# Renders the short [ClassName] form using EditorHelp's type color.
func _append_class_reference(
	label: RichTextLabel,
	class_name_value: String,
	context_class: String,
	interactive: bool
) -> void:
	if class_name_value == context_class:
		label.push_font(_get_font("doc_bold"))
		label.add_text(class_name_value)
		label.pop()
		return
	label.push_font(_get_font("doc_source"))
	label.push_font_size(_get_font_size("doc_source_size"))
	label.push_color(_get_color("type_color"))
	label.push_meta(
		{
			"kind": "class",
			"target": class_name_value,
			"interactive": interactive,
		},
		RichTextLabel.META_UNDERLINE_ON_HOVER
	)
	label.add_text(class_name_value)
	label.pop()
	label.pop()
	label.pop()
	label.pop()

# Consumes literal [code] or [kbd] content and renders it without parsing nested
# documentation tags, exactly as Godot's documentation parser specifies.
func _append_literal_span(
	label: RichTextLabel,
	text: String,
	opening_end: int,
	tag_name: String,
	font: Font,
	font_size: int,
	background_color: Color,
	foreground_color: Color
) -> int:
	var closing_tag := "[/%s]" % tag_name
	var end_position := text.find(closing_tag, opening_end + 1)
	if end_position < 0:
		end_position = text.length()
	label.push_font(font)
	label.push_font_size(font_size)
	label.push_bgcolor(background_color)
	label.push_color(foreground_color)
	label.add_text(text.substr(opening_end + 1, end_position - opening_end - 1))
	label.pop()
	label.pop()
	label.pop()
	label.pop()
	if end_position >= text.length():
		return text.length()
	return end_position + closing_tag.length()

# Renders a full-width code block with the same EditorHelp source font,
# background and padding. GDScript blocks use Godot's public editor syntax
# highlighter; text and unavailable languages fall back to plain source text.
func _append_codeblock(
	label: RichTextLabel,
	text: String,
	opening_end: int,
	tag: String,
	interactive: bool
) -> int:
	var closing_tag := "[/codeblock]"
	var end_position := text.find(closing_tag, opening_end + 1)
	if end_position < 0:
		end_position = text.length()
	var code := text.substr(opening_end + 1, end_position - opening_end - 1).strip_edges()
	var language := "gdscript"
	for argument in tag.trim_prefix("codeblock").split(" ", false):
		if argument.begins_with("lang="):
			language = argument.trim_prefix("lang=").to_lower()
	var code_background := _get_color("code_bg_color")
	var editor_scale := EditorInterface.get_editor_scale()
	label.push_font(_get_font("doc_source"))
	label.push_font_size(_get_font_size("doc_source_size"))
	label.push_table(2 if interactive else 1)
	label.set_table_column_expand(0, true, 1, false)
	label.push_cell()
	label.set_cell_row_background_color(
		code_background,
		Color(code_background, code_background.a * 0.99)
	)
	label.set_cell_padding(
		Rect2(
			CODEBLOCK_PADDING * editor_scale,
			CODEBLOCK_PADDING * editor_scale,
			CODEBLOCK_PADDING * editor_scale,
			CODEBLOCK_PADDING * editor_scale
		)
	)
	label.push_color(Color(_get_color("code_color"), 0.8))
	if language == "gdscript" or language.is_empty():
		_append_highlighted_gdscript(label, code)
	else:
		# CR is RichTextLabel's line break inside a paragraph. Using LF here
		# would also apply EditorHelp's paragraph_separation to every code line.
		label.add_text(code.replace("\n", "\r"))
	label.pop()
	label.pop()
	if interactive:
		label.push_cell()
		label.set_cell_row_background_color(
			code_background,
			Color(code_background, code_background.a * 0.99)
		)
		label.set_cell_padding(
			Rect2(
				0.0,
				CODEBLOCK_PADDING * editor_scale,
				0.0,
				CODEBLOCK_PADDING * editor_scale
			)
		)
		label.push_meta(
			{"kind": "copy", "text": code},
			RichTextLabel.META_UNDERLINE_ON_HOVER,
			"Copy code"
		)
		var copy_icon := _get_icon("ActionCopy")
		if copy_icon != null:
			label.add_image(
				copy_icon,
				24.0 * editor_scale,
				24.0 * editor_scale,
				Color(_get_color("link_color"), 0.55)
			)
		else:
			label.add_text("Copy")
		label.pop()
		label.pop()
	label.pop()
	label.pop()
	label.pop()
	if end_position >= text.length():
		return text.length()
	var next_position := end_position + closing_tag.length()
	# Normalized documentation already carries the paragraph break after a
	# codeblock. Only synthesize one for malformed/compact markup that continues
	# immediately on the same source line.
	if next_position < text.length():
		var next_character := text.substr(next_position, 1)
		if next_character != "\n" and next_character != "\r":
			label.newline()
	return next_position

# Uses GDScriptSyntaxHighlighter with a temporary CodeEdit to obtain the same
# user-configured syntax colors that Godot's script editor uses for GDScript.
func _append_highlighted_gdscript(label: RichTextLabel, code: String) -> void:
	var code_edit := CodeEdit.new()
	code_edit.theme = _theme
	var highlighter := GDScriptSyntaxHighlighter.new()
	code_edit.syntax_highlighter = highlighter
	code_edit.text = code
	highlighter.update_cache()
	var lines := code.split("\n", true)
	for line_index in range(lines.size()):
		var line := lines[line_index]
		var regions: Dictionary = highlighter.get_line_syntax_highlighting(line_index)
		_append_highlighted_line(label, line, regions)
		if line_index < lines.size() - 1:
			# Keep code lines inside one paragraph so EditorHelp's paragraph
			# spacing is not applied between every source line.
			label.add_text("\r")
	code_edit.free()

# Converts SyntaxHighlighter's column/color map for one line into RichTextLabel
# color spans while the surrounding code-block font/background stays active.
func _append_highlighted_line(
	label: RichTextLabel,
	line: String,
	regions: Dictionary
) -> void:
	if regions.is_empty():
		label.add_text(line)
		return
	var columns: Array = regions.keys()
	columns.sort()
	var position := 0
	for column_variant in columns:
		var column := int(column_variant)
		if column > position:
			label.add_text(line.substr(position, column - position))
		var next_position := line.length()
		var column_index := columns.find(column_variant)
		if column_index + 1 < columns.size():
			next_position = int(columns[column_index + 1])
		var region_data: Dictionary = regions[column_variant]
		if region_data.has("color"):
			label.push_color(region_data["color"] as Color)
			label.add_text(line.substr(column, next_position - column))
			label.pop()
		else:
			label.add_text(line.substr(column, next_position - column))
		position = next_position
	if position < line.length():
		label.add_text(line.substr(position))

# Consumes an image tag and supports the documented pixel/percentage width and
# height options. Invalid resources are ignored without breaking the tooltip.
func _append_image(
	label: RichTextLabel,
	text: String,
	opening_end: int,
	tag: String
) -> int:
	var closing_tag := "[/img]"
	var end_position := text.find(closing_tag, opening_end + 1)
	if end_position < 0:
		end_position = text.length()
	var image_path := text.substr(
		opening_end + 1,
		end_position - opening_end - 1
	).strip_edges()
	var width := 0.0
	var height := 0.0
	var width_unit := RichTextLabel.IMAGE_UNIT_PIXEL
	var height_unit := RichTextLabel.IMAGE_UNIT_PIXEL
	for argument in tag.trim_prefix("img").split(" ", false):
		if argument.begins_with("width="):
			var value := argument.trim_prefix("width=").trim_prefix("\"").trim_suffix("\"")
			if value.ends_with("%"):
				width_unit = RichTextLabel.IMAGE_UNIT_PERCENT
			width = value.trim_suffix("%").to_float()
		elif argument.begins_with("height="):
			var value := argument.trim_prefix("height=").trim_prefix("\"").trim_suffix("\"")
			if value.ends_with("%"):
				height_unit = RichTextLabel.IMAGE_UNIT_PERCENT
			height = value.trim_suffix("%").to_float()
	var texture := load(image_path) as Texture2D
	if texture != null:
		label.add_image(
			texture,
			width,
			height,
			Color.WHITE,
			INLINE_ALIGNMENT_CENTER,
			Rect2(),
			null,
			false,
			"",
			width_unit,
			height_unit,
			image_path
		)
	if end_position >= text.length():
		return text.length()
	return end_position + closing_tag.length()

# Adds a compact Deprecated/Experimental notice using EditorHelp's bold document
# font and the editor's standard error/warning colors and icons.
func _append_status(
	label: RichTextLabel,
	title: String,
	message: String,
	is_error: bool,
	interactive: bool
) -> void:
	var icon_name := "StatusError" if is_error else "NodeWarning"
	var icon := _get_icon(icon_name)
	if icon != null:
		label.add_image(icon, 0.0, float(_get_font_size("doc_size")))
		label.add_text(" ")
	label.push_color(
		_get_editor_color("error_color") if is_error
		else _get_editor_color("warning_color")
	)
	label.push_font(_get_font("doc_bold"))
	label.add_text(title + (":" if not message.is_empty() else ""))
	label.pop()
	label.pop()
	if not message.is_empty():
		label.add_text(" ")
		_append_markup(label, message, "", interactive)

# Adds tutorial links stored by GDScript's @tutorial documentation tag.
func _append_tutorials(
	label: RichTextLabel,
	tutorials: Array,
	interactive: bool
) -> void:
	label.push_font(_get_font("doc_bold"))
	label.add_text("Tutorials")
	label.pop()
	for tutorial_variant in tutorials:
		var tutorial: Dictionary = tutorial_variant
		var url := str(tutorial.get("url", ""))
		if url.is_empty():
			continue
		var title := str(tutorial.get("title", ""))
		if title.is_empty():
			title = url
		label.newline()
		label.add_text("• ")
		label.push_color(_get_color("link_color"))
		label.push_meta(
			{"kind": "url", "target": url, "interactive": interactive},
			RichTextLabel.META_UNDERLINE_ON_HOVER,
			url
		)
		label.add_text(title)
		label.pop()
		label.pop()
		_append_external_link_icon(label)

# Appends Godot's own external-link icon after a URL when the icon is available.
func _append_external_link_icon(label: RichTextLabel) -> void:
	var icon := _get_icon("ExternalLink")
	if icon == null:
		return
	label.add_text(" ")
	label.add_image(
		icon,
		0.0,
		float(_get_font_size("doc_size")),
		_get_color("link_color")
	)

# Resolves [url] and [url=...] target text without interpreting its body.
func _get_url_target(text: String, tag: String, opening_end: int) -> String:
	if tag.begins_with("url="):
		return tag.substr(4).strip_edges().trim_prefix("\"").trim_suffix("\"")
	var next_tag := text.find("[", opening_end + 1)
	if next_tag < 0:
		next_tag = text.length()
	return text.substr(opening_end + 1, next_tag - opening_end - 1).strip_edges()

# Handles URL, documentation-reference and copy metadata emitted by this renderer.
func _on_meta_clicked(meta: Variant) -> void:
	if not (meta is Dictionary):
		return
	var data := meta as Dictionary
	if data.has("interactive") and not bool(data.get("interactive", false)):
		return
	match str(data.get("kind", "")):
		"url":
			var target_url := str(data.get("target", ""))
			if not target_url.is_empty():
				OS.shell_open(target_url)
		"copy":
			DisplayServer.clipboard_set(str(data.get("text", "")))
		"class":
			_open_help_topic("class_name:" + str(data.get("target", "")))
		"reference":
			_open_reference_help(data)

# Converts a class-reference tag target into ScriptEditor.goto_help()'s encoded
# topic form. Unqualified member names use the renderer's current class context.
func _open_reference_help(data: Dictionary) -> void:
	var reference_kind := str(data.get("reference_kind", ""))
	if not REFERENCE_TAGS.has(reference_kind):
		return
	var target := str(data.get("target", ""))
	var context_class := str(data.get("context_class", ""))
	var class_name_value := context_class
	var member_name := target
	var last_dot := target.rfind(".")
	if last_dot >= 0:
		class_name_value = target.left(last_dot)
		member_name = target.substr(last_dot + 1)
	if class_name_value.is_empty() or member_name.is_empty():
		return
	_open_help_topic(
		str(REFERENCE_TAGS[reference_kind])
		+ ":"
		+ class_name_value
		+ ":"
		+ member_name
	)

# Opens an encoded Godot help topic when the current engine exposes goto_help().
# This guard keeps the renderer usable on older supported editor versions too.
func _open_help_topic(topic: String) -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor != null and script_editor.has_method("goto_help"):
		script_editor.call("goto_help", topic)

# Returns whether a tag can represent a documented class in the current editor.
func _is_documentation_class(tag: String) -> bool:
	if tag.is_empty() or tag.contains(" ") or tag.begins_with("/"):
		return false
	if ClassDB.class_exists(tag):
		return true
	if BUILTIN_DOCUMENTATION_TYPES.has(tag):
		return true
	if _global_classes.has(tag):
		return true
	return false

# Returns whether the opening tag is one of Godot's member-reference forms.
func _is_reference_tag(tag: String) -> bool:
	var split_position := tag.find(" ")
	if split_position < 0:
		return false
	return REFERENCE_TAGS.has(tag.left(split_position))

# Reuses Godot's exact EditorHelp inline-code color blend.
func _get_inline_code_color() -> Color:
	return _get_color("code_color").lerp(_get_editor_color("error_color"), 0.6)

# Lazily initializes theme data for consumers that create the renderer before
# their controls enter the editor tree.
func _ensure_theme() -> void:
	if _theme == null:
		refresh_theme()

# Reads one EditorHelp font with a safe editor/base-control fallback.
func _get_font(font_name: String) -> Font:
	if _theme.has_font(font_name, EDITOR_FONTS_THEME_TYPE):
		return _theme.get_font(font_name, EDITOR_FONTS_THEME_TYPE)
	return EditorInterface.get_base_control().get_theme_font("font")

# Reads one EditorHelp font size with a safe base-control fallback.
func _get_font_size(font_size_name: String) -> int:
	var base_size := EditorInterface.get_base_control().get_theme_font_size("font_size")
	if _theme.has_font_size(font_size_name, EDITOR_FONTS_THEME_TYPE):
		base_size = _theme.get_font_size(font_size_name, EDITOR_FONTS_THEME_TYPE)
	return Settings.scale_text_font_size(base_size) if use_tooltip_font_settings else base_size

# Reads an EditorHelp color with the base text color as fallback.
func _get_color(color_name: String) -> Color:
	if _theme.has_color(color_name, EDITOR_HELP_THEME_TYPE):
		return _theme.get_color(color_name, EDITOR_HELP_THEME_TYPE)
	return EditorInterface.get_base_control().get_theme_color("font_color", "Label")

# Reads a general Editor color used by EditorHelp for accents and notices.
func _get_editor_color(color_name: String) -> Color:
	if _theme.has_color(color_name, EDITOR_THEME_TYPE):
		return _theme.get_color(color_name, EDITOR_THEME_TYPE)
	return _get_color("text_color")

# Reads an editor icon used by EditorHelp. Missing icons degrade without errors.
func _get_icon(icon_name: String) -> Texture2D:
	if _theme.has_icon(icon_name, EDITOR_ICONS_THEME_TYPE):
		return _theme.get_icon(icon_name, EDITOR_ICONS_THEME_TYPE)
	return null
