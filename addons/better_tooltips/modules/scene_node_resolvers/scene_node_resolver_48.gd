@tool
extends BTSceneNodeResolver

## Godot 4.8: SceneTreeEditor stores paths relative to edited scene root.
func resolve(_scene_tree: Tree, edited_scene_root: Node, path: NodePath) -> Node:
	return edited_scene_root.get_node_or_null(path) if is_instance_valid(edited_scene_root) else null
