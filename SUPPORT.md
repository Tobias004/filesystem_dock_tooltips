# Support and feedback

Bug reports and feedback are welcome.

## From inside Godot

When the add-on is enabled, use:

- **Project > Tools > FileSystem Dock Tooltips: Report a Bug**
- **Project > Tools > FileSystem Dock Tooltips: Feedback / Feature Request**

These commands only open the corresponding GitHub form in your default browser.
The add-on does **not** automatically upload project files, logs, or other data.

The bug form automatically receives the installed add-on version and Godot
version when it is opened from the editor.

## Direct links

- [Report a bug](https://github.com/Tobias004/filesystem_dock_tooltips/issues/new?template=bug_report.yml)
- [Send feedback / request a feature](https://github.com/Tobias004/filesystem_dock_tooltips/issues/new?template=feedback.yml)
- [View existing issues](https://github.com/Tobias004/filesystem_dock_tooltips/issues)

## Debug information

The release configuration keeps debug messages disabled.

If a problem needs additional diagnostics, temporarily change:

```gdscript
const DEBUG_MESSAGES := false
```

to:

```gdscript
const DEBUG_MESSAGES := true
```

in:

`addons/filesystem_dock_tooltips/tooltip_settings.gd`

Reload the add-on or restart the editor, reproduce the issue, and include the
relevant Godot **Output** messages in the bug report.

Set the constant back to `false` afterwards.
