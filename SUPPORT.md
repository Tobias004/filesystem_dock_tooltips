# Support and feedback

Bug reports and feedback are welcome.

## From inside Godot

When the add-on is enabled, use:

- **Project > Tools > Better Tooltips: Report a Bug**
- **Project > Tools > Better Tooltips: Feedback / Feature Request**

These commands only open the corresponding GitHub form in your default browser.
The add-on does **not** automatically upload project files, logs, or other data.

The bug form automatically receives the installed add-on version and Godot
version when it is opened from the editor.

## Direct links

- [Report a bug](https://github.com/Tobias004/filesystem_dock_tooltips/issues/new?template=bug_report.yml)
- [Send feedback / request a feature](https://github.com/Tobias004/filesystem_dock_tooltips/issues/new?template=feedback.yml)
- [View existing issues](https://github.com/Tobias004/filesystem_dock_tooltips/issues)

## Debug information

Open **Project > Tools > Better Tooltips > Settings...** and enable **Show Better Tooltips diagnostics**. The option is stored per project and can be switched off again after collecting Godot **Output** messages for a bug report. No source-code edits or editor restart are required.

This controls only the add-on's own diagnostic logger (`BTDebug`). Godot parser errors, engine errors and invalid object-access errors cannot be hidden by this setting; they need to be fixed.

### Code Editor popup trace (diagnostic builds)

With **Show Better Tooltips diagnostics** enabled, a script-symbol hover logs
`[Code Editor] native created/populated/hidden/freed` for Godot-owned tooltip
windows, or `fallback created/closed` for an add-on-owned tooltip. Each event
includes a `popup` instance ID and the owning `editor` ID. Fallback closure
messages also identify the reason (for example `native_handoff`, `mouse_exit`,
`hover_changed`, or `lifetime_expired`).

A corresponding `[Script Documentation] live preview` message includes
`host=native` or `host=fallback`, plus matching `popup`, `base`, and `section`
instance IDs. Compare these IDs to distinguish an additional preview in the
same popup from a newly created popup. The same symbol can be hovered repeatedly;
only consecutive events with the pointer left stationary indicate unexpected
re-creation. This instrumentation reports behavior; it does not change popup
lifetime or suppress Godot errors.
