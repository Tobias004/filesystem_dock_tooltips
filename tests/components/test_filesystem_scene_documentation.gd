extends SceneTree

## Targeted FileSystem Scene-dock documentation regression: plain root scripts,
## architecture notes, optional contract mode and the theme-aware member insets.
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")
const ScriptPreview := preload("res://addons/better_tooltips/modules/script_documentation_tooltip.gd")
const ComponentPreview := preload("res://addons/better_tooltips/modules/component_documentation_tooltip.gd")
const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _text(base: Control, node_name: String) -> String:
	var label := base.find_child(node_name, true, false) as RichTextLabel
	return label.get_parsed_text() if label != null else ""

func _run() -> void:
	var prior_contracts := Settings.is_module_enabled(Settings.MODULE_COMPONENT_DOCUMENTATION)
	var prior_docs := Settings.is_module_enabled(Settings.MODULE_SCRIPT_DOCUMENTATION)
	var script_module := ScriptPreview.new()
	var component_module := ComponentPreview.new()
	check(script_module._handles("PackedScene"), "Script module must handle scene resources")
	check(script_module._handles("GDScript"), "Script module must still handle scripts")
	var main := "res://tests/components/scenes/osc_repo_main.tscn"
	var cockpit := "res://tests/components/scenes/osc_repo_cockpit_view.tscn"
	var hud := "res://tests/components/scenes/osc_repo_hud.tscn"
	Settings.set_module_enabled(Settings.MODULE_SCRIPT_DOCUMENTATION, true)
	Settings.set_module_enabled(Settings.MODULE_COMPONENT_DOCUMENTATION, false)
	for path in [main, cockpit, hud]:
		var base := VBoxContainer.new()
		script_module._make_tooltip_for_path(path, {}, base)
		var text := _text(base, "ScriptDocumentation")
		check(not text.is_empty(), "Scene root script documentation missing: " + path)
		check(text.contains("Implementation notes"), "Architecture notes missing from scene: " + path)
		base.free()
	var main_base := VBoxContainer.new()
	script_module._make_tooltip_for_path(main, {}, main_base)
	var first_label := main_base.find_child("ScriptDocumentation", true, false) as RichTextLabel
	check(first_label != null and _text(main_base, "ScriptDocumentation").contains("No COMPONENT_CONTRACT"), "Unregistered root script should retain implementation notes")
	main_base.free()
	Settings.set_module_enabled(Settings.MODULE_COMPONENT_DOCUMENTATION, true)
	var contracted_base := VBoxContainer.new()
	script_module._make_tooltip_for_path(hud, {}, contracted_base)
	check(_text(contracted_base, "ScriptDocumentation").is_empty(), "Contracted scene must not duplicate script documentation")
	component_module._make_tooltip_for_path(hud, {}, contracted_base)
	var contracted_text := _text(contracted_base, "ComponentDocumentation")
	check(contracted_text.contains("Required") and contracted_text.contains("Telemetry Source"), "Component reference lost required dependency details")
	check(contracted_text.contains("Implementation notes"), "Contract architecture notes missing")
	contracted_base.free()
	var noncontract_base := VBoxContainer.new()
	script_module._make_tooltip_for_path(cockpit, {}, noncontract_base)
	component_module._make_tooltip_for_path(cockpit, {}, noncontract_base)
	check(_text(noncontract_base, "ScriptDocumentation").contains("No COMPONENT_CONTRACT"), "Non-contract script documentation missing when components enabled")
	check(_text(noncontract_base, "ComponentDocumentation").is_empty(), "Non-contract scene documentation duplicated")
	noncontract_base.free()
	var standard_base := VBoxContainer.new()
	var script_path := "res://tests/components/osc_repo_plain_script.gd"
	script_module._make_tooltip_for_path(script_path, {}, standard_base)
	check(_text(standard_base, "ScriptDocumentation").contains("normal class description"), "Existing script tooltip behavior changed")
	standard_base.free()
	var fixture := Reader.for_path("res://tests/components/scenes/component_root.tscn")
	var component_label := ComponentPreview.create_content(fixture) as RichTextLabel
	check(component_label != null, "Rich contract presentation missing")
	if component_label != null:
		check(component_label.get_parsed_text().contains("Required"), "Contract fields missing from inset presentation")
		check(component_label.get_parsed_text().contains("Required read-only data source"), "Member description missing from inset presentation")
		check(component_label.get_parsed_text().contains("Emitted signals"), "Contract signal section missing")
		check(component_label.get_parsed_text().contains("Documented public methods"), "Contract method section missing")
		component_label.free()
	var help := FileAccess.get_file_as_string("res://addons/better_tooltips/COMPONENT_DOCUMENTATION_HELP.txt")
	check(help.contains("exact Godot BBCode block") and help.contains("No extra BBCode"), "Help does not explain the line formatting")
	Settings.set_module_enabled(Settings.MODULE_COMPONENT_DOCUMENTATION, prior_contracts)
	Settings.set_module_enabled(Settings.MODULE_SCRIPT_DOCUMENTATION, prior_docs)
	script_module.cleanup()
	if failures.is_empty():
		print("Scene FileSystem docs, contract insets and local help: PASS")
	for message in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)
