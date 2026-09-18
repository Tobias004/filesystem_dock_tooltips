@tool
extends RefCounted

signal settings_requested

const Debug := preload("res://addons/filesystem_dock_tooltips/tooltip_debug.gd")

const MODULE := "Support"
const MENU_NAME := "FileSystem Dock Tooltips"
const MENU_SETTINGS := "Settings..."
const MENU_BUG := "Report a Bug"
const MENU_FEEDBACK := "Feedback / Feature Request"
const MENU_SETTINGS_ID := 0
const MENU_BUG_ID := 1
const MENU_FEEDBACK_ID := 2

const BUG_REPORT_URL := (
	"https://github.com/Tobias004/filesystem_dock_tooltips/issues/new"
	+ "?template=bug_report.yml"
)
const FEEDBACK_URL := (
	"https://github.com/Tobias004/filesystem_dock_tooltips/issues/new"
	+ "?template=feedback.yml"
)

var _plugin: EditorPlugin
var _menu: PopupMenu

func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_menu = PopupMenu.new()
	_menu.add_item(MENU_SETTINGS, MENU_SETTINGS_ID)
	_menu.set_item_tooltip(
		_menu.get_item_index(MENU_SETTINGS_ID),
		"Enable or disable tooltip modules for this project."
	)
	_menu.add_separator()
	_menu.add_item(MENU_BUG, MENU_BUG_ID)
	_menu.set_item_tooltip(
		_menu.get_item_index(MENU_BUG_ID),
		"Opens the GitHub bug report form in your browser. "
		+ "You must be signed in to GitHub to submit it."
	)
	_menu.add_item(MENU_FEEDBACK, MENU_FEEDBACK_ID)
	_menu.set_item_tooltip(
		_menu.get_item_index(MENU_FEEDBACK_ID),
		"Opens the GitHub feedback form in your browser. "
		+ "You must be signed in to GitHub to submit it."
	)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	_plugin.add_tool_submenu_item(MENU_NAME, _menu)
	Debug.log(MODULE, "support menu registered")

func cleanup() -> void:
	if _plugin == null:
		return
	_plugin.remove_tool_menu_item(MENU_NAME)
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	_plugin = null
	Debug.log(MODULE, "support menu removed")

func _open_bug_report() -> void:
	_open_url(_with_environment(BUG_REPORT_URL))

func _open_feedback() -> void:
	_open_url(_with_environment(FEEDBACK_URL))

func _on_menu_id_pressed(id: int) -> void:
	match id:
		MENU_SETTINGS_ID:
			settings_requested.emit()
		MENU_BUG_ID:
			_open_bug_report()
		MENU_FEEDBACK_ID:
			_open_feedback()

func _with_environment(base_url: String) -> String:
	var plugin_version: String = _get_plugin_version()
	var version_info: Dictionary = Engine.get_version_info()
	var godot_version: String = str(
		version_info.get("string", "Unknown")
	)
	return (
		base_url
		+ "&plugin_version="
		+ plugin_version.uri_encode()
		+ "&godot_version="
		+ godot_version.uri_encode()
	)

func _get_plugin_version() -> String:
	var config := ConfigFile.new()
	var result: Error = config.load(
		"res://addons/filesystem_dock_tooltips/plugin.cfg"
	)
	if result != OK:
		Debug.log(
			MODULE,
			"could not read plugin version from plugin.cfg"
		)
		return "Unknown"
	return str(config.get_value("plugin", "version", "Unknown"))

func _open_url(url: String) -> void:
	var result: Error = OS.shell_open(url)
	if result != OK:
		Debug.error(
			MODULE,
			"could not open support URL: %s" % error_string(result)
		)
