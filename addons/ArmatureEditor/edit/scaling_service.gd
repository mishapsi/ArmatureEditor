@tool
extends RefCounted
class_name ArmatureScalingService

var context: ArmatureSkeletonContext = null
var selection_service: ArmatureSelectionService = null
var undo_snapshot_service: ArmatureUndoRedoService = null
var skeleton_edit_service: ArmatureEditService = null

var snap_enabled: bool = false
var snap_amount: float = 0.1


## Sets dependencies used by this service.
func set_dependencies(
	p_context: ArmatureSkeletonContext,
	p_selection_service: ArmatureSelectionService,
	p_undo_snapshot_service: ArmatureUndoRedoService,
	p_skeleton_edit_service: ArmatureEditService
) -> void:
	context = p_context
	selection_service = p_selection_service
	undo_snapshot_service = p_undo_snapshot_service
	skeleton_edit_service = p_skeleton_edit_service


## Returns true when the scaling modal is active.
func is_scaling() -> bool:
	return _is_scaling


## Begins the scaling modal using the current bone selection.
func try_begin(viewport: Object, start_mouse_pos: Vector2) -> bool:
	if _is_scaling:
		return false
	if context == null or context.skeleton == null:
		return false
	if not context.is_edit_mode():
		_push_edit_mode_toast()
		return false
	if selection_service == null or undo_snapshot_service == null or skeleton_edit_service == null:
		return false

	var selected := selection_service.get_contextual_bone_selection()
	if selected.is_empty():
		return false

	_is_scaling = true
	_scale_start_mouse = start_mouse_pos
	_scale_pre_snapshot = undo_snapshot_service.capture()
	_scale_selected_bones = selected
	_scale_factor = 1.0

	_mark_handled(viewport)
	return true


## Handles input while the scaling modal is active.
## @return int forwarding result (0 = pass, 1 = handled, 2 = handled + stop)
func handle(viewport: Object, event: InputEvent) -> int:
	if not _is_scaling:
		return 0
	if context == null or context.skeleton == null:
		cancel()
		_mark_handled(viewport)
		return 2

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_ESCAPE:
			cancel()
			_mark_handled(viewport)
			return 2

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			_mark_handled(viewport)
			return 2
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			commit()
			_mark_handled(viewport)
			return 2

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var factor := _compute_scale_factor_from_mouse(mm.position)
		_apply_preview(factor)
		_mark_handled(viewport)
		return 2

	_mark_handled(viewport)
	return 2


## Commits the current preview into a single UndoRedo action.
func commit() -> void:
	if not _is_scaling:
		return
	if undo_snapshot_service == null:
		_end()
		return

	var post := undo_snapshot_service.capture()
	undo_snapshot_service.commit("Scale Bone Lengths", _scale_pre_snapshot, post, true)
	_end()


## Cancels and restores the skeleton to the pre-snapshot.
func cancel() -> void:
	if not _is_scaling:
		return
	if undo_snapshot_service != null:
		undo_snapshot_service._restore_snapshot_internal(_scale_pre_snapshot)
	_end()

var _is_scaling := false
var _scale_start_mouse := Vector2.ZERO
var _scale_pre_snapshot: Array = []
var _scale_selected_bones: PackedInt32Array = PackedInt32Array()
var _scale_factor := 1.0


func _end() -> void:
	_is_scaling = false
	_scale_start_mouse = Vector2.ZERO
	_scale_pre_snapshot.clear()
	_scale_selected_bones = PackedInt32Array()
	_scale_factor = 1.0


func _compute_scale_factor_from_mouse(mouse_pos: Vector2) -> float:
	var dx := mouse_pos.x - _scale_start_mouse.x
	var factor := 1.0 + (dx * 0.005)
	factor = max(0.001, factor)

	if snap_enabled:
		factor = _snap_factor(factor)

	return factor


func _snap_factor(factor: float) -> float:
	var step := max(0.0001, absf(snap_amount))
	return max(0.001, round(factor / step) * step)


