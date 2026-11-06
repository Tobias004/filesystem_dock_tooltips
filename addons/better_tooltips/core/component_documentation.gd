@tool
class_name BTComponentDocumentation
extends RefCounted

## Reads component contracts from native Script reflection and PackedScene state.
## Never instantiates a hovered scene or calls its methods/configuration warnings.
## Resource loading follows Godot's normal script-loading semantics. Live nodes
## expose current Inspector assignments; file previews show saved root overrides.

const Parser := preload("res://addons/better_tooltips/core/gdscript_documentation_parser.gd")
const CONTRACT_NAME := "COMPONENT_CONTRACT"
const MAX_INHERITANCE_DEPTH := 16

## FileSystem/code-resource entry point; root scene only, including inheritance.
static func for_path(
	path: String,
	include_plain_script_docs: bool = false,
	include_contracts: bool = true
) -> Dictionary:
	if not path.get_extension().to_lower() in ["tscn", "scn", "gd"]:
		return {}
	if path.ends_with(".gd"):
		# Reuse loaded @tool scripts. Reloading a running script (including the
		# add-on's own tooltip_cache.gd) can crash Godot when this reader is called
		# from that script's active component-document cache method.
		return for_script(ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REUSE) as Script)
	# Read fresh saved scene state without recursively reloading live script
	# dependencies; script resources are managed by the editor's normal cache.
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		return {}
	var properties := _root_properties(scene.get_state(), 0)
	var script := properties.get("script") as Script
	var result := (
		for_scene_script(script, include_contracts, true)
		if include_plain_script_docs else for_script(script)
	)
	if result.is_empty():
		return {}
	if include_plain_script_docs and not bool(result.get("has_contract", false)):
		if str(result.get("description", "")).strip_edges().is_empty() and str(result.get("implementation_notes", "")).strip_edges().is_empty():
			return {}
	result["scene_description"] = str(properties.get("editor_description", ""))
	_apply_assignments(result, properties)
	return result

## Scene-dock selection combines the independent module toggles. Ordinary
## script help is enabled by the GDScript module (on by default); displaying
## exported contract dependencies still requires the opt-in component module.
## A notes-only script remains visible with either module, as before.
static func for_scene_script(script: Script, allow_contracts: bool, allow_script_help: bool) -> Dictionary:
	if script == null or not script is GDScript or (not allow_contracts and not allow_script_help):
		return {}
	# Avoid the expensive contract reflection entirely while the component
	# feature is off. The default script-docs path only reads the class header.
	var component := for_script(script) if allow_contracts else {}
	if not component.is_empty():
		if bool(component.get("has_contract", false)):
			return component
		# Notes-only classes were already parsed by for_script().
		return component
	if not allow_script_help:
		return {}
	var class_doc := _class_documentation(script, str(script.get_global_name()))
	var title := script.get_global_name()
	var has_global_name := not title.is_empty()
	if not has_global_name:
		title = script.resource_path.get_file()
	if title.is_empty():
		title = "Unnamed GDScript"
	return {
		"title": title,
		"script_only_title": not has_global_name,
		"description": str(class_doc.get("description", "")),
		"implementation_notes": str(class_doc.get("implementation_notes", "")),
		"has_contract": false,
		"properties": [], "signals": [], "commands": [], "issues": [],
	}

