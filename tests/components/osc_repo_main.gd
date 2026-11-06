## Scene-tree composition root. Game actions are registered once and shared by
## cockpit signals, existing input bindings and the developer console.
##
## [color=#888888][i]Implementation notes[/i][br]
## No COMPONENT_CONTRACT: this is the main composition root, not a reusable child.
## [/color]
extends Node3D
