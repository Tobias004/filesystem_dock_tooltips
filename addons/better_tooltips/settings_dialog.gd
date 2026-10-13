@tool
class_name BTSettingsDialog
extends AcceptDialog

## [b]Project settings dialog[/b] for enabling tooltip modules and configuring documentation, appearance, preview and cache behavior.
## Changes are applied immediately; [kbd]Clear Tooltip Caches[/kbd] removes both RAM and persistent disk previews so the next hover regenerates them.
## The two-column layout keeps documentation, appearance and resource-preview settings visible without requiring a scrolling settings surface.

signal module_setting_changed(module_id: String, enabled: bool)
signal cache_clear_requested()
signal code_editor_integration_settings_changed()

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const TOOLTIP_WRAP_COLUMNS := 64

@onready var _documentation_comments_checkbox: CheckBox = (
	$MarginContainer/Columns/DocumentationColumn/CodeEditorOptionsIndent/CodeEditorOptions/chkbDocumentationComments
)
@onready var _single_hash_checkbox: CheckBox = (
	$MarginContainer/Columns/DocumentationColumn/CodeEditorOptionsIndent/CodeEditorOptions/chkbSingleHashDoc
)
@onready var _replace_godot_member_docs_checkbox: CheckBox = (
	$MarginContainer/Columns/DocumentationColumn/CodeEditorOptionsIndent/CodeEditorOptions/chkbReplaceGodotMemberDocs
)
@onready var _quill_integration_checkbox: CheckBox = (
	$MarginContainer/Columns/DocumentationColumn/CodeEditorOptionsIndent/CodeEditorOptions/chkbQuillIntegration
)
@onready var _script_ide_integration_checkbox: CheckBox = (
	$MarginContainer/Columns/DocumentationColumn/CodeEditorOptionsIndent/CodeEditorOptions/chkbScriptIdeIntegration
)
@onready var _background_contrast_spin: SpinBox = (
	$MarginContainer/Columns/DocumentationColumn/BackgroundContrastRow/spnBackgroundContrast
)
@onready var _safety_limit_spin: SpinBox = (
	$MarginContainer/Columns/DocumentationColumn/SafetyLimitRow/spnPreviewSafetyLimit
)
@onready var _clear_cache_button: Button = (
	$MarginContainer/Columns/DocumentationColumn/btnClearCaches
)
@onready var _preview_size_spin: SpinBox = (
	$MarginContainer/Columns/PreviewColumn/PreviewSizeRow/spnPreviewSize
)

var _checkboxes: Dictionary = {}

# Connects all settings controls once the dialog enters the editor tree and adds
# the shared actions that affect every module or the tooltip caches.
func _ready() -> void:
	_checkboxes = {
		Settings.MODULE_SCRIPT_DOCUMENTATION: $MarginContainer/Columns/DocumentationColumn/chkbGdscriptDoc,
		Settings.MODULE_CODE_EDITOR_DOCUMENTATION: $MarginContainer/Columns/DocumentationColumn/chkbCodeEditorDoc,
		Settings.MODULE_MARKDOWN_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbMarkdown,
		Settings.MODULE_TEXT_FILE_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbTextFiles,
		Settings.MODULE_MATERIAL_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbMaterials,
		Settings.MODULE_MESH_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbMeshes,
		Settings.MODULE_FONT_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbFonts,
		Settings.MODULE_SHADER_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbShaders,
		Settings.MODULE_SPRITE_FRAMES_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbSpriteFrames,
		Settings.MODULE_THEME_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbThemes,
		Settings.MODULE_STYLEBOX_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbStyleBoxes,
		Settings.MODULE_CURVE_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbCurves,
		Settings.MODULE_GRADIENT_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbGradients,
		Settings.MODULE_ENVIRONMENT_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbEnvironments,
		Settings.MODULE_SKY_PREVIEW: $MarginContainer/Columns/PreviewColumn/chkbSkies,
	}
	for module_id in _checkboxes:
		var checkbox := _checkboxes[module_id] as CheckBox
		checkbox.toggled.connect(_on_checkbox_toggled.bind(module_id))
	_documentation_comments_checkbox.toggled.connect(
		_on_documentation_comments_toggled
	)
	_single_hash_checkbox.toggled.connect(_on_single_hash_toggled)
	_replace_godot_member_docs_checkbox.toggled.connect(
		_on_replace_godot_member_docs_toggled
	)
	_quill_integration_checkbox.toggled.connect(_on_quill_integration_toggled)
	_script_ide_integration_checkbox.toggled.connect(_on_script_ide_integration_toggled)
	_background_contrast_spin.value_changed.connect(
		_on_background_contrast_changed
	)
	_safety_limit_spin.value_changed.connect(
		_on_preview_safety_limit_changed
	)
	_preview_size_spin.value_changed.connect(_on_preview_size_changed)
	_clear_cache_button.pressed.connect(_on_clear_caches_pressed)
	ok_button_text = "Close"
	var enable_all_button := add_button("Enable All", false, "enable_all")
	var disable_all_button := add_button("Disable All", false, "disable_all")
	_configure_setting_tooltips(enable_all_button, disable_all_button)
	custom_action.connect(_on_custom_action)
	refresh()
	
