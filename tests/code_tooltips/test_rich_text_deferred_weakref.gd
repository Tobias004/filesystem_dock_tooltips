@tool
extends SceneTree

const TooltipAppearance := preload("res://addons/better_tooltips/core/tooltip_appearance.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# A documentation popup can disappear before its next-frame size pass.
	# This must not leave a Callable with a freed Control capture.
	var freed_label := RichTextLabel.new()
	root.add_child(freed_label)
	freed_label.add_text("Transient documentation")
	TooltipAppearance.limit_rich_text_height(freed_label)
	freed_label.free()
	await process_frame
	await process_frame
	var existing_label := RichTextLabel.new()
	root.add_child(existing_label)
	existing_label.add_text("Surviving documentation")
	TooltipAppearance.limit_rich_text_height(existing_label)
	await process_frame
	if not is_instance_valid(existing_label):
		push_error("Surviving label invalidated unexpectedly")
		quit(1)
		return
	if existing_label.has_meta("_bt_text_height_limit_pending"):
		push_error("Next-frame height limit was not applied")
		quit(1)
		return
	existing_label.free()
	print("PASS test_rich_text_deferred_weakref")
	quit()
