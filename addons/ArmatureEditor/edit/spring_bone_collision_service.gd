@tool
extends RefCounted
class_name ArmatureSpringBoneCollisionService

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager

## Creates a spring collision capsule attached to the given bone.
func create_capsule_for_bone(context: ArmatureSkeletonContext, bone_index: int) -> void:
	if editor_interface == null or undo_redo == null:
		return
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	if bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return

	var simulator := _ensure_spring_simulator(context)
	if simulator == null:
		return

	var capsule := _create_capsule_node()
	if capsule == null:
		return

	var bone_name := skeleton.get_bone_name(bone_index)
	capsule.name = _make_unique_child_name(simulator, "%s_COL" % bone_name)

	_assign_capsule_binding(capsule, skeleton, bone_index, bone_name)
	_apply_offsets_from_child_bones(capsule, skeleton, bone_index)

	var scene_root := editor_interface.get_edited_scene_root()
	var owner := scene_root if scene_root != null else skeleton

	undo_redo.create_action("Create Spring Collision Capsule")
	undo_redo.add_do_method(simulator, "add_child", capsule, true)
	undo_redo.add_do_method(capsule, "set_owner", owner)
	undo_redo.add_undo_method(simulator, "remove_child", capsule)
	undo_redo.add_undo_method(capsule, "queue_free")
	undo_redo.commit_action()

func _create_capsule_node() -> Node:
	if ClassDB.class_exists("SpringBoneCollisionCapsule3D"):
		return ClassDB.instantiate("SpringBoneCollisionCapsule3D") as Node
	return null


func _assign_capsule_binding(capsule: Node, skeleton: Skeleton3D, bone_index: int, bone_name: String) -> void:
	if capsule.has_method("set_skeleton_path"):
		capsule.call("set_skeleton_path", capsule.get_path_to(skeleton))
	elif capsule.has_method("set_skeleton"):
		capsule.call("set_skeleton", skeleton)
	elif "skeleton_path" in capsule:
		capsule.set("skeleton_path", capsule.get_path_to(skeleton))
	elif "skeleton" in capsule:
		capsule.set("skeleton", skeleton)

	if capsule.has_method("set_bone_index"):
		capsule.call("set_bone_index", bone_index)
	elif "bone_index" in capsule:
		capsule.set("bone_index", bone_index)
	elif capsule.has_method("set_bone_name"):
		capsule.call("set_bone_name", bone_name)
	elif "bone_name" in capsule:
		capsule.set("bone_name", bone_name)

func _apply_offsets_from_child_bones(capsule: Node, skeleton: Skeleton3D, bone_index: int) -> void:
	var dir_len := _get_local_child_direction_and_length(skeleton, bone_index)
	if dir_len.is_empty():
		return

	var dir: Vector3 = dir_len[0]
	var length: float = dir_len[1]

	_set_if_present(capsule, "position_offset", dir * (length * 0.5))

	var capsule_top_axis := Vector3.UP
	var q := _quat_from_axis_to_dir(capsule_top_axis, dir)
	_set_if_present(capsule, "rotation_offset", q)
	_set_if_present(capsule, "height", length)
	_set_if_present(capsule, "length", length)
	_set_if_present(capsule, "capsule_height", length)

func _quat_from_axis_to_dir(axis: Vector3, dir: Vector3) -> Quaternion:
	var a := axis.normalized()
	var b := dir.normalized()

	if a.length() <= 0.00001 or b.length() <= 0.00001:
		return Quaternion.IDENTITY

	var d := a.dot(b)

	if d < -0.9999:
		var ortho := Vector3.RIGHT
		if abs(a.dot(ortho)) > 0.999:
			ortho = Vector3.FORWARD
		var rot_axis := a.cross(ortho).normalized()
		return Quaternion(rot_axis, PI)

	return Quaternion(a, b)

func _get_local_child_direction_and_length(skeleton: Skeleton3D, bone_index: int) -> Array:
	var children := skeleton.get_bone_children(bone_index)
	if children.is_empty():
		return []

	var accum := Vector3.ZERO
	var longest := 0.0

	for child_idx in children:
		if child_idx < 0 or child_idx >= skeleton.get_bone_count():
			continue
		var child_rest := skeleton.get_bone_rest(child_idx)
		var v := child_rest.origin
		var l := v.length()
		if l <= 0.00001:
			continue
		accum += v.normalized()
		longest = max(longest, l)

	if accum.length() <= 0.00001 or longest <= 0.00001:
		return []

	return [accum.normalized(), longest]

func _rotation_value_for_property(node: Object, prop: StringName, basis: Basis) -> Variant:
	if not (prop in node):
		return null

	var current := node.get(prop)
	match typeof(current):
		TYPE_VECTOR3:
			return basis.get_euler()
		TYPE_QUATERNION:
			return basis.get_rotation_quaternion()
		TYPE_BASIS:
			return basis
		_:
			return null


func _set_if_present(node: Object, prop: StringName, value: Variant) -> void:
	if not (prop in node):
		return
	node.set(prop, value)


func _make_unique_child_name(parent: Node, base_name: String) -> String:
	if not parent.has_node(base_name):
		return base_name
	var i := 2
	while parent.has_node("%s_%d" % [base_name, i]):
		i += 1
	return "%s_%d" % [base_name, i]

## Ensures a SpringBoneSimulator3D exists under the active skeleton.
func _ensure_spring_simulator(context: ArmatureSkeletonContext) -> SpringBoneSimulator3D:
	if context == null or context.skeleton == null:
		return null
	if context.editor_interface == null:
		return null

	var skeleton := context.skeleton
	var scene_root := context.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return null

	for child in skeleton.get_children():
		if child is SpringBoneSimulator3D:
			return child

	var simulator := SpringBoneSimulator3D.new()
	simulator.name = "SpringBoneSimulator"
	skeleton.add_child(simulator)
	simulator.owner = scene_root
	return simulator
