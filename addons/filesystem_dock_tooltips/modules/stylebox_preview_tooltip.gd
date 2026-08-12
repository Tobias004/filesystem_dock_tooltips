@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "StyleBox"
const PREVIEW_WIDTH := 360.0
const PREVIEW_HEIGHT := 150.0
const PREVIEW_MARGIN := 10

func _handles(type: String) -> bool:
	return ClassDB.class_exists(type) and ClassDB.is_parent_class(type, "StyleBox")

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var style := _load_stylebox(path)
	if style == null:
		return base
	var scale := EditorInterface.get_editor_scale()
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(
		PREVIEW_WIDTH * scale,
		PREVIEW_HEIGHT * scale
	)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(panel)
	var label := Label.new()
	label.text = "StyleBox preview"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	base.add_child(HSeparator.new())
	base.add_child(outer)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_stylebox(path: String) -> StyleBox:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as StyleBox
