extends SceneTree

## Regression coverage for BBCode extraction, notes-only class tooltips and
## representative OSC scenes (the actual OSC project sources were not provided).
const Parser := preload("res://addons/better_tooltips/core/gdscript_documentation_parser.gd")
const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const ScriptPreview := preload("res://addons/better_tooltips/modules/script_documentation_tooltip.gd")
const ComponentPreview := preload("res://addons/better_tooltips/modules/component_documentation_tooltip.gd")
const Renderer := preload("res://addons/better_tooltips/core/documentation_renderer.gd")
const WithContract := preload("res://tests/components/osc_with_contract.gd")
const WithoutContract := preload("res://tests/components/osc_without_contract.gd")

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func check(condition: bool, problem: String) -> void:
    if not condition:
        failures.append(problem)

func _run() -> void:
    var with_contract := Parser.find_member_documentation((WithContract as Script).source_code, "BTOSCWithContract", -1, true, false)
    check(str(with_contract.get("description", "")).contains("Routes OSC messages"), "OSC contract primary description missing")
    check(not str(with_contract.get("description", "")).contains("Implementation notes"), "Special note wrapper leaked into primary description")
    check(str(with_contract.get("implementation_notes", "")).contains("UDP layer"), "OSC contract implementation notes missing")
    check(str(with_contract.get("implementation_notes", "")).contains("[method Node.get_node]"), "BBCode inside notes damaged")
    var without_contract := Parser.find_member_documentation((WithoutContract as Script).source_code, "BTOSCWithoutContract", -1, true, false)
    check(str(without_contract.get("description", "")).contains("Converts OSC"), "Non-contract primary description missing")
    check(str(without_contract.get("implementation_notes", "")).contains("transport adapter"), "Non-contract architecture notes missing")

    var ordinary := Parser.parse_documentation(PackedStringArray([
        '## A regular [color=orange]color example[/color] and [b]bold[/b] markup.',
        '## [codeblock lang=gdscript]',
        '## var example = "[color=#888888][i]Implementation notes[/i][br]not a note[/color]"',
        '## [/codeblock]',
    ]))
    check(str(ordinary.get("implementation_notes", "")).is_empty(), "Parser must ignore note marker in literal code block")
    check(str(ordinary.get("description", "")).contains("[color=orange]"), "Ordinary color markup was modified")
    check(str(ordinary.get("description", "")).contains("not a note[/color]"), "Code block was modified")
    var unclosed := Parser.parse_documentation(PackedStringArray([
        '## Intro [color=#888888][i]Implementation notes[/i][br]unfinished',
    ]))
    check(str(unclosed.get("implementation_notes", "")).is_empty(), "Broken block must not be extracted")
    check(str(unclosed.get("description", "")).contains("[color=#888888]"), "Malformed block should stay native")
    var nested := Parser.parse_documentation(PackedStringArray([
        '## Normal behavior.',
        '## [color=#888888][i]Implementation notes[/i][br]Supports [color=green]colored[/color] details.[/color]',
        '## A final paragraph remains ordinary.',
    ]))
    check(str(nested.get("implementation_notes", "")).contains("[color=green]colored[/color]"), "Nested colors truncated notes")
    check(str(nested.get("description", "")).contains("A final paragraph"), "Content after note removed")
    check(not str(nested.get("description", "")).contains("Implementation notes"), "Notes not removed from primary text")

    var literals := Parser.parse_documentation(PackedStringArray([
        '## Normal description.',
        '## [color=#888888][i]Implementation notes[/i][br]Keep [code]a[/color] literal[/code] text safe.[/color]',
    ]))
    check(str(literals.get("implementation_notes", "")).contains("literal[/code]"), "Inline code with closing-color text truncated the notes")
    check(str(literals.get("description", "")).strip_edges() == "Normal description.", "Literal colors spilled into main description")

    var preview := ScriptPreview.new()
    var script_document := preview._read_script_documentation("res://tests/components/osc_without_contract.gd")
    check(str(script_document.get("implementation_notes", "")).contains("transport adapter"), "FileSystem script parser did not use shared extraction")
    preview.cleanup()

    var contract_document := Reader.for_script(WithContract)
    check(bool(contract_document.get("has_contract", false)), "OSC contract not recognized")
    check(str(contract_document.get("implementation_notes", "")).contains("UDP layer"), "Contract reflection dropped notes")
    check(str(contract_document.get("description", "")).contains("validated"), "Contract primary description lost")
    var notes_only_document := Reader.for_script(WithoutContract)
    check(not notes_only_document.is_empty(), "Non-contract OSC scene must show architecture notes")
    check(not bool(notes_only_document.get("has_contract", true)), "Non-contract script was misidentified as a component")
    check(str(notes_only_document.get("implementation_notes", "")).contains("routing script"), "Non-contract notes lost")
    var plain := GDScript.new()
    plain.source_code = "extends Node\n"
    check(plain.reload() == OK and Reader.for_script(plain).is_empty(), "Undocumented scripts must not gain a component tooltip")
    for scene_path in ["res://tests/components/scenes/osc_with_contract.tscn", "res://tests/components/scenes/osc_without_contract.tscn"]:
        var scene_document := Reader.for_path(scene_path)
        check(not scene_document.is_empty(), "OSC scene documentation missing: " + scene_path)
        check(str(scene_document.get("implementation_notes", "")).length() > 10, "OSC scene notes missing: " + scene_path)
        var label := ComponentPreview.create_content(scene_document) as RichTextLabel
        check(label != null, "Rich component view missing")
        if label != null:
            check(label.get_parsed_text().contains("Implementation notes"), "Renderer missing notes heading")
            check(label.get_parsed_text().contains("OSC"), "Renderer removed class content")
            label.free()

    var renderer := Renderer.new()
    renderer.refresh_theme()
    var display := RichTextLabel.new()
    renderer.render_document(display, without_contract, "BTOSCWithoutContract", false)
    check(display.get_parsed_text().contains("Converts OSC"), "Primary documentation did not render")
    check(display.get_parsed_text().contains("Implementation notes"), "Implementation heading did not render")
    check(display.get_parsed_text().contains("routing script"), "Implementation body did not render")
    display.free()
    if failures.is_empty():
        print("OSC implementation notes, native BBCode, contracts/no-contracts: PASS")
    for failure in failures:
        push_error(failure)
    quit(0 if failures.is_empty() else 1)
