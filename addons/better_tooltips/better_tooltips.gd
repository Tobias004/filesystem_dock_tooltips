@tool
class_name BTController
extends RefCounted

## [b]Central controller[/b] for Better Tooltips.
## Keeps [code]plugin.gd[/code] limited to the [EditorPlugin] lifecycle while this class owns module registration, settings and support integration.
## Resource previews run through the central [BTTooltipPipeline] and share a bounded RAM hot cache plus a persistent project-local disk cache.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const Debug := preload("res://addons/better_tooltips/tooltip_debug.gd")
const SupportMenu := preload("res://addons/better_tooltips/support_menu.gd")
const SettingsDialogScene := preload(
	"res://addons/better_tooltips/settings_dialog.tscn"
)
const DocumentationHelpDialogScene := preload(
	"res://addons/better_tooltips/documentation_help_dialog.tscn"
)
const TooltipCache := preload(
	"res://addons/better_tooltips/core/tooltip_cache.gd"
)
const TooltipPipeline := preload(
	"res://addons/better_tooltips/core/tooltip_pipeline.gd"
)

# Central registry for the tooltip modules managed by the add-on.
# Keeping the registry here leaves plugin.gd responsible only for the Godot
# EditorPlugin lifecycle and provides one place for cache/pipeline coordination.
const MODULES := [
	{
		"id": Settings.MODULE_SCRIPT_DOCUMENTATION,
		"script_path": "res://addons/better_tooltips/modules/script_documentation_tooltip.gd",
		"name": "Script Documentation",
	},
	{
		"id": Settings.MODULE_CODE_EDITOR_DOCUMENTATION,
		"script_path": "res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd",
		"name": "Code Editor Documentation",
	},
	{
		"id": Settings.MODULE_MARKDOWN_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/markdown_preview_tooltip.gd",
		"name": "Markdown",
	},
	{
		"id": Settings.MODULE_TEXT_FILE_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/text_file_preview_tooltip.gd",
		"name": "Text File",
	},
	{
		"id": Settings.MODULE_MATERIAL_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/material_preview_tooltip.gd",
		"name": "Material",
	},
	{
		"id": Settings.MODULE_MESH_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/mesh_preview_tooltip.gd",
		"name": "Mesh",
	},
	{
		"id": Settings.MODULE_FONT_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/font_preview_tooltip.gd",
		"name": "Font",
	},
	{
		"id": Settings.MODULE_SHADER_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/shader_preview_tooltip.gd",
		"name": "Shader",
	},
	{
		"id": Settings.MODULE_SPRITE_FRAMES_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/sprite_frames_preview_tooltip.gd",
		"name": "SpriteFrames",
	},
	{
		"id": Settings.MODULE_THEME_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/theme_preview_tooltip.gd",
		"name": "Theme",
	},
	{
		"id": Settings.MODULE_STYLEBOX_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/stylebox_preview_tooltip.gd",
		"name": "StyleBox",
	},
	{
		"id": Settings.MODULE_CURVE_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/curve_preview_tooltip.gd",
		"name": "Curve",
	},
	{
		"id": Settings.MODULE_GRADIENT_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/gradient_preview_tooltip.gd",
		"name": "Gradient",
	},
	{
		"id": Settings.MODULE_ENVIRONMENT_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/environment_preview_tooltip.gd",
		"name": "Environment",
	},
	{
		"id": Settings.MODULE_SKY_PREVIEW,
		"script_path": "res://addons/better_tooltips/modules/sky_preview_tooltip.gd",
		"name": "Sky",
	},
]

var _plugin: EditorPlugin = null
var _tooltip_plugins: Dictionary = {}
var _tooltip_cache: BTTooltipCache = null
var _tooltip_pipeline: BTTooltipPipeline = null
var _support_menu: BTSupportMenu = null
var _settings_dialog: BTSettingsDialog = null
var _documentation_help_dialog: BTDocumentationHelpDialog = null

