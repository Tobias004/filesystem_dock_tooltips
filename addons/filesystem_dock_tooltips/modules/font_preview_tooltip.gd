@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "Font"
const PREVIEW_WIDTH := 460.0
const MARGIN := 10

func _handles(type: String) -> bool:
	return ClassDB.class_exists(type) and ClassDB.is_parent_class(type, "Font")

func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var font := _load_font(path)
	if font == null:
		return base
	var scale := EditorInterface.get_editor_scale()
	var width := PREVIEW_WIDTH * scale
	var margin := roundi(MARGIN * scale)
	var outer := MarginContainer.new()
	outer.custom_minimum_size.x = width
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = width
	outer.add_child(content)
	var large := Label.new()
	large.text = "Aa Bb Cc  0123456789"
	large.add_theme_font_override("font", font)
	large.add_theme_font_size_override("font_size", roundi(26 * scale))
	large.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(large)
	var sample := Label.new()
	sample.text = "The quick brown fox jumps over the lazy dog."
	sample.add_theme_font_override("font", font)
	sample.add_theme_font_size_override("font_size", roundi(18 * scale))
	sample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sample.custom_minimum_size.x = width
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(sample)
	var symbols := Label.new()
	symbols.text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n!? @#& () [] {} +-*/"
	symbols.add_theme_font_override("font", font)
	symbols.add_theme_font_size_override("font_size", roundi(15 * scale))
	symbols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(symbols)
	base.add_child(HSeparator.new())
	base.add_child(outer)
	Debug.log(MODULE, "preview added: " + path)
	return base

func _load_font(path: String) -> Font:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as Font
