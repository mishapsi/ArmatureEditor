@tool
extends EditorPlugin

const SKELETON_GIZMO = preload("res://addons/armatureeditor/skeleton_gizmo.gd")
const TOOLBAR_SCENE := preload("res://addons/armatureeditor/toolbar.tscn")

var toolbar: Control

var skeleton_gizmo
var skeleton: Skeleton3D
var _is_extruding := false
var _extrude_bone := -1
var _extrude_parent := -1
var _extrude_start_mouse := Vector2.ZERO
var _extrude_start_dir := Vector3.ZERO
var _extrude_length := 0.5
var _undo_redo: EditorUndoRedoManager
var _pre_extrude_snapshot := []
var _post_extrude_snapshot := []

func _enter_tree():
	_undo_redo = get_undo_redo()
	skeleton_gizmo = SKELETON_GIZMO.new()
	add_node_3d_gizmo_plugin(skeleton_gizmo)
	skeleton_gizmo.recorded_bones_changed.connect(_on_recorded_bones_changed)
	set_input_event_forwarding_always_enabled()
	toolbar = TOOLBAR_SCENE.instantiate()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar) 
	toolbar.mode_changed.connect(_on_skeleton_mode_changed)

func _on_recorded_bones_changed(bone_indices:Array):
	get_editor_interface().get_edited_scene_root().get_node("%AnimationPlayer").key_bone_indices(bone_indices)

func _on_skeleton_mode_changed(mode:int):
	skeleton_gizmo.set_mode(mode)
	if mode == 0:
		skeleton.show_rest_only = false
	elif mode == 1:
		skeleton.show_rest_only = true

func _exit_tree():
	remove_node_3d_gizmo_plugin(skeleton_gizmo)
	if toolbar:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar)
		toolbar.queue_free()
		toolbar = null

func _is_edit_mode() -> bool:
	return toolbar != null and toolbar.has_method("get") and int(toolbar.get("mode")) == 1

func _handles(object: Object) -> bool:
	if object is Skeleton3D:
		skeleton = object
		skeleton.pose_updated.connect(func():
			if skeleton:
				skeleton.update_gizmos()
			)
	else:
		skeleton = null
	return skeleton != null

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:

	if skeleton == null:
		return 0

	var gizmos = skeleton.get_gizmos()
	if gizmos.is_empty():
		return 0

	var gizmo = gizmos[0]
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and skeleton_gizmo._ik_drag_active:
		get_editor_interface().get_editor_viewport_3d().set_input_as_handled()
		skeleton_gizmo.influence_count = clamp(skeleton_gizmo.influence_count + 1, 2, 10)
		return 1
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and skeleton_gizmo._ik_drag_active:
		get_editor_interface().get_editor_viewport_3d().set_input_as_handled()
		skeleton_gizmo.influence_count = clamp(skeleton_gizmo.influence_count - 1, 2, 10)
		return 1
	# -------------------------
	# Hover update
	# -------------------------
	if event is InputEventMouseMotion and not _is_extruding:
		skeleton_gizmo.update_hover(camera, event.position, gizmo)


	# -------------------------
	# Start extrude
	# -------------------------
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_E and not _is_extruding:
			if _is_edit_mode():
				get_editor_interface().get_editor_viewport_3d().set_input_as_handled()
				_begin_extrude(event)
				return 2

	if _is_extruding and event is InputEventMouseMotion:
		_update_extrude(event)
		return 2

	if _is_extruding and event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_finish_extrude()
			return 2

	#if event is InputEventMouseButton:
		#if !_is_extruding:
			#if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				#var id = skeleton_gizmo._compute_hover(camera, event.position, gizmo)
				#if id != -1:
					#var t = skeleton_gizmo._get_subgizmo_transform(gizmo, id)
					#skeleton.set_subgizmo_selection(gizmo, id, t)
					#skeleton.update_gizmos()
					#return 2  # CRITICAL: stop editor transform gizmo
	return 0


