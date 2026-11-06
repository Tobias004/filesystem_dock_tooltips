extends SceneTree

# Code Editor tooltip windows are already owned by Godot (native help bits) or
# by the Code Editor fallback lifetime manager. The shared live-text pipeline
# must leave the host's children where they are, even when a GDScript source
# preview is added to a preload()/load() symbol.
const Pipeline := preload("res://addons/better_tooltips/core/tooltip_pipeline.gd")
const CodeDocumentation := preload("res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var code_documentation := CodeDocumentation.new()
    if code_documentation == null:
        push_error("Code Editor integration could not be instantiated.")
        quit(1)
        return
    var popup := PopupPanel.new()
    root.add_child(popup)
    var base := VBoxContainer.new()
    popup.add_child(base)
    var section := VBoxContainer.new()
    base.add_child(section)
    var pipeline := Pipeline.new() as BTTooltipPipeline
    pipeline._promote_live_text_tooltip(
        "script_documentation",
        "res://addons/better_tooltips/core/tooltip_cache.gd",
        {"source": "code_editor", "host_manages_popup": true},
        section, base, popup
    )
    if section.get_parent() != base or base.get_parent() != popup:
        push_error("Host-owned tooltip controls were reparented.")
        quit(1)
        return
    var source := FileAccess.get_file_as_string(
        "res://addons/better_tooltips/modules/code_editor_documentation_tooltip.gd"
    )
    # The two native branches now use one shared helper, while the fallback
    # keeps its own host-owned popup. Both must still refuse reparenting.
    if source.count('"host_manages_popup": true') != 2 or source.count('_append_native_resource_preview(') != 3:
        push_error("Native and fallback previews must retain their popup ownership.")
        quit(1)
        return
    popup.queue_free()
    print("Code Editor live-popup ownership test: PASS")
    quit(0)