## Uses the open edited node, so unsaved source and Inspector changes are visible.
## Reading exported values follows normal Godot property-getter semantics.
static func for_node(node: Node, parsed_script_document: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(node):
		return {}
	# For an unchanged Scene-Dock node reuse reflection + ## parsing; only
	# Inspector values are read again. Deep-copy prevents stale assignments.
	var result := (parsed_script_document.duplicate(true) if not parsed_script_document.is_empty()
		else for_script(node.get_script() as Script))
	if result.is_empty():
		return {}
	result["scene_description"] = node.editor_description
	var values: Dictionary = {}
	for entry: Dictionary in result.properties:
		values[entry.name] = node.get(entry.name)
	_apply_assignments(result, values, node)
	return result

## Types, signals and public documented methods come from the script, not metadata.
## The optional v1 constant supplies only required/optional property semantics.
static func for_script(script: Script) -> Dictionary:
	if script == null or not script is GDScript:
		return {}
	var contract: Variant = {}
	var contract_script: Script = script
	for depth: int in range(MAX_INHERITANCE_DEPTH):
		if contract_script == null:
			break
		var constants := contract_script.get_script_constant_map()
		if constants.has(CONTRACT_NAME):
			contract = constants[CONTRACT_NAME]
			break
		contract_script = contract_script.get_base_script()
	if not contract is Dictionary or contract.is_empty():
		# No contract is necessary for architecture/implementation notes. A class
		# with only the special note block still has an informative scene tooltip.
		var plain_class := _class_documentation(script, str(script.get_global_name()))
		var notes := str(plain_class.get("implementation_notes", ""))
		if notes.is_empty():
			return {}
		return {
			"title": script.get_global_name() if not script.get_global_name().is_empty() else script.resource_path.get_file(),
			"script_only_title": script.get_global_name().is_empty(),
			"description": str(plain_class.get("description", "")),
			"implementation_notes": notes,
			"has_contract": false,
			"properties": [], "signals": [], "commands": [], "issues": [],
		}
	if contract.get("version") != 1:
		return {"title": script.get_global_name(), "description": "Unsupported COMPONENT_CONTRACT version.", "properties": [], "signals": [], "commands": [], "issues": ["Unsupported COMPONENT_CONTRACT version."]}
	var required: Array[StringName] = _property_names(contract.get("required", []))
	var optional: Array[StringName] = _property_names(contract.get("optional", []))
	var title: String = script.get_global_name()
	if title.is_empty():
		title = script.resource_path.get_file()
	var class_doc := _class_documentation(script, str(script.get_global_name()))
	var result: Dictionary = {
		"title": title,
		"description": str(class_doc.get("description", "")),
		"implementation_notes": str(class_doc.get("implementation_notes", "")),
		"has_contract": true,
		"properties": [], "signals": [], "commands": [], "issues": [],
	}
	var known: Array[StringName] = []
	for property: Dictionary in _members(script, "get_script_property_list"):
		if not int(property.usage) & PROPERTY_USAGE_EDITOR or int(property.usage) & PROPERTY_USAGE_CATEGORY or int(property.usage) & PROPERTY_USAGE_GROUP:
			continue
		var name: StringName = property.name
		known.append(name)
		result.properties.append({
			"name": name, "type": _type_name(property),
			"requirement": "Required" if name in required else ("Optional" if name in optional else "Configuration"),
			"description": _documentation(script, name),
			"default": script.get_property_default_value(name),
		})
	for name: StringName in required + optional:
		if name not in known:
			result.issues.append("Contract names a non-exported property: " + name)
		elif name in required and name in optional:
			result.issues.append("Property is both required and optional: " + name)
	for signal_info: Dictionary in _members(script, "get_script_signal_list"):
		result.signals.append({"signature": _signature(signal_info), "description": _documentation(script, signal_info.name)})
	for method: Dictionary in _members(script, "get_script_method_list"):
		if str(method.name).begins_with("_"):
			continue
		var description := _documentation(script, method.name)
		if not description.is_empty():
			result.commands.append({"signature": _signature(method), "description": description})
	return result

## Reflection lists are local to a script; walk bases explicitly, keeping overrides.
static func _members(script: Script, method: String) -> Array[Dictionary]:
	var members: Dictionary = {}
	for depth: int in range(MAX_INHERITANCE_DEPTH):
		if script == null:
			break
		for entry: Dictionary in script.call(method):
			if not members.has(entry.name):
				members[entry.name] = entry
		script = script.get_base_script()
	var result: Array[Dictionary] = []
	for entry: Dictionary in members.values():
		result.append(entry)
	return result

static func _property_names(value: Variant) -> Array[StringName]:
	var names: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			if (entry is String or entry is StringName) and not String(entry).is_empty():
				names.append(StringName(entry))
	return names

static func _class_documentation(script: Script, _symbol: String) -> Dictionary:
	for depth: int in range(MAX_INHERITANCE_DEPTH):
		if script == null:
			break
		var document := Parser.find_script_documentation(script.source_code)
		if not document.is_empty():
			return document
		script = script.get_base_script()
	return {}

static func _documentation(script: Script, symbol: String) -> String:
	for depth: int in range(MAX_INHERITANCE_DEPTH):
		if script == null or symbol.is_empty():
			break
		var document := Parser.find_member_documentation(script.source_code, symbol, -1, true, false)
		if not document.is_empty():
			return str(document.get("description", ""))
		script = script.get_base_script()
	return ""

static func _type_name(info: Dictionary) -> String:
	var named: String = str(info.get("class_name", ""))
	var type_id: int = int(info.get("type", TYPE_NIL))
	return named if not named.is_empty() else ("Variant" if type_id == TYPE_NIL else type_string(type_id))

static func _signature(info: Dictionary) -> String:
	var arguments: PackedStringArray = []
	var parameters: Array = info.get("args", [])
	var defaults: Array = info.get("default_args", [])
	for index: int in range(parameters.size()):
		var argument: Dictionary = parameters[index]
		var text := "%s: %s" % [argument.name, _type_name(argument)]
		var default_index := index - (parameters.size() - defaults.size())
		if default_index >= 0:
			var value: Variant = defaults[default_index]
			text += " = " + ("<" + value.get_class() + ">" if value is Object else var_to_str(value))
		arguments.append(text)
	if int(info.get("flags", 0)) & METHOD_FLAG_VARARG:
		arguments.append("...")
	var signature := "%s(%s)" % [info.name, ", ".join(arguments)]
	if info.has("return"):
		var result: Dictionary = info["return"]
		var return_type := _type_name(result)
		if int(result.get("type", TYPE_NIL)) == TYPE_NIL:
			return_type = "Variant" if int(result.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT else "void"
		signature += " -> " + return_type
	return signature

static func _root_properties(state: SceneState, depth: int) -> Dictionary:
	if state == null or depth >= MAX_INHERITANCE_DEPTH or state.get_node_count() == 0:
		return {}
	var result := _root_properties(state.get_base_scene_state(), depth + 1)
	var instance := state.get_node_instance(0)
	if instance != null:
		result.merge(_root_properties(instance.get_state(), depth + 1), true)
	for index: int in range(state.get_node_property_count(0)):
		result[state.get_node_property_name(0, index)] = state.get_node_property_value(0, index)
	return result

static func _apply_assignments(result: Dictionary, values: Dictionary, context: Node = null) -> void:
	for entry: Dictionary in result.properties:
		var value: Variant = values.get(entry.name, entry.get("default"))
		if value is Node:
			entry["assignment"] = str(context.get_path_to(value)) if is_instance_valid(context) and context.is_inside_tree() and value.is_inside_tree() else str(value.name)
		elif value is NodePath:
			entry["assignment"] = str(value) if not value.is_empty() else "Unassigned"
		elif value == null:
			entry["assignment"] = "Unassigned"
		elif not value is Object:
			entry["assignment"] = str(value)
		else:
			entry["assignment"] = value.get_class()
