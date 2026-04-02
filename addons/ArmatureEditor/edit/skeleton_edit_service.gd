@tool
extends RefCounted
class_name ArmatureEditService

var context: ArmatureSkeletonContext = null

## Sets the context used by this service.
func set_context(p_context: ArmatureSkeletonContext) -> void:
	context = p_context

## Creates an initial root + tip bone if the skeleton has no bones.
## Preserves the original function name.
func _create_initial_root_bone() -> void:
	if context == null:
		return
	if context.skeleton == null:
		return

	var skeleton := context.skeleton
	if skeleton.get_bone_count() > 0:
		return

	var root_index := skeleton.get_bone_count()
	skeleton.add_bone("Root")
	skeleton.set_bone_parent(root_index, -1)

	var root_rest := Transform3D.IDENTITY
	root_rest.origin = Vector3.ZERO
	skeleton.set_bone_rest(root_index, root_rest)

	var tip_index := skeleton.get_bone_count()
	skeleton.add_bone("Root_tip")
	skeleton.set_bone_parent(tip_index, root_index)

	var tip_rest := Transform3D.IDENTITY
	tip_rest.origin = Vector3(0, .1, 0.0)
	skeleton.set_bone_rest(tip_index, tip_rest)

	_apply_skeleton_post_edit()
## Deletes all children (and deeper descendants) of a bone, preserving the root bone itself.
func _delete_selected_bone_with_children(delete_root: int) -> void:
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	if delete_root < 0 or delete_root >= skeleton.get_bone_count():
		return

	var to_delete := {}
	var stack: Array[int] = []

	for c in skeleton.get_bone_children(delete_root):
		stack.append(c)

	while not stack.is_empty():
		var i: int = stack.pop_back()
		if to_delete.has(i):
			continue
		to_delete[i] = true
		for c in skeleton.get_bone_children(i):
			stack.append(c)

	if to_delete.is_empty():
		return

	var bone_count := skeleton.get_bone_count()

	var names := []
	var parents := []
	var rests := []

	for i in range(bone_count):
		names.append(skeleton.get_bone_name(i))
		parents.append(skeleton.get_bone_parent(i))
		rests.append(skeleton.get_bone_rest(i))

	var index_remap := {}
	var new_index := 0

	for i in range(bone_count):
		if to_delete.has(i):
			continue
		index_remap[i] = new_index
		new_index += 1

	skeleton.clear_bones()

	for i in range(bone_count):
		if to_delete.has(i):
			continue
		skeleton.add_bone(names[i])

	for i in range(bone_count):
		if to_delete.has(i):
			continue

		var new_i: int = index_remap[i]
		var old_parent: int = parents[i]

		if old_parent == -1:
			skeleton.set_bone_parent(new_i, -1)
		elif to_delete.has(old_parent):
			skeleton.set_bone_parent(new_i, -1)
		else:
			skeleton.set_bone_parent(new_i, index_remap[old_parent])

	for i in range(bone_count):
		if to_delete.has(i):
			continue

		var new_i: int = index_remap[i]
		skeleton.set_bone_rest(new_i, rests[i])
	if skeleton.get_bone_count() == 1:
		skeleton.clear_bones()
	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	skeleton.update_gizmos()
	skeleton.property_list_changed.emit()


## Subdivides a bone by inserting a single intermediate bone between it and its children.
## Preserves the original function name.
func _apply_subdivide(bone_index: int, count: int = 2) -> void:
	if context == null:
		return
	if context.skeleton == null:
		return

	var skeleton := context.skeleton
	if bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return

	var original_name := skeleton.get_bone_name(bone_index)
	var original_rest := skeleton.get_bone_rest(bone_index)

	var children := skeleton.get_bone_children(bone_index)
	if children.is_empty():
		return

	var first_child := children[0]
	var child_rest := skeleton.get_bone_rest(first_child)

	var child_local := child_rest.origin
	var total_length := max(0.0001, child_local.length())
	var offset := child_local * 0.5

	var b_index := skeleton.get_bone_count()
	skeleton.add_bone("%s_B" % original_name)
	skeleton.set_bone_parent(b_index, bone_index)

	var b_rest := Transform3D.IDENTITY
	b_rest.basis = original_rest.basis
	b_rest.origin = offset
	skeleton.set_bone_rest(b_index, b_rest)

	for c in children:
		skeleton.set_bone_parent(c, b_index)
		var rest := b_rest.affine_inverse() * skeleton.get_bone_rest(c)
		skeleton.set_bone_rest(c, rest)

	_apply_skeleton_post_edit()

	var chain_data := _get_bone_chain(bone_index)
	_rename_chain(chain_data)


## Preserves the original function name.
func _get_bone_chain(bone_index: int) -> Dictionary:
	if context == null or context.skeleton == null:
		return {}

	return context._get_bone_chain(bone_index)


