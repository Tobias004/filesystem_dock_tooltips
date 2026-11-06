@tool
## Displays the passive cockpit frame around independently managed instruments.
## Each instrument owns its own presentation and data sources.
##
## [color=#888888][i]Implementation notes[/i][br]
## Requires View State in the Inspector, validated by an editor warning.
## No COMPONENT_CONTRACT yet: the typed export and configuration warning already
## describe its single required source; formalize if the integration grows.
## [/color]
class_name BTOSCCockpitViewFixture
extends Control

@export var view_state: Node
