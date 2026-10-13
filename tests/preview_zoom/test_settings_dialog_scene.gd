extends SceneTree

func _initialize() -> void:
	var scene := load("res://addons/better_tooltips/settings_dialog.tscn") as PackedScene
	if scene == null:
		push_error("Settings dialog scene failed to load.")
		quit(1)
		return
	var dialog := scene.instantiate()
	if dialog == null:
		push_error("Settings dialog scene failed to instantiate.")
		quit(1)
		return
	root.add_child(dialog)
	var size_spin := dialog.get_node_or_null("MarginContainer/Columns/PreviewColumn/PreviewSizeRow/spnPreviewSize") as SpinBox
	if size_spin == null:
		push_error("Default preview-size SpinBox is missing.")
		quit(1)
		return
	print("Settings dialog preview-size control: PASS")
	dialog.queue_free()
	quit(0)
