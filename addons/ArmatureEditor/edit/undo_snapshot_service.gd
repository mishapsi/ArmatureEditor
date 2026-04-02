@tool
extends RefCounted
class_name ArmatureUndoRedoService

var context: ArmatureSkeletonContext = null
var skeleton_gizmo:EditableSkeletonGizmo = null

var skin_rebuild_service: ArmatureSkinService = null
var _history: Array = []
var _current_index: int = -1

## Sets dependencies used by this service.
func set_dependencies(p_context: ArmatureSkeletonContext, p_skin_rebuild_service: ArmatureSkinService) -> void:
	context = p_context
	skin_rebuild_service = p_skin_rebuild_service


## Captures the current skeleton snapshot.
## Preserves the original function name.
func _snapshot_into(target_array: Array) -> void:
	target_array.clear()

	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	for i in range(skeleton.get_bone_count()):
		target_array.append({
			"name": skeleton.get_bone_name(i),
			"parent": skeleton.get_bone_parent(i),
			"rest": skeleton.get_bone_rest(i)
		})
func _restore_snapshot_internal(snapshot: Array) -> void:
	if context == null or context.skeleton == null:
		return

	if snapshot.is_empty():
		return

	var skeleton := context.skeleton

	var old_selected_ids: Array = skeleton_gizmo.get_selected_ids(context.get_active_gizmo())

	# ---- Rebuild skeleton ----
	skeleton.clear_bones()

	for bone_data in snapshot:
		skeleton.add_bone(bone_data.name)

	for i in range(snapshot.size()):
		var parent = snapshot[i].parent
		skeleton.set_bone_parent(
			i,
			parent if parent >= 0 and parent < snapshot.size() else -1
		)

	for i in range(snapshot.size()):
		skeleton.set_bone_rest(i, snapshot[i].rest)

	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	_repair_selection_after_restore(old_selected_ids)

	skeleton.update_gizmos()

func _repair_selection_after_restore(old_ids: Array) -> void:
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	var gizmo: EditorNode3DGizmo = context.get_active_gizmo()
	if gizmo == null:
		return

	var bone_count := skeleton.get_bone_count()
	var repaired_ids: Array[int] = []

	skeleton.clear_subgizmo_selection()

	for id in old_ids:
		var bone := int(id / 2)
		var part := int(id % 2)

		var repaired_bone := -1

		if bone >= 0 and bone < bone_count:
			repaired_bone = bone
		else:
			repaired_bone = _find_valid_ancestor(bone, bone_count)

		if repaired_bone == -1:
			continue

		var new_id := repaired_bone * 2 + part
		var t := skeleton.get_bone_global_rest(repaired_bone)

		skeleton.set_subgizmo_selection(gizmo, new_id, t)
		repaired_ids.append(new_id)
	skeleton_gizmo.set_selected_ids(gizmo,repaired_ids)

func _find_valid_ancestor(original_bone: int, bone_count: int) -> int:
	var b := original_bone

	while b >= 0:
		if b < bone_count:
			return b
		b -= 1

	return -1


## Captures and returns a snapshot array for convenience.
##
## @return Array snapshot data compatible with _restore_snapshot_from.
func capture() -> Array:
	var snap := []
	_snapshot_into(snap)
	return snap


## Commits an UndoRedo action that restores skeleton snapshots.
##
## @param action_name Name shown in Undo history.
## @param pre Snapshot before changes.
## @param post Snapshot after changes.
## @param rebuild_skins Whether to rebuild skins on both do/undo.
func commit(action_name: String, pre: Array, post: Array, rebuild_skins: bool = true) -> void:
	if context == null or context.undo_redo == null:
		return

	var ur := context.undo_redo

	var pre_index := _store_snapshot(pre, action_name)
	var post_index := _store_snapshot(post, action_name)

	ur.create_action(action_name)

	ur.add_do_method(self, "_restore_by_index", post_index)
	#if rebuild_skins:
		#ur.add_do_method(self, "_rebuild_skins")
	ur.add_undo_method(self, "_restore_by_index", pre_index)
	#if rebuild_skins:
		#ur.add_undo_method(self, "_rebuild_skins")
	ur.commit_action()

func _store_snapshot(snapshot: Array, action_name: String) -> int:
	var cloned := snapshot.duplicate(true)

	_history.append({
		"action": action_name,
		"snapshot": cloned
	})

	return _history.size() - 1
func _rebuild_skins() -> void:
	if skin_rebuild_service == null:
		return
	skin_rebuild_service._rebuild_skins_for_skeleton()

func _restore_by_index(index: int) -> void:
	if index < 0 or index >= _history.size():
		return

	var snapshot = _history[index].snapshot
	_restore_snapshot_internal(snapshot)
