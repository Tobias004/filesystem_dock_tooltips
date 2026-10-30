@tool
class_name BTGDScriptDocumentationParser
extends RefCounted

## Extracts member documentation from GDScript source without loading the script
## resource. Both [code]##[/code] and optional local [code]#[/code] blocks are
## normalized into the same document data consumed by the shared renderer.

const DOCUMENTATION_MARKER := "##"
const SINGLE_HASH_MARKER := "#"

# Finds documentation for the script class or script-level member named by a
# CodeEdit hover. Supported declarations mirror GDScript documentation members:
# the named script class, functions, variables/properties, constants, signals,
# enums, enum values and inner classes. The closest declaration to the hover line
# wins if a member name occurs more than once.
static func find_member_documentation(
	source: String,
	symbol: String,
	hover_line: int = -1,
	allow_documentation_comments: bool = true,
	allow_single_hash: bool = true
) -> Dictionary:
	if symbol.is_empty():
		return {}
	if source.begins_with("\uFEFF"):
		source = source.trim_prefix("\uFEFF")
	var lines: PackedStringArray = source.split("\n")
	var class_documentation := _find_script_class_documentation(
		lines,
		symbol,
		allow_documentation_comments,
		allow_single_hash
	)
	if not class_documentation.is_empty():
		return class_documentation
	var candidates := _find_member_candidates(lines, symbol)
	if candidates.is_empty():
		return {}
	var candidate := _choose_candidate(candidates, hover_line)
	var declaration_line := int(candidate.get("line", -1))
	if declaration_line < 0:
		return {}
	var documentation := (
		_extract_trailing_documentation(lines[declaration_line])
		if allow_documentation_comments
		else {}
	)
	var source_marker := DOCUMENTATION_MARKER
	if documentation.is_empty():
		var preceding := _find_preceding_documentation(
			lines,
			declaration_line,
			allow_documentation_comments,
			allow_single_hash
		)
		if preceding.is_empty():
			return {}
		documentation = preceding.get("documentation", {})
		source_marker = str(preceding.get("marker", DOCUMENTATION_MARKER))
	if not has_renderable_documentation(documentation):
		return {}
	documentation["source_marker"] = source_marker
	documentation["member_name"] = symbol
	documentation["member_kind"] = str(candidate.get("kind", "member"))
	documentation["declaration_line"] = declaration_line
	return documentation

# Extracts one complete GDScript method, including its declaration and body.
# No script is instantiated. A nearby outline line distinguishes methods of the
# same name in different inner classes; indentation terminates the method body.
# The original indentation is preserved to match the source editor.
static func extract_method_source(
	source: String,
	symbol: String,
	near_line: int = -1
) -> Dictionary:
	if source.is_empty() or symbol.is_empty():
		return {}
	var lines: PackedStringArray = source.replace("\r\n", "\n").split("\n")
	var declaration := RegEx.create_from_string(
		"^\\s*(?:(?:static|abstract)\\s+)*func\\s+([A-Za-z_][A-Za-z_0-9]*)\\s*\\("
	)
	var matches: Array[int] = []
	for index in range(lines.size()):
		var match := declaration.search(lines[index])
		if match != null and match.get_string(1) == symbol:
			matches.append(index)
	if matches.is_empty():
		return {}
	var first_line: int = matches[0]
	if near_line >= 0:
		var nearest_distance := absi(first_line - near_line)
		for candidate in matches:
			var distance := absi(candidate - near_line)
			if distance < nearest_distance:
				first_line = candidate
				nearest_distance = distance
	var indentation := _leading_whitespace_count(lines[first_line])
	var last_line := first_line
	for index in range(first_line + 1, lines.size()):
		var line: String = lines[index]
		if line.strip_edges().is_empty():
			continue
		if _leading_whitespace_count(line) <= indentation:
			break
		last_line = index
	# Include the method's last significant line, not the blank spacing before
	# the following declaration or another class member.
	return {
		"text": "\n".join(lines.slice(first_line, last_line + 1)),
		"line": first_line,
		"end_line": last_line,
	}

# Documentation for a particular function declaration, including functions
# inside inner classes. This avoids showing documentation from a different
# function with the same name in another class.
static func find_method_documentation_at_line(
	source: String,
	symbol: String,
	declaration_line: int,
	allow_documentation_comments: bool = true,
	allow_single_hash: bool = true
) -> Dictionary:
	var lines := source.replace("\r\n", "\n").split("\n")
	if declaration_line < 0 or declaration_line >= lines.size():
		return {}
	var declaration: String = lines[declaration_line]
	var indentation := declaration.substr(0, declaration.length() - declaration.lstrip(" \t").length())
	var start_line := declaration_line
	while start_line > 0:
		var preceding: String = lines[start_line - 1]
		if not preceding.begins_with(indentation):
			break
		var stripped := preceding.substr(indentation.length()).strip_edges()
		if stripped.begins_with("##") or stripped.begins_with("#") or stripped.begins_with("@"):
			start_line -= 1
		else:
			break
	var local_lines := PackedStringArray()
	for index in range(start_line, declaration_line + 1):
		var line: String = lines[index]
		local_lines.append(line.substr(indentation.length()) if line.begins_with(indentation) else line)
	var documentation := find_member_documentation(
		"\n".join(local_lines),
		symbol,
		-1,
		allow_documentation_comments,
		allow_single_hash
	)
	if not documentation.is_empty():
		documentation["declaration_line"] = declaration_line
	return documentation

