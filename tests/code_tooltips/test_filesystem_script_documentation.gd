extends SceneTree

## Focused regression: FileSystem .gd documentation uses the shared parser,
## including unnamed scripts, while every script retains a source preview.
## Run: godot --headless --editor --path . --script res://tests/code_tooltips/test_filesystem_script_documentation.gd

const ScriptPreview := preload("res://addons/better_tooltips/modules/script_documentation_tooltip.gd")
const Parser := preload("res://addons/better_tooltips/core/gdscript_documentation_parser.gd")

const NAMED_BEFORE := "res://tests/tooltip_test_resource.gd"
const NAMED_AFTER := "res://tests/tooltip_test_component.gd"
const UNNAMED_BEFORE := "res://tests/components/osc_repo_main.gd"
const UNNAMED_AFTER := "res://tests/text_previews/test_text_previews.gd"
const UNDOCUMENTED := "res://tests/components/osc_repo_no_docs.gd"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, problem: String) -> void:
	if not condition:
		failures.append(problem)

func _run() -> void:
	var preview := ScriptPreview.new()
	var cases := [
		{
			"path": NAMED_BEFORE,
			"title": "TooltipTestResource",
			"description": "Alternative documentation placement",
		},
		{
			"path": NAMED_AFTER,
			"title": "TooltipTestComponent",
			"description": "Demonstrates Godot documentation formatting",
		},
		{
			"path": UNNAMED_BEFORE,
			"title": "osc_repo_main.gd",
			"description": "Scene-tree composition root",
			"notes": "No COMPONENT_CONTRACT",
		},
		{
			"path": UNNAMED_AFTER,
			"title": "test_text_previews.gd",
			"description": "Regression checks for Markdown",
		},
	]
	for case: Dictionary in cases:
		var path: String = str(case.path)
		var parsed: Dictionary = preview._read_script_documentation(path)
		_expect(str(parsed.get("class_name", "")) == str(case.title), "Wrong title: " + path)
		_expect(str(parsed.get("description", "")).contains(str(case.description)), "Description missing: " + path)
		if case.has("notes"):
			_expect(str(parsed.get("implementation_notes", "")).contains(str(case.notes)), "Implementation notes missing: " + path)
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "Cannot read fixture " + path)
		if file != null:
			var shared_document := Parser.find_script_documentation(file.get_as_text())
			_expect(str(shared_document.get("description", "")) == str(parsed.get("description", "")), "FileSystem parser diverged from shared parser: " + path)
		var base := VBoxContainer.new()
		EditorInterface.get_base_control().add_child(base)
		preview._make_tooltip_for_path(path, {}, base)
		var documentation := base.find_child("ScriptDocumentation", true, false) as RichTextLabel
		var source := base.find_child("TextPreview", true, false) as RichTextLabel
		_expect(documentation != null, "Rendered documentation missing: " + path)
		_expect(source != null, "Source preview missing: " + path)
		if documentation != null:
			_expect(documentation.get_parsed_text().contains(str(case.description)), "Rendered description missing: " + path)
			if case.has("notes"):
				_expect(documentation.get_parsed_text().contains(str(case.notes)), "Rendered architecture notes missing: " + path)
		var title_found := false
		for label_node in base.find_children("*", "Label", true, false):
			if (label_node as Label).text == str(case.title):
				title_found = true
		_expect(title_found, "Visible class/script title missing: " + path)
		await process_frame
		base.free()
	var empty_doc := preview._read_script_documentation(UNDOCUMENTED)
	_expect(empty_doc.is_empty(), "Undocumented script must not invent documentation")
	var undecorated := VBoxContainer.new()
	EditorInterface.get_base_control().add_child(undecorated)
	preview._make_tooltip_for_path(UNDOCUMENTED, {}, undecorated)
	_expect(undecorated.find_child("TextPreview", true, false) != null, "Undocumented script lost source preview")
	_expect(undecorated.find_child("ScriptDocumentation", true, false) == null, "Undocumented script gained class section")
	undecorated.free()
	preview.cleanup()
	if failures.is_empty():
		print("FileSystem script documentation shared parser, named/unnamed scripts: PASS")
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
