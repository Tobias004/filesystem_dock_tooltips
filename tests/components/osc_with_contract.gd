@tool
class_name BTOSCWithContract
extends Node

## Routes OSC messages to configured output nodes.
## Requests are validated before forwarding.
##
## [color=#888888][i]Implementation notes[/i][br]
## The OSC receiver is kept separate from transport integration so teams can
## replace the UDP layer without changing scene-facing signals.
## Integration uses [code]osc_target[/code] and [method Node.get_node].
## [/color]
const COMPONENT_CONTRACT: Dictionary = {
    "version": 1,
    "required": [&"osc_target"],
    "optional": [],
}

## Node receiving OSC events.
@export var osc_target: Node

## Emitted after parsing an incoming OSC packet.
signal osc_packet_received(path: StringName)

## Resets the last OSC address.
func reset_address() -> void:
    pass
