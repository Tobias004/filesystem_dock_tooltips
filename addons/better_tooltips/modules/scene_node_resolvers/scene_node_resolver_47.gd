@tool
extends BTSceneNodeResolver

## Godot 4.7: SceneTreeEditor stores absolute paths to edited nodes.
func resolve(scene_tree: Tree, _edited_scene_root: Node, path: NodePath) -> Node:
	return scene_tree.get_node_or_null(path)
