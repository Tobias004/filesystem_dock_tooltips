@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Shader"
const PREVIEW_MARGIN := 8

func _handles(type: String) -> bool:
	return type == "Shader"

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var source_mode := _read_shader_mode(path)
	if source_mode == "":
		return base
	# Avoid loading unsupported shader modes. This also avoids triggering
	# shader compilation for particles/fog/texture-blit previews.
	if source_mode != "spatial" and source_mode != "canvas_item":
		Debug.log(MODULE, "unsupported shader type: " + source_mode)
		return base
	var shader := _load_shader(path)
	if shader == null:
		return base
	var preview: Control = null
	if shader.get_mode() == Shader.MODE_SPATIAL:
		preview = _create_spatial_preview(shader)
	elif shader.get_mode() == Shader.MODE_CANVAS_ITEM:
		preview = _create_canvas_preview(shader)
	if preview == null:
		return base
	base.add_child(HSeparator.new())
	base.add_child(preview)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _read_shader_mode(path: String) -> String:
	if not path.ends_with(".gdshader"):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var source := file.get_as_text()
	var regex := RegEx.new()
	if regex.compile("shader_type\\s+([A-Za-z0-9_]+)\\s*;") != OK:
		return ""
	var result := regex.search(source)
	if result == null:
		return ""
	return result.get_string(1)

func _load_shader(path: String) -> Shader:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as Shader

func _create_spatial_preview(shader: Shader) -> Control:
	var material := ShaderMaterial.new()
	material.shader = shader
	var scale := EditorInterface.get_editor_scale()
	var size := maxi(2, roundi(300.0 * scale))
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := _margin(margin)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(size, size)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size, size)
	viewport.disable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.world_3d = World3D.new()
	container.add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.08, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.46, 0.55)
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment_node.environment = environment
	root.add_child(environment_node)
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.76
	sphere_mesh.height = 1.52
	sphere_mesh.radial_segments = 64
	sphere_mesh.rings = 32
	var sphere := MeshInstance3D.new()
	sphere.mesh = sphere_mesh
	sphere.material_override = material
	root.add_child(sphere)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	key.light_energy = 0.70
	key.light_specular = 0.16
	key.shadow_enabled = false
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20.0, 140.0, 0.0)
	fill.light_color = Color(0.68, 0.80, 1.0)
	fill.light_energy = 0.30
	fill.light_specular = 0.04
	fill.shadow_enabled = false
	root.add_child(fill)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 3.75)
	camera.fov = 30.0
	camera.current = true
	root.add_child(camera)
	return outer

func _create_canvas_preview(shader: Shader) -> Control:
	var scale := EditorInterface.get_editor_scale()
	var width := maxi(2, roundi(360.0 * scale))
	var height := maxi(2, roundi(230.0 * scale))
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := _margin(margin)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(width, height)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var root := Control.new()
	root.size = Vector2(width, height)
	viewport.add_child(root)
	var cell := float(min(width, height)) / 6.0
	for y in range(6):
		for x in range(10):
			var rect := ColorRect.new()
			rect.position = Vector2(x * cell, y * cell)
			rect.size = Vector2(cell + 1.0, cell + 1.0)
			rect.color = (
				Color(0.10, 0.11, 0.14)
				if (x + y) % 2 == 0
				else Color(0.28, 0.30, 0.36)
			)
			root.add_child(rect)
	var source_texture := _create_source_texture(256, 160)
	if source_texture == null:
		return null
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	var image := TextureRect.new()
	image.position = Vector2(width * 0.10, height * 0.12)
	image.size = Vector2(width * 0.80, height * 0.76)
	image.texture = source_texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.material = shader_material
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(image)
	return outer

func _create_source_texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	if image == null:
		return null
	for y in range(height):
		for x in range(width):
			var u: float = float(x) / maxf(1.0, float(width - 1))
			var v: float = float(y) / maxf(1.0, float(height - 1))
			var checker_index: int = int(x / 32) + int(y / 32)
			var checker: float = 0.12 if checker_index % 2 == 0 else 0.28
			var color: Color = Color(
				clamp(checker + u * 0.55, 0.0, 1.0),
				clamp(checker + (1.0 - v) * 0.40, 0.0, 1.0),
				clamp(0.32 + v * 0.55, 0.0, 1.0),
				1.0
			)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _margin(value: int) -> MarginContainer:
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, value)
	return outer
