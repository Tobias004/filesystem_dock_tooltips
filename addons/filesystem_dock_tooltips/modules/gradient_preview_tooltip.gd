@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Gradient"
const WIDTH := 420.0
const HEIGHT := 92.0
const PREVIEW_MARGIN := 8

func _handles(type: String) -> bool:
	return type == "Gradient"

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var gradient := _load_gradient(path)
	if gradient == null or gradient.get_point_count() <= 0:
		return base
	var scale := EditorInterface.get_editor_scale()
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
	var stack := VBoxContainer.new()
	outer.add_child(stack)
	# The actual gradient is rendered in an isolated SubViewport. A dark/light
	# background makes transparency visible without modifying the resource.
	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(
		WIDTH * scale,
		HEIGHT * scale
	)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(viewport_container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(
		max(2, roundi(WIDTH * scale)),
		max(2, roundi(HEIGHT * scale))
	)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	var root := Control.new()
	root.size = Vector2(viewport.size)
	viewport.add_child(root)
	var cell := float(viewport.size.y) / 3.0
	for y in range(3):
		for x in range(14):
			var rect := ColorRect.new()
			rect.position = Vector2(x * cell, y * cell)
			rect.size = Vector2(cell + 1.0, cell + 1.0)
			rect.color = (
				Color(0.12, 0.13, 0.16)
				if (x + y) % 2 == 0
				else Color(0.34, 0.36, 0.42)
			)
			root.add_child(rect)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = max(64, viewport.size.x)
	var rect := TextureRect.new()
	rect.size = Vector2(viewport.size)
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	var points := Label.new()
	points.text = "%d color points" % gradient.get_point_count()
	points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(points)
	base.add_child(HSeparator.new())
	base.add_child(outer)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_gradient(path: String) -> Gradient:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as Gradient
