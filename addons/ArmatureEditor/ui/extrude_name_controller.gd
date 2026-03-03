# extrude_name_controller.gd
# Handles the "Name Bone" dialog after an extrusion completes.

@tool
extends Node
class_name ExtrudeNameController

signal confirmed(base_name: String, pending: Dictionary, pre_snapshot: Array)
signal canceled(pending: Dictionary, pre_snapshot: Array)

# =========================================================
# Exports
# =========================================================
@export_category("Dialog")
@export var dialog_title := "Name Bone"
@export var default_placeholder := "Bone name"

# =========================================================
# Public
# =========================================================
var context: ArmatureSkeletonContext = null


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


## Begins naming for a completed extrusion.
## pending must contain { "bone": int, "tip": int, "parent": int }.
func begin_naming(pending: Dictionary, pre_snapshot: Array) -> void:
	if context == null or context.skeleton == null:
		canceled.emit(pending, pre_snapshot)
		return

	_pending = pending
	_pre_snapshot = pre_snapshot.duplicate(true)

	_create_dialog_if_needed()

	var suggested := _suggest_extruded_bone_name(_pending.get("bone", -1))
	suggested = _make_unique_bone_name(suggested, [_pending.get("bone", -1), _pending.get("tip", -1)])

	_edit.text = suggested
	_validate_name_and_update_ui(suggested)

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
	_pending.clear()
	_pre_snapshot.clear()


# =========================================================
# Private
# =========================================================

var _editor_interface: EditorInterface = null
var _dialog: AcceptDialog = null
var _edit: LineEdit = null
var _warning_row: HBoxContainer = null
var _warning_icon: Label = null
var _warning_text: Label = null

var _pending: Dictionary = {}
var _pre_snapshot: Array = []


func _create_dialog_if_needed() -> void:
	if _dialog != null:
		return

	_dialog = AcceptDialog.new()
	_dialog.name = "ExtrudeNameDialog"
	_dialog.title = dialog_title
	_dialog.exclusive = true
	_dialog.dialog_hide_on_ok = true

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(320, 0)

	_edit = LineEdit.new()
	_edit.placeholder_text = default_placeholder
	_edit.text_changed.connect(_on_text_changed)

	_warning_row = HBoxContainer.new()
	_warning_row.visible = false
	_warning_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_warning_icon = Label.new()
	_warning_icon.text = "✖"
	_warning_icon.modulate = Color(1.0, 0.2, 0.2)

	_warning_text = Label.new()
	_warning_text.text = ""
	_warning_text.modulate = Color(1.0, 0.2, 0.2)
	_warning_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warning_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_warning_text.clip_text = true
	_warning_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_warning_row.add_child(_warning_icon)
	_warning_row.add_child(_warning_text)

	root.add_child(_edit)
	root.add_child(_warning_row)

	_dialog.add_child(root)

	_dialog.confirmed.connect(_on_confirmed)
	_dialog.canceled.connect(_on_canceled)


func _on_text_changed(new_text: String) -> void:
	_validate_name_and_update_ui(new_text)


func _validate_name_and_update_ui(raw_text: String) -> void:
	if _dialog == null:
		return

	var ok_button := _dialog.get_ok_button()
	if ok_button == null:
		return

	var name := _sanitize_bone_name(raw_text)

	if name.is_empty():
		ok_button.disabled = true
		_set_warning("Bone name required.")
		return

	var ignore:Array[int] = [_pending.get("bone", -1), _pending.get("tip", -1)]
	if _bone_name_exists(name, ignore):
		ok_button.disabled = true
		_set_warning("Bone name exists.")
		return

	ok_button.disabled = false
	_set_warning("")


func _set_warning(message: String) -> void:
	_warning_text.text = message
	_warning_row.visible = not message.is_empty()
	_dialog.call_deferred("reset_size")


func _on_confirmed() -> void:
	if context == null or context.skeleton == null:
		canceled.emit(_pending, _pre_snapshot)
		_clear_state()
		return

	var name := _sanitize_bone_name(_edit.text)
	if name.is_empty():
		return

	var ignore:Array[int] = [_pending.get("bone", -1), _pending.get("tip", -1)]
	if _bone_name_exists(name, ignore):
		return

	confirmed.emit(name, _pending, _pre_snapshot)
	_clear_state()
	_dialog.hide()


func _on_canceled() -> void:
	canceled.emit(_pending, _pre_snapshot)
	_clear_state()


func _clear_state() -> void:
	_pending.clear()
	_pre_snapshot.clear()


func _suggest_extruded_bone_name(bone_index: int) -> String:
	if context == null or context.skeleton == null:
		return "Bone"

	var skeleton := context.skeleton
	if bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return "Bone"

	var parent := skeleton.get_bone_parent(bone_index)
	if parent == -1:
		return "Root"

	var parent_name := skeleton.get_bone_name(parent)
	parent_name = parent_name.replace("_tip", "")
	return "%s" % parent_name


func _sanitize_bone_name(name: String) -> String:
	if context == null:
		return name
	return context._sanitize_bone_name(name)


func _bone_name_exists(name: String, ignore_bones: Array[int] = []) -> bool:
	if context == null:
		return false
	return context._bone_name_exists(name, ignore_bones)


func _make_unique_bone_name(base: String, ignore_bones: Array[int] = []) -> String:
	if context == null:
		return base
	return context._make_unique_bone_name(base, ignore_bones)
