@tool
extends EditorResourceTooltipPlugin

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")
const MODULE := "SpriteFrames"
const MAX_ANIMATIONS := 4
const MAX_FRAMES_PER_ANIMATION := 6
const FRAME_SIZE := 56.0
const PREVIEW_MARGIN := 8


func _handles(type: String) -> bool:
	return type == "SpriteFrames"


func _make_tooltip_for_path(
	path: String,
	_metadata: Dictionary,
	base: Control
) -> Control:
	var frames := _load_frames(path)
	if frames == null:
		return base

	var names := frames.get_animation_names()
	if names.is_empty():
		return base

	var scale := EditorInterface.get_editor_scale()
	var margin := roundi(PREVIEW_MARGIN * scale)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, margin)

	var content := VBoxContainer.new()
	outer.add_child(content)

	var shown_animations := 0
	for animation_name in names:
		if shown_animations >= MAX_ANIMATIONS:
			break

		var frame_count := frames.get_frame_count(animation_name)
		if frame_count <= 0:
			continue

		var header := Label.new()
		header.text = "%s  —  %d frames @ %.1f FPS" % [
			String(animation_name),
			frame_count,
			frames.get_animation_speed(animation_name)
		]
		content.add_child(header)

		var row := HBoxContainer.new()
		content.add_child(row)

		var shown_frames: int = mini(frame_count, MAX_FRAMES_PER_ANIMATION)
		for frame_index in range(shown_frames):
			var texture := frames.get_frame_texture(
				animation_name,
				frame_index
			)
			if texture == null:
				continue

			var rect := TextureRect.new()
			rect.custom_minimum_size = Vector2(
				FRAME_SIZE * scale,
				FRAME_SIZE * scale
			)
			rect.texture = texture
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(rect)

		if frame_count > MAX_FRAMES_PER_ANIMATION:
			var more := Label.new()
			more.text = "+%d" % (frame_count - MAX_FRAMES_PER_ANIMATION)
			row.add_child(more)

		shown_animations += 1

	if shown_animations == 0:
		return base

	if names.size() > shown_animations:
		var more_animations := Label.new()
		more_animations.text = "+%d more animations" % (
			names.size() - shown_animations
		)
		content.add_child(more_animations)

	base.add_child(HSeparator.new())
	base.add_child(outer)
	Debug.log(MODULE, "preview added: " + path)
	return base


func _load_frames(path: String) -> SpriteFrames:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.get_cached_ref(path)
	if resource == null:
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource as SpriteFrames