# Resolves documentation for the script's own class_name. Godot's normal class
# documentation position after class_name/extends is preferred for ## comments;
# the legacy/pre-declaration position is also accepted. Optional single-# local
# documentation is only associated when it precedes class_name itself.
static func _find_script_class_documentation(
	lines: PackedStringArray,
	symbol: String,
	allow_documentation_comments: bool,
	allow_single_hash: bool
) -> Dictionary:
	var class_data := _find_script_class(lines)
	if class_data.is_empty() or str(class_data.get("name", "")) != symbol:
		return {}
	var class_line := int(class_data.get("line", -1))
	if class_line < 0:
		return {}
	var documentation_lines := (
		_find_class_documentation_after_header(lines, class_line)
		if allow_documentation_comments
		else PackedStringArray()
	)
	var documentation := {}
	var source_marker := DOCUMENTATION_MARKER
	if not documentation_lines.is_empty():
		documentation = parse_documentation(
			documentation_lines,
			DOCUMENTATION_MARKER
		)
	else:
		var preceding := _find_preceding_class_documentation(
			lines,
			class_line,
			allow_documentation_comments,
			allow_single_hash
		)
		if preceding.is_empty():
			return {}
		documentation = preceding.get("documentation", {})
		source_marker = str(preceding.get("marker", DOCUMENTATION_MARKER))
	if not has_renderable_documentation(documentation):
		return {}
	documentation["source_marker"] = source_marker
	documentation["member_name"] = symbol
	documentation["member_kind"] = "class"
	documentation["declaration_line"] = class_line
	return documentation

# Finds class_name plus its source line without loading the Script resource.
static func _find_script_class(lines: PackedStringArray) -> Dictionary:
	for index: int in range(lines.size()):
		var stripped := _strip_comment(lines[index]).strip_edges()
		if not _starts_with_keyword(stripped, "class_name"):
			continue
		var remainder := stripped.trim_prefix("class_name").strip_edges()
		var name := _read_identifier(remainder)
		if not name.is_empty():
			return {"line": index, "name": name}
	return {}

