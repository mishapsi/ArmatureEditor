@tool
extends EditorPlugin

const SKELETON_GIZMO := preload("uid://yqxkavcemd2r")
const TOOLBAR_SCENE := preload("uid://caejk0juh8rr5")

var toolbar_scene: PackedScene = TOOLBAR_SCENE

var skeleton_gizmo: EditorNode3DGizmoPlugin
var context: ArmatureSkeletonContext

var toolbar_controller: ToolbarController
var context_menu_controller: ContextMenuController
var extrude_name_controller: ExtrudeNameController
var rename_dialog_controller: RenameDialogController
var spring_bone_collision_service: ArmatureSpringBoneCollisionService
var selection_service: ArmatureSelectionService
var view_plane_service: ArmatureViewPlaneService
var skeleton_edit_service: ArmatureEditService
var skin_rebuild_service: ArmatureSkinService
var undo_snapshot_service: ArmatureUndoRedoService
var extrude_service: ArmatureExtrudeService
var scaling_service: ArmatureScalingService
var copy_paste_service: ArmatureCopyPasteService
var spring_chain_service: ArmatureSpringBoneChainService
var viewport_input_router: ArmatureInputRouter
var auto_weight_service:ArmatureAutoWeightService

var _pending_extrude: Dictionary = {}
var _pending_extrude_pre: Array = []


var _saved_show_rest_only_by_id: Dictionary = {}
var _active_skeleton_id: int = 0
## Initializes plugin UI and services.
func _enter_tree() -> void:
	context = ArmatureSkeletonContext.new()
	add_child(context)

	context.editor_interface = get_editor_interface()
	context.undo_redo = get_undo_redo()

	skeleton_gizmo = SKELETON_GIZMO.new()
	add_node_3d_gizmo_plugin(skeleton_gizmo)
	skeleton_gizmo.recorded_bones_changed.connect(_on_recorded_bones_changed)
	context.gizmo_plugin = skeleton_gizmo

	toolbar_controller = ToolbarController.new()
	add_child(toolbar_controller)
	toolbar_controller.toolbar_scene = toolbar_scene
	toolbar_controller.attach_to_container(self, EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU)
	toolbar_controller.mode_changed.connect(_on_skeleton_mode_changed)
	context.toolbar = toolbar_controller.toolbar
	context.toolbar.snap_enabled_changed.connect(_on_snap_enabled_changed)
	context.toolbar.snap_amount_changed.connect(_on_snap_amount_changed)
	context.toolbar.create_root_bone.connect(_ensure_skeleton_has_root_bone)
	context_menu_controller = ContextMenuController.new()
	add_child(context_menu_controller)
	context_menu_controller.set_context(context)
	context_menu_controller.attach_to_editor(get_editor_interface())
	context_menu_controller.action_requested.connect(_on_context_menu_action_requested)

	extrude_name_controller = ExtrudeNameController.new()
	add_child(extrude_name_controller)
	extrude_name_controller.set_context(context)
	extrude_name_controller.attach_to_editor(get_editor_interface())
	extrude_name_controller.confirmed.connect(_on_extrude_name_confirmed)
	extrude_name_controller.canceled.connect(_on_extrude_name_canceled)

	rename_dialog_controller = RenameDialogController.new()
	add_child(rename_dialog_controller)
	rename_dialog_controller.set_context(context)
	rename_dialog_controller.attach_to_editor(get_editor_interface())
	rename_dialog_controller.confirmed.connect(_on_rename_confirmed)

	selection_service = ArmatureSelectionService.new()
	selection_service.set_context(context)

	view_plane_service = ArmatureViewPlaneService.new()

	skeleton_edit_service = ArmatureEditService.new()
	skeleton_edit_service.set_context(context)

	skin_rebuild_service = ArmatureSkinService.new()
	skin_rebuild_service.set_context(context)

	undo_snapshot_service = ArmatureUndoRedoService.new()
	undo_snapshot_service.set_dependencies(context, skin_rebuild_service)
	undo_snapshot_service.skeleton_gizmo = skeleton_gizmo
	extrude_service = ArmatureExtrudeService.new()
	extrude_service.set_dependencies(context, selection_service, view_plane_service)

	spring_chain_service = ArmatureSpringBoneChainService.new()
	spring_chain_service.set_dependencies(context, selection_service)
	
	scaling_service = ArmatureScalingService.new()
	scaling_service.set_dependencies(context, selection_service, undo_snapshot_service, skeleton_edit_service)
	
	copy_paste_service = ArmatureCopyPasteService.new()
	copy_paste_service.set_dependencies(context, selection_service, undo_snapshot_service, view_plane_service)
	spring_bone_collision_service = ArmatureSpringBoneCollisionService.new()
	spring_bone_collision_service.editor_interface = get_editor_interface()
	spring_bone_collision_service.undo_redo = get_undo_redo()
	viewport_input_router = ArmatureInputRouter.new()
	viewport_input_router.set_dependencies(
		context,
		selection_service,
		extrude_service,
		undo_snapshot_service,
		skeleton_edit_service,
		spring_chain_service,
		context_menu_controller,
		extrude_name_controller,
		scaling_service,
		copy_paste_service
	)
	auto_weight_service = ArmatureAutoWeightService.new()
	set_input_event_forwarding_always_enabled()
	call_deferred("_force_refresh_gizmos")


