@tool
extends RefCounted
class_name ArmatureSpringBoneChainService


var context: ArmatureSkeletonContext = null
var selection_service: ArmatureSelectionService = null


## Sets dependencies used by this service.
func set_dependencies(p_context: ArmatureSkeletonContext, p_selection_service: ArmatureSelectionService) -> void:
	context = p_context
	selection_service = p_selection_service


## Builds a valid linear chain from the current selection and registers it.
## The chain is authored directly into SpringBoneSimulator3D (no Skeleton meta storage).
func _build_valid_chain_from_selection() -> void:
	if context == null or context.skeleton == null:
		return
	if selection_service == null:
		return

	var skeleton := context.skeleton
	var selected: Array[int] = selection_service._get_selected_bone_indices()
	if selected.is_empty():
		return

	var simulator := _ensure_spring_simulator()
	if simulator == null:
		return

	var chain := PackedInt32Array()
	if selected.size() > 1:
		chain = _try_build_linear_chain(skeleton, selected)
	else:
		chain = _try_build_linear_chain_from_single(skeleton, selected[0])

	if chain.is_empty():
		return

	var conflict := _find_chain_conflict_bone(skeleton, simulator, chain)
	if conflict != -1:
		_warn_chain_conflict(conflict)
		return

	_add_chain_to_simulator(chain)



# Finds a conflicting bone index if this chain overlaps with existing chains.
# - OK: a bone being used as another chain's root/end, if this chain uses it as root/end too.
# - Not OK: any candidate bone that is an interior bone of an existing chain.
# - Not OK: any interior bone of the candidate chain that is used anywhere in an existing chain.
func _find_chain_conflict_bone(
	skeleton: Skeleton3D,
	simulator: SpringBoneSimulator3D,
	candidate: PackedInt32Array
) -> int:
	if skeleton == null or simulator == null:
		return -1
	if candidate.size() < 2:
		return -1

	var candidate_root := candidate[0]
	var candidate_end := candidate[candidate.size() - 1]

	var used_any := {}
	var used_interior := {}

	for i in range(simulator.setting_count):
		var root := simulator.get_root_bone(i)
		var end := simulator.get_end_bone(i)
		if root == -1 or end == -1:
			continue

		var chain_bones := _get_simulator_chain_bones(skeleton, root, end)
		if chain_bones.is_empty():
			continue

		for b in chain_bones:
			used_any[b] = true
		for j in range(1, chain_bones.size() - 1):
			used_interior[chain_bones[j]] = true

	for b in candidate:
		var is_endpoint := b == candidate_root or b == candidate_end

		if used_interior.has(b):
			return b

		if not is_endpoint and used_any.has(b):
			return b

	return -1


# Shows a warning toast for a conflicting bone.
func _warn_chain_conflict(bone_index: int) -> void:
	if context == null or context.skeleton == null:
		return
	if context.editor_interface == null:
		return

	var skeleton := context.skeleton
	var bone_name := skeleton.get_bone_name(bone_index) if bone_index >= 0 and bone_index < skeleton.get_bone_count() else str(bone_index)

	context.editor_interface.get_editor_toaster().push_toast(
		"Spring chain not created: bone '%s' is already part of an existing spring chain." % bone_name,
		EditorToaster.SEVERITY_WARNING
	)


# Reconstructs a simulator chain's bone list from end->root by walking parents.
func _get_simulator_chain_bones(skeleton: Skeleton3D, root: int, end: int) -> Array[int]:
	var out: Array[int] = []
	if skeleton == null:
		return out
	if root == -1 or end == -1:
		return out

	var bone_count := skeleton.get_bone_count()
	if root < 0 or root >= bone_count:
		return out
	if end < 0 or end >= bone_count:
		return out

	var current := end
	while current != -1:
		out.append(current)
		if current == root:
			break
		current = skeleton.get_bone_parent(current)

	if out.is_empty() or out[out.size() - 1] != root:
		return []

	out.reverse()
	return out


## Returns true if the given bone is referenced by the simulator and belongs to any chain.
func _is_spring_bone(skeleton: Skeleton3D, bone: int) -> bool:
	if skeleton == null:
		return false

	var simulator := _find_spring_simulator_child()
	if simulator == null:
		return false

	var bone_count := skeleton.get_bone_count()
	if bone < 0 or bone >= bone_count:
		return false

	for i in range(simulator.setting_count):
		var root := simulator.get_root_bone(i)
		var end := simulator.get_end_bone(i)

		if root == -1 or end == -1:
			continue

		var current := end
		while current != -1:
			if current == bone:
				return true
			if current == root:
				break
			current = skeleton.get_bone_parent(current)

	return false


