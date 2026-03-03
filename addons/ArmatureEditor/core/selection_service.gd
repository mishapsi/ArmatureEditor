# selection_service.gd
# Selection utilities for Skeleton3D gizmos.

@tool
extends RefCounted
class_name ArmatureSelectionService

var context: ArmatureSkeletonContext = null


## Sets the context used for selection queries.
func set_context(p_context: ArmatureSkeletonContext) -> void:
	context = p_context


## Returns the selected bone indices (unique) from the active gizmo selection.
## Preserves the original function name used in the monolithic script.
func _get_selected_bone_indices() -> Array[int]:
	if context == null:
		return []
	if context.skeleton == null:
		return []
	if context.gizmo_plugin == null:
		return []

	var gizmo := context.get_active_gizmo()
	if gizmo == null:
		return []

	var ids = context.gizmo_plugin.get_selected_ids(gizmo)

	var bones: Array[int] = []
	for id in ids:
		var bone_idx := _bone_index_from_subgizmo_id(id)
		if not bones.has(bone_idx):
			bones.append(bone_idx)
	return bones


## Returns a primary bone for context-menu operations.
## If a tip bone is selected, returns its parent.
func get_context_bone_from_selection() -> int:
	if context == null or context.skeleton == null:
		return -1

	var bones := _get_selected_bone_indices()
	if bones.is_empty():
		return -1
	return bones[0]


## Converts a selected bone index to its parent if it is a tip bone.
func normalize_tip_to_parent(bone_index: int) -> int:
	if context == null or context.skeleton == null:
		return bone_index

	if bone_index < 0 or bone_index >= context.skeleton.get_bone_count():
		return bone_index

	if _is_tip_bone(bone_index):
		return context.skeleton.get_bone_parent(bone_index)

	return bone_index


## Returns true if the current selection contains any bones.
func has_selection() -> bool:
	return not _get_selected_bone_indices().is_empty()

## Returns the subgizmo ids currently selected on the active gizmo.
func get_selected_subgizmo_ids() -> PackedInt32Array:
	if context == null:
		return PackedInt32Array()
	if context.skeleton == null:
		return PackedInt32Array()
	if context.gizmo_plugin == null:
		return PackedInt32Array()

	var gizmo := context.get_active_gizmo()
	if gizmo == null:
		return PackedInt32Array()
	return context.gizmo_plugin.get_selected_ids(gizmo)

func _bone_index_from_subgizmo_id(subgizmo_id: int) -> int:
	return subgizmo_id >> 1


func _is_tip_bone(bone_index: int) -> bool:
	var name := context.skeleton.get_bone_name(bone_index)
	return name.ends_with("_tip")

## Returns selected bone indices as a PackedInt32Array (unique).
## Tip bones are normalized to their parent bones.
func get_selected_bones() -> PackedInt32Array:
	var bones := _get_selected_bone_indices()
	if bones.is_empty():
		return PackedInt32Array()

	var set := {}
	for b in bones:
		var n := normalize_tip_to_parent(b)
		if n < 0:
			continue
		set[n] = true

	var out := PackedInt32Array()
	out.resize(set.size())

	var i := 0
	for k in set.keys():
		out[i] = int(k)
		i += 1

	return out


## Returns a non-empty bone selection suitable for edit operations.
## Falls back to the context bone if multi-selection is empty.
func get_contextual_bone_selection() -> PackedInt32Array:
	var selected := get_selected_bones()
	if not selected.is_empty():
		return selected

	var ctx := get_context_bone_from_selection()
	if ctx >= 0:
		return PackedInt32Array([ctx])

	return PackedInt32Array()