func _delete_bone(delete_index: int):

	if skeleton == null:
		return

	var bone_count := skeleton.get_bone_count()
	if delete_index < 0 or delete_index >= bone_count:
		return

	# --- Cache all existing bone data ---
	var names := []
	var parents := []
	var rests := []

	for i in bone_count:
		names.append(skeleton.get_bone_name(i))
		parents.append(skeleton.get_bone_parent(i))
		rests.append(skeleton.get_bone_rest(i))

	# --- Build remap table ---
	var index_remap := {}
	var new_index := 0

	for i in bone_count:
		if i == delete_index:
			continue
		index_remap[i] = new_index
		new_index += 1

	# --- Clear skeleton completely ---
	while skeleton.get_bone_count() > 0:
		skeleton.clear_bones()

	# --- Recreate bones except deleted ---
	for i in bone_count:
		if i == delete_index:
			continue
		skeleton.add_bone(names[i])

	# --- Reassign parents ---
	for i in bone_count:
		if i == delete_index:
			continue

		var new_i = index_remap[i]
		var old_parent = parents[i]

		if old_parent == -1 or old_parent == delete_index:
			skeleton.set_bone_parent(new_i, -1)
		else:
			skeleton.set_bone_parent(new_i, index_remap[old_parent])

	# --- Restore rest transforms ---
	for i in bone_count:
		if i == delete_index:
			continue

		var new_i = index_remap[i]
		skeleton.set_bone_rest(new_i, rests[i])

	skeleton.update_gizmos()
var _extrude_tip := -1

func _begin_extrude(event: InputEventKey):

	if skeleton == null:
		return

	var gizmos = skeleton.get_gizmos()
	if gizmos.is_empty():
		return

	var gizmo = gizmos[0]
	var selected_ids = skeleton_gizmo.get_selected_ids(gizmo)
	if selected_ids.is_empty():
		return

	_snapshot_into(_pre_extrude_snapshot)

	for id in selected_ids:

		var bone = id / 2
		var part = id % 2

		if part != 1:
			continue

		var is_leaf = skeleton.get_bone_children(bone).is_empty()
		var parent_bone = 0
		if is_leaf:
			parent_bone = bone
		else:
			parent_bone = skeleton.get_bone_children(bone)[0]
		_extrude_parent = parent_bone

		# If extruding from a tip, delete it first
		var bname = skeleton.get_bone_name(parent_bone)
		var old_rest = null
		var extrude_from_tip := false
		var real_parent = parent_bone

		var transferred_rest : Transform3D = Transform3D.IDENTITY

		if "tip" in bname:
			extrude_from_tip = true
			real_parent = skeleton.get_bone_parent(parent_bone)

			# capture tip rest relative to real_parent
			transferred_rest = skeleton.get_bone_rest(parent_bone)
			print(transferred_rest.origin)
			_delete_bone(parent_bone)
		_extrude_parent = real_parent
		_extrude_bone = _create_extrude_bone(real_parent,transferred_rest)
		_extrude_tip = _create_tip_bone(_extrude_bone)
		_is_extruding = true
		break

	if _extrude_bone == -1:
		return

	var new_subgizmo_id := _extrude_bone * 2 + 1
	var t := skeleton.get_bone_global_rest(_extrude_bone)

	skeleton.clear_subgizmo_selection()
	skeleton.set_subgizmo_selection(gizmo, new_subgizmo_id, t)
	skeleton.update_gizmos()
func _create_extrude_bone(parent_bone: int, rest: Transform3D) -> int:

	var new_index := skeleton.get_bone_count()

	skeleton.add_bone("Bone_%d" % new_index)
	skeleton.set_bone_parent(new_index, parent_bone)

	skeleton.set_bone_rest(new_index, rest)

	return new_index

func _create_tip_bone(parent_bone: int) -> int:

	var tip_index := skeleton.get_bone_count()

	skeleton.add_bone("Bone_%d_tip" % tip_index)
	skeleton.set_bone_parent(tip_index, parent_bone)

	var tip_rest := Transform3D.IDENTITY
	tip_rest.origin = Vector3(0, 0, 0.5)

	skeleton.set_bone_rest(tip_index, tip_rest)

	return tip_index
