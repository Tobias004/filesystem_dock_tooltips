@tool
class_name BTSettings
extends RefCounted

## [b]Central constants and project-scoped settings access[/b] for the add-on.
## Module toggles, code-documentation options and the preview safety limit are stored in Godot editor metadata rather than modifying [code]project.godot[/code].
## ScriptEditor navigation integration remains configurable, including independent compatibility switches for Quill IDE and Script-IDE tabs/outlines.

# Set this to true while developing the add-on. The release package uses false.
const DEBUG_MESSAGES := false
# Enables Project > Tools menu for settings, local documentation help and support links.
const ENABLE_SUPPORT_MENU := true
const SETTINGS_SECTION := "better_tooltips"
const LEGACY_SETTINGS_SECTION := "filesystem_dock_tooltips"
const MISSING_METADATA_SENTINEL := "__better_tooltips_missing_metadata__"
const PREVIEW_SAFETY_LIMIT_KEY := "preview_safety_limit_ms"
const PREVIEW_SIZE_PERCENT_KEY := "preview_size_percent"
# Text-only settings: no effect on bitmap previews or wheel zoom.
const TEXT_FONT_PERCENT_KEY := "text_font_percent"
const TEXT_MAX_WIDTH_KEY := "text_max_width"
const TEXT_MAX_HEIGHT_KEY := "text_max_height"
const DEFAULT_TEXT_FONT_PERCENT := 100
const DEFAULT_TEXT_MAX_WIDTH := 760
const DEFAULT_TEXT_MAX_HEIGHT := 620
const PREVIEW_SCALE_METADATA_KEY := "_bt_preview_scale"
const DOCUMENTATION_COMMENTS_KEY := "code_editor_documentation_comments"
const SINGLE_HASH_MEMBER_DOCUMENTATION_KEY := "single_hash_member_documentation"
const REPLACE_GODOT_MEMBER_DOCUMENTATION_KEY := "replace_godot_member_documentation"
const TOOLTIP_BACKGROUND_CONTRAST_KEY := "tooltip_background_contrast_percent"
const QUILL_IDE_INTEGRATION_KEY := "quill_ide_integration"
const SCRIPT_IDE_INTEGRATION_KEY := "script_ide_integration"
const DEFAULT_PREVIEW_SAFETY_LIMIT_MS := 5000
const DEFAULT_PREVIEW_SIZE_PERCENT := 100
const MIN_PREVIEW_SIZE_PERCENT := 50
const MAX_PREVIEW_SIZE_PERCENT := 200
const DEFAULT_DOCUMENTATION_COMMENTS := true
const DEFAULT_SINGLE_HASH_MEMBER_DOCUMENTATION := true
const DEFAULT_REPLACE_GODOT_MEMBER_DOCUMENTATION := true
const DEFAULT_TOOLTIP_BACKGROUND_CONTRAST_PERCENT := 5
const DEFAULT_QUILL_IDE_INTEGRATION := true
const DEFAULT_SCRIPT_IDE_INTEGRATION := true
const MODULE_SCRIPT_DOCUMENTATION := "script_documentation"
const MODULE_CODE_EDITOR_DOCUMENTATION := "code_editor_documentation"
const MODULE_MARKDOWN_PREVIEW := "markdown_preview"
const MODULE_TEXT_FILE_PREVIEW := "text_file_preview"
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
	MODULE_CODE_EDITOR_DOCUMENTATION: true,
	MODULE_MARKDOWN_PREVIEW: true,
	MODULE_TEXT_FILE_PREVIEW: true,
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

# Restores the complete project-local configuration. Write explicit defaults
# instead of removing metadata: otherwise 2.x legacy values would be imported
# again on the next read and silently undo the reset.
static func reset_to_defaults() -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	for module_id: String in MODULE_DEFAULTS:
		editor_settings.set_project_metadata(
			SETTINGS_SECTION, module_id, bool(MODULE_DEFAULTS[module_id])
		)
	var defaults := {
		PREVIEW_SAFETY_LIMIT_KEY: DEFAULT_PREVIEW_SAFETY_LIMIT_MS,
		PREVIEW_SIZE_PERCENT_KEY: DEFAULT_PREVIEW_SIZE_PERCENT,
		TEXT_FONT_PERCENT_KEY: DEFAULT_TEXT_FONT_PERCENT,
		TEXT_MAX_WIDTH_KEY: DEFAULT_TEXT_MAX_WIDTH,
		TEXT_MAX_HEIGHT_KEY: DEFAULT_TEXT_MAX_HEIGHT,
		DOCUMENTATION_COMMENTS_KEY: DEFAULT_DOCUMENTATION_COMMENTS,
		SINGLE_HASH_MEMBER_DOCUMENTATION_KEY: DEFAULT_SINGLE_HASH_MEMBER_DOCUMENTATION,
		REPLACE_GODOT_MEMBER_DOCUMENTATION_KEY: DEFAULT_REPLACE_GODOT_MEMBER_DOCUMENTATION,
		TOOLTIP_BACKGROUND_CONTRAST_KEY: DEFAULT_TOOLTIP_BACKGROUND_CONTRAST_PERCENT,
		QUILL_IDE_INTEGRATION_KEY: DEFAULT_QUILL_IDE_INTEGRATION,
		SCRIPT_IDE_INTEGRATION_KEY: DEFAULT_SCRIPT_IDE_INTEGRATION,
	}
	for key: String in defaults:
		editor_settings.set_project_metadata(SETTINGS_SECTION, key, defaults[key])

