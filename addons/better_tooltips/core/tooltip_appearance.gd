@tool
extends RefCounted

## Central theme-aware appearance helper for content added by this add-on.
## It starts from Godot's current tooltip style and changes only the background
## brightness, preserving native content margins when a reference style is used.

const Settings := preload(
	"res://addons/better_tooltips/tooltip_settings.gd"
)

const TOOLTIP_PANEL_THEME_TYPE := &"TooltipPanel"
const TOOLTIP_PANEL_STYLEBOX := &"panel"
const GRAPHICAL_PREVIEW_PADDING := 8.0
const MAX_TEXT_HEIGHT_SCREEN_FRACTION := 0.85
const MAX_TEXT_WIDTH_SCREEN_FRACTION := 0.90

# Applies the configured add-on contrast to an ordinary panel while otherwise
# keeping Godot's current TooltipPanel style. Existing child layout is untouched.
static func style_addon_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override(
		"panel",
		make_contrasted_stylebox(_get_tooltip_panel_stylebox())
	)

# Applies the configured add-on contrast to a RichTextLabel while copying the
# supplied native style's content margins. This lets injected Code Editor help
# use exactly the same 8/4/8/4-style inset that Godot's own help content uses.
static func style_addon_rich_text(
	label: RichTextLabel,
	reference_style: StyleBox
) -> void:
	if label == null:
		return
	var style := make_contrasted_stylebox(reference_style)
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_stylebox_override("focused", style)

# Duplicates a native StyleBoxFlat whenever possible so borders, corner radii
# and content margins remain native. Non-flat styles fall back to a flat tooltip
# background while retaining their content margins.
static func make_contrasted_stylebox(reference_style: StyleBox = null) -> StyleBoxFlat:
	var source := reference_style
	if source == null:
		source = _get_tooltip_panel_stylebox()
	var result: StyleBoxFlat = null
	if source is StyleBoxFlat:
		result = (source as StyleBoxFlat).duplicate() as StyleBoxFlat
	else:
		result = StyleBoxFlat.new()
		if source != null:
			_copy_content_margins(result, source)
		var tooltip_style := _get_tooltip_panel_stylebox()
		if tooltip_style is StyleBoxFlat:
			result.bg_color = (tooltip_style as StyleBoxFlat).bg_color
	result.bg_color = adjust_background_color(result.bg_color)
	return result

# Moves a dark tooltip background toward white and a light tooltip background
# toward black by the configured percentage. Alpha is preserved unchanged.
static func adjust_background_color(background: Color) -> Color:
	var amount := (
		float(Settings.get_tooltip_background_contrast_percent()) / 100.0
	)
	if amount <= 0.0:
		return background
	var target := Color.WHITE if background.get_luminance() < 0.5 else Color.BLACK
	var adjusted := background.lerp(target, amount)
	adjusted.a = background.a
	return adjusted

# Applies the add-on tooltip background to a graphical preview panel but removes
# inherited content margins. The preview pipeline owns one explicit symmetric
# MarginContainer around every image, so native asymmetric/default margins cannot
# make FileSystem and Code Editor previews look different.
static func style_graphical_preview_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	var style := make_contrasted_stylebox(_get_tooltip_panel_stylebox())
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	panel.add_theme_stylebox_override("panel", style)

# Caps the outer dimensions of text-only content. This must not be used for
# graphical previews, which retain their separate scale and wheel behavior.
static func get_text_max_width_pixels() -> float:
	var scale := EditorInterface.get_editor_scale()
	var screen := _editor_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var max_width := float(Settings.get_text_max_width()) * scale
	if usable.size.x > 0:
		max_width = minf(max_width, usable.size.x * MAX_TEXT_WIDTH_SCREEN_FRACTION)
	return maxf(120.0 * scale, max_width)

static func get_text_max_height_pixels() -> float:
	var scale := EditorInterface.get_editor_scale()
	var usable := DisplayServer.screen_get_usable_rect(_editor_screen())
	var max_height := float(Settings.get_text_max_height()) * scale
	if usable.size.y > 0:
		max_height = minf(max_height, usable.size.y * MAX_TEXT_HEIGHT_SCREEN_FRACTION)
	return maxf(80.0 * scale, max_height)

