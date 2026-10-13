extends SceneTree

const Parser: GDScript = preload("res://addons/better_tooltips/core/gdscript_documentation_parser.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_direct_resource()
	_test_multiline_resource()
	_test_alias_chain()
	_test_local_alias()
	_test_node_reference_direct()
	_test_node_reference_calls()
	_test_node_reference_alias_chain()
	_test_documentation()
	if failures.is_empty():
		print("Code tooltip parser tests: PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		print("Code tooltip parser tests: FAIL (%d)" % failures.size())
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_direct_resource() -> void:
	var source: String = 'const MAT := preload("res://tests/materials/blue_metal_material_3d.tres")\n'
	var result: Dictionary = Parser.find_resource_reference(source, "MAT", 0)
	_expect(
		str(result.get("path", "")) == "res://tests/materials/blue_metal_material_3d.tres",
		"Direct preload resource was not resolved."
	)


func _test_multiline_resource() -> void:
	var source: String = '''@export var curve: Curve = preload(
	"res://tests/curves/ease_curve.tres"
)
'''
	var result: Dictionary = Parser.find_resource_reference(source, "curve", 2)
	_expect(
		str(result.get("path", "")) == "res://tests/curves/ease_curve.tres",
		"Multiline preload resource was not resolved."
	)


func _test_alias_chain() -> void:
	var source: String = '''const ORIGINAL := preload("res://tests/themes/blue_theme.tres")
const ALIAS := ORIGINAL
const ALIAS_2 := ALIAS
'''
	var result: Dictionary = Parser.find_resource_reference(source, "ALIAS_2", 2)
	_expect(
		str(result.get("path", "")) == "res://tests/themes/blue_theme.tres",
		"Two-step Resource alias was not resolved."
	)
	_expect(int(result.get("alias_depth", 0)) >= 1, "Alias metadata was not recorded.")


func _test_local_alias() -> void:
	var source: String = '''func demo() -> void:
	var original := load("res://tests/curves/path_2d_curve.tres")
	var alias := original
	print(alias)
'''
	var result: Dictionary = Parser.find_resource_reference(source, "alias", 3)
	_expect(
		str(result.get("path", "")) == "res://tests/curves/path_2d_curve.tres",
		"Local Resource alias was not resolved inside its function."
	)


func _test_node_reference_direct() -> void:
	var source: String = '''func demo() -> void:
	var target: Node = $PreviewTarget
	var camera: Camera2D = $PreviewTarget/Camera2D
	var unique_target: Node = %PreviewTarget
	print(target, camera, unique_target)
'''
	var target: Dictionary = Parser.find_node_reference(source, "target", 4)
	var camera: Dictionary = Parser.find_node_reference(source, "camera", 4)
	var unique_target: Dictionary = Parser.find_node_reference(source, "unique_target", 4)
	_expect(str(target.get("path", "")) == "$PreviewTarget", "Node variable $ initializer was not resolved.")
	_expect(
		str(camera.get("path", "")) == "$PreviewTarget/Camera2D",
		"Nested $ Node variable initializer was not resolved."
	)
	_expect(
		str(unique_target.get("path", "")) == "%PreviewTarget",
		"%UniqueName variable initializer was not resolved."
	)


func _test_node_reference_calls() -> void:
	var source: String = '''func demo() -> void:
	var target: Node = get_node("PreviewTarget")
	var camera: Node = get_node_or_null(
		"PreviewTarget/Camera2D"
	)
	var path: NodePath = NodePath("PreviewTarget")
	print(target, camera, path)
'''
	var target: Dictionary = Parser.find_node_reference(source, "target", 6)
	var camera: Dictionary = Parser.find_node_reference(source, "camera", 6)
	var path: Dictionary = Parser.find_node_reference(source, "path", 6)
	_expect(str(target.get("path", "")) == "PreviewTarget", "get_node() variable initializer was not resolved.")
	_expect(
		str(camera.get("path", "")) == "PreviewTarget/Camera2D",
		"Multiline get_node_or_null() initializer was not resolved."
	)
	_expect(str(path.get("path", "")) == "PreviewTarget", "NodePath() variable initializer was not resolved.")


func _test_node_reference_alias_chain() -> void:
	var source: String = '''func demo() -> void:
	var original: Node = $PreviewTarget
	var alias: Node = original
	var alias_2: Node = alias
	print(alias_2)
'''
	var result: Dictionary = Parser.find_node_reference(source, "alias_2", 4)
	_expect(str(result.get("path", "")) == "$PreviewTarget", "Node alias chain was not resolved.")
	_expect(int(result.get("alias_depth", 0)) >= 1, "Node alias metadata was not recorded.")


func _test_documentation() -> void:
	var source: String = '''class_name ParserDocumentationFixture
extends RefCounted

## Documents an example member.
##
## [b]Formatting[/b] and [code]inline code[/code] should survive parsing.
var documented_value := 1
'''
	var result: Dictionary = Parser.find_member_documentation(source, "documented_value", 6, true, true)
	_expect(not result.is_empty(), "Documented member was not found.")
	_expect(
		str(result.get("description", "")).contains("Formatting"),
		"Documentation content was not parsed."
	)
