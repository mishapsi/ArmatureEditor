@tool
extends Control

signal create_root_bone
signal mode_changed(mode: int)
signal snap_enabled_changed(enabled: bool)
signal snap_amount_changed(amount: float)

enum MODE { POSE, EDIT }

@onready var _root_bone:Button = %RootBone
@onready var _mode_selector: OptionButton = %ModeSelector
@onready var _snap_button: CheckButton = %Snap
@onready var _snap_amount: SpinBox = %SnapAmount

var mode: MODE = MODE.POSE
var snap_enabled: bool = true
var snap_amount: float = 0.1


func _ready() -> void:
	_initialize_ui()
	_connect_signals()

func _initialize_ui() -> void:
	_mode_selector.clear()
	_mode_selector.add_item("Pose", MODE.POSE)
	_mode_selector.add_item("Edit", MODE.EDIT)
	_mode_selector.select(mode)
	_snap_button.button_pressed = snap_enabled
	_snap_amount.value = snap_amount
	_snap_amount.editable = snap_enabled


func _connect_signals() -> void:
	_mode_selector.item_selected.connect(_on_mode_selected)
	_snap_button.toggled.connect(_on_snap_toggled)
	_snap_amount.value_changed.connect(_on_snap_amount_changed)
	_root_bone.pressed.connect(func():create_root_bone.emit())


func _on_mode_selected(index: int) -> void:
	mode = index
	mode_changed.emit(mode)


func _on_snap_toggled(enabled: bool) -> void:
	snap_enabled = enabled
	_snap_amount.editable = enabled
	snap_enabled_changed.emit(enabled)


func _on_snap_amount_changed(value: float) -> void:
	snap_amount = value
	snap_amount_changed.emit(value)

func set_can_create_root_bone(visible: bool) -> void:
	_root_bone.visible = visible
