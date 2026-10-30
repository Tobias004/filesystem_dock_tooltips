@tool
class_name BTTooltipPresenter
extends RefCounted

## Stateless presentation helpers shared by Better Tooltips preview pipelines.
## Owns preview/status section construction and tooltip relayout/clamping only;
## it does not decide when a tooltip opens or closes and keeps no hover state.

const TooltipCache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const TooltipAppearance := preload("res://addons/better_tooltips/core/tooltip_appearance.gd")

const STATUS_WIDTH := 360.0
const PREVIEW_FRAME_NAME := &"PreviewFrame"
const PREVIEW_TEXTURE_NAME := &"PreviewTexture"

func create_section(base: Control) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(HSeparator.new())
	var background_panel := PanelContainer.new()
	background_panel.name = "Background"
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TooltipAppearance.style_graphical_preview_panel(background_panel)
	section.add_child(background_panel)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_panel.add_child(body)
	base.add_child(section)
	return section

func create_status_section(base: Control, message: String) -> VBoxContainer:
	var section := create_section(base)
	set_section_text(section, message)
	return section

func set_section_preview(section: VBoxContainer, entry: Dictionary) -> void:
	if not is_instance_valid(section):
		return
	var texture := entry.get("texture", null) as Texture2D
	var size_value: Variant = entry.get("size", Vector2i.ZERO)
	if texture == null or not (size_value is Vector2i):
		set_section_text(section, "Preview could not be displayed.")
		return
	var background_panel := section.get_node_or_null("Background") as PanelContainer
	var body := section.get_node_or_null("Background/Body") as VBoxContainer
	if background_panel == null or body == null:
		return
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	background_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	free_children(body)
	var size := size_value as Vector2i
	var frame := MarginContainer.new()
	frame.name = PREVIEW_FRAME_NAME
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame_padding := roundi(
		TooltipAppearance.GRAPHICAL_PREVIEW_PADDING * EditorInterface.get_editor_scale()
	)
	for side: String in ["left", "top", "right", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, frame_padding)
	body.add_child(frame)
	var rect := TextureRect.new()
	rect.name = PREVIEW_TEXTURE_NAME
	rect.custom_minimum_size = Vector2(size.x, size.y)
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(rect)
	section.reset_size()

func set_section_text(section: VBoxContainer, message: String) -> void:
	if not is_instance_valid(section):
		return
	var body := section.get_node_or_null("Background/Body") as VBoxContainer
	if body == null:
		return
	free_children(body)
	var label := Label.new()
	var scale := EditorInterface.get_editor_scale()
	label.custom_minimum_size = Vector2(STATUS_WIDTH * scale, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = message
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(label)
	section.reset_size()

func set_section_failure(
	section: VBoxContainer,
	status: String,
	safety_limit_ms: int,
	elapsed_ms: int
) -> void:
	if status == TooltipCache.STATUS_SAFETY_LIMIT:
		var measured := ""
		if elapsed_ms > 0:
			measured = " Work had reached about %d ms." % elapsed_ms
		set_section_text(
			section,
			"Preview stopped at the %d ms safety limit.%s\nHold Shift while hovering to force regeneration without the safety limit." % [
				safety_limit_ms,
				measured,
			]
		)
		return
	set_section_text(section, "Preview could not be generated.")

func generating_text(module_entry: Dictionary) -> String:
	var module_name := String(module_entry.get("name", "Preview"))
	return "Generating %s preview..." % module_name.to_lower()

func remove_generated_separators(container: Control) -> void:
	for child in container.get_children():
		if child is HSeparator:
			container.remove_child(child)
			child.free()

func free_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()

func refresh_tooltip_layout(base: Control, resize_target: Node = null) -> void:
	var effective_target := resolve_tooltip_resize_target(base, resize_target)
	_refresh_tooltip_layout_pass(base, effective_target)
	var base_ref: WeakRef = weakref(base) if is_instance_valid(base) else null
	var target_ref: WeakRef = weakref(effective_target) if is_instance_valid(effective_target) else null
	call_deferred("_refresh_tooltip_layout_deferred", base_ref, target_ref)

func _refresh_tooltip_layout_deferred(base_ref: WeakRef, target_ref: WeakRef) -> void:
	var base := base_ref.get_ref() as Control if base_ref != null else null
	var requested_target := target_ref.get_ref() as Node if target_ref != null else null
	var resize_target := resolve_tooltip_resize_target(base, requested_target)
	_refresh_tooltip_layout_pass(base, resize_target)

func _refresh_tooltip_layout_pass(base: Control, resize_target: Node = null) -> void:
	if is_instance_valid(base):
		base.update_minimum_size()
		base.reset_size()
		if base.has_method("queue_sort"):
			base.call("queue_sort")
	if not is_instance_valid(resize_target) or resize_target == base:
		return
	if resize_target is Control:
		var resize_control := resize_target as Control
		resize_control.update_minimum_size()
		resize_control.reset_size()
		if resize_control.has_method("queue_sort"):
			resize_control.call("queue_sort")
	elif resize_target.has_method("reset_size"):
		resize_target.call("reset_size")
	clamp_resize_target_to_screen(resize_target)

func resolve_tooltip_resize_target(base: Control, requested_target: Node) -> Node:
	if requested_target is Window:
		return requested_target
	var current: Node = base
	while is_instance_valid(current):
		if current is PopupPanel:
			return current
		current = current.get_parent()
	return requested_target if is_instance_valid(requested_target) else base

func clamp_resize_target_to_screen(resize_target: Node) -> void:
	var window := resize_target as Window
	if window == null:
		return
	var size: Vector2i = window.size
	if size.x <= 0 or size.y <= 0:
		return
	var screen := window.current_screen
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var max_x := usable_rect.position.x + maxi(0, usable_rect.size.x - size.x)
	var max_y := usable_rect.position.y + maxi(0, usable_rect.size.y - size.y)
	window.position = Vector2i(
		clampi(window.position.x, usable_rect.position.x, max_x),
		clampi(window.position.y, usable_rect.position.y, max_y)
	)
