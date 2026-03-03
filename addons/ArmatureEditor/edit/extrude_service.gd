@tool
extends RefCounted
class_name ArmatureExtrudeService

signal finished_extrusion

var context: ArmatureSkeletonContext = null
var selection_service: ArmatureSelectionService = null
var view_plane_service: ArmatureViewPlaneService = null

var _is_extruding := false
var _extrude_bone := -1
var _extrude_tip := -1
var _extrude_parent := -1
var _extrude_length := 0.5

var snap_enabled = true
var snap_amount = .1

## Sets the context and dependencies used by this service.
func set_dependencies(
	p_context: ArmatureSkeletonContext,
	p_selection_service: ArmatureSelectionService,
	p_view_plane_service: ArmatureViewPlaneService
) -> void:
	context = p_context
	selection_service = p_selection_service
	view_plane_service = p_view_plane_service


## Returns true if an extrude drag is currently active.
func is_extruding() -> bool:
	return _is_extruding


## Begins an extrude from the current selection.
## Preserves the original function name.
func _begin_extrude() -> void:
	if context == null:
		return
	if context.skeleton == null:
		return
	if selection_service == null:
		return

	var skeleton := context.skeleton
	var gizmo := context.get_active_gizmo()
	if gizmo == null:
		return

	var selected_ids := selection_service.get_selected_subgizmo_ids()
	if selected_ids.is_empty():
		return

	for sub_id in selected_ids:
		var bone: int = int(sub_id / 2)
		var part: int = int(sub_id % 2) # 0 = body, 1 = joint

		if bone < 0 or bone >= skeleton.get_bone_count():
			continue

		if part == 1:
			var preceding := skeleton.get_bone_parent(bone)
			if preceding != -1:
				bone = preceding

		var is_leaf := skeleton.get_bone_children(bone).is_empty()

		var parent_bone := bone if is_leaf else int(skeleton.get_bone_children(bone)[0])
		_extrude_parent = parent_bone

		var transferred_rest := Transform3D.IDENTITY
		var parent_is_leaf := skeleton.get_bone_children(parent_bone).is_empty()
		var real_parent := parent_bone

		if parent_is_leaf:
			real_parent = skeleton.get_bone_parent(parent_bone)
			transferred_rest = skeleton.get_bone_rest(parent_bone)
			_delete_bone(parent_bone)

		_extrude_parent = real_parent
		_extrude_bone = _create_extrude_bone(real_parent, transferred_rest)
		_extrude_tip = _create_tip_bone(_extrude_bone, _extrude_length)
		_is_extruding = true
		break

	if _extrude_bone == -1:
		return

	var new_subgizmo_id := _extrude_bone * 2 + 1
	var t := skeleton.get_bone_global_rest(_extrude_bone)

	skeleton.clear_subgizmo_selection()
	skeleton.set_subgizmo_selection(gizmo, new_subgizmo_id, t)
	skeleton.update_gizmos()

## Updates the current extrude drag using a mouse motion event.
## Preserves the original function name.
func _update_extrude(event: InputEventMouseMotion) -> void:
	if not _is_extruding:
		return
	if context == null or context.skeleton == null:
		return
	if context.editor_interface == null:
		return
	if view_plane_service == null:
		return

	var skeleton := context.skeleton
	var viewport := context.editor_interface.get_editor_viewport_3d()
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return

	var ray_origin := camera.project_ray_origin(event.position)
	var ray_dir := camera.project_ray_normal(event.position)

	var parent_rest := skeleton.get_bone_global_rest(_extrude_parent)
	var parent_global := skeleton.global_transform * parent_rest
	var parent_tail_world := parent_global.origin

	var plane := view_plane_service.get_major_view_plane(camera, parent_tail_world)
	var hit := plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return

	var new_tail_world: Vector3 = hit
	if snap_enabled:
		new_tail_world = new_tail_world.snapped(Vector3(snap_amount,snap_amount,snap_amount))
	var dir_world := new_tail_world - parent_tail_world
	var length := dir_world.length()

	if length < 0.01:
		return

	dir_world = dir_world.normalized()

	var parent_basis := parent_global.basis
	var basis_world := Basis().looking_at(-dir_world, parent_basis.y)

	var rest := skeleton.get_bone_rest(_extrude_bone)
	rest.basis = parent_basis.inverse() * basis_world
	skeleton.set_bone_rest(_extrude_bone, rest)

	var tip_rest := skeleton.get_bone_rest(_extrude_tip)
	tip_rest.origin = Vector3(0, 0, length)
	if snap_enabled:
		tip_rest.origin = tip_rest.origin.snapped(Vector3(snap_amount, snap_amount, snap_amount))
	skeleton.set_bone_rest(_extrude_tip, tip_rest)

	skeleton.update_gizmos()


## Ends the current extrude drag and returns the created bone indices.
## The caller is responsible for naming and undo/redo commit steps.
##
## @return Dictionary { "bone": int, "tip": int, "parent": int }
func finish_extrude() -> Dictionary:
	if not _is_extruding:
		return {}

	var result := {
		"bone": _extrude_bone,
		"tip": _extrude_tip,
		"parent": _extrude_parent,
	}

	_is_extruding = false
	_extrude_bone = -1
	_extrude_tip = -1
	_extrude_parent = -1
	return result


func _create_extrude_bone(parent_bone: int, rest: Transform3D) -> int:
	var skeleton := context.skeleton
	var new_index := skeleton.get_bone_count()
	skeleton.add_bone("Bone_%d" % new_index)
	skeleton.set_bone_parent(new_index, parent_bone)
	skeleton.set_bone_rest(new_index, rest)
	return new_index


func _create_tip_bone(parent_bone: int, length: float) -> int:
	var skeleton := context.skeleton
	var tip_index := skeleton.get_bone_count()
	skeleton.add_bone("Bone_%d_tip" % tip_index)
	skeleton.set_bone_parent(tip_index, parent_bone)

	var tip_rest := Transform3D.IDENTITY
	tip_rest.origin = Vector3(0, 0, length)
	skeleton.set_bone_rest(tip_index, tip_rest)
	return tip_index


func _delete_bone(delete_index: int) -> void:
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	var bone_count := skeleton.get_bone_count()
	if delete_index < 0 or delete_index >= bone_count:
		return

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
		if i == delete_index:
			continue
		index_remap[i] = new_index
		new_index += 1

	skeleton.clear_bones()

	for i in range(bone_count):
		if i == delete_index:
			continue
		skeleton.add_bone(names[i])

	for i in range(bone_count):
		if i == delete_index:
			continue

		var new_i: int = index_remap[i]
		var old_parent: int = parents[i]

		if old_parent == -1 or old_parent == delete_index:
			skeleton.set_bone_parent(new_i, -1)
		else:
			skeleton.set_bone_parent(new_i, index_remap[old_parent])

	for i in range(bone_count):
		if i == delete_index:
			continue

		var new_i: int = index_remap[i]
		skeleton.set_bone_rest(new_i, rests[i])

	skeleton.update_gizmos()