## Renames a chain (bones[1..]) and ensures the last is named as tip.
## Preserves the original function name.
func _rename_chain(chain_data: Dictionary) -> void:
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	if chain_data.is_empty():
		return

	var bones: Array = chain_data.get("bones", [])
	if bones.is_empty():
		return

	var chain_start: int = chain_data.get("start", -1)
	if chain_start == -1:
		return

	var parent := skeleton.get_bone_parent(chain_start)
	var base_name := ""

	if parent != -1:
		base_name = skeleton.get_bone_name(parent)
	else:
		base_name = skeleton.get_bone_name(chain_start)

	base_name = _clean_chain_base_name(base_name)

	for i in range(1, bones.size()):
		var bone_index: int = bones[i]
		var is_end := i == bones.size() - 1

		var new_name := "%s_%d" % [base_name, i]
		if is_end:
			new_name = "%s_tip" % base_name

		skeleton.set_bone_name(bone_index, _make_unique_bone_name(new_name, [bone_index]))

	skeleton.property_list_changed.emit()
	skeleton.update_gizmos()


## Preserves the original function name.
func _get_bone_segment_length(bone_index: int) -> float:
	if context == null or context.skeleton == null:
		return 0.2

	var skeleton := context.skeleton
	var children := skeleton.get_bone_children(bone_index)

	if children.size() > 0:
		var child_index := children[0]
		var child_rest := skeleton.get_bone_rest(child_index)
		return max(0.0001, child_rest.origin.length())

	return 0.2


## Finds a direct "_tip" child for the bone, or creates one if missing.
## Preserves the original function name.
func _find_or_create_tip_for(bone_index: int) -> int:
	if context == null or context.skeleton == null:
		return -1

	var skeleton := context.skeleton
	var children := skeleton.get_bone_children(bone_index)
	for c in children:
		if skeleton.get_bone_name(c).ends_with("_tip"):
			return c

	var tip_index := skeleton.get_bone_count()
	skeleton.add_bone("%s_tip" % skeleton.get_bone_name(bone_index))
	skeleton.set_bone_parent(tip_index, bone_index)

	var tip_rest := Transform3D.IDENTITY
	tip_rest.origin = Vector3(0, 0, 0.5)
	skeleton.set_bone_rest(tip_index, tip_rest)

	return tip_index


## Snapshot a child subtree so it can be reattached after bone replacement.
## Preserves the original function name.
func _snapshot_subtree(root_bone: int) -> Dictionary:
	if context == null or context.skeleton == null:
		return {}

	var skeleton := context.skeleton
	var items := []
	var stack := [root_bone]

	while not stack.is_empty():
		var i: int = stack.pop_back()
		var parent := skeleton.get_bone_parent(i)
		items.append({
			"old_index": i,
			"parent_old": parent,
			"name": skeleton.get_bone_name(i),
			"rest": skeleton.get_bone_rest(i),
		})
		for c in skeleton.get_bone_children(i):
			stack.append(c)

	return {"items": items}


## Restore a previously snapshotted subtree under a new parent bone.
## Preserves the original function name.
func _restore_subtree(snapshot: Dictionary, new_parent: int) -> void:
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	var items: Array = snapshot.get("items", [])
	if items.is_empty():
		return

	var index_map := {}
	var root_old = items[0].old_index

	for it in items:
		var new_i := skeleton.get_bone_count()
		skeleton.add_bone(it.name)
		index_map[it.old_index] = new_i

	for it in items:
		var new_i: int = index_map[it.old_index]
		if it.old_index == root_old:
			skeleton.set_bone_parent(new_i, new_parent)
		else:
			var new_p: int = index_map.get(it.parent_old, -1)
			skeleton.set_bone_parent(new_i, new_p)
		skeleton.set_bone_rest(new_i, it.rest)

## Applies common post-edit calls to keep Skeleton3D stable after topology changes.
func apply_post_edit() -> void:
	_apply_skeleton_post_edit()


## Returns a sanitized bone name via the shared context helper.
func sanitize_bone_name(name: String) -> String:
	if context == null:
		return name
	return context._sanitize_bone_name(name)


## Returns true if a bone name exists on the current skeleton.
func bone_name_exists(name: String, ignore_bones: Array[int] = []) -> bool:
	if context == null:
		return false
	return context._bone_name_exists(name, ignore_bones)


## Makes a unique bone name on the current skeleton.
func make_unique_bone_name(base: String, ignore_bones: Array[int] = []) -> String:
	if context == null:
		return base
	return context._make_unique_bone_name(base, ignore_bones)

func _apply_skeleton_post_edit() -> void:
	var skeleton := context.skeleton
	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	skeleton.update_gizmos()
	skeleton.property_list_changed.emit()


func _clean_chain_base_name(base_name: String) -> String:
	var out := base_name
	out = out.replace("_0", "")
	out = out.replace("_A", "")
	out = out.replace("_B", "")
	out = out.replace("_tip", "")
	out = out.replace("_chain", "")
	out = out.replace("_start", "")
	return out


func _make_unique_bone_name(base: String, ignore_bones: Array[int] = []) -> String:
	if context == null:
		return base
	return context._make_unique_bone_name(base, ignore_bones)
