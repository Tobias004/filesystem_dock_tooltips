@tool
extends EditorPlugin

const Settings := preload("res://addons/filesystem_dock_tooltips/tooltip_settings.gd")
const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const SupportMenu := preload("res://addons/filesystem_dock_tooltips/support_menu.gd")
const SettingsDialogScene := preload("res://addons/filesystem_dock_tooltips/settings_dialog.tscn")

const MODULES := [
	{
		"id": Settings.MODULE_SCRIPT_DOCUMENTATION,
		"script_path": "res://addons/filesystem_dock_tooltips/filesystem_dock_tooltips.gd",
		"name": "Script Documentation",
	},
	{
		"id": Settings.MODULE_MATERIAL_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/material_preview_tooltip.gd",
		"name": "Material",
	},
	{
		"id": Settings.MODULE_MESH_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/mesh_preview_tooltip.gd",
		"name": "Mesh",
	},
	{
		"id": Settings.MODULE_FONT_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/font_preview_tooltip.gd",
		"name": "Font",
	},
	{
		"id": Settings.MODULE_SHADER_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/shader_preview_tooltip.gd",
		"name": "Shader",
	},
	{
		"id": Settings.MODULE_SPRITE_FRAMES_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/sprite_frames_preview_tooltip.gd",
		"name": "SpriteFrames",
	},
	{
		"id": Settings.MODULE_THEME_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/theme_preview_tooltip.gd",
		"name": "Theme",
	},
	{
		"id": Settings.MODULE_STYLEBOX_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/stylebox_preview_tooltip.gd",
		"name": "StyleBox",
	},
	{
		"id": Settings.MODULE_CURVE_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/curve_preview_tooltip.gd",
		"name": "Curve",
	},
	{
		"id": Settings.MODULE_GRADIENT_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/gradient_preview_tooltip.gd",
		"name": "Gradient",
	},
	{
		"id": Settings.MODULE_ENVIRONMENT_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/environment_preview_tooltip.gd",
		"name": "Environment",
	},
	{
		"id": Settings.MODULE_SKY_PREVIEW,
		"script_path": "res://addons/filesystem_dock_tooltips/modules/sky_preview_tooltip.gd",
		"name": "Sky",
	},
]

var _tooltip_plugins: Dictionary = {}
var _support_menu: Variant = null
var _settings_dialog: Variant = null

func _enter_tree() -> void:
	if Settings.ENABLE_SUPPORT_MENU:
		_support_menu = SupportMenu.new()
		_support_menu.settings_requested.connect(_open_settings_dialog)
		_support_menu.setup(self)
	for module in MODULES:
		_register_module(module)

func _exit_tree() -> void:
	if is_instance_valid(_support_menu):
		_support_menu.cleanup()
		_support_menu = null
	if is_instance_valid(_settings_dialog):
		_settings_dialog.queue_free()
	_settings_dialog = null
	for module in MODULES:
		_unregister_module(module)
	_tooltip_plugins.clear()

func _register_module(module: Dictionary) -> void:
	var module_id: String = module["id"]
	var module_name: String = module["name"]
	var script_path: String = module["script_path"]
	if _tooltip_plugins.has(module_id):
		return
	if not Settings.is_module_enabled(module_id):
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
	_tooltip_plugins[module_id] = tooltip_plugin
	Debug.log(module_name, "registered")

func _unregister_module(module: Dictionary) -> void:
	var module_id: String = module["id"]
	if not _tooltip_plugins.has(module_id):
		return
	var tooltip_plugin := _tooltip_plugins[module_id] as EditorResourceTooltipPlugin
	if tooltip_plugin != null:
		EditorInterface.get_file_system_dock().remove_resource_tooltip_plugin(
			tooltip_plugin
		)
	_tooltip_plugins.erase(module_id)
	var module_name: String = module["name"]
	Debug.log(module_name, "unregistered")

func _open_settings_dialog() -> void:
	if _settings_dialog == null or not is_instance_valid(_settings_dialog):
		_settings_dialog = SettingsDialogScene.instantiate()
		if _settings_dialog == null:
			Debug.error("Settings", "could not instantiate settings dialog")
			return
		_settings_dialog.hide()
		_settings_dialog.theme = EditorInterface.get_editor_theme()
		EditorInterface.get_base_control().add_child(_settings_dialog)
		_settings_dialog.module_setting_changed.connect(_on_module_setting_changed)
	_settings_dialog.refresh()
	_settings_dialog.reset_size()
	_settings_dialog.popup_centered()

func _on_module_setting_changed(module_id: String, enabled: bool) -> void:
	var module := _find_module(module_id)
	if module.is_empty():
		return
	if enabled:
		_register_module(module)
	else:
		_unregister_module(module)

func _find_module(module_id: String) -> Dictionary:
	for module in MODULES:
		if module["id"] == module_id:
			return module
	return {}
