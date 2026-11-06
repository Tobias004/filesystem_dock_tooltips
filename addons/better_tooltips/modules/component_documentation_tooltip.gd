@tool
class_name BTComponentDocumentationTooltip
extends EditorResourceTooltipPlugin

## Live component reference for scenes/scripts declaring COMPONENT_CONTRACT v1.
## Uses the shared documentation renderer and live-text pipeline, without rendering
## or instantiating PackedScenes. Native file/path information stays intact.

const Reader := preload("res://addons/better_tooltips/core/component_documentation.gd")
const Renderer := preload("res://addons/better_tooltips/core/documentation_renderer.gd")
const Appearance := preload("res://addons/better_tooltips/core/tooltip_appearance.gd")
const Cache := preload("res://addons/better_tooltips/core/tooltip_cache.gd")
const Settings := preload("res://addons/better_tooltips/tooltip_settings.gd")

var _cache: BTTooltipCache = null

func setup_cache(cache: BTTooltipCache) -> void:
	_cache = cache

func _handles(type: String) -> bool:
	return type in ["PackedScene", "GDScript"]

func is_live_preview() -> bool:
	return true

func _make_tooltip_for_path(path: String, _metadata: Dictionary, base: Control) -> Control:
	# Shift-hover requests a fresh read, like the bitmap preview modules.
	if _cache != null and Input.is_key_pressed(KEY_SHIFT):
		_cache.invalidate_component_document(path)
	var document := _cache.get_component_document(path) if _cache != null else Reader.for_path(path)
	# Ordinary scripts and non-contract scene roots are handled by the standard
	# documentation module. Only contracts add a separate API when both run.
	if Settings.is_module_enabled(Settings.MODULE_SCRIPT_DOCUMENTATION):
		if not bool(document.get("has_contract", false)):
			return base
		if path.ends_with(".gd"):
			# The .gd tooltip already includes the script's architecture notes.
			document = document.duplicate(true)
			document.erase("implementation_notes")
	if not document.is_empty():
		base.add_child(create_content(document))
	return base

## Shared rich view for file tooltips and editor integration tests.
static func create_content(document: Dictionary) -> Control:
	var renderer := Renderer.new() as BTDocumentationRenderer
	renderer.refresh_theme()
	var label := RichTextLabel.new()
	label.name = &"ComponentDocumentation"
	renderer.configure_label(label, false)
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.focus_mode = Control.FOCUS_NONE
	label.custom_minimum_size.x = Appearance.text_content_width(640.0 * EditorInterface.get_editor_scale())
	renderer.render_document(label, {
		"description": describe(document),
		"implementation_notes": str(document.get("implementation_notes", "")),
	}, str(document.get("title", "")), false)
	if bool(document.get("has_contract", true)):
		_append_contract_details(label, renderer, document)
	Appearance.limit_rich_text_height(label)
	return label

## Formats the full native API reference for the existing rich-text renderer.
static func describe(document: Dictionary) -> String:
	var has_contract := bool(document.get("has_contract", true))
	var prefix := "Component: " if has_contract else (
		"Script: " if bool(document.get("script_only_title", false)) else "Class: "
	)
	var lines: PackedStringArray = ["[b]" + prefix + _escape(str(document.get("title", ""))) + "[/b]"]
	var purpose: String = str(document.get("description", ""))
	if not purpose.is_empty():
		lines.append(purpose)
	var scene_description: String = str(document.get("scene_description", ""))
	if not scene_description.is_empty() and scene_description != purpose:
		lines.append(_escape(scene_description))
	return "\n".join(lines)

# Keep one continuous theme-derived left rule around the entire contract API,
# not separate rules around every property description. Signatures remain
# prominent, while explanatory text is muted like Implementation notes.
static func _append_contract_details(
	label: RichTextLabel,
	renderer: BTDocumentationRenderer,
	document: Dictionary
) -> void:
	var context_class := str(document.get("title", ""))
	label.newline()
	renderer.begin_document_inset(label)
	var first_entry := true
	for entry: Dictionary in document.get("properties", []):
		if not first_entry:
			label.newline()
		first_entry = false
		var assignment: String = " — " + _escape(str(entry.assignment)) if entry.has("assignment") else ""
		renderer.append_document_markup(
			label,
			"[b]%s[/b] [code]%s: %s[/code]%s" % [entry.requirement, _escape(str(entry.name)), _escape(str(entry.type)), assignment],
			context_class
		)
		if not str(entry.description).is_empty():
			label.newline()
			renderer.append_document_secondary_markup(label, str(entry.description), context_class)
	for section: String in ["signals", "commands"]:
		if not first_entry:
			label.newline()
		first_entry = false
		renderer.append_document_markup(
			label, "[b]Emitted signals[/b]" if section == "signals" else "[b]Documented public methods[/b]", context_class
		)
		var members: Array = document.get(section, [])
		if members.is_empty():
			label.newline()
			label.add_text("None.")
		for entry: Dictionary in members:
			label.newline()
			renderer.append_document_markup(label, "[code]" + _escape(str(entry.signature)) + "[/code]", context_class)
			if not str(entry.description).is_empty():
				label.newline()
				renderer.append_document_secondary_markup(label, str(entry.description), context_class)
	for issue: String in document.get("issues", []):
		label.newline()
		label.add_text(issue)
	renderer.end_document_inset(label)

static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
