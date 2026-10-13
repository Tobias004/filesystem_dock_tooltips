class_name CodeTooltipShowcase
extends Node

## Manual showcase for Code Editor tooltip features.
##
## Open this script together with [code]code_tooltip_showcase.tscn[/code] in the
## editor and hover the marked expressions. The file deliberately demonstrates
## ordinary project documentation and every source-aware tooltip added through
## the Code Editor integration.
##
## [b]Resource preview expectation:[/b] resource hovers reuse the same modules,
## RAM/persistent cache and Shift-forced regeneration as FileSystem previews.
##
## [b]Special string/path expectation:[/b] InputMap, ProjectSettings and NodePath
## strings receive concise editor-context information rather than being treated
## as ordinary identifiers.

const TargetScript: GDScript = preload("res://tests/code_tooltips/code_tooltip_target.gd")

## Direct Material resource. Hover MATERIAL or the res:// string itself.
const MATERIAL: Material = preload("res://tests/materials/blue_metal_material_3d.tres")

## Direct Theme resource. Hover UI_THEME or its literal path.
const UI_THEME: Theme = preload("res://tests/themes/blue_theme.tres")

## Direct Mesh resource.
const TEST_MESH: Mesh = preload("res://tests/meshes/torus_mesh.tres")

## Direct Font resource.
const TEST_FONT: Font = preload("res://tests/fonts/system_font.tres")

## Direct StyleBox resource.
const TEST_STYLEBOX: StyleBox = preload("res://tests/styleboxes/rounded_panel.tres")

## Direct Gradient resource.
const TEST_GRADIENT: Gradient = preload("res://tests/gradients/transparent_gradient.tres")

## Direct Environment resource.
const TEST_ENVIRONMENT: Environment = preload("res://tests/environments/blue_environment.tres")

## Direct Sky resource.
const TEST_SKY: Sky = preload("res://tests/skies/sunset_sky.tres")

## Direct SpriteFrames resource.
const TEST_FRAMES: SpriteFrames = preload("res://tests/sprite_frames/test_sprite_frames.tres")

## Direct Shader resource.
const TEST_SHADER: Shader = preload("res://tests/shaders/grid_spatial.gdshader")

## Direct Markdown project-file path. Hover TEST_MARKDOWN or the res:// string itself.
## This is intentionally a String because Markdown files are not loadable Resources.
const TEST_MARKDOWN: String = "res://tests/text_previews/showcase.md"

## Direct generic text-file path. Hover TEST_TEXT_FILE or its literal path.
const TEST_TEXT_FILE: String = "res://tests/text_previews/showcase.txt"

## Text-file alias, demonstrating the same short source-only alias following.
const TEST_TEXT_ALIAS: String = TEST_TEXT_FILE

## First alias step: hover MATERIAL_ALIAS to verify source-only alias following.
const MATERIAL_ALIAS: Material = MATERIAL

## Second alias step: the resolver intentionally follows a short, bare-identifier chain.
const MATERIAL_ALIAS_2: Material = MATERIAL_ALIAS

## Exported typed Resource with a literal initializer.
@export var response_curve: Curve = preload("res://tests/curves/ease_curve.tres")

## Ordinary project documentation still appears beside the new special hovers.
@export var showcase_enabled: bool = true


## Demonstrates all contextual Code Tooltip triggers in executable GDScript.
func demonstrate_tooltips() -> void:
	# 1) Resource variables and local aliases.
	var local_curve: Curve2D = load("res://tests/curves/path_2d_curve.tres") as Curve2D
	var local_curve_alias: Curve2D = local_curve
	var material_copy: Material = MATERIAL_ALIAS_2
	if local_curve_alias == null or material_copy == null:
		return

	# 1) Direct resource-path hover: hover inside the quoted res:// path.
	var direct_path_hover: Material = preload("res://tests/materials/green_glass_material_3d.tres")
	if direct_path_hover == null:
		return

	# 2) InputMap action hover. Hover ui_accept / ui_cancel / ui_left / ui_right.
	if Input.is_action_just_pressed("ui_accept"):
		print("accept")
	if InputMap.has_action("ui_cancel"):
		var events: Array[InputEvent] = InputMap.action_get_events("ui_cancel")
		if not events.is_empty():
			print(events[0])
	var horizontal: float = Input.get_axis("ui_left", "ui_right")
	if horizontal > 2.0:
		print(horizontal)

	# 3) NodePath hover. The showcase scene attaches this script once to its root,
	# so relative $ and get_node() paths have an unambiguous resolution base.
	# Hover both the path expression and the variable name. Variable hovers follow
	# the initializer back to the same scene node; short aliases are followed too.
	var target: Node = $PreviewTarget
	var target_alias: Node = target
	var target_alias_2: Node = target_alias
	var camera: Camera2D = $PreviewTarget/Camera2D
	var unique_target: Node = %PreviewTarget
	var literal_target: Node = get_node("PreviewTarget")
	var literal_camera: Node = get_node_or_null("PreviewTarget/Camera2D")
	var literal_path: NodePath = NodePath("PreviewTarget")
	if target == null or target_alias_2 == null or camera == null or unique_target == null:
		return
	if literal_target == null or literal_camera == null or literal_path.is_empty():
		return

	# 4) ProjectSettings key hover: current value and Variant type are displayed.
	var project_name: String = str(ProjectSettings.get_setting("application/config/name", ""))
	var has_name: bool = ProjectSettings.has_setting("application/config/name")
	if has_name and str(project_name).is_empty():
		print("Unnamed test project")

	# 5) Cross-script documentation remains available for project class members.
	var fixture: CodeTooltipTarget = TargetScript.new() as CodeTooltipTarget
	fixture.documented_value += fixture.documented_method()


# Single-# implementation documentation remains testable independently from ## docs.
func implementation_note_example() -> void:
	pass
