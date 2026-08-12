@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Curve"
const WIDTH := 420
const HEIGHT := 210
const PREVIEW_MARGIN := 8

func _handles(type: String) -> bool:
	return type == "Curve" or type == "Curve2D" or type == "Curve3D"

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var resource := _load_resource(path)
	if resource == null:
		return base
	var image: Image = null
	if resource is Curve:
		image = _render_curve(resource as Curve)
	elif resource is Curve2D:
		image = _render_curve_2d(resource as Curve2D)
	elif resource is Curve3D:
		image = _render_curve_3d(resource as Curve3D)
	if image == null or image.is_empty():
		return base
	var texture := ImageTexture.create_from_image(image)
	if texture == null:
		return base
	var scale := EditorInterface.get_editor_scale()
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(WIDTH * scale, HEIGHT * scale)
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(rect)
	base.add_child(HSeparator.new())
	base.add_child(outer)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_resource(path: String) -> Resource:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource

func _new_image() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.065, 0.075, 0.095, 1.0))
	for x in [WIDTH / 4, WIDTH / 2, WIDTH * 3 / 4]:
		var grid_x := int(x)
		_draw_line(image, Vector2i(grid_x, 0), Vector2i(grid_x, HEIGHT - 1), Color(0.18, 0.20, 0.25), 1)
	for y in [HEIGHT / 4, HEIGHT / 2, HEIGHT * 3 / 4]:
		var grid_y := int(y)
		_draw_line(image, Vector2i(0, grid_y), Vector2i(WIDTH - 1, grid_y), Color(0.18, 0.20, 0.25), 1)
	return image

func _render_curve(curve: Curve) -> Image:
	if curve.point_count <= 0:
		return null
	var image := _new_image()
	var min_x: float = curve.min_domain
	var max_x: float = curve.max_domain
	var min_y: float = curve.min_value
	var max_y: float = curve.max_value
	if is_equal_approx(min_x, max_x) or is_equal_approx(min_y, max_y):
		return null
	var previous := Vector2i()
	var has_previous := false
	for pixel_x in range(WIDTH):
		var t: float = float(pixel_x) / float(WIDTH - 1)
		var x: float = lerpf(min_x, max_x, t)
		var y: float = curve.sample(x)
		var normalized_y: float = inverse_lerp(min_y, max_y, y)
		var pixel_y: int = roundi((1.0 - normalized_y) * float(HEIGHT - 1))
		pixel_y = clampi(pixel_y, 0, HEIGHT - 1)
		var point := Vector2i(pixel_x, pixel_y)
		if has_previous:
			_draw_line(
				image,
				previous,
				point,
				Color(0.20, 0.82, 1.0),
				2
			)
		previous = point
		has_previous = true
	return image

func _render_curve_2d(curve: Curve2D) -> Image:
	if curve.point_count <= 0:
		return null
	var baked := curve.get_baked_points()
	if baked.size() < 2:
		return null
	var points := PackedVector2Array()
	for point in baked:
		points.append(point)
	return _render_points(points)

func _render_curve_3d(curve: Curve3D) -> Image:
	if curve.point_count <= 0:
		return null
	var baked := curve.get_baked_points()
	if baked.size() < 2:
		return null
	var projected := PackedVector2Array()
	for point in baked:
		# Fixed isometric projection. No user camera is required.
		projected.append(
			Vector2(
				point.x - point.z * 0.55,
				-point.y + point.z * 0.28
			)
		)
	return _render_points(projected)

func _render_points(points: PackedVector2Array) -> Image:
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point_value in points:
		var point: Vector2 = point_value
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	var extent: Vector2 = max_point - min_point
	if extent.length_squared() <= 0.000001:
		return null
	var padding: float = 18.0
	var usable: Vector2 = Vector2(WIDTH, HEIGHT) - Vector2.ONE * padding * 2.0
	var scale_factor: float = minf(
		usable.x / maxf(0.001, extent.x),
		usable.y / maxf(0.001, extent.y)
	)
	var image := _new_image()
	var previous := Vector2i()
	var has_previous := false
	for point_value in points:
		var point: Vector2 = point_value
		var local: Vector2 = (point - min_point) * scale_factor
		var px: int = roundi(padding + local.x)
		var py: int = roundi(padding + local.y)
		var current: Vector2i = Vector2i(px, py)
		if has_previous:
			_draw_line(
				image,
				previous,
				current,
				Color(0.20, 0.82, 1.0),
				2
			)
		previous = current
		has_previous = true
	return image

func _draw_line(
	image: Image,
	from: Vector2i,
	to: Vector2i,
	color: Color,
	thickness: int
) -> void:
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y
	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		for oy in range(-thickness + 1, thickness):
			for ox in range(-thickness + 1, thickness):
				var px: int = x0 + ox
				var py: int = y0 + oy
				if px >= 0 and px < image.get_width() and py >= 0 and py < image.get_height():
					image.set_pixel(px, py, color)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
