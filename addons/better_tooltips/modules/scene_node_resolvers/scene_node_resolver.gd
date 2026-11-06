@tool
class_name BTSceneNodeResolver
extends RefCounted

## Version-specific interpretation of the Scene dock's TreeItem NodePath.
## The editor tree lookup, tooltip lifecycle and documentation remain shared.
func resolve(_scene_tree: Tree, _edited_scene_root: Node, _path: NodePath) -> Node:
	return null
