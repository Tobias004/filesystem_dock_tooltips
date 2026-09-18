@tool
extends AcceptDialog

signal module_setting_changed(module_id: String, enabled: bool)

const Settings := preload("res://addons/filesystem_dock_tooltips/tooltip_settings.gd")

var _checkboxes: Dictionary = {}

func _ready() -> void:
	_checkboxes = {
		Settings.MODULE_SCRIPT_DOCUMENTATION: $MarginContainer/VBoxContainer/chkbGdscriptDoc,
		Settings.MODULE_MATERIAL_PREVIEW: $MarginContainer/VBoxContainer/chkbMaterials,
		Settings.MODULE_MESH_PREVIEW: $MarginContainer/VBoxContainer/chkbMeshes,
		Settings.MODULE_FONT_PREVIEW: $MarginContainer/VBoxContainer/chkbFonts,
		Settings.MODULE_SHADER_PREVIEW: $MarginContainer/VBoxContainer/chkbShaders,
		Settings.MODULE_SPRITE_FRAMES_PREVIEW: $MarginContainer/VBoxContainer/chkbSpriteFrames,
		Settings.MODULE_THEME_PREVIEW: $MarginContainer/VBoxContainer/chkbThemes,
		Settings.MODULE_STYLEBOX_PREVIEW: $MarginContainer/VBoxContainer/chkbStyleBoxes,
		Settings.MODULE_CURVE_PREVIEW: $MarginContainer/VBoxContainer/chkbCurves,
		Settings.MODULE_GRADIENT_PREVIEW: $MarginContainer/VBoxContainer/chkbGradients,
		Settings.MODULE_ENVIRONMENT_PREVIEW: $MarginContainer/VBoxContainer/chkbEnvironments,
		Settings.MODULE_SKY_PREVIEW: $MarginContainer/VBoxContainer/chkbSkies,
	}
	for module_id in _checkboxes:
		var checkbox := _checkboxes[module_id] as CheckBox
		checkbox.toggled.connect(_on_checkbox_toggled.bind(module_id))
	ok_button_text = "Close"
	add_button("Enable All", false, "enable_all")
	add_button("Disable All", false, "disable_all")
	custom_action.connect(_on_custom_action)	
	refresh()

func refresh() -> void:
	if _checkboxes.is_empty():
		return
	for module_id in _checkboxes:
		var checkbox := _checkboxes[module_id] as CheckBox
		checkbox.set_pressed_no_signal(Settings.is_module_enabled(module_id))

func _on_checkbox_toggled(enabled: bool, module_id: String) -> void:
	Settings.set_module_enabled(module_id, enabled)
	module_setting_changed.emit(module_id, enabled)

func _set_all(enabled: bool) -> void:
	for module_id in _checkboxes:
		var checkbox := _checkboxes[module_id] as CheckBox
		if checkbox.button_pressed == enabled:
			continue
		checkbox.set_pressed_no_signal(enabled)
		Settings.set_module_enabled(module_id, enabled)
		module_setting_changed.emit(module_id, enabled)

func _on_custom_action(action: StringName) -> void:
	match action:
		&"enable_all":
			_set_all(true)
		&"disable_all":
			_set_all(false)