# A PopupPanel's Window.size may be stale while it is hidden. The Control
# contents have already measured their minimum size after layout frames, so
# use the larger of the two before choosing which side of the cursor can fit.
# The caller must then use popup(Rect2i(position, prepared_size)) to open it
# without exposing an initial, too-small window that is moved on the next frame.
static func prepared_text_popup_size(popup: PopupPanel) -> Vector2i:
	if popup == null:
		return Vector2i.ZERO
	popup.reset_size()
	var content := popup.get_contents_minimum_size()
	return Vector2i(
		maxi(popup.size.x, ceili(content.x)),
		maxi(popup.size.y, ceili(content.y))
	)

static func text_content_width(desired_width: float) -> float:
	return minf(desired_width, get_text_max_width_pixels() - 24.0 * EditorInterface.get_editor_scale())

static func _editor_screen() -> int:
	var editor_window := EditorInterface.get_base_control().get_window()
	if editor_window != null and editor_window.current_screen >= 0:
		return editor_window.current_screen
	return DisplayServer.get_primary_screen()

# Limits long add-on documentation blocks to a readable fraction of the current
# screen. Short text keeps fit_content semantics; only genuinely tall text turns
# into its own vertically scrollable RichTextLabel. Graphical preview sections are
# never routed through this helper and therefore never become scrollable.
static func limit_rich_text_height(label: RichTextLabel) -> void:
	if label == null:
		return
	_apply_rich_text_height_limit(label)
	# RichTextLabel reports content height as zero until its first layout pass.
	# Re-check once on the next frame so freshly created tooltip documentation is
	# bounded without requiring every caller to own an extra deferred callback.
	if label.is_inside_tree() and not label.has_meta("_bt_text_height_limit_pending"):
		label.set_meta("_bt_text_height_limit_pending", true)
		var callback: Callable = func() -> void:
			if not is_instance_valid(label):
				return
			label.remove_meta("_bt_text_height_limit_pending")
			_apply_rich_text_height_limit(label)
		label.get_tree().process_frame.connect(callback, CONNECT_ONE_SHOT)

static func _apply_rich_text_height_limit(label: RichTextLabel) -> void:
	if label == null:
		return
	var maximum_height := maxf(65.0 * EditorInterface.get_editor_scale(),
		get_text_max_height_pixels() - 95.0 * EditorInterface.get_editor_scale())
	var content_height := float(label.get_content_height())
	if content_height <= 0.0:
		return
	if content_height <= maximum_height:
		label.fit_content = true
		label.scroll_active = false
		label.custom_minimum_size.y = 0.0
		# Short Markdown previews still contain clickable hyperlinks.
		label.mouse_filter = (Control.MOUSE_FILTER_STOP if label.has_meta("_bt_interactive_links") else Control.MOUSE_FILTER_IGNORE)
		label.update_minimum_size()
		return
	label.fit_content = false
	label.scroll_active = true
	label.custom_minimum_size.y = maximum_height
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.update_minimum_size()

# Resolves the current Godot TooltipPanel style instead of hard-coding colors,
# so theme changes and custom editor themes remain the source of truth.
static func _get_tooltip_panel_stylebox() -> StyleBox:
	var theme := EditorInterface.get_editor_theme()
	if (
		theme != null
		and theme.has_stylebox(TOOLTIP_PANEL_STYLEBOX, TOOLTIP_PANEL_THEME_TYPE)
	):
		return theme.get_stylebox(
			TOOLTIP_PANEL_STYLEBOX,
			TOOLTIP_PANEL_THEME_TYPE
		)
	return StyleBoxFlat.new()

# Copies only layout-relevant margins when a non-flat reference style needs a
# flat replacement. Negative/default values are left to Godot as zero margins.
static func _copy_content_margins(target: StyleBoxFlat, source: StyleBox) -> void:
	target.content_margin_left = maxf(0.0, source.get_content_margin(SIDE_LEFT))
	target.content_margin_top = maxf(0.0, source.get_content_margin(SIDE_TOP))
	target.content_margin_right = maxf(0.0, source.get_content_margin(SIDE_RIGHT))
	target.content_margin_bottom = maxf(0.0, source.get_content_margin(SIDE_BOTTOM))