# Reads project metadata from the Better Tooltips namespace. When upgrading from
# FileSystem Dock Tooltips 2.x, an existing value is copied lazily from the old
# namespace so users keep their module and appearance preferences after the rename.
static func _get_project_metadata(key: String, default_value: Variant) -> Variant:
	var editor_settings := EditorInterface.get_editor_settings()
	var value: Variant = editor_settings.get_project_metadata(
		SETTINGS_SECTION,
		key,
		MISSING_METADATA_SENTINEL
	)
	if not _is_missing_metadata(value):
		return value
	var legacy_value: Variant = editor_settings.get_project_metadata(
		LEGACY_SETTINGS_SECTION,
		key,
		MISSING_METADATA_SENTINEL
	)
	if not _is_missing_metadata(legacy_value):
		editor_settings.set_project_metadata(SETTINGS_SECTION, key, legacy_value)
		return legacy_value
	return default_value

# Distinguishes the string sentinel from real bool/int setting values without
# relying on cross-type Variant comparison, which GDScript rejects.
static func _is_missing_metadata(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and String(value) == MISSING_METADATA_SENTINEL

# Returns whether one tooltip module is enabled for the current project, using
# the built-in default when no project-specific value has been stored yet.
static func is_module_enabled(module_id: String) -> bool:
	var default_value := bool(MODULE_DEFAULTS.get(module_id, true))
	return bool(
		_get_project_metadata(module_id, default_value)
	)

# Persists one module toggle in Godot's project metadata. Unknown module ids are
# ignored so callers cannot accidentally create unsupported settings entries.
static func set_module_enabled(module_id: String, enabled: bool) -> void:
	if not MODULE_DEFAULTS.has(module_id):
		return
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		module_id,
		enabled
	)

# Returns the generous end-to-end safety limit used by the central pipeline.
# Ordinary slow previews are allowed to finish and are cached. A positive limit
# only stops work at safe checkpoints when more expensive work still remains.
# A value of 0 disables this safety limit completely.
static func get_preview_safety_limit_ms() -> int:
	var stored_value := int(
		_get_project_metadata(
			PREVIEW_SAFETY_LIMIT_KEY,
			DEFAULT_PREVIEW_SAFETY_LIMIT_MS
		)
	)
	return maxi(0, stored_value)

# Persists the preview safety limit in milliseconds. Raising the value, or
# setting it to 0 (unlimited), retries entries previously stopped by the limit.
static func set_preview_safety_limit_ms(limit_ms: int) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		PREVIEW_SAFETY_LIMIT_KEY,
		maxi(0, limit_ms)
	)

# Text sizing is relative to Godot's current document/source font. At 100%,
# Better Tooltips uses one point less than Godot's theme size.
static func get_text_font_percent() -> int:
	return clampi(int(_get_project_metadata(TEXT_FONT_PERCENT_KEY, DEFAULT_TEXT_FONT_PERCENT)), 50, 200)

static func set_text_font_percent(percent: int) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION, TEXT_FONT_PERCENT_KEY, clampi(percent, 50, 200)
	)

static func scale_text_font_size(theme_size: int) -> int:
	return maxi(6, roundi(maxi(1, theme_size - 1) * get_text_font_percent() / 100.0))

# User-facing maximums are logical editor pixels; actual limits account for
# editor UI scale and available screen area at display time.
static func get_text_max_width() -> int:
	return clampi(int(_get_project_metadata(TEXT_MAX_WIDTH_KEY, DEFAULT_TEXT_MAX_WIDTH)), 240, 2000)

static func set_text_max_width(width: int) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION, TEXT_MAX_WIDTH_KEY, clampi(width, 240, 2000)
	)

static func get_text_max_height() -> int:
	return clampi(int(_get_project_metadata(TEXT_MAX_HEIGHT_KEY, DEFAULT_TEXT_MAX_HEIGHT)), 160, 1600)

static func set_text_max_height(height: int) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION, TEXT_MAX_HEIGHT_KEY, clampi(height, 160, 1600)
	)

# Returns the project-local default render size for cached graphical previews.
# The value is a percentage of each module's natural preview dimensions, which
# preserves the different aspect ratios used by materials, curves, themes, etc.
static func get_preview_size_percent() -> int:
	var stored_value := int(
		_get_project_metadata(
			PREVIEW_SIZE_PERCENT_KEY,
			DEFAULT_PREVIEW_SIZE_PERCENT
		)
	)
	return clampi(
		stored_value,
		MIN_PREVIEW_SIZE_PERCENT,
		MAX_PREVIEW_SIZE_PERCENT
	)

