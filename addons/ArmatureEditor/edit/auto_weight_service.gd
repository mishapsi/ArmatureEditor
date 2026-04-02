@tool
extends RefCounted
class_name ArmatureAutoWeightService

signal request_refresh

var undo_redo: EditorUndoRedoManager

var bone_radius_multiplier: float = 0.25
var blend_falloff_power: float = 4.0
var weight_smoothing: float = 0.25
var ignored_bones: Array[String] = []
var recalculate_normals:bool = false

## Opens the modal weighting dialog and waits for confirmation.
func open_dialog() -> void:
	var selection := EditorInterface.get_selection()
	var nodes := selection.get_selected_nodes()
	var skeleton := _get_active_skeleton(nodes)

	if skeleton == null:
		push_warning("Select a Skeleton3D.")
		return

	var dialog := _build_dialog(skeleton)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	await dialog.confirmed
	dialog.queue_free()

	_execute()

func _build_dialog(skeleton: Skeleton3D) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = "Auto Weight Meshes"
	dialog.size = Vector2(400, 500)

	var vb := VBoxContainer.new()
	dialog.add_child(vb)

	var radius_spin := SpinBox.new()
	radius_spin.min_value = 0.01
	radius_spin.max_value = 5.0
	radius_spin.step = 0.01
	radius_spin.value = bone_radius_multiplier
	vb.add_child(_labeled("Bone Radius Multiplier", radius_spin))

	var falloff_spin := SpinBox.new()
	falloff_spin.min_value = 1.0
	falloff_spin.max_value = 10.0
	falloff_spin.step = 0.1
	falloff_spin.value = blend_falloff_power
	vb.add_child(_labeled("Falloff Power", falloff_spin))

	var smooth_spin := SpinBox.new()
	smooth_spin.min_value = 0.0
	smooth_spin.max_value = 1.0
	smooth_spin.step = 0.01
	smooth_spin.value = weight_smoothing
	vb.add_child(_labeled("Weight Smoothing", smooth_spin))

	var recalc := CheckButton.new()
	recalc.button_pressed = recalculate_normals
	vb.add_child(_labeled("Recalculate Normals", recalc))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)

	var bone_list := VBoxContainer.new()
	scroll.add_child(bone_list)

	var bone_checkboxes := {}

	for i in range(skeleton.get_bone_count()):
		var name := skeleton.get_bone_name(i)

		var cb := CheckBox.new()
		cb.text = name
		cb.button_pressed = false

		bone_list.add_child(cb)
		bone_checkboxes[name] = cb

	var label := Label.new()
	label.text = "Ignored Bones (unchecked = ignored)"
	vb.add_child(label)

	vb.add_child(scroll)
	dialog.confirmed.connect(func():
		bone_radius_multiplier = radius_spin.value
		blend_falloff_power = falloff_spin.value
		weight_smoothing = smooth_spin.value
		recalculate_normals = recalc.button_pressed

		ignored_bones.clear()

		for name in bone_checkboxes:
			if not bone_checkboxes[name].button_pressed:
				ignored_bones.append(name)
	)

	return dialog


func _labeled(text: String, control: Control) -> Control:
	var hb := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 180
	hb.add_child(label)
	hb.add_child(control)
	return hb


func _execute() -> void:
	var selection := EditorInterface.get_selection()
	var nodes := selection.get_selected_nodes()

	var skeleton := _get_active_skeleton(nodes)
	if skeleton == null:
		push_warning("Select a Skeleton3D and mesh instances.")
		return

	var meshes := _get_selected_meshes(nodes)
	if meshes.is_empty():
		push_warning("No MeshInstance3D selected.")
		return

	for mesh_instance in meshes:
		_apply_weights_to_mesh(mesh_instance, skeleton)

	request_refresh.emit()


func _get_active_skeleton(nodes: Array) -> Skeleton3D:
	for node in nodes:
		if node is Skeleton3D:
			return node
	return null