func _update_extrude(event: InputEventMouseMotion):

	if !_is_extruding:
		return

	var viewport = get_editor_interface().get_editor_viewport_3d()
	var camera: Camera3D = viewport.get_camera_3d()

	if camera == null:
		return

	var ray_origin = camera.project_ray_origin(event.position)
	var ray_dir = camera.project_ray_normal(event.position)

	# Parent world transform
	var parent_rest := skeleton.get_bone_global_rest(_extrude_parent)
	var parent_global := skeleton.global_transform * parent_rest
	var parent_tail_world := parent_global.origin

	# Drag plane (camera facing)
	var plane := Plane(camera.global_transform.basis.z, parent_tail_world)
	var hit = plane.intersects_ray(ray_origin, ray_dir)

	if hit == null:
		return

	var new_tail_world: Vector3 = hit.snapped(Vector3(0.1, 0.1, 0.1))
	var dir_world := new_tail_world - parent_tail_world

	var length := dir_world.length()
	if length < 0.01:
		return

	dir_world = dir_world.normalized()

	# Compute orientation
	var parent_basis := parent_global.basis
	var basis_world := Basis().looking_at(-dir_world, parent_basis.y)

	var rest := skeleton.get_bone_rest(_extrude_bone)
	rest.basis = parent_basis.inverse() * basis_world
	skeleton.set_bone_rest(_extrude_bone, rest)

	# Update tip length ONLY
	var tip_rest := skeleton.get_bone_rest(_extrude_tip)
	tip_rest.origin = Vector3(0, 0, length).snapped(Vector3(0.1, 0.1, 0.1))

	skeleton.set_bone_rest(_extrude_tip, tip_rest)

	skeleton.update_gizmos()
	
func _finish_extrude():
	_snapshot_into(_post_extrude_snapshot)

	var pre := _pre_extrude_snapshot.duplicate(true)
	var post := _post_extrude_snapshot.duplicate(true)

	_undo_redo.create_action("Extrude Bone")
	_undo_redo.add_do_method(self, "_restore_snapshot_from", post)
	_undo_redo.add_do_method(self, "_rebuild_skins_for_skeleton") # 👈 ADD
	_undo_redo.add_undo_method(self, "_restore_snapshot_from", pre)
	_undo_redo.add_undo_method(self, "_rebuild_skins_for_skeleton") # 👈 ADD
	_undo_redo.commit_action()

	_is_extruding = false
	_extrude_bone = -1
	_extrude_parent = -1
	skeleton.clear_bones_global_pose_override()

func _snapshot_into(target_array: Array):

	target_array.clear()

	for i in range(skeleton.get_bone_count()):
		target_array.append({
			"name": skeleton.get_bone_name(i),
			"parent": skeleton.get_bone_parent(i),
			"rest": skeleton.get_bone_rest(i)
		})

func _restore_snapshot_from(snapshot: Array):

	skeleton.clear_bones()

	for bone_data in snapshot:
		skeleton.add_bone(bone_data.name)

	for i in range(snapshot.size()):
		skeleton.set_bone_parent(i, snapshot[i].parent)
		skeleton.set_bone_rest(i, snapshot[i].rest)

	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	skeleton.update_gizmos()

func _rebuild_skins_for_skeleton():
	if skeleton == null:
		return

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(skeleton, meshes)

	for mesh in meshes:
		if mesh.skin == null:
			continue

		var old_skin: Skin = mesh.skin
		var new_skin := Skin.new()

		var bone_count := skeleton.get_bone_count()
		var old_bind_count := old_skin.get_bind_count()

		for i in range(old_bind_count):
			var bone_name := old_skin.get_bind_name(i)
			var bind_pose := old_skin.get_bind_pose(i)
			new_skin.add_named_bind(bone_name,bind_pose)

		for i in range(old_bind_count, bone_count):
			var bone_name := skeleton.get_bone_name(i)
			new_skin.add_named_bind(bone_name, Transform3D.IDENTITY)

		mesh.skin = new_skin

func _collect_meshes(node: Node, out: Array):
	for child in node.get_children():
		if child is MeshInstance3D and child.skeleton and child.get_node(child.skeleton) == skeleton:
			out.append(child)
		_collect_meshes(child, out)
