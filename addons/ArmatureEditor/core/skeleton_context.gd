# ArmatureSkeletonContext.gd
# Centralized context for the active Skeleton3D and related editor services.

@tool
extends Node
class_name ArmatureSkeletonContext

var skeleton: Skeleton3D = null
var gizmo_plugin: EditorNode3DGizmoPlugin = null
var editor_interface: EditorInterface = null
var undo_redo: EditorUndoRedoManager = null
var toolbar: Node = null

func _init():
	pass


# Sets the active skeleton for the context.
# The context will hold a weak reference to the provided skeleton and wire necessary callbacks.
#
# @param sk The Skeleton3D node to set as active.
func set_skeleton(sk: Skeleton3D) -> void:
	_clear_existing_skeleton()
	if sk == null:
		return
	skeleton = sk
	# Connect to pose updates so external UI can refresh gizmos when pose changes.
	if not skeleton.is_connected("pose_updated",_on_skeleton_pose_updated):
		skeleton.connect("pose_updated",_on_skeleton_pose_updated,CONNECT_DEFERRED)


# Clears the active skeleton from the context and removes any connected hooks.
func clear_skeleton() -> void:
	_clear_existing_skeleton()
	skeleton = null

func get_edit_mode() -> int:
	if toolbar == null:
		return 0
	if not toolbar.has_method("get"):
		return 0

	return int(toolbar.get("mode"))

# Returns true when the current toolbar indicates edit mode.
func is_edit_mode() -> bool:
	if toolbar == null:
		return false
	if not toolbar.has_method("get"):
		return false
	return int(toolbar.get("mode")) == 1


# Return the currently active gizmo instance for the active skeleton, or null.
func get_active_gizmo() -> EditorNode3DGizmo:
	if skeleton == null:
		return null
	var gizmos := skeleton.get_gizmos()
	if gizmos.is_empty():
		return null
	return gizmos[0]


# Return selected bone indices (unique) from the active gizmo selection.
# This preserves the original function name used in the monolithic script.
#
# Returns an Array[int] of selected bone indices.
func _get_selected_bone_indices() -> Array[int]:
	if skeleton == null:
		return []
	if gizmo_plugin == null:
		return []

	var gizmos = skeleton.get_gizmos()
	if gizmos.is_empty():
		return []

	var gizmo = gizmos[0]
	var ids = gizmo_plugin.get_selected_ids(gizmo)

	var bones: Array[int] = []
	for id in ids:
		var bone_idx = id >> 1
		if not bones.has(bone_idx):
			bones.append(bone_idx)
	return bones


# Return a single context bone suitable for context-menu operations.
# If a tip bone is selected the parent is returned so operations target the real bone.
#
# Returns an int bone index or -1 if none available.
func get_context_bone_from_selection() -> int:
	var bones := _get_selected_bone_indices()
	if bones.is_empty():
		return -1
	var bone_index := bones[0]
	if skeleton == null:
		return -1
	var name := skeleton.get_bone_name(bone_index)
	if name.ends_with("_tip"):
		return skeleton.get_bone_parent(bone_index)
	return bone_index


# Return a deterministic bone chain structure (start, end, bones[])
# Mirrors the previous _get_bone_chain function name and behavior.
#
# @param bone_index The bone index to inspect.
# @return Dictionary { "start":int, "end":int, "bones":Array[int] }
func _get_bone_chain(bone_index: int) -> Dictionary:
	if skeleton == null:
		return {}
	if bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return {}

	var start := bone_index
	var end := bone_index

	var current := bone_index
	while true:
		var parent := skeleton.get_bone_parent(current)
		if parent == -1:
			break
		var parent_children := skeleton.get_bone_children(parent)
		if parent_children.size() != 1:
			break
		start = parent
		current = parent

	current = bone_index
	while true:
		var children := skeleton.get_bone_children(current)
		if children.size() != 1:
			break
		var child := children[0]
		end = child
		current = child

	var chain := []
	current = start
	chain.append(current)
	while current != end:
		var children := skeleton.get_bone_children(current)
		if children.is_empty():
			break
		current = children[0]
		chain.append(current)

	return {
		"start": start,
		"end": end,
		"bones": chain
	}


# Sanitize a candidate bone name to a safe canonical form.
# Removes illegal characters and collapses repeated underscores.
#
# @param name Raw user-provided name.
# @return String sanitized name.
func _sanitize_bone_name(name: String) -> String:
	var out := name.strip_edges()
	out = out.replace(" ", "_")
	out = out.replace("/", "_")
	out = out.replace("\\", "_")
	out = out.replace(":", "_")
	out = out.replace(";", "_")
	out = out.replace("\t", "_")
	out = out.replace("\n", "_")
	while out.find("__") != -1:
		out = out.replace("__", "_")
	return out


# Check whether a bone name already exists on the current skeleton.
#
# @param name Candidate bone name.
# @param ignore_bones Optional array of bone indices to ignore.
# @return bool true if name exists (excluding ignored).
func _bone_name_exists(name: String, ignore_bones: Array[int] = []) -> bool:
	if skeleton == null:
		return false
	for i in range(skeleton.get_bone_count()):
		if ignore_bones.has(i):
			continue
		if skeleton.get_bone_name(i) == name:
			return true
	return false


# Create a unique bone name by appending numeric suffixes when needed.
#
# @param base Base candidate name.
# @param ignore_bones Optional array of bone indices to ignore when checking collisions.
# @return String unique name (may be base if free).
func _make_unique_bone_name(base: String, ignore_bones: Array[int] = []) -> String:
	if not _bone_name_exists(base, ignore_bones):
		return base
	var i := 2
	while true:
		var candidate := "%s_%d" % [base, i]
		if not _bone_name_exists(candidate, ignore_bones):
			return candidate
		i += 1
	return base


# Determine the major camera-aligned view plane for projection helpers.
#
# Returns a Plane oriented on the dominant camera axis passing through origin.
func _get_major_view_plane(camera: Camera3D, origin: Vector3) -> Plane:
	var forward := -camera.global_transform.basis.z.normalized()
	var abs_x := abs(forward.x)
	var abs_y := abs(forward.y)
	var abs_z := abs(forward.z)
	if abs_x > abs_y and abs_x > abs_z:
		return Plane(Vector3.RIGHT, origin)
	if abs_y > abs_x and abs_y > abs_z:
		return Plane(Vector3.UP, origin)
	return Plane(Vector3.BACK, origin)


func _clear_existing_skeleton() -> void:
	if skeleton != null and skeleton.is_connected("pose_updated", _on_skeleton_pose_updated):
		skeleton.disconnect("pose_updated", _on_skeleton_pose_updated)


func _on_skeleton_pose_updated() -> void:
	if skeleton:
		skeleton.update_gizmos()
