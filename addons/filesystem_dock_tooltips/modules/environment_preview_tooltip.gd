@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Environment"
const WIDTH := 360.0
const HEIGHT := 235.0
const PREVIEW_MARGIN := 8

func _handles(type: String) -> bool:
	return type == "Environment"

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var environment := _load_environment(path)
	if environment == null:
		return base
	var preview := _create_preview(environment)
	if preview == null:
		return base
	base.add_child(HSeparator.new())
	base.add_child(preview)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_environment(path: String) -> Environment:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as Environment

func _create_preview(environment: Environment) -> Control:
	var scale := EditorInterface.get_editor_scale()
	var width := maxi(2, roundi(WIDTH * scale))
	var height := maxi(2, roundi(HEIGHT * scale))
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(width, height)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.disable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.world_3d = World3D.new()
	container.add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	root.add_child(env_node)
	_add_reference_objects(root)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.25, 4.25)
	camera.fov = 38.0
	camera.current = true
	root.add_child(camera)
	return outer

func _add_reference_objects(root: Node3D) -> void:
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.62
	sphere_mesh.height = 1.24
	sphere_mesh.radial_segments = 48
	sphere_mesh.rings = 24
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.62, 0.65, 0.70)
	chrome.metallic = 1.0
	chrome.roughness = 0.08
	var rough := StandardMaterial3D.new()
	rough.albedo_color = Color(0.62, 0.20, 0.08)
	rough.metallic = 0.0
	rough.roughness = 0.78
	var left := MeshInstance3D.new()
	left.mesh = sphere_mesh
	left.position = Vector3(-0.78, 0.15, 0.0)
	left.material_override = chrome
	root.add_child(left)
	var right := MeshInstance3D.new()
	right.mesh = sphere_mesh
	right.position = Vector3(0.78, 0.15, 0.0)
	right.material_override = rough
	root.add_child(right)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(5.5, 5.5)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.18, 0.19, 0.21)
	floor_material.roughness = 0.72
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.55, 0.0)
	floor.material_override = floor_material
	root.add_child(floor)
	# A small reference light is necessary for environments that only define a
	# background but no usable ambient source.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	light.light_energy = 0.55
	light.light_specular = 0.25
	light.shadow_enabled = false
	root.add_child(light)
