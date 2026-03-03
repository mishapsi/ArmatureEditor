@tool
extends RefCounted
class_name ArmatureSkinService


var context: ArmatureSkeletonContext = null


## Sets the context used by this service.
func set_context(p_context: ArmatureSkeletonContext) -> void:
	context = p_context


## Rebuilds Skin binds for all MeshInstance3D nodes using the active skeleton.
## Preserves the original function name.
func _rebuild_skins_for_skeleton() -> void:
	if context == null:
		return
	if context.skeleton == null:
		return
	if context.editor_interface == null:
		return

	var skeleton := context.skeleton

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(context.editor_interface.get_edited_scene_root(), meshes)

	for mesh in meshes:
		if mesh == null:
			continue
		if mesh.skin == null:
			continue

		var old_skin: Skin = mesh.skin
		var new_skin := Skin.new()

		var bone_count := skeleton.get_bone_count()
		var old_bind_count := old_skin.get_bind_count()

		for i in range(old_bind_count):
			var bone_name := old_skin.get_bind_name(i)
			var bind_pose := old_skin.get_bind_pose(i)
			new_skin.add_named_bind(bone_name, bind_pose)

		for i in range(old_bind_count, bone_count):
			var bone_name := skeleton.get_bone_name(i)
			new_skin.add_named_bind(bone_name, Transform3D.IDENTITY)

		mesh.skin = new_skin


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton

	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if _mesh_uses_skeleton(mi, skeleton):
				out.append(mi)

		_collect_meshes(child, out)


func _mesh_uses_skeleton(mesh: MeshInstance3D, skeleton: Skeleton3D) -> bool:
	if mesh == null:
		return false
	if skeleton == null:
		return false

	if not mesh.skeleton:
		return false

	var resolved := mesh.get_node_or_null(mesh.skeleton)
	return resolved == skeleton
