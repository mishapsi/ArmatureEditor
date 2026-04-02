@tool
extends RefCounted
class_name ArmatureInputRouter

var context: ArmatureSkeletonContext = null
var selection_service: ArmatureSelectionService = null
var extrude_service: ArmatureExtrudeService = null
var undo_snapshot_service: ArmatureUndoRedoService = null
var skeleton_edit_service: ArmatureEditService = null
var spring_chain_service: ArmatureSpringBoneChainService = null
var scaling_service: ArmatureScalingService = null
var copy_paste_service: ArmatureCopyPasteService = null
var context_menu_controller: Object = null 
var extrude_name_controller: Object = null 
var toaster: EditorToaster = null
## Sets dependencies used by this router.
func set_dependencies(
	p_context: ArmatureSkeletonContext,
	p_selection_service: ArmatureSelectionService,
	p_extrude_service: ArmatureExtrudeService,
	p_undo_snapshot_service: ArmatureUndoRedoService,
	p_skeleton_edit_service: ArmatureEditService,
	p_spring_chain_service: ArmatureSpringBoneChainService,
	p_context_menu_controller: ContextMenuController,
	p_extrude_name_controller: ExtrudeNameController,
	p_scaling_service: ArmatureScalingService,
	p_copy_paste_service: ArmatureCopyPasteService
) -> void:
	context = p_context
	selection_service = p_selection_service
	extrude_service = p_extrude_service
	undo_snapshot_service = p_undo_snapshot_service
	skeleton_edit_service = p_skeleton_edit_service
	spring_chain_service = p_spring_chain_service
	context_menu_controller = p_context_menu_controller
	extrude_name_controller = p_extrude_name_controller
	scaling_service = p_scaling_service
	copy_paste_service = p_copy_paste_service


## Handles a 3D viewport input event.
##
## @return int forwarding result (0 = pass, 1 = handled, 2 = handled + stop)
func handle(camera: Camera3D, event: InputEvent) -> int:
	if context == null or context.skeleton == null:
		return 0
	if context.editor_interface == null:
		return 0

	var skeleton := context.skeleton
	var gizmo := context.get_active_gizmo()
	if gizmo == null:
		return 0

	var viewport := context.editor_interface.get_editor_viewport_3d()
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()

	if scaling_service != null and scaling_service.is_scaling():
		return scaling_service.handle(viewport, event)

	if copy_paste_service != null and copy_paste_service.is_modal():
		return copy_paste_service.handle(viewport, event)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			var global_pos := viewport.get_screen_transform().origin + mb.position
			if not context.is_edit_mode():
				if selected_nodes.size() > 1:
					if _should_show_multi_selection_menu():
						if context_menu_controller != null and context_menu_controller.has_method("popup_for_multi_selection"):
							context_menu_controller.call("popup_for_multi_selection", global_pos)
						viewport.set_input_as_handled()
						return 1
				_push_edit_mode_toast()
				return 1

			var bone_index := selection_service.get_context_bone_from_selection()


			if bone_index >= 0:
				if context_menu_controller != null and context_menu_controller.has_method("popup_for_bone"):
					context_menu_controller.call("popup_for_bone", bone_index, global_pos)
				viewport.set_input_as_handled()
				return 1

			if selected_nodes.size() > 1:
				if _should_show_multi_selection_menu():
					if context_menu_controller != null and context_menu_controller.has_method("popup_for_multi_selection"):
						context_menu_controller.call("popup_for_multi_selection", global_pos)
					viewport.set_input_as_handled()
					return 1

			return 0

	if event is InputEventMouseMotion and extrude_service != null and not extrude_service.is_extruding():
		var mm := event as InputEventMouseMotion
		if context.gizmo_plugin != null and context.gizmo_plugin.has_method("update_hover"):
			context.gizmo_plugin.call("update_hover", camera, mm.position, gizmo)

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_E:
			if not context.is_edit_mode():
				_push_edit_mode_toast()
				return 1

			viewport.set_input_as_handled()

			if skeleton.get_bone_count() == 0:
				var pre := undo_snapshot_service.capture()
				skeleton_edit_service._create_initial_root_bone()
				var post := undo_snapshot_service.capture()
				undo_snapshot_service.commit("Create Root Bone", pre, post, true)
				return 2

			if undo_snapshot_service != null:
				var pre_extrude := undo_snapshot_service.capture()
				extrude_service._begin_extrude()
				if extrude_service.is_extruding():
					_store_pending_extrude_snapshot(pre_extrude)
					return 2

			return 2

	if extrude_service != null and extrude_service.is_extruding():
		if event is InputEventMouseMotion:
			extrude_service._update_extrude(event as InputEventMouseMotion)
			return 2

		if event is InputEventMouseButton:
			var lmb := event as InputEventMouseButton
			if lmb.pressed and lmb.button_index == MOUSE_BUTTON_LEFT:
				var pending := extrude_service.finish_extrude()

				if extrude_name_controller != null and extrude_name_controller.has_method("begin_naming"):
					var pre := _consume_pending_extrude_snapshot()
					extrude_name_controller.call("begin_naming", pending, pre)

				return 2

	if event is InputEventKey:
		var ks := event as InputEventKey
		if ks.pressed and not ks.echo and ks.keycode == KEY_S:
			var start_pos := viewport.get_mouse_position()
			if scaling_service != null and scaling_service.try_begin(viewport, start_pos):
				return 2

	if event is InputEventKey:
		var kc := event as InputEventKey
		if kc.pressed and not kc.echo:

			if kc.keycode == KEY_C and kc.ctrl_pressed:
				if copy_paste_service != null and copy_paste_service.copy_from_selection():
					viewport.set_input_as_handled()
					return 2

			if kc.keycode == KEY_V and kc.ctrl_pressed:
				if copy_paste_service != null:

					if not context.is_edit_mode():
						_push_edit_mode_toast()
						return 1

					var parent := selection_service.get_context_bone_from_selection()
					if parent < 0:
						return 1

					if copy_paste_service.try_begin_modal(parent):
						viewport.set_input_as_handled()
						return 2
	return 0

func _should_show_multi_selection_menu() -> bool:
	if context == null or context.skeleton == null:
		return false

	var selection := EditorInterface.get_selection()
	if selection == null:
		return false

	var nodes := selection.get_selected_nodes()
	if nodes.size() < 2:
		return false

	return context.skeleton in nodes


var _pending_extrude_pre_snapshot: Array = []


func _store_pending_extrude_snapshot(pre_snapshot: Array) -> void:
	_pending_extrude_pre_snapshot = pre_snapshot.duplicate(true)


func _consume_pending_extrude_snapshot() -> Array:
	var out := _pending_extrude_pre_snapshot.duplicate(true)
	_pending_extrude_pre_snapshot.clear()
	return out


func _push_edit_mode_toast() -> void:
	var toaster_obj := context.editor_interface.get_editor_toaster()
	if toaster_obj != null:
		toaster_obj.push_toast(
			"Switch to Edit Mode to modify bones.",
			EditorToaster.SEVERITY_INFO
		)