# Refreshes controls from project metadata without emitting change signals, so
# simply opening the dialog never rewrites project-scoped editor settings.
func refresh() -> void:
	if _checkboxes.is_empty():
		return
	for module_id in _checkboxes:
		var checkbox := _checkboxes[module_id] as CheckBox
		checkbox.set_pressed_no_signal(Settings.is_module_enabled(module_id))
	_documentation_comments_checkbox.set_pressed_no_signal(
		Settings.is_documentation_comments_enabled()
	)
	_single_hash_checkbox.set_pressed_no_signal(
		Settings.is_single_hash_member_documentation_enabled()
	)
	_replace_godot_member_docs_checkbox.set_pressed_no_signal(
		Settings.is_replace_godot_member_documentation_enabled()
	)
	_quill_integration_checkbox.set_pressed_no_signal(
		Settings.is_quill_ide_integration_enabled()
	)
	_script_ide_integration_checkbox.set_pressed_no_signal(
		Settings.is_script_ide_integration_enabled()
	)
	_update_code_editor_option_availability()
	_background_contrast_spin.set_value_no_signal(
		Settings.get_tooltip_background_contrast_percent()
	)
	_safety_limit_spin.set_value_no_signal(Settings.get_preview_safety_limit_ms())
	_preview_size_spin.set_value_no_signal(Settings.get_preview_size_percent())

# Persists one module checkbox and tells the controller to apply the change to
# the current editor integration immediately.
func _on_checkbox_toggled(enabled: bool, module_id: String) -> void:
	Settings.set_module_enabled(module_id, enabled)
	module_setting_changed.emit(module_id, enabled)
	if module_id == Settings.MODULE_CODE_EDITOR_DOCUMENTATION:
		_update_code_editor_option_availability()

# Stores whether normal Godot ## comments are shown through the shared Code
# Editor renderer. The active integration reads the value for every new tooltip.
func _on_documentation_comments_toggled(enabled: bool) -> void:
	Settings.set_documentation_comments_enabled(enabled)
	_update_code_editor_option_availability()

# Stores the optional add-on-only # documentation behavior. The active CodeEdit
# integration reads this setting when each tooltip is created, so no reload is needed.
func _on_single_hash_toggled(enabled: bool) -> void:
	Settings.set_single_hash_member_documentation_enabled(enabled)

# Controls whether duplicate native project-member descriptions are hidden in
# favor of the shared renderer. Godot engine API help is never affected.
func _on_replace_godot_member_docs_toggled(enabled: bool) -> void:
	Settings.set_replace_godot_member_documentation_enabled(enabled)

# Enables or disables only the optional Quill navigation bridge. Standard Godot
# CodeEdit and script-list documentation remain active when this is disabled.
func _on_quill_integration_toggled(enabled: bool) -> void:
	Settings.set_quill_ide_integration_enabled(enabled)
	code_editor_integration_settings_changed.emit()

# Enables or disables only the optional Script-IDE navigation bridge. Standard
# Godot and Quill integration settings remain independent.
func _on_script_ide_integration_toggled(enabled: bool) -> void:
	Settings.set_script_ide_integration_enabled(enabled)
	code_editor_integration_settings_changed.emit()

# Stores the visual separation between add-on-owned sections and Godot's native
# tooltip background. Newly created tooltips read the current value immediately.
func _on_background_contrast_changed(value: float) -> void:
	Settings.set_tooltip_background_contrast_percent(roundi(value))

func _update_code_editor_option_availability() -> void:
	var code_checkbox := (
		_checkboxes.get(Settings.MODULE_CODE_EDITOR_DOCUMENTATION, null) as CheckBox
	)
	var code_enabled := code_checkbox != null and code_checkbox.button_pressed
	_documentation_comments_checkbox.disabled = not code_enabled
	_single_hash_checkbox.disabled = not code_enabled
	_replace_godot_member_docs_checkbox.disabled = (
		not code_enabled or not _documentation_comments_checkbox.button_pressed
	)
	_quill_integration_checkbox.disabled = not code_enabled
	_script_ide_integration_checkbox.disabled = not code_enabled

