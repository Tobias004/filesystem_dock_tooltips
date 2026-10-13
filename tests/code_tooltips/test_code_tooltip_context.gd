extends SceneTree

const TooltipModule: GDScript = preload("res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd")

var failures: Array[String] = []

func _init() -> void:
	_test_direct_resource_literal()
	_test_input_action_literal()
	_test_project_setting_literal()
	_test_node_path_tokens()
	if failures.is_empty():
		print("Code tooltip context tests: PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		print("Code tooltip context tests: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _resolve_line(source: String, needle: String) -> Dictionary:
	var editor: CodeEdit = CodeEdit.new()
	editor.text = source
	var column: int = source.find(needle) + maxi(1, needle.length() / 2)
	var module: BTCodeEditorDocumentationTooltip = TooltipModule.new() as BTCodeEditorDocumentationTooltip
	var result: Dictionary = module._resolve_special_hover(
		editor,
		{"symbol": "", "line": 0, "column": column}
	)
	editor.free()
	return result

func _test_direct_resource_literal() -> void:
	var path: String = "res://tests/themes/blue_theme.tres"
	var result: Dictionary = _resolve_line('var theme := preload("%s")' % path, path)
	_expect(str(result.get("resource_path", "")) == path, "Direct preload path hover was not detected.")

func _test_input_action_literal() -> void:
	var result: Dictionary = _resolve_line('Input.is_action_just_pressed("ui_accept")', "ui_accept")
	_expect(str(result.get("title", "")) == "Input action", "Input action hover was not detected.")
	_expect(str(result.get("plain_text", "")).contains("ui_accept"), "Input action details omit the action name.")

func _test_project_setting_literal() -> void:
	var result: Dictionary = _resolve_line(
		'ProjectSettings.get_setting("application/config/name")',
		"application/config/name"
	)
	_expect(str(result.get("title", "")) == "Project setting", "ProjectSettings hover was not detected.")
	_expect(str(result.get("plain_text", "")).contains("String"), "ProjectSettings hover omits the Variant type.")

func _test_node_path_tokens() -> void:
	var dollar: Dictionary = TooltipModule._find_node_path_token_at_column(
		"var camera := $PreviewTarget/Camera2D",
		29
	)
	_expect(str(dollar.get("value", "")) == "$PreviewTarget/Camera2D", "$ NodePath token was not detected.")
	var unique: Dictionary = TooltipModule._find_node_path_token_at_column(
		"var target := %PreviewTarget",
		20
	)
	_expect(str(unique.get("value", "")) == "%PreviewTarget", "%UniqueName token was not detected.")