# Mirrors Godot's documented script-class placement: blank lines, annotations
# and extends belong to the header and may appear before the following ## block.
static func _find_class_documentation_after_header(
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
	return _collect_comment_block(lines, index, 1, DOCUMENTATION_MARKER)

# Accepts the pre-class_name compatibility placement. Blank lines and script
# annotations between the block and declaration are ignored for ## comments.
# A single-# block is intentionally stricter and must be the nearest comment block.
static func _find_preceding_class_documentation(
	lines: PackedStringArray,
	class_line: int,
	allow_documentation_comments: bool,
	allow_single_hash: bool
) -> Dictionary:
	var index := class_line - 1
	while index >= 0:
		var stripped := lines[index].strip_edges()
		if stripped.is_empty() or stripped.begins_with("@"):
			index -= 1
			continue
		break
	if index < 0:
		return {}
	var marker := ""
	if allow_documentation_comments and _is_documentation_comment(lines[index]):
		marker = DOCUMENTATION_MARKER
	elif allow_single_hash and _is_single_hash_comment(lines[index]):
		marker = SINGLE_HASH_MARKER
	else:
		return {}
	var block := _collect_comment_block(lines, index, -1, marker)
	if block.is_empty():
		return {}
	return {
		"marker": marker,
		"documentation": parse_documentation(block, marker),
	}

# Collects one contiguous comment block while preserving source order.
static func _collect_comment_block(
	lines: PackedStringArray,
	start_index: int,
	direction: int,
	marker: String
) -> PackedStringArray:
	var result := PackedStringArray()
	var index := start_index
	while index >= 0 and index < lines.size():
		var valid := (
			_is_documentation_comment(lines[index])
			if marker == DOCUMENTATION_MARKER
			else _is_single_hash_comment(lines[index])
		)
		if not valid:
			break
		if direction > 0:
			result.append(lines[index])
		else:
			result.insert(0, lines[index])
		index += direction
	return result

# Returns the optional class_name used as context when resolving documentation
# references. Scripts without class_name simply render references without a
# project-class context, matching the renderer's existing fallback behavior.
static func get_script_class_name(source: String) -> String:
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if not _starts_with_keyword(stripped, "class_name"):
			continue
		var remainder := stripped.trim_prefix("class_name").strip_edges()
		var name := _read_identifier(remainder)
		if not name.is_empty():
			return name
	return ""

# Resolves a top-level script alias declared through preload()/load(). This is
# intentionally source-only: it lets Code Editor tooltips follow constants such
# as `const Cache := preload("res://cache.gd")` to that script's class docs
# without loading or instantiating the target merely for documentation lookup.
static func find_script_reference_constant(source: String, symbol: String) -> Dictionary:
	if source.begins_with("\uFEFF"):
		source = source.trim_prefix("\uFEFF")
	if symbol.is_empty():
		return {}
	var lines: PackedStringArray = source.split("\n")
	for index: int in range(lines.size()):
		var raw_line: String = lines[index].trim_suffix("\r")
		if _leading_whitespace_count(raw_line) != 0:
			continue
		var code_line: String = _strip_comment(raw_line).strip_edges()
		if not _starts_with_keyword(code_line, "const"):
			continue
		var remainder := code_line.trim_prefix("const").strip_edges()
		var name := _read_identifier(remainder)
		if name != symbol:
			continue
		var after_name := remainder.substr(name.length()).strip_edges()
		var assignment_position: int = after_name.find(":=")
		var assignment_length: int = 2
		if assignment_position < 0:
			assignment_position = after_name.find("=")
			assignment_length = 1
		if assignment_position < 0:
			return {}
		var expression: String = after_name.substr(
			assignment_position + assignment_length
		).strip_edges()
		var end_index: int = index
		while end_index < lines.size() and end_index - index <= 16:
			var path := _extract_script_load_path(expression)
			if not path.is_empty():
				return {
					"path": path,
					"line": index,
				}
			end_index += 1
			if end_index >= lines.size():
				break
			var continuation_raw: String = lines[end_index].trim_suffix("\r")
			var continuation: String = _strip_comment(continuation_raw).strip_edges()
			# A new top-level statement means the constant expression already ended.
			# The closing parenthesis of the usual multiline preload form is harmless.
			if (
				_leading_whitespace_count(continuation_raw) == 0
				and not continuation.is_empty()
				and continuation != ")"
			):
				break
			expression += "\n" + continuation
		return {}
	return {}

# Resolves a literal preload()/load() or direct res:// string assigned to a GDScript variable or constant.
# Script-level members are available from any line, while local declarations are
# considered only when they belong to the function containing the hover position.
# The result remains source-only: no Resource is loaded merely to discover a path.
static func find_resource_reference(
	source: String,
	symbol: String,
	hover_line: int = -1
) -> Dictionary:
	return _find_resource_reference_internal(source, symbol, hover_line, {}, 0)

# Resolves direct preload()/load() or project-file string assignments and a small chain of statically
# unambiguous identifier aliases. Alias following deliberately stops at four
# links and never evaluates expressions, calls or member access, so a tooltip can
# only claim a concrete Resource when the source itself makes that relationship clear.
static func _find_resource_reference_internal(
	source: String,
	symbol: String,
	hover_line: int,
	visited: Dictionary,
	depth: int
) -> Dictionary:
	if source.begins_with("\uFEFF"):
		source = source.trim_prefix("\uFEFF")
	if symbol.is_empty() or depth > 4 or visited.has(symbol):
		return {}
	visited[symbol] = true
	var lines: PackedStringArray = source.split("\n")
	var declaration_regex: RegEx = RegEx.new()
	declaration_regex.compile(
		"^(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\\([^\\n]*?\\))?)\\s+)*"
		+ "(?:(?:static)\\s+)*(const|var)\\s+([A-Za-z_][A-Za-z0-9_]*)"
	)
	var enclosing_function_line: int = _find_enclosing_function_line(lines, hover_line)
	var member_candidates: Array[Dictionary] = []
	var local_candidates: Array[Dictionary] = []
	for index: int in range(lines.size()):
		var raw_line: String = lines[index].trim_suffix("\r")
		var code_line: String = _strip_comment(raw_line).strip_edges()
		if code_line.is_empty():
			continue
		var match: RegExMatch = declaration_regex.search(code_line)
		if match == null or match.get_string(2) != symbol:
			continue
		var declaration_indent: int = _leading_whitespace_count(raw_line)
		var is_script_member: bool = declaration_indent == 0
		var is_local_in_hover_function: bool = (
			not is_script_member
			and enclosing_function_line >= 0
			and index > enclosing_function_line
			and (hover_line < 0 or index <= hover_line)
		)
		if not is_script_member and not is_local_in_hover_function:
			continue

		var after_name: String = code_line.substr(match.get_end(2)).strip_edges()
		var assignment_position: int = after_name.find(":=")
		var assignment_length: int = 2
		if assignment_position < 0:
			assignment_position = after_name.find("=")
			assignment_length = 1
		if assignment_position < 0:
			continue
		var expression: String = after_name.substr(
			assignment_position + assignment_length
		).strip_edges()
		var end_index: int = index
		var path: String = ""
		while end_index < lines.size() and end_index - index <= 16:
			path = _extract_resource_load_path(expression)
			if path.is_empty():
				path = _extract_direct_project_path(expression)
			if not path.is_empty():
				break
			end_index += 1
			if end_index >= lines.size():
				break
			var continuation_raw: String = lines[end_index].trim_suffix("\r")
			var continuation: String = _strip_comment(continuation_raw).strip_edges()
			if (
				not continuation.is_empty()
				and _leading_whitespace_count(continuation_raw) <= declaration_indent
				and continuation != ")"
			):
				break
			expression += "\n" + continuation
		var candidate: Dictionary = {
			"path": path,
			"line": index,
			"kind": match.get_string(1),
			"local": not is_script_member,
			"alias": "",
		}
		if path.is_empty():
			var alias: String = _extract_identifier_alias(expression)
			if alias.is_empty() or alias == symbol:
				continue
			candidate["alias"] = alias
		if is_script_member:
			member_candidates.append(candidate)
		else:
			local_candidates.append(candidate)
	var selected: Dictionary = {}
	if not local_candidates.is_empty():
		selected = local_candidates.back()
	elif not member_candidates.is_empty():
		selected = member_candidates[0]
		if hover_line >= 0 and member_candidates.size() > 1:
			var best_distance: int = absi(int(selected.get("line", 0)) - hover_line)
			for candidate: Dictionary in member_candidates:
				var distance: int = absi(int(candidate.get("line", 0)) - hover_line)
				if distance < best_distance:
					selected = candidate
					best_distance = distance
	if selected.is_empty():
		return {}
	if not str(selected.get("path", "")).is_empty():
		return selected
	var alias_symbol: String = str(selected.get("alias", ""))
	if alias_symbol.is_empty():
		return {}
	var resolved: Dictionary = _find_resource_reference_internal(
		source,
		alias_symbol,
		hover_line,
		visited,
		depth + 1
	)
	if resolved.is_empty():
		return {}
	resolved["alias_depth"] = depth + 1
	resolved["alias_symbol"] = alias_symbol
	resolved["requested_symbol"] = symbol
	return resolved

# Resolves a GDScript variable or constant whose initializer is a statically
# identifiable scene-node reference. Script members and locals follow the same
# scope rules as Resource references, and short bare-identifier alias chains are
# supported without evaluating arbitrary expressions or assignments.
static func find_node_reference(
	source: String,
	symbol: String,
	hover_line: int = -1
) -> Dictionary:
	return _find_node_reference_internal(source, symbol, hover_line, {}, 0)

static func _find_node_reference_internal(
	source: String,
	symbol: String,
	hover_line: int,
	visited: Dictionary,
	depth: int
) -> Dictionary:
	if source.begins_with("\uFEFF"):
		source = source.trim_prefix("\uFEFF")
	if symbol.is_empty() or depth > 4 or visited.has(symbol):
		return {}
	visited[symbol] = true
	var lines: PackedStringArray = source.split("\n")
	var declaration_regex: RegEx = RegEx.new()
	declaration_regex.compile(
		"^(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\\([^\\n]*?\\))?)\\s+)*"
		+ "(?:(?:static)\\s+)*(const|var)\\s+([A-Za-z_][A-Za-z0-9_]*)"
	)
	var enclosing_function_line: int = _find_enclosing_function_line(lines, hover_line)
	var member_candidates: Array[Dictionary] = []
	var local_candidates: Array[Dictionary] = []
	for index: int in range(lines.size()):
		var raw_line: String = lines[index].trim_suffix("\r")
		var code_line: String = _strip_comment(raw_line).strip_edges()
		if code_line.is_empty():
			continue
		var match: RegExMatch = declaration_regex.search(code_line)
		if match == null or match.get_string(2) != symbol:
			continue
		var declaration_indent: int = _leading_whitespace_count(raw_line)
		var is_script_member: bool = declaration_indent == 0
		var is_local_in_hover_function: bool = (
			not is_script_member
			and enclosing_function_line >= 0
			and index > enclosing_function_line
			and (hover_line < 0 or index <= hover_line)
		)
		if not is_script_member and not is_local_in_hover_function:
			continue
		var after_name: String = code_line.substr(match.get_end(2)).strip_edges()
		var assignment_position: int = after_name.find(":=")
		var assignment_length: int = 2
		if assignment_position < 0:
			assignment_position = after_name.find("=")
			assignment_length = 1
		if assignment_position < 0:
			continue
		var expression: String = after_name.substr(
			assignment_position + assignment_length
		).strip_edges()
		var end_index: int = index
		var node_reference: Dictionary = {}
		while end_index < lines.size() and end_index - index <= 16:
			node_reference = _extract_node_reference_expression(expression)
			if not node_reference.is_empty():
				break
			end_index += 1
			if end_index >= lines.size():
				break
			var continuation_raw: String = lines[end_index].trim_suffix("\r")
			var continuation: String = _strip_comment(continuation_raw).strip_edges()
			if (
				not continuation.is_empty()
				and _leading_whitespace_count(continuation_raw) <= declaration_indent
				and continuation != ")"
			):
				break
			expression += "\n" + continuation
		var candidate: Dictionary = {
			"path": str(node_reference.get("path", "")),
			"line": index,
			"kind": match.get_string(1),
			"local": not is_script_member,
			"node_kind": str(node_reference.get("node_kind", "")),
			"is_shorthand": bool(node_reference.get("is_shorthand", false)),
			"alias": "",
		}
		if node_reference.is_empty():
			var alias: String = _extract_identifier_alias(expression)
			if alias.is_empty() or alias == symbol:
				continue
			candidate["alias"] = alias
		if is_script_member:
			member_candidates.append(candidate)
		else:
			local_candidates.append(candidate)
	var selected: Dictionary = {}
	if not local_candidates.is_empty():
		selected = local_candidates.back()
	elif not member_candidates.is_empty():
		selected = member_candidates[0]
		if hover_line >= 0 and member_candidates.size() > 1:
			var best_distance: int = absi(int(selected.get("line", 0)) - hover_line)
			for candidate: Dictionary in member_candidates:
				var distance: int = absi(int(candidate.get("line", 0)) - hover_line)
				if distance < best_distance:
					selected = candidate
					best_distance = distance
	if selected.is_empty():
		return {}
	if not str(selected.get("path", "")).is_empty():
		return selected
	var alias_symbol: String = str(selected.get("alias", ""))
	if alias_symbol.is_empty():
		return {}
	var resolved: Dictionary = _find_node_reference_internal(
		source,
		alias_symbol,
		hover_line,
		visited,
		depth + 1
	)
	if resolved.is_empty():
		return {}
	resolved["alias_depth"] = depth + 1
	resolved["alias_symbol"] = alias_symbol
	resolved["requested_symbol"] = symbol
	return resolved

# Recognizes only initializer forms whose scene-node meaning is fixed by source:
# $path, %UniqueName, get_node("..."), get_node_or_null("...") and NodePath("...").
# Optional `as Type` casts are allowed because they do not change the referenced path.
static func _extract_node_reference_expression(expression: String) -> Dictionary:
	var stripped: String = expression.strip_edges()
	if stripped.is_empty():
		return {}
	var shorthand_regex: RegEx = RegEx.new()
	shorthand_regex.compile(
		"^(\\$(?:(?:\\.\\.?|[A-Za-z0-9_]+)(?:/(?:\\.\\.?|[A-Za-z0-9_]+))*)"
		+ "|%[A-Za-z_][A-Za-z0-9_]*)"
		+ "(?:\\s+as\\s+[A-Za-z_][A-Za-z0-9_.]*)?\\s*$"
	)
	var shorthand_match: RegExMatch = shorthand_regex.search(stripped)
	if shorthand_match != null:
		return {
			"path": shorthand_match.get_string(1),
			"node_kind": "shorthand",
			"is_shorthand": true,
		}
	for function_name: String in ["get_node", "get_node_or_null", "NodePath"]:
		var call_reference: Dictionary = _extract_literal_node_call(stripped, function_name)
		if not call_reference.is_empty():
			return call_reference
	return {}

static func _extract_literal_node_call(expression: String, function_name: String) -> Dictionary:
	if not expression.begins_with(function_name):
		return {}
	var cursor: int = function_name.length()
	if cursor < expression.length() and _is_identifier_character(expression.substr(cursor, 1)):
		return {}
	while cursor < expression.length() and expression.substr(cursor, 1) in [" ", "\t", "\r", "\n"]:
		cursor += 1
	if cursor >= expression.length() or expression.substr(cursor, 1) != "(":
		return {}
	cursor += 1
	while cursor < expression.length() and expression.substr(cursor, 1) in [" ", "\t", "\r", "\n"]:
		cursor += 1
	if cursor >= expression.length():
		return {}
	var quote: String = expression.substr(cursor, 1)
	if quote != "\"" and quote != "'":
		return {}
	var literal_start: int = cursor + 1
	cursor = literal_start
	var escaped: bool = false
	var literal_end: int = -1
	while cursor < expression.length():
		var character: String = expression.substr(cursor, 1)
		if escaped:
			escaped = false
		elif character == "\\":
			escaped = true
		elif character == quote:
			literal_end = cursor
			break
		cursor += 1
	if literal_end < 0:
		return {}
	var path: String = expression.substr(literal_start, literal_end - literal_start)
	cursor = literal_end + 1
	while cursor < expression.length() and expression.substr(cursor, 1) in [" ", "\t", "\r", "\n"]:
		cursor += 1
	if cursor >= expression.length() or expression.substr(cursor, 1) != ")":
		return {}
	cursor += 1
	var remainder: String = expression.substr(cursor).strip_edges()
	if not remainder.is_empty():
		if not remainder.begins_with("as "):
			return {}
		var type_name: String = remainder.trim_prefix("as ").strip_edges()
		if type_name.is_empty():
			return {}
		for index: int in range(type_name.length()):
			var type_character: String = type_name.substr(index, 1)
			if not _is_identifier_character(type_character) and type_character != ".":
				return {}
	if path.is_empty():
		return {}
	return {
		"path": path,
		"node_kind": function_name,
		"is_shorthand": false,
	}

# Accepts only a bare identifier as an alias. Parenthesized values, calls,
# member access and arithmetic intentionally remain unresolved rather than guessed.
static func _extract_identifier_alias(expression: String) -> String:
	var stripped: String = expression.strip_edges()
	if stripped.is_empty() or stripped.contains("\n"):
		return ""
	var identifier: String = _read_identifier(stripped)
	return identifier if identifier == stripped else ""

# Returns the nearest top-level function declaration containing the hover line.
# The first non-empty top-level statement encountered while scanning backwards is
# decisive: if it is not a function, the hover is at script scope instead.
static func _find_enclosing_function_line(
	lines: PackedStringArray,
	hover_line: int
) -> int:
	if hover_line < 0 or hover_line >= lines.size():
		return -1
	for index in range(hover_line, -1, -1):
		var raw_line: String = lines[index].trim_suffix("\r")
		var code_line: String = _strip_comment(raw_line).strip_edges()
		if code_line.is_empty() or _leading_whitespace_count(raw_line) != 0:
			continue
		return index if _starts_with_keyword(code_line, "func") else -1
	return -1

# Extracts the first literal project-resource path passed to preload()/load().
# Both res:// and uid:// references are retained; the preview pipeline resolves
# UIDs to file paths before cache identity and resource-type lookup.
static func _extract_resource_load_path(expression: String) -> String:
	for function_name_value in ["preload", "load"]:
		var function_name := str(function_name_value)
		var search_position := expression.find(function_name)
		while search_position >= 0:
			var before_ok := (
				search_position == 0
				or not _is_identifier_character(
					expression.substr(search_position - 1, 1)
				)
			)
			var after_name := search_position + function_name.length()
			var after_ok := (
				after_name >= expression.length()
				or not _is_identifier_character(expression.substr(after_name, 1))
			)
			if before_ok and after_ok:
				var open_parenthesis := expression.find("(", after_name)
				if open_parenthesis >= 0:
					var cursor := open_parenthesis + 1
					while (
						cursor < expression.length()
						and expression.substr(cursor, 1) in [" ", "\t", "\r", "\n"]
					):
						cursor += 1
					if cursor < expression.length():
						var quote := expression.substr(cursor, 1)
						if quote == "\"" or quote == "'":
							var end_quote := cursor + 1
							var escaped := false
							while end_quote < expression.length():
								var character := expression.substr(end_quote, 1)
								if escaped:
									escaped = false
								elif character == "\\":
									escaped = true
								elif character == quote:
									var path := expression.substr(
										cursor + 1,
										end_quote - cursor - 1
									)
									return path if (
										path.begins_with("res://")
										or path.begins_with("uid://")
									) else ""
								end_quote += 1
			search_position = expression.find(function_name, search_position + 1)
	return ""

# Extracts a direct quoted res:// or uid:// initializer such as
# `const README_PATH := "res://README.md"`. This lets non-Resource project files
# participate in the same safe hover-preview resolution as preload()/load().
static func _extract_direct_project_path(expression: String) -> String:
	var trimmed := expression.strip_edges()
	if trimmed.length() < 2:
		return ""
	var quote := trimmed.substr(0, 1)
	if quote != "\"" and quote != "'":
		return ""
	var escaped := false
	for index: int in range(1, trimmed.length()):
		var character := trimmed.substr(index, 1)
		if escaped:
			escaped = false
		elif character == "\\":
			escaped = true
		elif character == quote:
			var remainder := trimmed.substr(index + 1).strip_edges()
			if not remainder.is_empty():
				return ""
			var path := trimmed.substr(1, index - 1)
			return path if (
				path.begins_with("res://") or path.begins_with("uid://")
			) else ""
	return ""

# Extracts the literal resource path passed to preload()/load(). Only GDScript
# targets are returned because other resource constants have no class docs for
# this resolver to display.
static func _extract_script_load_path(expression: String) -> String:
	var path := _extract_resource_load_path(expression)
	return path if path.ends_with(".gd") else ""

# Parses a contiguous documentation-comment block into the data shape consumed
# by BTDocumentationRenderer. Both ## and optional # blocks intentionally use
# identical formatting and line-level metadata semantics.
static func parse_documentation(
	lines: PackedStringArray,
	marker: String = DOCUMENTATION_MARKER
) -> Dictionary:
	var documentation := _empty_documentation()
	if lines.is_empty():
		return documentation
	var description_lines := PackedStringArray()
	var in_codeblock := false
	for source_line in lines:
		var line := _remove_comment_prefix(source_line, marker)
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

# Reports whether a parsed block contains anything visible in a documentation
# tooltip, including status/tutorial metadata without ordinary description text.
static func has_renderable_documentation(documentation: Dictionary) -> bool:
	return (
		not str(documentation.get("description", "")).strip_edges().is_empty()
		or bool(documentation.get("is_deprecated", false))
		or bool(documentation.get("is_experimental", false))
		or not (documentation.get("tutorials", []) as Array).is_empty()
	)

# Collects declaration candidates at script scope plus documented enum values.
# Local variables/functions are deliberately ignored so their names cannot be
# confused with a script member when a native Godot symbol tooltip is shown.
static func _find_member_candidates(
	lines: PackedStringArray,
	symbol: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var member_regex := RegEx.new()
	member_regex.compile(
		"^(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\\([^\\n]*?\\))?)\\s+)*"
		+ "(?:(?:static|abstract)\\s+)*"
		+ "(signal|enum|const|var|func|class)\\s+([A-Za-z_][A-Za-z0-9_]*)"
	)
	var index := 0
	while index < lines.size():
		var raw_line: String = lines[index].trim_suffix("\r")
		if _leading_whitespace_count(raw_line) != 0:
			index += 1
			continue
		var code_line: String = _strip_comment(raw_line).strip_edges()
		if code_line.is_empty():
			index += 1
			continue
		var match := member_regex.search(code_line)
		if match != null:
			var kind := match.get_string(1)
			var name := match.get_string(2)
			if name == symbol:
				result.append({
					"line": index,
					"kind": _normalize_member_kind(kind),
				})
			if kind == "enum" and _line_opens_enum(code_line):
				var enum_end := _find_enum_end(lines, index)
				var enum_candidate := _find_enum_value_candidate(
					lines,
					index + 1,
					enum_end,
					symbol
				)
				if not enum_candidate.is_empty():
					result.append(enum_candidate)
				index = maxi(index, enum_end)
		elif _line_opens_enum(code_line):
			# Also supports anonymous enums: enum { VALUE, ... }.
			var enum_end := _find_enum_end(lines, index)
			var enum_candidate := _find_enum_value_candidate(
				lines,
				index + 1,
				enum_end,
				symbol
			)
			if not enum_candidate.is_empty():
				result.append(enum_candidate)
			index = maxi(index, enum_end)
		index += 1
	return result

# Selects the declaration nearest the code position that caused the tooltip.
static func _choose_candidate(
	candidates: Array[Dictionary],
	hover_line: int
) -> Dictionary:
	if candidates.size() == 1 or hover_line < 0:
		return candidates[0]
	var best: Dictionary = candidates[0]
	var best_distance := absi(int(best.get("line", 0)) - hover_line)
	for candidate in candidates:
		var distance := absi(int(candidate.get("line", 0)) - hover_line)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

# Reads documentation immediately above a declaration. Annotation-only lines may
# sit between the comment and declaration exactly as in Godot's documented style;
# a blank or ordinary code line ends the association.
static func _find_preceding_documentation(
	lines: PackedStringArray,
	declaration_line: int,
	allow_documentation_comments: bool,
	allow_single_hash: bool
) -> Dictionary:
	var index := declaration_line - 1
	while index >= 0 and _is_annotation_only_line(lines[index]):
		index -= 1
	if index < 0:
		return {}
	var marker := ""
	if allow_documentation_comments and _is_documentation_comment(lines[index]):
		marker = DOCUMENTATION_MARKER
	elif allow_single_hash and _is_single_hash_comment(lines[index]):
		marker = SINGLE_HASH_MARKER
	else:
		return {}
	var block := PackedStringArray()
	while index >= 0:
		var line := lines[index]
		if marker == DOCUMENTATION_MARKER:
			if not _is_documentation_comment(line):
				break
		else:
			if not _is_single_hash_comment(line):
				break
		block.insert(0, line)
		index -= 1
	return {
		"marker": marker,
		"documentation": parse_documentation(block, marker),
	}

# Supports Godot's trailing member documentation form (e.g. `var x := 1 ## ...`).
# The first real comment marker is located outside quoted strings so hashes in
# literals are not mistaken for comments.
static func _extract_trailing_documentation(line: String) -> Dictionary:
	var comment_position := _find_comment_start(line)
	if comment_position < 0:
		return {}
	var comment := line.substr(comment_position).trim_suffix("\r")
	if not comment.begins_with(DOCUMENTATION_MARKER):
		return {}
	var code_before := line.left(comment_position).strip_edges()
	if code_before.is_empty():
		return {}
	return parse_documentation(
		PackedStringArray([comment]),
		DOCUMENTATION_MARKER
	)

# Finds one enum value declaration inside a top-level enum body. Documentation
# comments are handled later by the same preceding/trailing extraction path.
static func _find_enum_value_candidate(
	lines: PackedStringArray,
	start_line: int,
	end_line: int,
	symbol: String
) -> Dictionary:
	for index in range(start_line, mini(end_line + 1, lines.size())):
		var raw_line := lines[index]
		var code_line: String = _strip_comment(raw_line).strip_edges()
		if code_line.is_empty() or code_line.begins_with("}"):
			continue
		var name := _read_identifier(code_line)
		if name == symbol:
			return {
				"line": index,
				"kind": "enum_value",
			}
	return {}

# Finds the line that closes an enum body while ignoring braces inside comments
# and quoted strings. Malformed/incomplete source simply ends at the last line.
static func _find_enum_end(lines: PackedStringArray, start_line: int) -> int:
	var depth := 0
	for index in range(start_line, lines.size()):
		depth += _brace_delta(lines[index])
		if index > start_line and depth <= 0:
			return index
	return lines.size() - 1

static func _line_opens_enum(line: String) -> bool:
	return _starts_with_keyword(line, "enum") and line.contains("{")

# Counts structural braces outside strings/comments for enum-body traversal.
static func _brace_delta(line: String) -> int:
	var delta := 0
	var quote := ""
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if not quote.is_empty():
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
			continue
		if character == "\"" or character == "'":
			quote = character
			continue
		if character == "#":
			break
		if character == "{":
			delta += 1
		elif character == "}":
			delta -= 1
	return delta

# Removes the first source comment outside quoted strings while leaving the code
# before it intact for declaration matching.
static func _strip_comment(line: String) -> String:
	var comment_position := _find_comment_start(line)
	if comment_position < 0:
		return line
	return line.left(comment_position)

static func _find_comment_start(line: String) -> int:
	var quote := ""
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if not quote.is_empty():
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
			continue
		if character == "\"" or character == "'":
			quote = character
			continue
		if character == "#":
			return index
	return -1

# Annotation-only lines may separate a member documentation block from the
# declaration. Same-line annotations are handled by the declaration matcher.
static func _is_annotation_only_line(line: String) -> bool:
	var stripped := _strip_comment(line).strip_edges()
	return stripped.begins_with("@") and not _contains_member_keyword(stripped)

static func _contains_member_keyword(line: String) -> bool:
	for keyword_value in ["signal", "enum", "const", "var", "func", "class"]:
		var keyword := str(keyword_value)
		var search_position: int = line.find(keyword)
		while search_position >= 0:
			var before_ok: bool = (
				search_position == 0
				or line.substr(search_position - 1, 1) in [" ", "\t", ")"]
			)
			var after_position: int = search_position + keyword.length()
			var after_ok: bool = (
				after_position >= line.length()
				or line.substr(after_position, 1) in [" ", "\t"]
			)
			if before_ok and after_ok:
				return true
			search_position = line.find(keyword, search_position + 1)
	return false

static func _is_documentation_comment(line: String) -> bool:
	return line.strip_edges(true, false).begins_with(DOCUMENTATION_MARKER)

# A single-hash block is intentionally distinct from Godot's ## docs and region
# directives. It is an add-on-only convenience for implementation documentation.
static func _is_single_hash_comment(line: String) -> bool:
	var stripped := line.strip_edges(true, false)
	if not stripped.begins_with(SINGLE_HASH_MARKER):
		return false
	if stripped.begins_with(DOCUMENTATION_MARKER):
		return false
	var directive := stripped.substr(1).strip_edges().to_lower()
	return directive != "region" and directive != "endregion" and not directive.begins_with("region ")

static func _remove_comment_prefix(line: String, marker: String) -> String:
	var content := line.strip_edges(true, false)
	if not content.begins_with(marker):
		return line.trim_suffix("\r")
	content = content.substr(marker.length())
	if content.begins_with(" "):
		content = content.substr(1)
	return content.trim_suffix("\r")

static func _parse_special_tag(line: String, documentation: Dictionary) -> bool:
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

# Normalizes ordinary wrapped documentation exactly as the existing class-level
# extractor: source lines join with spaces, blank comment lines split paragraphs,
# and codeblock contents retain their source line structure.
static func _normalize_description(lines: PackedStringArray) -> String:
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

static func _flush_paragraph(
	output: PackedStringArray,
	paragraph: PackedStringArray
) -> void:
	if paragraph.is_empty():
		return
	output.append(" ".join(paragraph))
	paragraph.clear()

static func _empty_documentation() -> Dictionary:
	return {
		"description": "",
		"tutorials": [],
		"is_deprecated": false,
		"deprecated": "",
		"is_experimental": false,
		"experimental": "",
	}

static func _normalize_member_kind(keyword: String) -> String:
	match keyword:
		"func":
			return "function"
		"var":
			return "property"
		"const":
			return "constant"
		"signal":
			return "signal"
		"enum":
			return "enum"
		"class":
			return "inner_class"
	return "member"

static func _leading_whitespace_count(line: String) -> int:
	var count := 0
	while count < line.length() and line.substr(count, 1) in [" ", "\t"]:
		count += 1
	return count

static func _read_identifier(text: String) -> String:
	var result := ""
	for index in range(text.length()):
		var character := text.substr(index, 1)
		var valid := (
			character == "_"
			or (character >= "a" and character <= "z")
			or (character >= "A" and character <= "Z")
			or (not result.is_empty() and character >= "0" and character <= "9")
		)
		if not valid:
			break
		result += character
	return result

static func _is_identifier_character(character: String) -> bool:
	return (
		character == "_"
		or (character >= "a" and character <= "z")
		or (character >= "A" and character <= "Z")
		or (character >= "0" and character <= "9")
	)

static func _starts_with_keyword(line: String, keyword: String) -> bool:
	if not line.begins_with(keyword):
		return false
	if line.length() == keyword.length():
		return true
	var next_character := line.substr(keyword.length(), 1)
	return next_character in [" ", "\t", "{"]
