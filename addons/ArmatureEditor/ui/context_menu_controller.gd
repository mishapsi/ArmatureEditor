# context_menu_controller.gd
# Popup menu controller for bone context actions.

@tool
extends Node
class_name ContextMenuController

signal action_requested(action_id: int, bone_index: int)

@export_category("Menu")
@export var menu_title := "Bone Menu"

var context: ArmatureSkeletonContext = null

## Sets the context used by this controller.
func set_context(p_context: ArmatureSkeletonContext) -> void:
	context = p_context

## Builds and attaches the popup menu to the editor base control.
func attach_to_editor(editor_interface: EditorInterface) -> void:
	if editor_interface == null:
		return
	_editor_interface = editor_interface
	_create_menu_if_needed()
	if _popup.get_parent() == null:
		_editor_interface.get_base_control().add_child(_popup)

## Shows the menu for the given bone at the given screen position.
func popup_for_bone(bone_index: int, screen_pos: Vector2) -> void:
	if bone_index < 0:
		return
	_context_bone = bone_index
	_create_menu_if_needed()
	_rebuild_menu(_MenuMode.BONE)
	_popup.popup(Rect2(screen_pos, Vector2.ZERO))

## Shows a minimal menu when multi-selection includes the active skeleton.
func popup_for_multi_selection(screen_pos: Vector2) -> void:
	_context_bone = -1
	_create_menu_if_needed()
	_rebuild_menu(_MenuMode.MULTI_SELECTION)
	_popup.popup(Rect2(screen_pos, Vector2.ZERO))

## Frees the popup menu and clears internal state.
func dispose() -> void:
	if _popup != null:
		_popup.queue_free()
	_popup = null
	_context_bone = -1
	_editor_interface = null

var _popup: PopupMenu = null
var _context_bone := -1
var _editor_interface: EditorInterface = null

enum _MenuMode { BONE, MULTI_SELECTION }

const ACTION_SUBDIVIDE := 0
const ACTION_EXTRUDE := 1
const ACTION_CREATE_SPRING_CHAIN := 2
const ACTION_DELETE := 3
const ACTION_RENAME := 4
const ACTION_SCALE := 5
const ACTION_COPY := 6
const ACTION_PASTE_AS_CHILD := 7
const ACTION_CREATE_SPRING_BONE_COLLISION := 8
const ACTION_AUTO_WEIGHT := 9


func _create_menu_if_needed() -> void:
	if _popup != null:
		return

	_popup = PopupMenu.new()
	_popup.name = "ArmatureEditorContextMenu"
	_popup.id_pressed.connect(_on_id_pressed)


func _rebuild_menu(mode: int) -> void:
	_popup.clear()

	match mode:
		_MenuMode.BONE:
			_popup.add_item("Subdivide", ACTION_SUBDIVIDE)
			_popup.add_item("[E]xtrude", ACTION_EXTRUDE)
			_popup.add_item("[S]cale…", ACTION_SCALE)
			_popup.add_separator()
			_popup.add_item("[Ctrl+C] Copy Bone Subtree", ACTION_COPY)
			_popup.add_item("[Ctrl+V] Paste as Child", ACTION_PASTE_AS_CHILD)
			_popup.add_separator()
			_popup.add_item("Create Spring Bone Chain", ACTION_CREATE_SPRING_CHAIN)
			_popup.add_item("Create Spring Collision Capsule", ACTION_CREATE_SPRING_BONE_COLLISION)
			_popup.add_separator()
			_popup.add_item("Delete", ACTION_DELETE)
			_popup.add_item("Rename…", ACTION_RENAME)

		_MenuMode.MULTI_SELECTION:
			_popup.add_item("Auto Weight Selected Meshes…", ACTION_AUTO_WEIGHT)


func _on_id_pressed(id: int) -> void:
	action_requested.emit(id, _context_bone)