# Persists the cached-preview render size. The cache signature includes this
# value, so existing previews are invalidated lazily without a destructive clear.
static func set_preview_size_percent(percent: int) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		PREVIEW_SIZE_PERCENT_KEY,
		clampi(percent, MIN_PREVIEW_SIZE_PERCENT, MAX_PREVIEW_SIZE_PERCENT)
	)

# Converts the pipeline's reserved metadata value into a safe module scale.
# Normal cached generation writes the configured default here; transient wheel
# zoom writes the requested temporary value without touching the cache.
static func get_preview_scale_from_metadata(metadata: Dictionary) -> float:
	return clampf(
		float(metadata.get(PREVIEW_SCALE_METADATA_KEY, 1.0)),
		0.25,
		3.0
	)

# Returns whether Godot-style ## documentation from project scripts should be
# shown through the add-on renderer in Code Editor symbol tooltips. This setting
# is independent from ordinary single-# implementation comments.
static func is_documentation_comments_enabled() -> bool:
	return bool(
		_get_project_metadata(
			DOCUMENTATION_COMMENTS_KEY,
			DEFAULT_DOCUMENTATION_COMMENTS
		)
	)

# Persists whether project ## documentation participates in Code Editor tooltips.
static func set_documentation_comments_enabled(enabled: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		DOCUMENTATION_COMMENTS_KEY,
		enabled
	)

# Returns whether ordinary single-# blocks immediately above GDScript members
# should be treated as local implementation documentation in CodeEdit tooltips.
# This option is independent from the Godot-style ## documentation setting.
static func is_single_hash_member_documentation_enabled() -> bool:
	return bool(
		_get_project_metadata(
			SINGLE_HASH_MEMBER_DOCUMENTATION_KEY,
			DEFAULT_SINGLE_HASH_MEMBER_DOCUMENTATION
		)
	)

# Persists the add-on-only single-# member documentation preference per project.
static func set_single_hash_member_documentation_enabled(enabled: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		SINGLE_HASH_MEMBER_DOCUMENTATION_KEY,
		enabled
	)

# Returns whether native Godot descriptions that represent the same project ##
# documentation should be replaced by the shared add-on renderer. Engine API
# documentation is never replaced because no project source block resolves to it.
static func is_replace_godot_member_documentation_enabled() -> bool:
	return bool(
		_get_project_metadata(
			REPLACE_GODOT_MEMBER_DOCUMENTATION_KEY,
			DEFAULT_REPLACE_GODOT_MEMBER_DOCUMENTATION
		)
	)

# Persists the preference for replacing Godot-rendered project member docs.
static func set_replace_godot_member_documentation_enabled(enabled: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		REPLACE_GODOT_MEMBER_DOCUMENTATION_KEY,
		enabled
	)

# Returns whether optional Quill IDE navigation controls should be discovered and
# extended. The standard Godot CodeEdit and script-list integrations remain
# independent, so this can be disabled as a compatibility fallback.
static func is_quill_ide_integration_enabled() -> bool:
	return bool(
		_get_project_metadata(
			QUILL_IDE_INTEGRATION_KEY,
			DEFAULT_QUILL_IDE_INTEGRATION
		)
	)

# Persists whether Quill-specific tab/outline discovery is enabled for this project.
static func set_quill_ide_integration_enabled(enabled: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		QUILL_IDE_INTEGRATION_KEY,
		enabled
	)

# Returns whether optional Script-IDE navigation controls should be discovered and
# extended. Script-IDE and Quill are detected independently because projects may
# install either compatibility target, while the standard Godot integration stays active.
static func is_script_ide_integration_enabled() -> bool:
	return bool(
		_get_project_metadata(
			SCRIPT_IDE_INTEGRATION_KEY,
			DEFAULT_SCRIPT_IDE_INTEGRATION
		)
	)

# Persists whether Script-IDE-specific tab/outline discovery is enabled.
static func set_script_ide_integration_enabled(enabled: bool) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		SCRIPT_IDE_INTEGRATION_KEY,
		enabled
	)

# Returns how strongly add-on-owned tooltip sections differ from Godot's native
# tooltip background. Dark themes are lightened and light themes are darkened,
# so the same percentage remains meaningful across editor themes.
static func get_tooltip_background_contrast_percent() -> int:
	var stored_value := int(
		_get_project_metadata(
			TOOLTIP_BACKGROUND_CONTRAST_KEY,
			DEFAULT_TOOLTIP_BACKGROUND_CONTRAST_PERCENT
		)
	)
	return clampi(stored_value, 0, 30)


# Persists the add-on tooltip background contrast as a project-local percentage.
# A value of zero keeps the corresponding Godot background unchanged.
static func set_tooltip_background_contrast_percent(percent: int) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		SETTINGS_SECTION,
		TOOLTIP_BACKGROUND_CONTRAST_KEY,
		clampi(percent, 0, 30)
	)
