extends EditorNode3DGizmoPlugin
class_name EditableSkeletonGizmo
signal recorded_bones_changed

var _unit_sphere : ArrayMesh
var _hover_id := -1
var mode: int = 0 # 1 = Edit (rest), 0 = Pose

var _undo_redo: EditorUndoRedoManager
var _drag_start_pose_origin := []
var _drag_start_rest_origin := []
var _drag_original_pose := []
var _drag_original_rest := []
var _drag_active := false
var last_transform = Transform3D.IDENTITY
var snap_enabled = true
var snap_amount = .1
func _is_node_selected(node: Node) -> bool:
	var selection := EditorInterface.get_selection()
	return node in selection.get_selected_nodes()

func _get_gizmo_name() -> String:
	return "CustomSkeletonGizmo"

func set_mode(p_mode: int) -> void:
	mode = p_mode

func _init() -> void:
	add_material("bone_edit_normal", _make_material(Color(0.6, 0.6, 0.6)))
	add_material("bone_edit_selected", _make_material(Color(1.0, 0.7, 0.2)))
	add_material("bone_edit_hover", _make_material(Color(1.0, 1.0, 1.0)))

	add_material("bone_pose_normal", _make_material(Color(0.35, 0.9, .6)))
	add_material("bone_pose_selected", _make_material(Color(0.55, 0.8, 1.0)))
	add_material("bone_pose_hover", _make_material(Color(0.75, 0.9, 1.0)))

	add_material("joint_normal", _make_material(Color(0.2, 0.6, 1.0)))
	add_material("joint_selected", _make_material(Color(1.0, 1.0, 0.2)))
	add_material("joint_hover", _make_material(Color(0.4, 1.0, 1.0)))
	add_material("bone_edit_spring_normal", _make_material(Color(1.0, 0.35, 0.55)))
	add_material("bone_edit_spring_selected", _make_material(Color(1.0, 0.6, 0.7)))
	add_material("bone_edit_spring_hover", _make_material(Color(1.0, 0.45, 0.65)))
	_unit_sphere = _create_unit_sphere_mesh()

	_undo_redo = EditorInterface.get_editor_undo_redo()

func _is_spring_bone(skeleton: Skeleton3D, bone: int) -> bool:

	for child in skeleton.get_children():
		if child is SpringBoneSimulator3D:
			var simulator := child as SpringBoneSimulator3D

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

func _begin_drag(skeleton: Skeleton3D) -> void:
	_drag_original_pose.clear()
	_drag_original_rest.clear()
	_drag_start_pose_origin.clear()
	_drag_start_rest_origin.clear()

	for i in range(skeleton.get_bone_count()):
		var p := skeleton.get_bone_pose(i)
		var r := skeleton.get_bone_rest(i)

		_drag_original_pose.append(p)
		_drag_original_rest.append(r)
		_drag_start_pose_origin.append(p.origin)
		_drag_start_rest_origin.append(r.origin)

	_drag_active = true


func _has_gizmo(node) -> bool:
	return node is Skeleton3D


