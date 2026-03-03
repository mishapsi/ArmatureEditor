# toolbar_controller.gd
# Wraps the toolbar scene instance and exposes stable API for mode queries and signals.

@tool
extends Node
class_name ToolbarController

signal mode_changed(mode: int)

# =========================================================
# Exports
# =========================================================
@export_category("Toolbar")
@export var toolbar_scene: PackedScene

# =========================================================
# Public
# =========================================================
var toolbar: Control = null


## Creates the toolbar instance and adds it to the given editor container.
func attach_to_container(editor_plugin: EditorPlugin, container_id: int) -> void:
	if editor_plugin == null:
		return
	if toolbar_scene == null:
		return

	if toolbar != null:
		return

	toolbar = toolbar_scene.instantiate() as Control
	if toolbar == null:
		return

	editor_plugin.add_control_to_container(container_id, toolbar)

	if toolbar.has_signal("mode_changed"):
		toolbar.mode_changed.connect(_on_toolbar_mode_changed)


## Removes the toolbar from the container and frees it.
func detach_from_container(editor_plugin: EditorPlugin, container_id: int) -> void:
	if editor_plugin == null:
		return
	if toolbar == null:
		return

	editor_plugin.remove_control_from_container(container_id, toolbar)
	toolbar.queue_free()
	toolbar = null


## Returns true if the toolbar indicates edit mode.
## Preserves the original function name.
func _is_edit_mode() -> bool:
	return is_edit_mode()


## Returns true if the toolbar indicates edit mode.
func is_edit_mode() -> bool:
	if toolbar == null:
		return false
	if not toolbar.has_method("get"):
		return false
	return int(toolbar.get("mode")) == 1


## Returns the raw toolbar mode value if available, else -1.
func get_mode() -> int:
	if toolbar == null:
		return -1
	if not toolbar.has_method("get"):
		return -1
	return int(toolbar.get("mode"))


# =========================================================
# Private
# =========================================================

func _on_toolbar_mode_changed(mode: int) -> void:
	mode_changed.emit(mode)
