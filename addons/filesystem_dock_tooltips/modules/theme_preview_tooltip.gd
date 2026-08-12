@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Theme"
const PREVIEW_WIDTH := 430.0
const PREVIEW_HEIGHT := 245.0
const PREVIEW_MARGIN := 8

func _handles(type: String) -> bool:
	return type == "Theme"

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var theme := _load_theme(path)
	if theme == null:
		return base
	var scale := EditorInterface.get_editor_scale()
	var width := maxi(2, roundi(PREVIEW_WIDTH * scale))
	var height := maxi(2, roundi(PREVIEW_HEIGHT * scale))
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
	# Isolate custom theme minimum sizes from the tooltip's own layout.
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(width, height)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var panel := PanelContainer.new()
	panel.position = Vector2(0, 0)
	panel.size = Vector2(width, height)
	panel.theme = theme
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(panel)
	var margin_box := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin_box.add_theme_constant_override("margin_" + side, roundi(12 * scale))
	panel.add_child(margin_box)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_box.add_child(content)
	var heading := Label.new()
	heading.text = "Theme Preview"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(heading)
	var row := HBoxContainer.new()
	content.add_child(row)
	var button := Button.new()
	button.text = "Button"
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(button)
	var check := CheckBox.new()
	check.text = "Check box"
	check.button_pressed = true
	check.focus_mode = Control.FOCUS_NONE
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(check)
	var edit := LineEdit.new()
	edit.text = "Text field"
	edit.editable = false
	edit.focus_mode = Control.FOCUS_NONE
	edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(edit)
	var progress := ProgressBar.new()
	progress.value = 67.0
	progress.show_percentage = true
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(progress)
	var slider := HSlider.new()
	slider.value = 62.0
	slider.editable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(slider)
	base.add_child(HSeparator.new())
	base.add_child(outer)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_theme(path: String) -> Theme:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as Theme
