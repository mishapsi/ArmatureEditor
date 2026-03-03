@tool
extends RefCounted
class_name ArmatureCopyPasteService

var _is_modal := false
var _modal_parent := -1
var _modal_root := -1
var _modal_snapshot: Array = []
var _modal_initial_local_rests: Dictionary = {}
var context: ArmatureSkeletonContext
var selection_service: ArmatureSelectionService
var undo_snapshot_service: ArmatureUndoRedoService
var view_plane_service: ArmatureViewPlaneService


func set_dependencies(
	p_context: ArmatureSkeletonContext,
	p_selection_service: ArmatureSelectionService,
	p_undo_snapshot_service: ArmatureUndoRedoService,
	p_view_plane_service: ArmatureViewPlaneService
) -> void:
	context = p_context
	selection_service = p_selection_service
	undo_snapshot_service = p_undo_snapshot_service
	view_plane_service = p_view_plane_service


var _clipboard: Array = []

func has_clipboard() -> bool:
	return not _clipboard.is_empty()

func is_modal():
	return _is_modal
func copy_from_selection() -> bool:
	if not _can_access_skeleton():
		return false

	var bone := selection_service.get_context_bone_from_selection()
	if not _is_valid_bone(bone):
		return false

	_clipboard = _capture_subtree(context.skeleton, bone)
	return has_clipboard()


func copy_from_context_bone(bone_index: int) -> bool:
	if not _can_access_skeleton():
		return false
	if not _is_valid_bone(bone_index):
		return false

	_clipboard = _capture_subtree(context.skeleton, bone_index)
	return has_clipboard()


func try_begin_modal(parent_bone_index: int) -> bool:
	if _is_modal:
		return false
	if not _can_paste():
		return false
	if not _is_valid_bone(parent_bone_index):
		return false

	var skeleton := context.skeleton

	_is_modal = true
	_modal_parent = parent_bone_index
	_modal_snapshot = undo_snapshot_service.capture()

	_modal_root = _paste_subtree(parent_bone_index)
	if _modal_root == -1:
		return false

	_capture_modal_initial_rests(context.skeleton, _modal_root)
	return _modal_root != -1


func _capture_modal_initial_rests(skeleton: Skeleton3D, root: int) -> void:
	_modal_initial_local_rests.clear()
	var bones := []
	_collect_subtree(skeleton, root, bones)

	for b in bones:
		_modal_initial_local_rests[b] = skeleton.get_bone_rest(b)

func handle(viewport: Object, event: InputEvent) -> int:
	if not _is_modal:
		return 0

	if event is InputEventMouseMotion:
		_update_modal_position(event.position)
		return 2

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_commit_modal()
			return 2
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_modal()
			return 2

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			_cancel_modal()
			return 2

	return 2


func _commit_modal() -> void:
	var post := undo_snapshot_service.capture()
	undo_snapshot_service.commit("Paste Bone Subtree", _modal_snapshot, post, true)
	_end_modal()


func _cancel_modal() -> void:
	undo_snapshot_service._restore_snapshot_internal(_modal_snapshot)
	_end_modal()


func _end_modal() -> void:
	_is_modal = false
	_modal_parent = -1
	_modal_root = -1
	_modal_snapshot.clear()
	_modal_initial_local_rests.clear()

func _update_modal_position(mouse_pos: Vector2) -> void:
	if view_plane_service == null:
		return

	var skeleton := context.skeleton
	var viewport := context.editor_interface.get_editor_viewport_3d()
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var parent_global := skeleton.global_transform * skeleton.get_bone_global_rest(_modal_parent)
	var plane := view_plane_service.get_major_view_plane(camera, parent_global.origin)
	var hit := plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return

	_translate_subtree_to_world_point(skeleton, _modal_root, hit)

func paste_as_child_of_bone(parent_bone_index: int) -> bool:
	if not _can_paste():
		return false
	if not _is_valid_bone(parent_bone_index):
		return false

	var pre := undo_snapshot_service.capture()
	_paste_subtree(parent_bone_index)
	var post := undo_snapshot_service.capture()

	undo_snapshot_service.commit("Paste Bone Subtree", pre, post, true)
	return true

func _paste_subtree(target_parent: int) -> int:
	return _build_subtree(context.skeleton, target_parent, _clipboard)