# Initializes the add-on integrations owned by the controller. One central
# preview pipeline is registered with Godot; resource-specific modules are added
# to it, FileSystem documentation stays a direct tooltip plugin, and CodeEdit
# documentation attaches independently to Godot's ScriptEditor.
func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_tooltip_cache = TooltipCache.new() as BTTooltipCache
	_tooltip_cache.setup(EditorInterface.get_base_control())
	_tooltip_pipeline = TooltipPipeline.new() as BTTooltipPipeline
	_tooltip_pipeline.setup(_tooltip_cache, EditorInterface.get_base_control())
	EditorInterface.get_file_system_dock().add_resource_tooltip_plugin(
		_tooltip_pipeline
	)
	if Settings.ENABLE_SUPPORT_MENU:
		_support_menu = SupportMenu.new() as BTSupportMenu
		_support_menu.settings_requested.connect(_open_settings_dialog)
		_support_menu.documentation_help_requested.connect(
			_open_documentation_help_dialog
		)
		_support_menu.setup(_plugin)
	for module in MODULES:
		_register_module(module)

# Forwards editor-wide input to the preview pipeline. The pipeline consumes only
# wheel events while one of its graphical tooltip sections is actually visible.
func handle_input(event: InputEvent) -> bool:
	return _tooltip_pipeline != null and _tooltip_pipeline.handle_input(event)

# Removes every editor integration created by setup(). Modules are detached from
# the pipeline first, then the single preview plugin and shared cache are
# released so no asynchronous job can publish into already removed UI state.
func cleanup() -> void:
	if is_instance_valid(_support_menu):
		_support_menu.cleanup()
		_support_menu = null
	if is_instance_valid(_settings_dialog):
		_settings_dialog.queue_free()
	_settings_dialog = null
	if is_instance_valid(_documentation_help_dialog):
		_documentation_help_dialog.queue_free()
	_documentation_help_dialog = null
	for module in MODULES:
		_unregister_module(module)
	_tooltip_plugins.clear()
	if _tooltip_pipeline != null:
		EditorInterface.get_file_system_dock().remove_resource_tooltip_plugin(
			_tooltip_pipeline
		)
		_tooltip_pipeline.cleanup()
	_tooltip_pipeline = null
	if _tooltip_cache != null:
		_tooltip_cache.cleanup()
	_tooltip_cache = null
	_plugin = null

# Creates one enabled module. FileSystem documentation is registered directly
# with Godot, CodeEdit documentation owns its ScriptEditor hook, and resource
# previews are registered inside the shared pipeline.
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
	if module_id == Settings.MODULE_CODE_EDITOR_DOCUMENTATION:
		if instance == null or not instance.has_method("setup"):
			Debug.error(module_name, "editor integration has no setup() method")
			return
		instance.call("setup", _tooltip_pipeline)
		_tooltip_plugins[module_id] = instance
		Debug.log(module_name, "registered")
		return
	if not (instance is EditorResourceTooltipPlugin):
		Debug.error(module_name, "module is not an EditorResourceTooltipPlugin")
		if instance != null and is_instance_valid(instance):
			instance.free()
		return
	var module_plugin := instance as EditorResourceTooltipPlugin
	if module_id == Settings.MODULE_SCRIPT_DOCUMENTATION:
		EditorInterface.get_file_system_dock().add_resource_tooltip_plugin(
			module_plugin
		)
	else:
		if _tooltip_pipeline == null:
			Debug.error(module_name, "preview pipeline is not available")
			return
		_tooltip_pipeline.add_module(
			module_id,
			module_name,
			module_plugin
		)
	_tooltip_plugins[module_id] = module_plugin
	Debug.log(module_name, "registered")