func _get_selected_meshes(nodes: Array) -> Array:
	var out := []
	for node in nodes:
		if node is MeshInstance3D:
			out.append(node)
	return out


func _apply_weights_to_mesh(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> void:
	if mesh_instance.mesh == null:
		return
	if undo_redo == null:
		_process_mesh_weighting(mesh_instance, skeleton)
		return

	var pre_mesh: Mesh = mesh_instance.mesh
	var pre_skin: Skin = mesh_instance.skin

	undo_redo.create_action("Auto Weight Mesh")
	undo_redo.add_do_method(self, "_process_mesh_weighting", mesh_instance, skeleton)
	undo_redo.add_undo_method(self, "_restore_mesh_and_skin", mesh_instance, pre_mesh, pre_skin)
	undo_redo.commit_action()


func _restore_mesh_and_skin(mesh_instance: MeshInstance3D, pre_mesh: Mesh, pre_skin: Skin) -> void:
	mesh_instance.mesh = pre_mesh
	mesh_instance.skin = pre_skin


func _restore_skin(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.skin = null


func _process_mesh_weighting(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> void:
	apply_bone_weights(mesh_instance, skeleton)


## Applies automatic bone weights to a mesh using unified multi-surface topology.
func apply_bone_weights(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> void:
	var source_mesh := mesh_instance.mesh
	if source_mesh == null or not (source_mesh is ArrayMesh):
		return

	var sk: Skeleton3D = skeleton
	if sk == null:
		return

	# ---------------- MERGE SURFACES ----------------
	var merged := _merge_surfaces(source_mesh)
	var vertices: PackedVector3Array = merged.vertices
	var indices: PackedInt32Array = merged.indices
	var surface_ranges: Array = merged.ranges

	var vertex_count := vertices.size()

	# ---------------- ADJACENCY ----------------
	var adjacency := build_vertex_adjacency(indices, vertex_count)

	# ---------------- WORLD POS ----------------
	var world_positions := PackedVector3Array()
	world_positions.resize(vertex_count)

	for i in range(vertex_count):
		world_positions[i] = mesh_instance.global_transform * vertices[i]

	# ---------------- WELD MAP ----------------
	var weld_map := {}
	var weld_tolerance := 0.0001

	for i in range(vertex_count):
		var pos = vertices[i]
		var key = Vector3(
			round(pos.x / weld_tolerance),
			round(pos.y / weld_tolerance),
			round(pos.z / weld_tolerance)
		)

		if not weld_map.has(key):
			weld_map[key] = []
		weld_map[key].append(i)

	var bone_segments := []
	var bone_count := sk.get_bone_count()

	var ignored_set := {}
	for name in ignored_bones:
		var idx = sk.find_bone(name)
		if idx != -1:
			ignored_set[idx] = true

	for i in range(bone_count):
		if i == 0 or ignored_set.has(i):
			continue

		var rest_a: Transform3D = sk.global_transform * sk.get_bone_global_rest(i)
		var children = sk.get_bone_children(i)

		var rest_b: Vector3

		if children.size() > 0:
			var child = children[0]
			if not ignored_set.has(child):
				var child_rest: Transform3D = sk.global_transform * sk.get_bone_global_rest(child)
				rest_b = child_rest.origin
			else:
				rest_b = rest_a.origin + rest_a.basis.y.normalized() * 0.05
		else:
			rest_b = rest_a.origin + rest_a.basis.y.normalized() * 0.05

		bone_segments.append({
			"index": i,
			"a": rest_a.origin,
			"b": rest_b
		})

	var temp_weights := []
	temp_weights.resize(vertex_count)

	for v in range(vertex_count):

		var bone_data := []

		for segment in bone_segments:
			var bone_length = segment.a.distance_to(segment.b)
			var radius = bone_length * bone_radius_multiplier

			var dist = get_capsule_distance(
				world_positions[v],
				segment.a,
				segment.b,
				radius
			)

			dist = max(dist, 0.0)

			bone_data.append({
				"index": segment.index,
				"distance": dist
			})

		if bone_data.is_empty():
			continue

		var current_indices := PackedInt32Array([0,0,0,0])
		var current_weights := Vector4.ZERO
		var current_res := Vector4(INF, INF, INF, INF)

		for bone in bone_data:
			var result = blend_bone_weights(
				bone.distance,
				null,
				bone.index,
				current_res,
				current_indices,
				current_weights,
				blend_falloff_power
			)

			if result.is_empty():
				continue

			current_indices = result.bone_indices
			current_weights = result.bone_weights
			current_res = result.bone_res

		temp_weights[v] = {
			"indices": current_indices,
			"weights": current_weights
		}

	for group in weld_map.values():

		var combined := {}

		for vtx in group:
			var data = temp_weights[vtx]
			for i in range(4):
				var idx = data.indices[i]
				var w = data.weights[i]
				if w <= 0.0:
					continue
				if not combined.has(idx):
					combined[idx] = 0.0
				combined[idx] += w

		var total := 0.0
		for w in combined.values():
			total += w

		if total <= 0.0:
			continue

		var sorted := []
		for k in combined.keys():
			sorted.append({"index": k, "weight": combined[k] / total})

		sorted.sort_custom(func(a,b): return a.weight > b.weight)

		var final_indices := PackedInt32Array([0,0,0,0])
		var final_weights := Vector4.ZERO

		for i in range(min(4, sorted.size())):
			final_indices[i] = sorted[i].index
			final_weights[i] = sorted[i].weight

		for vtx in group:
			temp_weights[vtx] = {
				"indices": final_indices,
				"weights": final_weights
			}

	# ---------------- REBUILD SURFACES ----------------
	var new_mesh := ArrayMesh.new()

	var vertex_cursor := 0

	for s in range(source_mesh.get_surface_count()):

		var arrays = source_mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var count := verts.size()

		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()

		bones.resize(count * 4)
		weights.resize(count * 4)

		for i in range(count):
			var data = temp_weights[vertex_cursor + i]

			for j in range(4):
				bones[i * 4 + j] = data.indices[j]
				weights[i * 4 + j] = data.weights[j]

		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights

		var primitive = source_mesh.surface_get_primitive_type(s)
		var material = source_mesh.surface_get_material(s)

		new_mesh.add_surface_from_arrays(primitive, arrays)
		new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, material)

		vertex_cursor += count

	mesh_instance.mesh = new_mesh

	if recalculate_normals:
		recalc_welded_normals(mesh_instance)

	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	mesh_instance.skin = build_skin_from_skeleton_rest(sk)

## Merges all surfaces into one unified vertex/index set.
func _merge_surfaces(mesh: ArrayMesh) -> Dictionary:
	var merged_vertices := PackedVector3Array()
	var merged_indices := PackedInt32Array()
	var ranges := []

	var vertex_offset := 0

	for s in range(mesh.get_surface_count()):

		var arrays = mesh.surface_get_arrays(s)

		if arrays.is_empty():
			continue

		var verts = arrays[Mesh.ARRAY_VERTEX]
		if verts == null or verts.is_empty():
			continue

		var indices = arrays[Mesh.ARRAY_INDEX]

		if indices == null or indices.is_empty():
			indices = PackedInt32Array()
			indices.resize(verts.size())
			for i in range(verts.size()):
				indices[i] = i

		for v in verts:
			merged_vertices.append(v)

		for idx in indices:
			merged_indices.append(idx + vertex_offset)

		ranges.append({
			"start": vertex_offset,
			"count": verts.size()
		})

		vertex_offset += verts.size()

	if merged_vertices.is_empty():
		push_error("Merge surfaces failed: no vertices found")
		return {
			"vertices": PackedVector3Array(),
			"indices": PackedInt32Array(),
			"ranges": []
		}

	return {
		"vertices": merged_vertices,
		"indices": merged_indices,
		"ranges": ranges
	}

func get_capsule_distance(p: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var ab = b - a
	var t = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest = a + ab * t
	return p.distance_to(closest) - radius


func blend_bone_weights(brush_res: float, brush, brush_bone_index: int, bone_res: Vector4, bone_index: PackedInt32Array, bone_weight: Vector4, power := 2.0):
	var bone_data = []
	for i in range(4):
		if bone_res[i] < INF:
			bone_data.append({"index": bone_index[i], "distance": bone_res[i], "weight": bone_weight[i]})
	bone_data.append({"index": brush_bone_index, "distance": brush_res, "weight": 0.0})
	bone_data.sort_custom(func(a, b): return a.distance < b.distance)
	if bone_data.size() > 4:
		bone_data.resize(4)
	var total_weight = 0.0
	for i in range(bone_data.size()):
		var distance = bone_data[i].distance
		var w = 1.0 / pow(max(kEpsilon, distance), power)
		bone_data[i].weight = w
		total_weight += w

	if total_weight < kEpsilon:
		return {} 
	var new_bone_weights = Vector4.ZERO
	var new_bone_indices = PackedInt32Array([0, 0, 0, 0])
	var new_bone_res = Vector4(INF, INF, INF, INF)
	
	for i in range(bone_data.size()):
		new_bone_weights[i] = bone_data[i].weight / total_weight
		new_bone_indices[i] = bone_data[i].index
		new_bone_res[i] = bone_data[i].distance

	var min_keep = 0.01
	var keep_count = 0
	for i in range(4):
		if new_bone_weights[i] < min_keep:
			new_bone_weights[i] = 0.0
			new_bone_indices[i] = 0
		else:
			keep_count += 1

	if keep_count > 0:
		new_bone_weights = normalize_bone_weight(new_bone_weights)
	return {
		"bone_weights": new_bone_weights,
		"bone_indices": new_bone_indices,
		"bone_res": new_bone_res
	}


const kEpsilon = 0.000001


func normalize_bone_weight(bone_weight: Vector4) -> Vector4:
	var total = bone_weight.x + bone_weight.y + bone_weight.z + bone_weight.w
	if total < kEpsilon:
		return Vector4.ZERO
	return bone_weight / total

func normalize_bone_weights(
	temp_weights: Array,
	bone_count: int,
	min_keep: float = 0.00001
):
	for v in range(temp_weights.size()):
		var data: Dictionary = temp_weights[v]
		var idxs: PackedInt32Array = data.indices
		var w: Vector4 = data.weights

		for i in range(4):
			var bi := idxs[i]
			var wi := w[i]

			if wi <= min_keep:
				w[i] = 0.0
				idxs[i] = 0
				continue

			if bi < 0 or bi >= bone_count:
				w[i] = 0.0
				idxs[i] = 0

		var total := w.x + w.y + w.z + w.w
		if total > kEpsilon:
			w /= total
		else:
			w = Vector4(1.0, 0.0, 0.0, 0.0)
			idxs = PackedInt32Array([0, 0, 0, 0])

		data.indices = idxs
		data.weights = w
		temp_weights[v] = data
	return temp_weights
	
func recalc_welded_normals(mesh_instance:MeshInstance3D):

	if mesh_instance.mesh == null:
		return

	var child_mesh: ArrayMesh = mesh_instance.mesh

	for s in range(child_mesh.get_surface_count()):

		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(child_mesh, s) != OK:
			continue

		var vertex_count = mdt.get_vertex_count()
		var face_count = mdt.get_face_count()

		var normal_accum := []
		normal_accum.resize(vertex_count)

		for i in range(vertex_count):
			normal_accum[i] = Vector3.ZERO

		for f in range(face_count):

			var v0 = mdt.get_face_vertex(f, 0)
			var v1 = mdt.get_face_vertex(f, 1)
			var v2 = mdt.get_face_vertex(f, 2)

			var p0 = mdt.get_vertex(v0)
			var p1 = mdt.get_vertex(v1)
			var p2 = mdt.get_vertex(v2)

			var face_normal = (p2 - p0).cross(p1 - p0)
			if face_normal.length_squared() > 0.0:
				face_normal = face_normal.normalized()

			normal_accum[v0] += face_normal
			normal_accum[v1] += face_normal
			normal_accum[v2] += face_normal

		for v in range(vertex_count):
			if normal_accum[v].length_squared() > 0.0:
				normal_accum[v] = normal_accum[v].normalized()

		var position_groups = {}

		for i in range(vertex_count):
			var pos = mdt.get_vertex(i)
			var key = snapped_position_key(pos)

			if not position_groups.has(key):
				position_groups[key] = []

			position_groups[key].append(i)

		for key in position_groups:

			var group = position_groups[key]
			if group.size() < 2:
				continue

			var accum := Vector3.ZERO

			for v in group:
				accum += normal_accum[v]

			if accum.length_squared() > 0.0:
				accum = accum.normalized()

			for v in group:
				normal_accum[v] = accum

		for v in range(vertex_count):
			mdt.set_vertex_normal(v, normal_accum[v])

		child_mesh.surface_remove(s)
		mdt.commit_to_surface(child_mesh)
		mdt.clear()

func build_vertex_adjacency(indices: PackedInt32Array, vertex_count: int) -> Array:
	var adjacency := []
	adjacency.resize(vertex_count)

	for i in range(vertex_count):
		adjacency[i] = []

	for i in range(0, indices.size(), 3):
		var a = indices[i]
		var b = indices[i + 1]
		var c = indices[i + 2]

		adjacency[a].append(b)
		adjacency[a].append(c)

		adjacency[b].append(a)
		adjacency[b].append(c)

		adjacency[c].append(a)
		adjacency[c].append(b)

	return adjacency

func _compute_geodesic_distances(
	mdt: MeshDataTool,
	adjacency: Array,
	seeds: PackedInt32Array,
	max_d: float
) -> PackedFloat32Array:

	var vertex_count = mdt.get_vertex_count()
	var dist := PackedFloat32Array()
	dist.resize(vertex_count)

	var INF = 1e20
	for i in range(vertex_count):
		dist[i] = INF

	var queue := []

	for v in seeds:
		dist[v] = 0.0
		queue.append(v)

	while queue.size() > 0:

		var current = queue.pop_front()
		var p0 = mdt.get_vertex(current)

		for n in adjacency[current]:

			var p1 = mdt.get_vertex(n)
			var edge_len = p0.distance_to(p1)

			var new_dist = dist[current] + edge_len

			if new_dist < dist[n] and new_dist < max_d:
				dist[n] = new_dist
				queue.append(n)

	return dist


func smooth_weights(mdt: MeshDataTool, iterations := 4, strength := 0.3):

	var adjacency = build_adjacency_spatial(mdt)
	var full_weights = []
	
	for v in range(mdt.get_vertex_count()):
		var map = {}
		var bones = mdt.get_vertex_bones(v)
		var weights = mdt.get_vertex_weights(v)
		
		for i in range(4):
			if weights[i] > 0.0:
				map[bones[i]] = weights[i]
		
		full_weights.append(map)
	for _i in range(iterations):
		
		var new_maps = []
		
		for v in range(mdt.get_vertex_count()):
			
			var self_map = full_weights[v]
			var avg_map = {}
			var neighbor_count = 0
			
			if adjacency.has(v):
				for n in adjacency[v]:
					neighbor_count += 1
					for bone in full_weights[n]:
						if avg_map.has(bone):
							avg_map[bone] += full_weights[n][bone]
						else:
							avg_map[bone] = full_weights[n][bone]
			
			if neighbor_count > 0:
				for bone in avg_map:
					avg_map[bone] /= neighbor_count
			var blended = {}
			for bone in self_map:
				blended[bone] = self_map[bone] * (1.0 - strength)
			
			for bone in avg_map:
				if blended.has(bone):
					blended[bone] += avg_map[bone] * strength
				else:
					blended[bone] = avg_map[bone] * strength
			
			new_maps.append(blended)
		
		full_weights = new_maps
	for v in range(mdt.get_vertex_count()):
		var reduced = reduce_to_4(full_weights[v])
		mdt.set_vertex_bones(v, reduced.bones)
		mdt.set_vertex_weights(v, reduced.weights)


func enforce_position_groups(mdt: MeshDataTool):
	var position_groups = {}
	for i in range(mdt.get_vertex_count()):
		var pos = mdt.get_vertex(i)
		var key = snapped_position_key(pos)
		
		if not position_groups.has(key):
			position_groups[key] = []
		
		position_groups[key].append(i)
	for key in position_groups:
		var group = position_groups[key]
		if group.size() < 2:
			continue
		
		var accum = {}
		
		for v in group:
			var bones = mdt.get_vertex_bones(v)
			var weights = mdt.get_vertex_weights(v)
			
			for j in range(4):
				if weights[j] > 0:
					if accum.has(bones[j]):
						accum[bones[j]] += weights[j]
					else:
						accum[bones[j]] = weights[j]
		for bone in accum:
			accum[bone] /= group.size()
		
		var reduced = reduce_to_4(accum)
		
		for v in group:
			mdt.set_vertex_bones(v, reduced.bones)
			mdt.set_vertex_weights(v, reduced.weights)


func build_skin_from_skeleton_rest(skel: Skeleton3D) -> Skin:
	var s := Skin.new()
	var bc := skel.get_bone_count()
	for bone_i in range(0,bc):
		var bname = skel.get_bone_name(bone_i)
		var inv_bind: Transform3D = skel.get_bone_global_rest(bone_i).affine_inverse()
		s.add_named_bind(bname, inv_bind)
	return s

func build_adjacency_spatial(mdt: MeshDataTool) -> Dictionary:
	var adjacency = {}
	var position_groups = {}
	for i in range(mdt.get_vertex_count()):
		var pos = mdt.get_vertex(i)
		var key = snapped_position_key(pos)
		
		if not position_groups.has(key):
			position_groups[key] = []
		
		position_groups[key].append(i)
	for i in range(mdt.get_edge_count()):
		var a = mdt.get_edge_vertex(i, 0)
		var b = mdt.get_edge_vertex(i, 1)
		
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		
		adjacency[a].append(b)
		adjacency[b].append(a)
	
	for key in position_groups:
		var group = position_groups[key]
		if group.size() < 2:
			continue
		
		for v in group:
			if not adjacency.has(v):
				adjacency[v] = []
			
			for other in group:
				if other != v:
					adjacency[v].append(other)
	
	return adjacency

func reduce_to_4(influence_map: Dictionary) -> Dictionary:
	var influences = []
	
	for bone in influence_map:
		influences.append({
			"bone": bone,
			"weight": influence_map[bone]
		})
	
	influences.sort_custom(func(a,b): return a.weight > b.weight)
	
	var out_bones := PackedInt32Array()
	var out_weights := PackedFloat32Array()
	
	out_bones.resize(4)
	out_weights.resize(4)
	
	var total := 0.0
	
	for i in range(4):
		if i < influences.size():
			out_bones[i] = influences[i].bone
			out_weights[i] = influences[i].weight
			total += influences[i].weight
		else:
			out_bones[i] = 0
			out_weights[i] = 0.0
	
	if total > 0:
		for i in range(4):
			out_weights[i] /= total
	
	return {
		"bones": out_bones,
		"weights": out_weights
	}

func snapped_position_key(pos: Vector3) -> String:
	var snap = 0.00001
	return str(
		round(pos.x / snap) * snap, "_",
		round(pos.y / snap) * snap, "_",
		round(pos.z / snap) * snap
	)