func _apply_preview(factor: float) -> void:
	if context == null or context.skeleton == null:
		return
	if undo_snapshot_service == null or skeleton_edit_service == null:
		return
	if _scale_pre_snapshot.is_empty() or _scale_selected_bones.is_empty():
		return

	undo_snapshot_service._restore_snapshot_internal(_scale_pre_snapshot)
	scale_bone_lengths(context.skeleton, _scale_selected_bones, factor)
	_scale_factor = factor


func _mark_handled(viewport: Object) -> void:
	if viewport != null and viewport.has_method("set_input_as_handled"):
		viewport.call("set_input_as_handled")


func _push_edit_mode_toast() -> void:
	if context == null or context.editor_interface == null:
		return
	var toaster_obj := context.editor_interface.get_editor_toaster()
	if toaster_obj != null:
		toaster_obj.push_toast(
			"Switch to Edit Mode to modify bones.",
			EditorToaster.SEVERITY_INFO
		)

## Scales the rest-length of the given bones by scaling their direct children offsets.
## Intended for proportional edits without changing Skeleton3D node scale.
func scale_bone_lengths(
	skeleton: Skeleton3D,
	bone_indices: PackedInt32Array,
	length_scale: float,
	min_child_distance: float = 0.0001
) -> void:
	if skeleton == null:
		return
	if bone_indices.is_empty():
		return

	var s := max(min_child_distance, absf(length_scale))
	var unique := _unique_valid_bones(skeleton, bone_indices)
	if unique.is_empty():
		return

	for bone in unique:
		_scale_direct_children_offsets(skeleton, bone, s, min_child_distance)


## Scales the rest-length of a single bone by scaling its direct children offsets.
## Intended for proportional edits without changing Skeleton3D node scale.
func scale_bone_length(
	skeleton: Skeleton3D,
	bone_index: int,
	length_scale: float,
	min_child_distance: float = 0.0001
) -> void:
	if skeleton == null:
		return
	if bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return

	var s := max(min_child_distance, absf(length_scale))
	_scale_direct_children_offsets(skeleton, bone_index, s, min_child_distance)

func _unique_valid_bones(skeleton: Skeleton3D, bone_indices: PackedInt32Array) -> PackedInt32Array:
	var set := {}
	for b in bone_indices:
		if b < 0 or b >= skeleton.get_bone_count():
			continue
		set[b] = true

	var out := PackedInt32Array()
	out.resize(set.size())

	var i := 0
	for k in set.keys():
		out[i] = int(k)
		i += 1

	return out

func _scale_direct_children_offsets(
	skeleton: Skeleton3D,
	parent_bone: int,
	length_scale: float,
	min_child_distance: float
) -> void:
	var children := skeleton.get_bone_children(parent_bone)
	if children.is_empty():
		return

	var snap_step := max(0.0001, absf(snap_amount))

	for child in children:
		var parent_rest := skeleton.get_bone_rest(parent_bone)
		var child_rest := skeleton.get_bone_rest(child)

		var local_offset := child_rest.origin
		var local_len := local_offset.length()

		if local_len <= 0.0:
			local_offset = Vector3(0.0, 0.0, min_child_distance)
			local_len = local_offset.length()

		var dir := local_offset / local_len

		var parent_global := parent_rest.affine_inverse()
		var world_parent_basis := parent_rest.basis

		var world_offset := world_parent_basis * local_offset
		var world_len := world_offset.length()

		var target_world_len := max(min_child_distance, world_len * length_scale)

		if snap_enabled:
			target_world_len = max(
				min_child_distance,
				snappedf(target_world_len, snap_step)
			)


		var parent_scale := world_parent_basis.get_scale()
		var uniform_scale := parent_scale.x

		var target_local_len = target_world_len / max(0.0001, uniform_scale)

		child_rest.origin = dir * target_local_len
		skeleton.set_bone_rest(child, child_rest)
