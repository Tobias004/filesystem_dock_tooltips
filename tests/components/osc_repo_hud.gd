@tool
## Displays passive flight symbology and readouts from one aircraft.
## Reads shared telemetry and view state; emits no gameplay intents.
## Visible Modes controls presentation, not system availability.
## RUNNING/INTERACTIVE refresh immediately; AFK freezes presentation.
##
## [color=#888888][i]Implementation notes[/i][br]
## Assign Telemetry Source and View State in the Inspector. Both are required
## by COMPONENT_CONTRACT. The HUD subscribes internally and reads initial state;
## owners must not connect the same updates again.
## [/color]
class_name BTOSCHUDFixture
extends Control

const COMPONENT_CONTRACT: Dictionary = {
    "version": 1,
    "required": [&"telemetry_source", &"view_state"],
    "optional": [],
}

## Aircraft telemetry source.
@export var telemetry_source: Node
## Current view context.
@export var view_state: Node