# Builds a chain by walking up/down from a single bone until a boundary is reached.
func _try_build_linear_chain_from_single(skeleton: Skeleton3D, start_bone: int) -> PackedInt32Array:
	if skeleton == null:
		return PackedInt32Array()

	var bone_count := skeleton.get_bone_count()
	if start_bone < 0 or start_bone >= bone_count:
		return PackedInt32Array()

	var root := _find_linear_root(skeleton, start_bone)
	var end := _find_linear_end(skeleton, start_bone)

	if root == -1 or end == -1:
		return PackedInt32Array()

	var out := PackedInt32Array()
	var current := root
	while current != -1:
		out.append(current)
		if current == end:
			break

		var children := skeleton.get_bone_children(current)
		if children.size() != 1:
			return PackedInt32Array()

		current = children[0]

	if out.size() < 2:
		return PackedInt32Array()

	return out


# Walk parents while the parent has exactly one child (no branching).
func _find_linear_root(skeleton: Skeleton3D, bone: int) -> int:
	var current := bone
	while true:
		var p := skeleton.get_bone_parent(current)
		if p == -1:
			return current

		var siblings := skeleton.get_bone_children(p)
		if siblings.size() != 1:
			return current

		current = p
	return current


# Walk children while there is exactly one child (no branching).
func _find_linear_end(skeleton: Skeleton3D, bone: int) -> int:
	var current := bone
	while true:
		var children := skeleton.get_bone_children(current)
		if children.size() != 1:
			return current
		current = children[0]
	return current


func _try_build_linear_chain(skeleton: Skeleton3D, selected: Array[int]) -> PackedInt32Array:
	var selected_set := {}
	for b in selected:
		selected_set[b] = true

	var next_of := {}
	var prev_of := {}
	var in_degree := {}
	var out_degree := {}

	for b in selected:
		next_of[b] = -1
		prev_of[b] = -1
		in_degree[b] = 0
		out_degree[b] = 0

	for b in selected:
		var p := skeleton.get_bone_parent(b)
		if p == -1:
			continue
		if not selected_set.has(p):
			continue

		if prev_of[b] != -1 and prev_of[b] != p:
			return PackedInt32Array()

		prev_of[b] = p
		in_degree[b] = 1

		if next_of[p] != -1 and next_of[p] != b:
			return PackedInt32Array()

		next_of[p] = b
		out_degree[p] = 1

	var root := -1
	for b in selected:
		if in_degree[b] == 0:
			if root != -1:
				return PackedInt32Array()
			root = b

	if root == -1:
		return PackedInt32Array()

	var ordered: Array[int] = []
	var current := root
	while current != -1:
		ordered.append(current)
		current = next_of[current]

	if ordered.size() != selected.size():
		return PackedInt32Array()

	var last_selected := ordered[ordered.size() - 1]
	var tip := last_selected
	var children := skeleton.get_bone_children(last_selected)
	if not children.is_empty():
		tip = children[0]

	if not ordered.has(tip):
		ordered.append(tip)

	var out := PackedInt32Array()
	for b in ordered:
		out.append(b)
	return out


## Ensures a SpringBoneSimulator3D exists under the active skeleton.
func _ensure_spring_simulator() -> SpringBoneSimulator3D:
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


## Adds a chain definition to the simulator if it doesn't already exist.
func _add_chain_to_simulator(bones: PackedInt32Array) -> void:
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	var simulator := _ensure_spring_simulator()
	if simulator == null:
		return
	if bones.size() < 2:
		return

	var root := bones[0]
	var end := bones[bones.size() - 1]

	for i in range(simulator.setting_count):
		if simulator.get_root_bone(i) == root:
			return

	var index := simulator.setting_count
	simulator.setting_count = index + 1

	simulator.set_root_bone(index, root)
	simulator.set_end_bone(index, end)

	simulator.set_center_from(index, SpringBoneSimulator3D.CENTER_FROM_NODE)
	simulator.set_center_node(index, skeleton.get_path())

	simulator.set_stiffness(index, 0.6)
	simulator.set_drag(index, 0.2)

	var gravity_vec := Vector3(0, 1, 0)
	simulator.set_gravity(index, gravity_vec.length())
	if gravity_vec.length() > 0.00001:
		simulator.set_gravity_direction(index, gravity_vec.normalized())

	simulator.set_rotation_axis(index, SkeletonModifier3D.ROTATION_AXIS_ALL)
	simulator.set_radius(index, 0.02)

	simulator.reset()


func _find_spring_simulator_child() -> SpringBoneSimulator3D:
	if context == null or context.skeleton == null:
		return null
	for child in context.skeleton.get_children():
		if child is SpringBoneSimulator3D:
			return child
	return null
