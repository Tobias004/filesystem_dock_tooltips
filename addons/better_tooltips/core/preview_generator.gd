@tool
class_name BTPreviewGenerator
extends Node

## Isolated renderer for generated graphical tooltip previews.
## Resource-specific modules still build their own Controls; this component owns
## temporary SubViewport capture, safety checks and cancellation checkpoints.

const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const TooltipCache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")

const STATUS_READY := "READY"
const STATUS_NO_PREVIEW := "NO_PREVIEW"
const STATUS_CANCELLED := "CANCELLED"
const CAPTURE_RENDER_FRAMES := 2

func setup(parent: Node) -> void:
	name = "BTPreviewGenerator"
	if get_parent() == null and is_instance_valid(parent):
		parent.add_child(self)

func cleanup() -> void:
	if is_inside_tree():
		queue_free()

func generate(
	plugin: EditorResourceTooltipPlugin,
	path: String,
	metadata: Dictionary,
	safety_limit_ms: int,
	is_current: Callable
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if plugin == null:
		return _with_elapsed({"status": TooltipCache.STATUS_FAILED}, started_usec)
	var generated := VBoxContainer.new()
	generated.theme = EditorInterface.get_editor_theme()
	generated.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var result: Variant = plugin.call(
		"_make_tooltip_for_path",
		path,
		metadata,
		generated
	)
	_remove_generated_separators(generated)
	if result == null:
		generated.free()
		return _with_elapsed({"status": TooltipCache.STATUS_FAILED}, started_usec)
	if generated.get_child_count() == 0:
		generated.free()
		return _with_elapsed({"status": STATUS_NO_PREVIEW}, started_usec)
	if safety_limit_exceeded(started_usec, safety_limit_ms):
		generated.free()
		return _with_elapsed({"status": TooltipCache.STATUS_SAFETY_LIMIT}, started_usec)
	var capture := await _render_and_capture(
		generated,
		started_usec,
		safety_limit_ms,
		is_current
	)
	return _with_elapsed(capture, started_usec)

func _render_and_capture(
	content: Control,
	started_usec: int,
	safety_limit_ms: int,
	is_current: Callable
) -> Dictionary:
	if not is_inside_tree():
		content.free()
		return {"status": TooltipCache.STATUS_FAILED}
	content.theme = EditorInterface.get_editor_theme()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2, 2)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	content.position = Vector2.ZERO
	viewport.add_child(content)
	var tree := EditorInterface.get_base_control().get_tree()
	await tree.process_frame
	if not _call_is_current(is_current):
		viewport.queue_free()
		return {"status": STATUS_CANCELLED}
	content.reset_size()
	var minimum_size := content.get_combined_minimum_size()
	if minimum_size.x <= 0.0 or minimum_size.y <= 0.0:
		viewport.queue_free()
		return {"status": TooltipCache.STATUS_FAILED}
	var size := Vector2i(
		maxi(2, ceili(minimum_size.x)),
		maxi(2, ceili(minimum_size.y))
	)
	viewport.size = size
	content.position = Vector2.ZERO
	content.size = Vector2(size.x, size.y)
	for frame_index in range(CAPTURE_RENDER_FRAMES):
		RenderingServer.force_draw(false)
		await tree.process_frame
		if not _call_is_current(is_current):
			viewport.queue_free()
			return {"status": STATUS_CANCELLED}
		if (
			frame_index < CAPTURE_RENDER_FRAMES - 1
			and safety_limit_exceeded(started_usec, safety_limit_ms)
		):
			viewport.queue_free()
			return {"status": TooltipCache.STATUS_SAFETY_LIMIT}
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return {"status": TooltipCache.STATUS_FAILED}
	var texture := ImageTexture.create_from_image(image)
	viewport.queue_free()
	if texture == null:
		return {"status": TooltipCache.STATUS_FAILED}
	return {
		"status": STATUS_READY,
		"texture": texture,
		"image": image,
		"size": size,
	}

func _call_is_current(callback: Callable) -> bool:
	if not callback.is_valid():
		return true
	return bool(callback.call())

func _remove_generated_separators(container: Control) -> void:
	for child in container.get_children():
		if child is HSeparator:
			container.remove_child(child)
			child.free()

func _with_elapsed(result: Dictionary, started_usec: int) -> Dictionary:
	result["elapsed_ms"] = elapsed_ms(started_usec)
	return result

static func safety_limit_exceeded(started_usec: int, safety_limit_ms: int) -> bool:
	return (
		safety_limit_ms > 0
		and float(Time.get_ticks_usec() - started_usec) / 1000.0 >= float(safety_limit_ms)
	)

static func elapsed_ms(started_usec: int) -> int:
	return ceili(float(Time.get_ticks_usec() - started_usec) / 1000.0)