# Persists the generous safety limit. Ordinary slow previews are not rejected;
# the limit only stops work at safe checkpoints while expensive work remains.
func _on_preview_safety_limit_changed(value: float) -> void:
	Settings.set_preview_safety_limit_ms(roundi(value))

# Persists the default size used when graphical previews are rendered into the
# shared cache. The size is part of the cache signature, so new hovers regenerate
# at the selected size without requiring an explicit cache clear.
func _on_preview_size_changed(value: float) -> void:
	Settings.set_preview_size_percent(roundi(value))

# Requests that the controller clears bounded RAM entries, transient failures and
# persistent disk previews. The next hover regenerates the current file version.
func _on_clear_caches_pressed() -> void:
	cache_clear_requested.emit()
	set_cache_available(false)

# Updates both the clear button's enabled state and its explanatory tooltip. The
# controller calls this when opening the dialog and after an explicit clear.
func set_cache_available(has_cache: bool) -> void:
	if not is_instance_valid(_clear_cache_button):
		return
	_clear_cache_button.disabled = not has_cache
	if has_cache:
		_clear_cache_button.tooltip_text = _wrap_tooltip(
			"Cached previews or remembered preview failures are present. Clears the add-on's RAM cache, failure cache and persistent preview files; affected resources are regenerated on the next hover."
		)
	else:
		_clear_cache_button.tooltip_text = _wrap_tooltip(
			"No tooltip preview cache is currently stored, so there is nothing to clear. The button becomes available after a preview result or failure has been cached."
		)

# Applies the same enabled state to every module while retaining the user's
# individual Code Editor documentation preferences as sub-options.
func _set_all(enabled: bool) -> void:
	for module_id in _checkboxes:
		var checkbox := _checkboxes[module_id] as CheckBox
		if checkbox.button_pressed == enabled:
			continue
		checkbox.set_pressed_no_signal(enabled)
		Settings.set_module_enabled(module_id, enabled)
		module_setting_changed.emit(module_id, enabled)
	_update_code_editor_option_availability()