func _on_snap_enabled_changed(enabled: bool) -> void:
	skeleton_gizmo.snap_enabled = enabled
	extrude_service.snap_enabled = enabled
	scaling_service.snap_enabled = enabled

func _on_snap_amount_changed(amount: float) -> void:
	extrude_service.snap_amount = amount
	scaling_service.snap_amount = amount
	skeleton_gizmo.snap_amount = amount
	
## Disposes plugin UI and services.
func _exit_tree() -> void:
	_restore_active_skeleton_show_rest_only()
	if context.skeleton:
		context.skeleton.clear_gizmos()
	if skeleton_gizmo != null:
		remove_node_3d_gizmo_plugin(skeleton_gizmo)
		skeleton_gizmo = null
	if toolbar_controller != null:
		toolbar_controller.detach_from_container(self, EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU)
		toolbar_controller.queue_free()
		toolbar_controller = null

	if context_menu_controller != null:
		context_menu_controller.dispose()
		context_menu_controller.queue_free()
		context_menu_controller = null

	if extrude_name_controller != null:
		extrude_name_controller.dispose()
		extrude_name_controller.queue_free()
		extrude_name_controller = null

	if rename_dialog_controller != null:
		rename_dialog_controller.dispose()
		rename_dialog_controller.queue_free()
		rename_dialog_controller = null

	if context != null:
		context.queue_free()
		context = null


## Returns true if this plugin handles the given object.
func _handles(object: Object) -> bool:
	var c = object.get_class()
	if c == "Skeleton3D":
		var next_skeleton := object as Skeleton3D
		_switch_active_skeleton(next_skeleton)
		context.set_skeleton(next_skeleton)
		context.skeleton.clear_subgizmo_selection()
		if !context.skeleton.property_list_changed.is_connected(check_create_root_bone):
			context.skeleton.property_list_changed.connect(check_create_root_bone)

		toolbar_controller.toolbar.visible = true
	elif c == "MultiNodeEdit":
		var selected = EditorInterface.get_selection().get_selected_nodes()
		for node in selected:
			if node is Skeleton3D:
				var next_skeleton = node
				_switch_active_skeleton(next_skeleton)
				context.set_skeleton(next_skeleton)
				context.skeleton.clear_subgizmo_selection()
				if !context.skeleton.property_list_changed.is_connected(check_create_root_bone):
					context.skeleton.property_list_changed.connect(check_create_root_bone)

				toolbar_controller.toolbar.visible = true
	else:
		_switch_active_skeleton(null)
		context.clear_skeleton()
		toolbar_controller.toolbar.visible = false
	return context.skeleton != null

func check_create_root_bone():
	if !context.skeleton:
		return
	if context.skeleton.get_bone_count() == 0:
		toolbar_controller.toolbar.set_can_create_root_bone(true)
	else:
		toolbar_controller.toolbar.set_can_create_root_bone(false)