func _get_bone_world_transform(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var skel_xf := skeleton.global_transform
	
	if mode == 1:
		return skel_xf * skeleton.get_bone_global_rest(bone)
	else:
		return skel_xf * skeleton.get_bone_global_pose(bone)

func _get_bone_transform(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var skel_xf := skeleton.global_transform
	
	if mode == 1:
		return skeleton.get_bone_global_rest(bone)
	else:
		return skeleton.get_bone_global_pose(bone)

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var skeleton := gizmo.get_node_3d() as Skeleton3D
	if skeleton == null:
		return
	if not _is_node_selected(skeleton):
		return

	var bone_count := skeleton.get_bone_count()
	if bone_count == 0:
		return
	var selected = 0
	for parent_bone in range(bone_count):

		if parent_bone < 0 or parent_bone >= bone_count:
			continue

		var parent_world := _get_bone_transform(skeleton, parent_bone)
		var head := parent_world.origin

		var children := skeleton.get_bone_children(parent_bone)
		if children.is_empty():
			continue

		var body_id := parent_bone * 2

		var body_selected := false
		if parent_bone < bone_count:
			body_selected = gizmo.is_subgizmo_selected(body_id)

		var bone_mat = null
		if mode == 1:
			var is_spring := false
			if parent_bone < bone_count:
				is_spring = _is_spring_bone(skeleton, parent_bone)

			if is_spring:
				bone_mat = get_material("bone_edit_spring_selected") if body_selected \
				else get_material("bone_edit_spring_hover") if _hover_id == body_id \
				else get_material("bone_edit_spring_normal")
			else:
				bone_mat = get_material("bone_edit_selected") if body_selected \
				else get_material("bone_edit_hover") if _hover_id == body_id \
				else get_material("bone_edit_normal")
		else:
			bone_mat = get_material("bone_pose_selected") if body_selected \
			else get_material("bone_pose_hover") if _hover_id == body_id \
			else get_material("bone_pose_normal")

		for child_idx in range(children.size()):
			selected+=1
			var child_bone: int = children[child_idx]

			if child_bone < 0 or child_bone >= bone_count:

				continue

			var child_world := _get_bone_transform(skeleton, child_bone)
			var tail := child_world.origin

			var length := head.distance_to(tail)
			if length < 0.0001:
				continue

			var joint_id := child_bone * 2 + 1

			var joint_selected := false
			if child_bone < bone_count:
				joint_selected = gizmo.is_subgizmo_selected(joint_id)

			var joint_mat := get_material("joint_selected") if joint_selected \
			else get_material("joint_hover") if _hover_id == joint_id \
			else get_material("joint_normal")
			
			if children.size() == 1 or skeleton.get_bone_children(child_bone).size() == 0:
				gizmo.add_mesh(
					_create_bone_octahedron(head, tail),
					bone_mat,
					Transform3D.IDENTITY
				)
			else:
				_add_dashed_line(gizmo, head, tail, bone_mat, length * 0.12, length * 0.08)

			var radius := 0.025
			var joint_xf := Transform3D(
				Basis().scaled(Vector3(radius, radius, radius)),
				tail
			)

			gizmo.add_mesh(
				_unit_sphere,
				joint_mat,
				joint_xf
			)

func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, id: int) -> Transform3D:
	var skeleton := gizmo.get_node_3d() as Skeleton3D
	var bone := id / 2
	var part := id % 2

	var bone_world := _get_bone_transform(skeleton, bone)

	if part == 0:
		return bone_world

	var children := skeleton.get_bone_children(bone)
	if children.is_empty():
		var basis := bone_world.basis
		var tail := bone_world.origin + basis.z.normalized() * 0.1
		return Transform3D(basis, tail)

	return bone_world


func _subgizmos_intersect_ray(
	gizmo: EditorNode3DGizmo,
	camera: Camera3D,
	screen_pos: Vector2
) -> int:

	var id := _pick_subgizmo_id(gizmo, camera, screen_pos)

	if id != _hover_id:
		_hover_id = id
		_redraw(gizmo)
	return id

func _ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var oc := origin - center
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var h := b * b - c
	if h < 0.0:
		return -1.0

	var s := sqrt(h)
	var t0 := -b - s
	var t1 := -b + s

	if t0 >= 0.0:
		return t0
	if t1 >= 0.0:
		return t1
	return -1.0


func _ray_segment(
	camera: Camera3D,
	screen_pos: Vector2,
	a: Vector3,
	b: Vector3
) -> float:

	var a_screen := camera.unproject_position(a)
	var b_screen := camera.unproject_position(b)

	var ab := b_screen - a_screen
	var ab_len2 := ab.length_squared()
	if ab_len2 == 0.0:
		return -1.0

	var t := clamp((screen_pos - a_screen).dot(ab) / ab_len2, 0.0, 1.0)
	var closest = a_screen + ab * t

	var pixel_dist := screen_pos.distance_to(closest)
	if pixel_dist > 10.0:
		return -1.0

	var world_point = a + (b - a) * t
	return camera.global_transform.origin.distance_to(world_point)

func _ray_capsule(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 < 1e-10:
		return _ray_sphere(origin, dir, a, radius)

	var ao := origin - a

	var d_dot_d := dir.dot(dir) # should be 1, but keep robust
	var d_dot_ab := dir.dot(ab)
	var ab_dot_ab := ab_len2
	var d_dot_ao := dir.dot(ao)
	var ab_dot_ao := ab.dot(ao)

	var denom := d_dot_d * ab_dot_ab - d_dot_ab * d_dot_ab
	var t := 0.0
	var u := 0.0

	if abs(denom) > 1e-10:
		t = (d_dot_ab * ab_dot_ao - ab_dot_ab * d_dot_ao) / denom
		u = (d_dot_d * ab_dot_ao - d_dot_ab * d_dot_ao) / denom
	else:
		u = clamp(ab_dot_ao / ab_dot_ab, 0.0, 1.0)
		var q := a + ab * u
		t = dir.dot(q - origin)

	if t < 0.0:
		return -1.0

	u = clamp(u, 0.0, 1.0)
	var p := origin + dir * t
	var q2 := a + ab * u
	var dist2 := p.distance_squared_to(q2)

	if dist2 > radius * radius:
		return -1.0

	return _ray_sphere(origin, dir, q2, radius)

func _commit_subgizmos(gizmo, ids, restores, cancel):

	if not _drag_active:
		return

	var skeleton := gizmo.get_node_3d() as Skeleton3D
	var changed := false

	_undo_redo.create_action("Transform Bones")

	for i in range(skeleton.get_bone_count()):

		var before_pose = _drag_original_pose[i]
		var after_pose = skeleton.get_bone_pose(i)

		if before_pose != after_pose:
			changed = true
			_undo_redo.add_do_method(
				skeleton,
				"set_bone_pose",
				i,
				after_pose
			)
			_undo_redo.add_undo_method(
				skeleton,
				"set_bone_pose",
				i,
				before_pose
			)

		var before_rest = _drag_original_rest[i]
		var after_rest = skeleton.get_bone_rest(i)

		if before_rest != after_rest:
			changed = true
			_undo_redo.add_do_method(
				skeleton,
				"set_bone_rest",
				i,
				after_rest
			)
			_undo_redo.add_undo_method(
				skeleton,
				"set_bone_rest",
				i,
				before_rest
			)

	if changed:
		_undo_redo.commit_action()

	_drag_active = false


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_color.a = .95
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = true
	#m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _create_unit_sphere_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 8

	var arr := ArrayMesh.new()
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	return arr


## Builds an octahedral bone mesh with outward-facing normals.
func _create_bone_octahedron(head: Vector3, tail: Vector3) -> ArrayMesh:
	var dir := tail - head
	var length := dir.length()
	if length < 0.0001:
		return ArrayMesh.new()

	var forward := dir / length

	var up := Vector3.UP
	if absf(up.dot(forward)) > 0.999:
		up = Vector3.RIGHT

	var right := up.cross(forward).normalized()
	up = forward.cross(right).normalized()

	var head_len := length * 0.15
	var thickness := length * 0.08
	var waist_pos := head + forward * head_len

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()

	var center := head + forward * (length * 0.5)

	var add_tri := func(a: Vector3, b: Vector3, c: Vector3):
		var n := (c - a).cross(b - a).normalized()
		var face_center := (a + b + c) * (1.0 / 3.0)
		var outward := (face_center - center).normalized()
		if n.dot(outward) < 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		verts.append_array([a, b, c])
		norms.append_array([n, n, n])

	var head_tip := head
	var tail_tip := tail

	var w_left := waist_pos - right * thickness
	var w_right := waist_pos + right * thickness
	var w_front := waist_pos + up * thickness
	var w_back := waist_pos - up * thickness

	add_tri.call(tail_tip, w_left, w_front)
	add_tri.call(tail_tip, w_front, w_right)
	add_tri.call(tail_tip, w_right, w_back)
	add_tri.call(tail_tip, w_back, w_left)

	add_tri.call(head_tip, w_front, w_left)
	add_tri.call(head_tip, w_right, w_front)
	add_tri.call(head_tip, w_back, w_right)
	add_tri.call(head_tip, w_left, w_back)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func update_hover(camera: Camera3D, screen_pos: Vector2, gizmo: EditorNode3DGizmo) -> void:
	var id = _compute_hover(camera, screen_pos, gizmo)

	if id != _hover_id:
		_hover_id = id
		_redraw(gizmo)

func _compute_hover(camera: Camera3D, screen_pos: Vector2, gizmo: EditorNode3DGizmo) -> int:
	return _pick_subgizmo_id(gizmo, camera, screen_pos)


func get_selected_ids(gizmo: EditorNode3DGizmo) -> Array[int]:
	var ids: Array[int] = []

	var skeleton := gizmo.get_node_3d() as Skeleton3D
	for i in range(skeleton.get_bone_count() * 2):
		if gizmo.is_subgizmo_selected(i):
			ids.append(i)
	return ids

func set_selected_ids(
	gizmo: EditorNode3DGizmo,
	ids: Array[int]
) -> void:
	if gizmo == null:
		return

	var skeleton := gizmo.get_node_3d() as Skeleton3D
	if skeleton == null:
		return

	var bone_count := skeleton.get_bone_count()
	if bone_count == 0:
		return

	skeleton.clear_subgizmo_selection()

	for id in ids:
		var bone := int(id / 2)
		var part := int(id % 2)

		if bone < 0 or bone >= bone_count:
			continue

		var t := skeleton.get_bone_global_rest(bone)

		skeleton.set_subgizmo_selection(gizmo, id, t)

func _set_subgizmo_transform(
	gizmo: EditorNode3DGizmo,
	id: int,
	transform: Transform3D
) -> void:
	var skeleton := gizmo.get_node_3d() as Skeleton3D
	if skeleton == null:
		return

	if not _drag_active:
		_begin_drag(skeleton)

	var bone := id / 2
	var part := id % 2

	var skel_xf := skeleton.global_transform
	var skel_inv := skel_xf.affine_inverse()

	var original_world := _get_subgizmo_transform(gizmo, id)
	var delta_rot := transform.basis * original_world.basis.inverse()
	var delta_pos := transform.origin - original_world.origin

	var is_edit := mode == 1
	_apply_bone_transform_with_snap(
		gizmo,
		skeleton,
		skel_inv,
		bone,
		part,
		delta_rot,
		delta_pos,
		is_edit
	)

func _apply_bone_transform_with_snap(
	gizmo: EditorNode3DGizmo,
	skeleton: Skeleton3D,
	skel_inv: Transform3D,
	bone: int,
	part: int,
	delta_rot: Basis,
	delta_pos: Vector3,
	is_edit: bool
) -> void:
	var bone_world := _get_bone_world_transform(skeleton, bone)
	var new_world := Transform3D(delta_rot * bone_world.basis, bone_world.origin + delta_pos)

	if snap_enabled:
		new_world.origin = _snap_world_origin(new_world.origin)

	var new_skel := skel_inv * new_world

	var parent := skeleton.get_bone_parent(bone)
	var parent_global := Transform3D.IDENTITY
	if parent != -1:
		parent_global = skeleton.get_bone_global_rest(parent) if is_edit else skeleton.get_bone_global_pose(parent)

	var desired_local_basis := parent_global.basis.inverse() * new_skel.basis
	var desired_local_origin := parent_global.basis.inverse() * (new_skel.origin - parent_global.origin)

	if is_edit:
		var rest := skeleton.get_bone_rest(bone)
		rest.basis = desired_local_basis
		rest.origin = desired_local_origin
		skeleton.set_bone_rest(bone, rest)
	else:
		var pose := skeleton.get_bone_pose(bone)
		pose.basis = desired_local_basis
		pose.origin = desired_local_origin
		skeleton.set_bone_pose(bone, pose)

	_redraw(gizmo)


func _snap_world_origin(world_origin: Vector3) -> Vector3:
	var step := max(0.0001, absf(snap_amount))
	return world_origin.snapped(Vector3(step, step, step))

func _add_dashed_line(
	gizmo: EditorNode3DGizmo,
	from: Vector3,
	to: Vector3,
	mat: Material,
	dash_len: float = 0.12,
	gap_len: float = 0.08
) -> void:
	var dir := to - from
	var total := dir.length()
	if total < 0.0001:
		return

	var fwd := dir / total
	var step := max(0.0001, dash_len + gap_len)

	var lines := PackedVector3Array()
	var t := 0.0
	while t < total:
		var a := from + fwd * t
		var b = from + fwd * min(t + dash_len, total)
		lines.append(a)
		lines.append(b)
		t += step

	gizmo.add_lines(lines, mat, true)
func _pick_subgizmo_id(
	gizmo: EditorNode3DGizmo,
	camera: Camera3D,
	screen_pos: Vector2
) -> int:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return _pick_subgizmo_id_ortho(gizmo, camera, screen_pos)
	return _pick_subgizmo_id_perspective(gizmo, camera, screen_pos)


func _pick_subgizmo_id_perspective(
	gizmo: EditorNode3DGizmo,
	camera: Camera3D,
	screen_pos: Vector2
) -> int:
	var skeleton := gizmo.get_node_3d() as Skeleton3D
	if skeleton == null:
		return -1

	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos).normalized()

	var best_body_id := -1
	var best_body_t := INF

	var best_joint_id := -1
	var best_joint_t := INF
	var best_joint_radius := 0.0

	for parent_bone in range(skeleton.get_bone_count()):
		var parent_world := _get_bone_world_transform(skeleton, parent_bone)
		var head := parent_world.origin

		var children := skeleton.get_bone_children(parent_bone)
		if children.is_empty():
			continue

		# ------------------------------
		# Joints: unchanged (per child)
		# ------------------------------
		for child_bone in children:
			var child_world := _get_bone_world_transform(skeleton, child_bone)
			var joint_center := child_world.origin

			var seg_len := head.distance_to(joint_center)
			if seg_len < 0.0001:
				continue

			var joint_radius := max(seg_len * 0.06, 0.02)
			var t_joint := _ray_sphere(ray_from, ray_dir, joint_center, joint_radius)
			if t_joint >= 0.0 and t_joint < best_joint_t:
				best_joint_t = t_joint
				best_joint_id = (child_bone * 2) + 1
				best_joint_radius = joint_radius

		# ------------------------------------------
		# Body: pick against the closest child limb
		# ------------------------------------------
		var best_parent_body_t := INF
		var best_parent_body_radius := 0.0

		for child_bone in children:
			var child_world := _get_bone_world_transform(skeleton, child_bone)
			var tail := child_world.origin

			var seg_len := head.distance_to(tail)
			if seg_len < 0.0001:
				continue

			var body_radius := max(seg_len * 0.05, 0.012)
			var t_body := _ray_capsule(ray_from, ray_dir, head, tail, body_radius)

			if t_body >= 0.0 and t_body < best_parent_body_t:
				best_parent_body_t = t_body
				best_parent_body_radius = body_radius

		if best_parent_body_t < best_body_t:
			best_body_t = best_parent_body_t
			best_body_id = parent_bone * 2

	if best_joint_id != -1:
		var joint_wins_margin := max(best_joint_radius * 0.6, 0.02)
		if best_body_id == -1:
			return best_joint_id
		if best_joint_t <= best_body_t + joint_wins_margin:
			return best_joint_id

	return best_body_id
func _pick_subgizmo_id_ortho(
	gizmo: EditorNode3DGizmo,
	camera: Camera3D,
	screen_pos: Vector2
) -> int:
	var skeleton := gizmo.get_node_3d() as Skeleton3D
	if skeleton == null:
		return -1

	var best_joint_id := -1
	var best_joint_px := INF

	var best_body_id := -1
	var best_body_px := INF

	for parent_bone in range(skeleton.get_bone_count()):
		var parent_world := _get_bone_world_transform(skeleton, parent_bone)
		var head_w := parent_world.origin

		var children := skeleton.get_bone_children(parent_bone)
		if children.is_empty():
			continue

		var head_s := camera.unproject_position(head_w)

		# ------------------------------
		# Joints: unchanged (per child)
		# ------------------------------
		for child_bone in children:
			var child_world := _get_bone_world_transform(skeleton, child_bone)
			var joint_w := child_world.origin
			var joint_s := camera.unproject_position(joint_w)

			var seg_len_px := head_s.distance_to(joint_s)
			if seg_len_px < 0.001:
				continue

			var joint_radius_px := max(seg_len_px * 0.20, 10.0)
			var d_px := screen_pos.distance_to(joint_s)

			if d_px <= joint_radius_px and d_px < best_joint_px:
				best_joint_px = d_px
				best_joint_id = (child_bone * 2) + 1

		# --------------------------------------------
		# Body: pick the closest dashed/limb segment
		# --------------------------------------------
		var best_parent_body_px := INF
		var best_parent_body_radius_px := 0.0

		for child_bone in children:
			var child_world := _get_bone_world_transform(skeleton, child_bone)
			var tail_w := child_world.origin

			var tail_s := camera.unproject_position(tail_w)

			var seg_len_px := head_s.distance_to(tail_s)
			if seg_len_px < 0.001:
				continue

			var body_radius_px := max(seg_len_px * 0.10, 8.0)
			var d_seg_px := _distance_point_to_segment_2d(screen_pos, head_s, tail_s)

			if d_seg_px <= body_radius_px and d_seg_px < best_parent_body_px:
				best_parent_body_px = d_seg_px
				best_parent_body_radius_px = body_radius_px

		if best_parent_body_px < best_body_px:
			best_body_px = best_parent_body_px
			best_body_id = parent_bone * 2

	if best_joint_id != -1:
		if best_body_id == -1:
			return best_joint_id

		var joint_wins_margin_px := 6.0
		if best_joint_px <= best_body_px + joint_wins_margin_px:
			return best_joint_id

	return best_body_id


func _distance_point_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 <= 1e-10:
		return p.distance_to(a)
	var t := clamp((p - a).dot(ab) / ab_len2, 0.0, 1.0)
	var q = a + ab * t
	return p.distance_to(q)

func _subgizmos_intersect_frustum(
	gizmo: EditorNode3DGizmo,
	camera: Camera3D,
	frustum: Array[Plane]
) -> PackedInt32Array:
	var skeleton := gizmo.get_node_3d() as Skeleton3D
	if skeleton == null:
		return PackedInt32Array()

	var result := PackedInt32Array()

	for bone in range(skeleton.get_bone_count()):

		# ----------------------------------
		# Test bone body (head position)
		# ----------------------------------
		var world := _get_bone_world_transform(skeleton, bone)
		var head := world.origin

		if _point_in_frustum(head, frustum):
			result.append(bone * 2)  # body id

		# ----------------------------------
		# Test joint (tail position)
		# ----------------------------------
		var children := skeleton.get_bone_children(bone)
		if children.is_empty():
			continue

		for child in children:
			var child_world := _get_bone_world_transform(skeleton, child)
			var tail := child_world.origin

			if _point_in_frustum(tail, frustum):
				result.append(child * 2 + 1)
	return result

func _point_in_frustum(point: Vector3, frustum: Array[Plane]) -> bool:
	const EPS := 0.01
	for plane in frustum:
		if plane.distance_to(point) > EPS:
			return false
	return true
