@tool
class_name BTOSCWithoutContract
extends Node

## Converts OSC address patterns into local routes.
## Keeps transport-independent routing logic available to tools.
##
## [color=#888888][i]Implementation notes[/i][br]
## A small routing script avoids coupling the scene to a specific OSC library.
## Replace the transport adapter without changing these address mappings.
## [/color]

@export var route_prefix := "/game/"
