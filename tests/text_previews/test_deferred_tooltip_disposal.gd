extends SceneTree

# A native tooltip can disappear while the shared text preview is waiting for
# RichTextLabel layout. Passing its freed controls to typed functions used to
# report a Godot engine error on returning from a background application.
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var pipeline := Pipeline.new()
	var popup := PopupPanel.new()
	root.add_child(popup)
	var base := VBoxContainer.new()
	popup.add_child(base)
	var section := VBoxContainer.new()
	base.add_child(section)
	# Deferred work is deliberately allowed to begin before closing the popup.
	pipeline.call_deferred(
		"_finalize_live_text_section", weakref(section), weakref(base),
		weakref(popup), "text_file_preview", "res://test.txt", {}
	)
	await process_frame
	popup.queue_free()
	for _frame in range(5):
		await process_frame
	print("Deferred tooltip disposal: PASS")
	quit(0)
