@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Mesh"
const PREVIEW_SIZE := 300.0
const PREVIEW_MARGIN := 8

func _handles(type: String) -> bool:
	return ClassDB.class_exists(type) and ClassDB.is_parent_class(type, "Mesh")

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var mesh := _load_mesh(path)
	if mesh == null:
		return base
	var aabb := mesh.get_aabb()
	var radius := aabb.size.length() * 0.5
	if not is_finite(radius) or radius <= 0.00001:
		Debug.log(MODULE, "empty or unsupported AABB: " + path)
		return base
	var preview := _create_preview(mesh, aabb, radius)
	if preview == null:
		return base
	base.add_child(HSeparator.new())
	base.add_child(preview)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_mesh(path: String) -> Mesh:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as Mesh

func _create_preview(mesh: Mesh, aabb: AABB, radius: float) -> Control:
	var scale := EditorInterface.get_editor_scale()
	var size := max(2, roundi(PREVIEW_SIZE * scale))
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
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
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.075, 0.085, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.52, 0.62)
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment_node.environment = environment
	root.add_child(environment_node)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = -aabb.get_center()
	instance.rotation_degrees = Vector3(-18.0, 32.0, 0.0)
	var neutral := StandardMaterial3D.new()
	neutral.albedo_color = Color(0.54, 0.63, 0.76)
	neutral.metallic = 0.10
	neutral.roughness = 0.48
	instance.material_override = neutral
	root.add_child(instance)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key.light_energy = 1.15
	key.light_specular = 0.35
	key.shadow_enabled = false
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25.0, 135.0, 0.0)
	fill.light_color = Color(0.65, 0.78, 1.0)
	fill.light_energy = 0.48
	fill.light_specular = 0.10
	fill.shadow_enabled = false
	root.add_child(fill)
	var fov: float = 32.0
	var half_fov: float = deg_to_rad(fov * 0.5)
	var distance: float = radius / maxf(0.05, tan(half_fov))
	distance += radius * 1.00
	distance = maxf(distance, 1.0)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, distance)
	camera.fov = fov
	camera.near = maxf(0.001, distance - radius * 3.0)
	camera.far = distance + radius * 4.0 + 10.0
	camera.current = true
	root.add_child(camera)
	return outer
	