# Adds explanatory hover text to every actual setting, including the less
# obvious cache/safety controls, so the dialog is understandable on its own.
func _configure_setting_tooltips(
	enable_all_button: Button,
	disable_all_button: Button
) -> void:
	var module_tooltips := {
		Settings.MODULE_SCRIPT_DOCUMENTATION: "Adds class_name and Godot ## documentation to GDScript files in the FileSystem dock.",
		Settings.MODULE_CODE_EDITOR_DOCUMENTATION: "Extends Godot Code Editor symbol help and ScriptEditor navigation controls with project GDScript documentation. This includes the stock script list plus compatible tabs/outlines from Quill IDE and Script-IDE.",
		Settings.MODULE_MARKDOWN_PREVIEW: "Shows a live Markdown preview with editor-sized text. Long documents scroll inside the tooltip; graphical zoom is not used.",
		Settings.MODULE_TEXT_FILE_PREVIEW: "Shows a live editor-font preview for Godot TextFile entries other than Markdown. Long files scroll inside the tooltip.",
		Settings.MODULE_MATERIAL_PREVIEW: "Generates larger hover previews for supported 3D materials and spatial ShaderMaterials.",
		Settings.MODULE_MESH_PREVIEW: "Generates fitted 3D hover previews for Mesh resources.",
		Settings.MODULE_FONT_PREVIEW: "Shows rendered font samples in FileSystem tooltips.",
		Settings.MODULE_SHADER_PREVIEW: "Generates previews for supported spatial and canvas_item .gdshader resources.",
		Settings.MODULE_SPRITE_FRAMES_PREVIEW: "Shows a contact-sheet preview for SpriteFrames resources.",
		Settings.MODULE_THEME_PREVIEW: "Shows representative Godot controls rendered with the hovered Theme resource.",
		Settings.MODULE_STYLEBOX_PREVIEW: "Shows the hovered StyleBox on a representative panel.",
		Settings.MODULE_CURVE_PREVIEW: "Shows visual previews for Curve, Curve2D and Curve3D resources.",
		Settings.MODULE_GRADIENT_PREVIEW: "Shows the hovered Gradient over a transparency checkerboard.",
		Settings.MODULE_ENVIRONMENT_PREVIEW: "Renders Environment resources on a fixed reference scene.",
		Settings.MODULE_SKY_PREVIEW: "Renders Sky resources in a fixed wide-angle reference view.",
	}
	for module_id in _checkboxes:
		var checkbox := _checkboxes[module_id] as CheckBox
		checkbox.tooltip_text = _wrap_tooltip(
			str(module_tooltips.get(module_id, ""))
		)
	_documentation_comments_checkbox.tooltip_text = _wrap_tooltip(
		"Shows Godot-style ## documentation comments with the add-on renderer for supported project classes and members in code and ScriptEditor navigation tooltips. This preserves source line breaks and avoids the clipping behavior of Godot's compact native project documentation tooltip."
	)
	_single_hash_checkbox.tooltip_text = _wrap_tooltip(
		"Treats an ordinary contiguous # comment block directly above a supported project class/member as tooltip documentation in code and ScriptEditor navigation tooltips. This is an add-on extension for implementation-specific notes that should not become Godot API documentation."
	)
	_replace_godot_member_docs_checkbox.tooltip_text = _wrap_tooltip(
		"When Godot's native tooltip is showing the same project ## documentation, hide that duplicate description and render it with the add-on instead. Godot's own engine/API documentation and distinct inherited help remain untouched."
	)
	_quill_integration_checkbox.tooltip_text = _wrap_tooltip(
		"Searches for Quill IDE script tabs and outline controls and adds the same project documentation tooltips there. Disable this compatibility integration if a future Quill version changes its editor controls or causes problems; standard Godot code and script-list tooltips remain enabled."
	)
	_script_ide_integration_checkbox.tooltip_text = _wrap_tooltip(
		"Searches for Script-IDE script tabs and outline controls and adds the same project documentation tooltips there. Disable this compatibility integration if a future Script-IDE version changes its editor controls or causes problems; standard Godot code and script-list tooltips remain enabled."
	)
	_set_shared_tooltip(
		[
			$MarginContainer/Columns/DocumentationColumn/BackgroundContrastRow/lblBackgroundContrast,
			_background_contrast_spin,
		],
		"Changes only add-on-owned tooltip sections relative to Godot's current tooltip background. Dark themes are made lighter, light themes darker. 0% keeps the native background brightness."
	)
	_set_shared_tooltip(
		[
			$MarginContainer/Columns/DocumentationColumn/lblSafetyHint,
			$MarginContainer/Columns/DocumentationColumn/SafetyLimitRow/lblPreviewSafetyLimit,
			_safety_limit_spin,
		],
		"Maximum elapsed time for uncached resource-preview generation before the add-on stops at a safe checkpoint. 0 disables the limit. Hold Shift while hovering to force one regeneration attempt without the limit."
	)
	_set_shared_tooltip(
		[
			$MarginContainer/Columns/PreviewColumn/PreviewSizeRow/lblPreviewSize,
			_preview_size_spin,
		],
		"Default render size for cached graphical previews. While a graphical tooltip is visible, use the mouse wheel to resize only that hover temporarily; temporary zoom renders are never written to the cache. The live maximum is reduced automatically when necessary to keep the complete graphical tooltip within a manageable portion of the current screen."
	)
	enable_all_button.tooltip_text = _wrap_tooltip(
		"Enable every tooltip module for this project."
	)
	disable_all_button.tooltip_text = _wrap_tooltip(
		"Disable every tooltip module for this project."
	)

# Assigns one explanation to a label/control group that represents one setting,
# so hovering either the caption or the editor control shows the same help.
func _set_shared_tooltip(controls: Array, tooltip: String) -> void:
	for control_value in controls:
		var control := control_value as Control
		if control != null:
			control.tooltip_text = _wrap_tooltip(tooltip)

# Inserts explicit line breaks into native Godot tooltips so long descriptions
# stay readable instead of stretching across most of the editor window.
func _wrap_tooltip(text: String, max_columns: int = TOOLTIP_WRAP_COLUMNS) -> String:
	if text.is_empty() or max_columns <= 0:
		return text
	var result := PackedStringArray()
	for paragraph in text.split("\n", true):
		if paragraph.is_empty():
			result.append("")
			continue
		var line := ""
		for word in paragraph.split(" ", false):
			var candidate := str(word) if line.is_empty() else line + " " + str(word)
			if not line.is_empty() and candidate.length() > max_columns:
				result.append(line)
				line = str(word)
			else:
				line = candidate
		if not line.is_empty():
			result.append(line)
	return "\n".join(result)

# Handles the dialog's module-wide action buttons. Cache clearing has its own
# button in the cache section because the action belongs to those settings.
func _on_custom_action(action: StringName) -> void:
	match action:
		&"enable_all":
			_set_all(true)
		&"disable_all":
			_set_all(false)
