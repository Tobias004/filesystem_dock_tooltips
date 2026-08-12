@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Material"
const PREVIEW_SIZE := 300.0
const PREVIEW_MARGIN := 8

var _studio_sky: Sky

func _handles(type: String) -> bool:
	if type == "ShaderMaterial":
		return true
	if not ClassDB.class_exists(type):
		return false
	return ClassDB.is_parent_class(type, "BaseMaterial3D")

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var resource := _load_resource(path)
	if resource == null:
		return base
	if not _is_supported_material(resource):
		return base
	var preview := _create_preview(resource as Material)
	if preview == null:
		return base
	base.add_child(HSeparator.new())
	base.add_child(preview)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_resource(path: String) -> Resource:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var cached := ResourceLoader.get_cached_ref(path)
	if cached != null:
		return cached
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)


func _is_supported_material(resource: Resource) -> bool:
	if resource is BaseMaterial3D:
		return true
	if resource is ShaderMaterial:
		var shader_material := resource as ShaderMaterial
		if shader_material.shader == null:
			return false
		return shader_material.shader.get_mode() == Shader.MODE_SPATIAL
	return false


func _create_preview(material: Material) -> Control:
	var scale := EditorInterface.get_editor_scale()
	var size := maxi(2, roundi(PREVIEW_SIZE * scale))
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", margin)
	outer.add_theme_constant_override("margin_right", margin)
	outer.add_theme_constant_override("margin_top", margin)
	outer.add_theme_constant_override("margin_bottom", margin)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(size, size)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size, size)
	viewport.disable_3d = false
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.world_3d = World3D.new()
	container.add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var environment_node := WorldEnvironment.new()
	environment_node.environment = _create_environment()
	root.add_child(environment_node)
	_add_checker_backdrop(root)
	_add_lights(root)
	var mesh := SphereMesh.new()
	mesh.radius = 0.76
	mesh.height = 1.52
	mesh.radial_segments = 64
	mesh.rings = 32
	var sphere := MeshInstance3D.new()
	sphere.mesh = mesh
	sphere.position = Vector3(0.0, 0.08, 0.0)
	sphere.material_override = material
	root.add_child(sphere)
	_add_pedestal(root)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 3.75)
	camera.fov = 30.0
	camera.near = 0.05
	camera.far = 20.0
	camera.current = true
	root.add_child(camera)
	return outer

func _create_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.050, 0.065)
	environment.sky = _get_studio_sky()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	return environment

func _get_studio_sky() -> Sky:
	if _studio_sky != null:
		return _studio_sky
	var panorama_image: Image = _create_studio_panorama()
	if panorama_image == null or panorama_image.is_empty():
		var fallback_material := ProceduralSkyMaterial.new()
		fallback_material.sky_top_color = Color(0.16, 0.18, 0.23)
		fallback_material.sky_horizon_color = Color(0.34, 0.37, 0.43)
		fallback_material.ground_horizon_color = Color(0.22, 0.24, 0.29)
		fallback_material.ground_bottom_color = Color(0.07, 0.075, 0.09)
		_studio_sky = Sky.new()
		_studio_sky.sky_material = fallback_material
		_studio_sky.radiance_size = Sky.RADIANCE_SIZE_128
		return _studio_sky
	var panorama_texture: ImageTexture = ImageTexture.create_from_image(
		panorama_image
	)
	if panorama_texture == null:
		return null
	var panorama_material := PanoramaSkyMaterial.new()
	panorama_material.panorama = panorama_texture
	panorama_material.energy_multiplier = 1.0
	panorama_material.filter = true
	_studio_sky = Sky.new()
	_studio_sky.sky_material = panorama_material
	_studio_sky.radiance_size = Sky.RADIANCE_SIZE_128
	return _studio_sky

func _create_studio_panorama() -> Image:
	# Low-resolution floating-point panorama is sufficient for the radiance
	# map, cheap to generate once, and allows values above 1.0 for softboxes.
	const WIDTH := 256
	const HEIGHT := 128
	var image := Image.create(
		WIDTH,
		HEIGHT,
		false,
		Image.FORMAT_RGBAF
	)
	if image == null:
		return null
	for y in range(HEIGHT):
		var v: float = float(y) / float(HEIGHT - 1)
		for x in range(WIDTH):
			var u: float = float(x) / float(WIDTH - 1)
			var base_value: float = lerpf(0.055, 0.11, 1.0 - v)
			var color := Color(
				base_value * 0.92,
				base_value * 0.98,
				base_value * 1.08,
				1.0
			)
			# Broad warm key softbox.
			var key_du: float = _wrapped_distance(u, 0.19)
			var key_dv: float = v - 0.42
			var key_strength: float = exp(
				-(
					(key_du * key_du) / 0.0055
					+ (key_dv * key_dv) / 0.055
				)
			)
			color += Color(4.2, 3.8, 3.25, 0.0) * key_strength
			# Cooler, wider fill card.
			var fill_du: float = _wrapped_distance(u, 0.72)
			var fill_dv: float = v - 0.47
			var fill_strength: float = exp(
				-(
					(fill_du * fill_du) / 0.010
					+ (fill_dv * fill_dv) / 0.085
				)
			)
			color += Color(2.1, 2.55, 3.4, 0.0) * fill_strength
			# Narrow top strip to describe the sphere silhouette.
			var top_du: float = _wrapped_distance(u, 0.48)
			var top_dv: float = v - 0.14
			var top_strength: float = exp(
				-(
					(top_du * top_du) / 0.030
					+ (top_dv * top_dv) / 0.0045
				)
			)
			color += Color(1.65, 1.70, 1.85, 0.0) * top_strength
			image.set_pixel(x, y, color)
	return image

func _wrapped_distance(a: float, b: float) -> float:
	var distance: float = absf(a - b)
	return minf(distance, 1.0 - distance)

func _add_lights(root: Node3D) -> void:
	# The studio panorama provides most of the specular definition. These
	# low-specular directional lights mainly keep rough/diffuse materials
	# readable and avoid the large white circles from the early prototypes.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	key.light_color = Color(1.0, 0.95, 0.88)
	key.light_energy = 0.52
	key.light_specular = 0.12
	key.shadow_enabled = false
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(22.0, 145.0, 0.0)
	fill.light_color = Color(0.72, 0.84, 1.0)
	fill.light_energy = 0.22
	fill.light_specular = 0.04
	fill.shadow_enabled = false
	root.add_child(fill)

func _add_pedestal(root: Node3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.54
	mesh.bottom_radius = 0.66
	mesh.height = 0.15
	mesh.radial_segments = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.12, 0.15)
	material.metallic = 0.12
	material.roughness = 0.78
	var pedestal := MeshInstance3D.new()
	pedestal.mesh = mesh
	pedestal.position = Vector3(0.0, -0.72, 0.0)
	pedestal.material_override = material
	root.add_child(pedestal)

func _add_checker_backdrop(root: Node3D) -> void:
	var tile_mesh := QuadMesh.new()
	tile_mesh.size = Vector2(0.78, 0.78)
	var dark := _unshaded(Color(0.075, 0.085, 0.11))
	var light := _unshaded(Color(0.21, 0.23, 0.28))
	for y in range(4):
		for x in range(4):
			var tile := MeshInstance3D.new()
			tile.mesh = tile_mesh
			tile.position = Vector3(
				-1.17 + float(x) * 0.78,
				1.17 - float(y) * 0.78,
				-1.12
			)
			tile.material_override = dark if (x + y) % 2 == 0 else light
			root.add_child(tile)

func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
