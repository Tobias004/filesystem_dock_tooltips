@tool
extends EditorPlugin

const Settings := preload("res://addons/filesystem_dock_tooltips/tooltip_settings.gd")
const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")

var _tooltip_plugins: Array[EditorResourceTooltipPlugin] = []


func _enter_tree() -> void:
	_register_module(
		Settings.ENABLE_SCRIPT_DOCUMENTATION,
		"res://addons/filesystem_dock_tooltips/filesystem_dock_tooltips.gd",
		"Script Documentation"
	)
	_register_module(
		Settings.ENABLE_MATERIAL_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/material_preview_tooltip.gd",
		"Material"
	)
	_register_module(
		Settings.ENABLE_MESH_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/mesh_preview_tooltip.gd",
		"Mesh"
	)
	_register_module(
		Settings.ENABLE_FONT_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/font_preview_tooltip.gd",
		"Font"
	)
	_register_module(
		Settings.ENABLE_SHADER_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/shader_preview_tooltip.gd",
		"Shader"
	)
	_register_module(
		Settings.ENABLE_SPRITE_FRAMES_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/sprite_frames_preview_tooltip.gd",
		"SpriteFrames"
	)
	_register_module(
		Settings.ENABLE_THEME_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/theme_preview_tooltip.gd",
		"Theme"
	)
	_register_module(
		Settings.ENABLE_STYLEBOX_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/stylebox_preview_tooltip.gd",
		"StyleBox"
	)
	_register_module(
		Settings.ENABLE_CURVE_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/curve_preview_tooltip.gd",
		"Curve"
	)
	_register_module(
		Settings.ENABLE_GRADIENT_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/gradient_preview_tooltip.gd",
		"Gradient"
	)
	_register_module(
		Settings.ENABLE_ENVIRONMENT_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/environment_preview_tooltip.gd",
		"Environment"
	)
	_register_module(
		Settings.ENABLE_SKY_PREVIEW,
		"res://addons/filesystem_dock_tooltips/modules/sky_preview_tooltip.gd",
		"Sky"
	)


func _exit_tree() -> void:
	var file_system_dock := EditorInterface.get_file_system_dock()
	for tooltip_plugin in _tooltip_plugins:
		if tooltip_plugin != null:
			file_system_dock.remove_resource_tooltip_plugin(tooltip_plugin)

	_tooltip_plugins.clear()


func _register_module(
	enabled: bool,
	script_path: String,
	module_name: String
) -> void:
	if not enabled:
		Debug.log(module_name, "disabled")
		return
	var module_script := load(script_path) as Script
	if module_script == null:
		Debug.error(module_name, "could not load module script")
		return
	var instance: Variant = module_script.new()
	if not instance is EditorResourceTooltipPlugin:
		Debug.error(module_name, "module is not an EditorResourceTooltipPlugin")
		if instance != null and is_instance_valid(instance):
			instance.free()
		return
	var tooltip_plugin := instance as EditorResourceTooltipPlugin
	EditorInterface.get_file_system_dock().add_resource_tooltip_plugin(
		tooltip_plugin
	)
	_tooltip_plugins.append(tooltip_plugin)
	Debug.log(module_name, "registered")