## Applies the toolbar mode to the skeleton display.
func _on_skeleton_mode_changed(mode: int) -> void:
	if context == null or context.skeleton == null:
		return

	if context.gizmo_plugin != null and context.gizmo_plugin.has_method("set_mode"):
		context.gizmo_plugin.call("set_mode", mode)

	if mode == 0:
		context.skeleton.show_rest_only = false
	elif mode == 1:
		context.skeleton.show_rest_only = true

func _switch_active_skeleton(next_skeleton: Skeleton3D) -> void:
	var next_id := 0 if next_skeleton == null else int(next_skeleton.get_instance_id())
	if next_id == _active_skeleton_id:
		return

	#_restore_active_skeleton_show_rest_only()

	_active_skeleton_id = next_id

	if next_skeleton == null:
		return
	_on_skeleton_mode_changed(context.get_edit_mode())
	if not _saved_show_rest_only_by_id.has(_active_skeleton_id):
		_saved_show_rest_only_by_id[_active_skeleton_id] = next_skeleton.show_rest_only
	next_skeleton.property_list_changed.emit()


func _restore_active_skeleton_show_rest_only() -> void:
	if _active_skeleton_id == 0:
		return
	if context == null:
		return

	var current := context.skeleton
	if current == null:
		_active_skeleton_id = 0
		return

	var current_id := int(current.get_instance_id())
	if current_id != _active_skeleton_id:
		_active_skeleton_id = 0
		return

	if _saved_show_rest_only_by_id.has(_active_skeleton_id):
		current.show_rest_only = bool(_saved_show_rest_only_by_id[_active_skeleton_id])

	_active_skeleton_id = 0


## Forwards 3D viewport input into the router.
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if viewport_input_router == null:
		return 0

	return viewport_input_router.handle(camera, event)


## Refreshes gizmos for all Skeleton3D nodes in the edited scene.
func _force_refresh_gizmos() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	_refresh_skeletons_in_tree(root)


func _refresh_skeletons_in_tree(node: Node) -> void:
	if node is Skeleton3D:
		(node as Skeleton3D).update_gizmos()

	for child in node.get_children():
		_refresh_skeletons_in_tree(child)

## Ensures the active skeleton has at least one bone.
func _ensure_skeleton_has_root_bone() -> void:
	if context == null or context.skeleton == null:
		return
	if undo_snapshot_service == null or skeleton_edit_service == null:
		return

	var skeleton := context.skeleton
	if skeleton.get_bone_count() > 0:
		return

	var pre := undo_snapshot_service.capture()
	skeleton_edit_service._create_initial_root_bone()
	var post := undo_snapshot_service.capture()
	undo_snapshot_service.commit("Create Root Bone", pre, post, true)
## Receives recorded bones updates from the gizmo.
func _on_recorded_bones_changed(bone_indices: Array) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var ap := root.get_node_or_null("%AnimationPlayer")
	if ap != null and ap.has_method("key_bone_indices"):
		ap.call("key_bone_indices", bone_indices)

## Dispatches context menu actions to edit services.
func _on_context_menu_action_requested(action_id: int, bone_index: int) -> void:
	if context == null or context.skeleton == null:
		return

	match action_id:
		ContextMenuController.ACTION_SUBDIVIDE:
			_on_request_subdivide(bone_index)
		ContextMenuController.ACTION_EXTRUDE:
			_on_request_extrude()
		ContextMenuController.ACTION_CREATE_SPRING_CHAIN:
			_on_request_create_spring_chain()
		ContextMenuController.ACTION_DELETE:
			_on_request_delete_hierarchy(bone_index)
		ContextMenuController.ACTION_RENAME:
			_on_request_rename(bone_index)
		ContextMenuController.ACTION_SCALE:
			_on_request_scale()
		ContextMenuController.ACTION_COPY:
			_on_request_copy(bone_index)
		ContextMenuController.ACTION_PASTE_AS_CHILD:
			_on_request_paste_as_child(bone_index)
		ContextMenuController.ACTION_CREATE_SPRING_BONE_COLLISION:
			spring_bone_collision_service.create_capsule_for_bone(context, bone_index)
		ContextMenuController.ACTION_AUTO_WEIGHT:
			auto_weight_service.open_dialog()