func _build_subtree(
	skeleton: Skeleton3D,
	target_parent: int,
	subtree: Array
) -> int:
	if subtree.is_empty():
		return -1

	var existing := _build_name_set(skeleton)
	var parent_cache := {}
	var parent_global := _get_rest_global(skeleton, target_parent, parent_cache)

	var local_to_new := {}
	var global_cache := {}
	var new_root := -1

	for i in range(subtree.size()):
		var node: Dictionary = subtree[i]

		var name := _make_unique_name(existing, String(node.name))
		skeleton.add_bone(name)
		var new_bone := skeleton.get_bone_count() - 1
		local_to_new[i] = new_bone

		if i == 0:
			new_root = new_bone

		var parent_local := int(node.parent_local)
		var parent = target_parent if parent_local == -1 else local_to_new[parent_local]
		skeleton.set_bone_parent(new_bone, parent)

		var parent_global_xf = parent_global if parent_local == -1 else global_cache[parent_local]
		var rel_global: Transform3D = node.rel_global
		var desired_global := parent_global * rel_global
		var local_rest = parent_global_xf.affine_inverse() * desired_global

		skeleton.set_bone_rest(new_bone, local_rest)
		global_cache[i] = parent_global_xf * local_rest

	_refresh(skeleton)
	return new_root

func _translate_subtree_to_world_point(
	skeleton: Skeleton3D,
	root: int,
	world_target: Vector3
) -> void:
	var parent := skeleton.get_bone_parent(root)
	var parent_global := Transform3D.IDENTITY
	if parent != -1:
		parent_global = skeleton.global_transform * skeleton.get_bone_global_rest(parent)
	var desired_local_origin := parent_global.affine_inverse().origin + parent_global.basis.inverse() * (world_target - parent_global.origin)
	var original_rest: Transform3D = _modal_initial_local_rests[root]

	var new_rest := original_rest
	new_rest.origin = desired_local_origin

	skeleton.set_bone_rest(root, new_rest)

	_refresh(skeleton)

func _capture_subtree(skeleton: Skeleton3D, root: int) -> Array:
	var ordered := []
	_collect_subtree(skeleton, root, ordered)

	var index_of := {}
	for i in range(ordered.size()):
		index_of[ordered[i]] = i

	var cache := {}
	var root_global := _get_rest_global(skeleton, root, cache)
	var root_inv := root_global.affine_inverse()

	var out := []
	out.resize(ordered.size())

	for i in range(ordered.size()):
		var bone = ordered[i]
		var parent_local := -1

		if bone != root:
			var p := skeleton.get_bone_parent(bone)
			if index_of.has(p):
				parent_local = index_of[p]

		var bone_global := _get_rest_global(skeleton, bone, cache)
		out[i] = {
			"name": skeleton.get_bone_name(bone),
			"parent_local": parent_local,
			"rel_global": root_inv * bone_global
		}

	return out

func _collect_subtree(skeleton: Skeleton3D, bone: int, out: Array) -> void:
	out.append(bone)
	for c in skeleton.get_bone_children(bone):
		_collect_subtree(skeleton, c, out)


func _get_rest_global(skeleton: Skeleton3D, bone: int, cache: Dictionary) -> Transform3D:
	if cache.has(bone):
		return cache[bone]

	var rest := skeleton.get_bone_rest(bone)
	var parent := skeleton.get_bone_parent(bone)
	var result := rest if parent < 0 else _get_rest_global(skeleton, parent, cache) * rest

	cache[bone] = result
	return result


func _build_name_set(skeleton: Skeleton3D) -> Dictionary:
	var set := {}
	for i in range(skeleton.get_bone_count()):
		set[skeleton.get_bone_name(i)] = true
	return set


func _make_unique_name(existing: Dictionary, base: String) -> String:
	base = base.strip_edges()
	if base.is_empty():
		base = "Bone"

	if not existing.has(base):
		existing[base] = true
		return base

	var i := 1
	while true:
		var candidate := "%s_copy%d" % [base, i]
		if not existing.has(candidate):
			existing[candidate] = true
			return candidate
		i += 1
	return base

func _refresh(skeleton: Skeleton3D) -> void:
	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	skeleton.update_gizmos()
	skeleton.property_list_changed.emit()


func _can_access_skeleton() -> bool:
	return context != null and context.skeleton != null


func _can_paste() -> bool:
	if not _can_access_skeleton():
		return false
	if not context.is_edit_mode():
		_push_edit_mode_toast()
		return false
	if undo_snapshot_service == null:
		return false
	return has_clipboard()


func _is_valid_bone(index: int) -> bool:
	return index >= 0 and index < context.skeleton.get_bone_count()


func _push_edit_mode_toast() -> void:
	if context == null or context.editor_interface == null:
		return
	var toaster := context.editor_interface.get_editor_toaster()
	if toaster != null:
		toaster.push_toast(
			"Switch to Edit Mode to modify bones.",
			EditorToaster.SEVERITY_INFO
		)
