@tool
extends Node
class_name RenameDialogController

signal confirmed(bone_index: int, new_name: String)
signal canceled(bone_index: int)

@export_category("Dialog")
@export var dialog_title := "Rename Bone"
@export var default_placeholder := "New bone name"

var context: ArmatureSkeletonContext = null
var _editor_interface: EditorInterface = null
var _dialog: AcceptDialog = null
var _edit: LineEdit = null
var _old_label: Label = null
var _target_bone := -1

## Sets the context used by this controller.
func set_context(p_context: ArmatureSkeletonContext) -> void:
	context = p_context


## Creates and attaches the dialog to the editor base control.
func attach_to_editor(editor_interface: EditorInterface) -> void:
	if editor_interface == null:
		return
	_editor_interface = editor_interface
	_create_dialog_if_needed()
	if _dialog.get_parent() == null:
		_editor_interface.get_base_control().add_child(_dialog)


## Pops up the dialog for the given bone index.
## Preserves the original function name.
func _popup_rename_bone_dialog(bone_index: int) -> void:
	if context == null or context.skeleton == null:
		return

	var skeleton := context.skeleton
	if bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return

	_target_bone = bone_index

	var old_name := skeleton.get_bone_name(bone_index)

	_create_dialog_if_needed()
	_edit.text = old_name
	_old_label.text = "Current name: %s" % old_name
	_validate_name(old_name)

	_dialog.popup_centered()
	_dialog.call_deferred("reset_size")
	_edit.grab_focus()
	_edit.select_all()


## Frees dialog resources.
func dispose() -> void:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = null
	_editor_interface = null
	_target_bone = -1




func _create_dialog_if_needed() -> void:
	if _dialog != null:
		return

	_dialog = AcceptDialog.new()
	_dialog.name = "RenameBoneDialog"
	_dialog.title = dialog_title
	_dialog.exclusive = true
	_dialog.dialog_hide_on_ok = true

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(320, 0)

	_edit = LineEdit.new()
	_edit.placeholder_text = default_placeholder
	_edit.text_changed.connect(_on_text_changed)

	_old_label = Label.new()
	_old_label.modulate = Color(0.6, 0.6, 0.6)
	_old_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_old_label.clip_text = true
	_old_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	root.add_child(_edit)
	root.add_child(_old_label)

	_dialog.add_child(root)

	_dialog.confirmed.connect(_on_confirmed)
	_dialog.canceled.connect(_on_canceled)


func _on_text_changed(new_text: String) -> void:
	_validate_name(new_text)


func _validate_name(raw_text: String) -> void:
	if _dialog == null:
		return

	var ok_button := _dialog.get_ok_button()
	if ok_button == null:
		return

	var name := _sanitize_bone_name(raw_text)

	if name.is_empty():
		ok_button.disabled = true
		return

	if _bone_name_exists(name, [_target_bone]):
		ok_button.disabled = true
		return

	ok_button.disabled = false


func _on_confirmed() -> void:
	if context == null or context.skeleton == null:
		_target_bone = -1
		return
	if _target_bone < 0:
		return

	var new_name := _sanitize_bone_name(_edit.text)
	if new_name.is_empty():
		return

	if _bone_name_exists(new_name, [_target_bone]):
		return

	confirmed.emit(_target_bone, new_name)
	_target_bone = -1


func _on_canceled() -> void:
	canceled.emit(_target_bone)
	_target_bone = -1


func _sanitize_bone_name(name: String) -> String:
	if context == null:
		return name
	return context._sanitize_bone_name(name)


func _bone_name_exists(name: String, ignore_bones: Array[int] = []) -> bool:
	if context == null:
		return false
	return context._bone_name_exists(name, ignore_bones)