# Unregisters one active module. CodeEdit integrations disconnect their editor
# hooks; preview modules are removed from the pipeline instead of FileSystemDock.
func _unregister_module(module: Dictionary) -> void:
	var module_id: String = module["id"]
	if not _tooltip_plugins.has(module_id):
		return
	var instance: Variant = _tooltip_plugins[module_id]
	if module_id == Settings.MODULE_CODE_EDITOR_DOCUMENTATION:
		if instance != null and instance.has_method("cleanup"):
			instance.call("cleanup")
		_tooltip_plugins.erase(module_id)
		var integration_name: String = module["name"]
		Debug.log(integration_name, "unregistered")
		return
	var module_plugin := instance as EditorResourceTooltipPlugin
	if module_id == Settings.MODULE_SCRIPT_DOCUMENTATION:
		if module_plugin != null:
			EditorInterface.get_file_system_dock().remove_resource_tooltip_plugin(
				module_plugin
			)
	else:
		if _tooltip_pipeline != null:
			_tooltip_pipeline.remove_module(module_id)
	if module_plugin != null and module_plugin.has_method("cleanup"):
		module_plugin.call("cleanup")
	_tooltip_plugins.erase(module_id)
	var module_name: String = module["name"]
	Debug.log(module_name, "unregistered")

# Lazily creates the settings dialog, keeps it connected to live module changes
# and the shared cache, and refreshes its state every time it is opened.
func _open_settings_dialog() -> void:
	if _settings_dialog == null or not is_instance_valid(_settings_dialog):
		_settings_dialog = SettingsDialogScene.instantiate() as BTSettingsDialog
		if _settings_dialog == null:
			Debug.error("Settings", "could not instantiate settings dialog")
			return
		_settings_dialog.hide()
		_settings_dialog.theme = EditorInterface.get_editor_theme()
		EditorInterface.get_base_control().add_child(_settings_dialog)
		_settings_dialog.module_setting_changed.connect(_on_module_setting_changed)
		_settings_dialog.code_editor_integration_settings_changed.connect(
			_on_code_editor_integration_settings_changed
		)
		_settings_dialog.cache_clear_requested.connect(_on_cache_clear_requested)
	_settings_dialog.refresh()
	_settings_dialog.set_cache_available(
		_tooltip_cache != null and _tooltip_cache.has_entries()
	)
	_settings_dialog.reset_size()
	_settings_dialog.popup_centered()

# Lazily creates the local documentation-syntax reference. Its body uses the
# same reusable documentation renderer as tooltip content, including EditorHelp
# fonts, colors, spacing, code blocks and clickable class-reference links.
func _open_documentation_help_dialog() -> void:
	if (
		_documentation_help_dialog == null
		or not is_instance_valid(_documentation_help_dialog)
	):
		_documentation_help_dialog = DocumentationHelpDialogScene.instantiate() as BTDocumentationHelpDialog
		if _documentation_help_dialog == null:
			Debug.error("Documentation", "could not instantiate help dialog")
			return
		_documentation_help_dialog.hide()
		_documentation_help_dialog.theme = EditorInterface.get_editor_theme()
		EditorInterface.get_base_control().add_child(_documentation_help_dialog)
	_documentation_help_dialog.refresh()
	_documentation_help_dialog.popup_centered()

# Applies a changed module setting immediately by registering or unregistering
# only the affected tooltip module.
func _on_module_setting_changed(module_id: String, enabled: bool) -> void:
	var module := _find_module(module_id)
	if module.is_empty():
		return
	if enabled:
		_register_module(module)
	else:
		_unregister_module(module)

# Applies compatibility-option changes that affect ScriptEditor navigation
# discovery without recreating the full Code Editor documentation module.
func _on_code_editor_integration_settings_changed() -> void:
	var instance: Variant = _tooltip_plugins.get(
		Settings.MODULE_CODE_EDITOR_DOCUMENTATION,
		null
	)
	if instance != null and instance.has_method("refresh_navigation_controls"):
		instance.call("refresh_navigation_controls")

# Clears bounded RAM entries, transient failures and persistent disk previews.
# The following hover therefore performs its preview generation again.
func _on_cache_clear_requested() -> void:
	if _tooltip_pipeline != null:
		_tooltip_pipeline.clear_cache()
	elif _tooltip_cache != null:
		_tooltip_cache.clear()
	if is_instance_valid(_settings_dialog):
		_settings_dialog.set_cache_available(false)
	Debug.log("Cache", "tooltip caches cleared")

# Returns the registry entry for a module id, or an empty dictionary when the
# id is unknown.
func _find_module(module_id: String) -> Dictionary:
	for module in MODULES:
		if module["id"] == module_id:
			return module
	return {}
