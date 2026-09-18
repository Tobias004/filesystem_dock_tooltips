@tool
extends RefCounted

# Set this to true while developing the add-on. The release package uses false.
const DEBUG_MESSAGES := false

# Enables Project > Tools menu for settings, GitHub bug reports and feedback.
const ENABLE_SUPPORT_MENU := true

const SETTINGS_SECTION := "filesystem_dock_tooltips"
const MODULE_SCRIPT_DOCUMENTATION := "script_documentation"
const MODULE_MATERIAL_PREVIEW := "material_preview"
const MODULE_MESH_PREVIEW := "mesh_preview"
const MODULE_FONT_PREVIEW := "font_preview"
const MODULE_SHADER_PREVIEW := "shader_preview"
const MODULE_SPRITE_FRAMES_PREVIEW := "sprite_frames_preview"
const MODULE_THEME_PREVIEW := "theme_preview"
const MODULE_STYLEBOX_PREVIEW := "stylebox_preview"
const MODULE_CURVE_PREVIEW := "curve_preview"
const MODULE_GRADIENT_PREVIEW := "gradient_preview"
const MODULE_ENVIRONMENT_PREVIEW := "environment_preview"
const MODULE_SKY_PREVIEW := "sky_preview"

const MODULE_DEFAULTS := {
	MODULE_SCRIPT_DOCUMENTATION: true,
	MODULE_MATERIAL_PREVIEW: true,
	MODULE_MESH_PREVIEW: true,
	MODULE_FONT_PREVIEW: true,
	MODULE_SHADER_PREVIEW: true,
	MODULE_SPRITE_FRAMES_PREVIEW: true,
	MODULE_THEME_PREVIEW: true,
	MODULE_STYLEBOX_PREVIEW: true,
	MODULE_CURVE_PREVIEW: true,
	MODULE_GRADIENT_PREVIEW: true,
	MODULE_ENVIRONMENT_PREVIEW: true,
	MODULE_SKY_PREVIEW: true,
}

static func is_module_enabled(module_id: String) -> bool:
	var default_value := bool(MODULE_DEFAULTS.get(module_id, true))
	return bool(
		EditorInterface.get_editor_settings().get_project_metadata(
			SETTINGS_SECTION,
			module_id,
			default_value
		)
	)

static func set_module_enabled(module_id: String, enabled: bool) -> void:
	if not MODULE_DEFAULTS.has(module_id):
		return
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		module_id,
		enabled
	)