func _on_request_scale() -> void:
	if scaling_service == null:
		return
	if context == null or context.editor_interface == null:
		return

	var viewport := context.editor_interface.get_editor_viewport_3d()
	var start_pos := viewport.get_mouse_position()
	scaling_service.try_begin(viewport, start_pos)


func _on_request_copy(bone_index: int) -> void:
	if copy_paste_service == null:
		return
	copy_paste_service.copy_from_context_bone(bone_index)


func _on_request_paste_as_child(bone_index: int) -> void:
	if copy_paste_service == null:
		return
	copy_paste_service.paste_as_child_of_bone(bone_index)

func _on_request_subdivide(bone_index: int) -> void:
	var pre := undo_snapshot_service.capture()
	skeleton_edit_service._apply_subdivide(bone_index, 2)
	var post := undo_snapshot_service.capture()
	undo_snapshot_service.commit("Subdivide Bone", pre, post, true)


func _on_request_extrude() -> void:
	if context == null or context.skeleton == null:
		return
	if not context.is_edit_mode():
		return

	_pending_extrude_pre = undo_snapshot_service.capture()
	extrude_service._begin_extrude()

func _on_request_create_spring_chain() -> void:
	spring_chain_service._build_valid_chain_from_selection()


func _on_request_delete_hierarchy(bone_index: int) -> void:
	var pre := undo_snapshot_service.capture()
	skeleton_edit_service._delete_selected_bone_with_children(bone_index)
	var post := undo_snapshot_service.capture()
	undo_snapshot_service.commit("Delete Bone Hierarchy", pre, post, true)


func _on_request_rename(bone_index: int) -> void:
	rename_dialog_controller._popup_rename_bone_dialog(bone_index)


## Applies the name to the pending extruded bone and commits undo.
func _on_extrude_name_confirmed(base_name: String, pending: Dictionary, pre_snapshot: Array) -> void:
	if context == null or context.skeleton == null:
		return

	_pending_extrude = pending
	_pending_extrude_pre = pre_snapshot.duplicate(true)

	_apply_extrude_bone_name(base_name, _pending_extrude)
	var post := undo_snapshot_service.capture()
	undo_snapshot_service.commit("Extrude Bone", _pending_extrude_pre, post, true)

	_pending_extrude.clear()
	_pending_extrude_pre.clear()


## Restores pre-snapshot when extrude naming is canceled.
func _on_extrude_name_canceled(pending: Dictionary, pre_snapshot: Array) -> void:
	if context == null or context.skeleton == null:
		return
	if pre_snapshot.is_empty():
		return

	undo_snapshot_service._restore_snapshot_internal(pre_snapshot)
	_pending_extrude.clear()
	_pending_extrude_pre.clear()


## Commits a rename action.
func _on_rename_confirmed(bone_index: int, new_name: String) -> void:
	if context == null or context.skeleton == null:
		return

	var pre := undo_snapshot_service.capture()
	context.skeleton.set_bone_name(bone_index, new_name)
	var post := undo_snapshot_service.capture()
	undo_snapshot_service.commit("Rename Bone", pre, post, false)

	context.skeleton.update_gizmos()
	context.skeleton.property_list_changed.emit()


func _apply_extrude_bone_name(base_name: String, pending: Dictionary) -> void:
	var skeleton := context.skeleton
	var bone_index: int = int(pending.get("bone", -1))
	var tip_index: int = int(pending.get("tip", -1))

	if bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return

	var cleaned := context._sanitize_bone_name(base_name)
	if cleaned.is_empty():
		return

	skeleton.set_bone_name(bone_index, cleaned)

	if tip_index >= 0 and tip_index < skeleton.get_bone_count():
		var tip_name := "%s_tip" % cleaned
		tip_name = context._make_unique_bone_name(tip_name, [bone_index, tip_index])
		skeleton.set_bone_name(tip_index, tip_name)

	skeleton.update_gizmos()
	skeleton.property_list_changed.emit()
