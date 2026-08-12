@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Sky"
const WIDTH := 360.0
const HEIGHT := 220.0
const PREVIEW_MARGIN := 8

func _handles(type: String) -> bool:
	return type == "Sky"

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var sky := _load_sky(path)
	if sky == null or sky.sky_material == null:
		return base
	var preview := _create_preview(sky)
	if preview == null:
		return base
	base.add_child(HSeparator.new())
	base.add_child(preview)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_sky(path: String) -> Sky:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as Sky

func _create_preview(sky: Sky) -> Control:
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
	viewport.world_3d = World3D.new()
	container.add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	root.add_child(env_node)
	var camera := Camera3D.new()
	camera.position = Vector3.ZERO
	camera.fov = 72.0
	camera.current = true
	root.add_child(camera)
	return outer
