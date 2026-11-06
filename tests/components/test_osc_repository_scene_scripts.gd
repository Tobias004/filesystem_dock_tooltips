extends SceneTree

## OSC-derived fixture class headers were checked against Tobias004/OSC-private
## dev at commit 3ed4e38423c85b2cd80b0f5e7f55728e045c0649.
## The full OSC gameplay code is intentionally not duplicated in this test repo.
const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const Parser := preload("res://addons/better_tooltips/core/gdscript_documentation_parser.gd")
const Bridge := preload("res://addons/better_tooltips/modules/scene_component_tooltip.gd")
const MainScript := preload("res://tests/components/osc_repo_main.gd")
const CockpitScript := preload("res://tests/components/osc_repo_cockpit_view.gd")
const HUDScript := preload("res://tests/components/osc_repo_hud.gd")
const PlainScript := preload("res://tests/components/osc_repo_plain_script.gd")
const BareScript := preload("res://tests/components/osc_repo_no_docs.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _popup_text(bridge: RefCounted) -> String:
	if bridge._popup == null:
		return ""
	var label := bridge._popup.find_child("ComponentDocumentation", true, false) as RichTextLabel
	return label.get_parsed_text() if label != null else ""

func _run() -> void:
	var unnamed: Dictionary = Parser.find_script_documentation((MainScript as Script).source_code)
	check(str(unnamed.get("description", "")).contains("composition root"), "Unnamed OSC main class description missing")
	check(str(unnamed.get("implementation_notes", "")).contains("No COMPONENT_CONTRACT"), "Unnamed OSC main architecture notes missing")
	for case: Dictionary in [
		{"path": "res://tests/components/scenes/osc_repo_main.tscn", "title": "osc_repo_main.gd", "text": "not a reusable child"},
		{"path": "res://tests/components/scenes/osc_repo_cockpit_view.tscn", "title": "BTOSCCockpitViewFixture", "text": "No COMPONENT_CONTRACT yet"},
		{"path": "res://tests/components/scenes/osc_repo_hud.tscn", "title": "BTOSCHUDFixture", "text": "owners must not connect"},
	]:
		var scene_doc := Reader.for_path(str(case.path))
		check(not scene_doc.is_empty(), "OSC-derived file scene missing documentation: " + str(case.path))
		check(str(scene_doc.get("implementation_notes", "")).contains(str(case.text)), "OSC-derived file scene lost architecture notes: " + str(case.path))
	var no_contract_doc := Reader.for_scene_script(CockpitScript, false, true)
	check(str(no_contract_doc.get("description", "")).contains("passive cockpit"), "OSC cockpit primary text missing")
	check(str(no_contract_doc.get("implementation_notes", "")).contains("No COMPONENT_CONTRACT yet"), "OSC cockpit absence of contract missing")
	check(not bool(no_contract_doc.get("has_contract", true)), "OSC cockpit is not a component")
	var main_doc := Reader.for_scene_script(MainScript, false, true)
	check(bool(main_doc.get("script_only_title", false)), "Unnamed OSC main should use Script title")
	var contract := Reader.for_scene_script(HUDScript, true, true)
	check(bool(contract.get("has_contract", false)) and (contract.get("properties", []) as Array).size() >= 2, "OSC HUD opt-in contract details missing")
	var hidden_contract := Reader.for_scene_script(HUDScript, false, true)
	check(not bool(hidden_contract.get("has_contract", true)), "Disabled contract module must hide contract API details")
	check(str(hidden_contract.get("implementation_notes", "")).contains("Telemetry Source"), "Contract script ordinary docs still expected")
	check(Reader.for_scene_script(HUDScript, false, false).is_empty(), "Both disabled modules should produce no scene tooltip")
	check(not Reader.for_scene_script(CockpitScript, true, false).is_empty(), "Notes-only scenes should remain available with component module")
	check(str(Reader.for_scene_script(PlainScript, false, true).get("description", "")).contains("normal class description"), "Plain non-contract documentation missing")
	check(not Reader.for_scene_script(BareScript, false, true).is_empty(), "Undocumented attached script should still show its script identity")

	var tree := Tree.new()
	EditorInterface.get_base_control().add_child(tree)
	var item := tree.create_item()
	item.set_tooltip_text(0, "Native OSC scene description")
	var node: Node = CockpitScript.new()
	root.add_child(node)
	var bridge := Bridge.new()
	bridge.set_documentation_modes(false, true)
	bridge.update_item(item, node)
	await process_frame
	await process_frame
	check(_popup_text(bridge).contains("Class: BTOSCCockpitViewFixture"), "Non-contract OSC class must appear in Scene dock")
	check(_popup_text(bridge).contains("Implementation notes"), "Scene dock should display architecture notes separately")
	check(_popup_text(bridge).contains("No COMPONENT_CONTRACT yet"), "Scene dock should explain missing contract")
	check(item.get_tooltip_text(0).is_empty(), "Native OSC tooltip should be suppressed only during enhanced view")
	bridge.set_documentation_modes(false, false)
	check(item.get_tooltip_text(0) == "Native OSC scene description", "Original OSC tooltip must be restored when disabled")
	bridge.cleanup()
	node.free()
	tree.free()
	if failures.is_empty():
		print("OSC repository-derived scene scripts, contracts and toggles: PASS")
	for error in failures:
		push_error(error)
	quit(0 if failures.is_empty() else 1)
