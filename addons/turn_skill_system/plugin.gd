@tool
extends EditorPlugin

const AUTOLOAD_NAME := "TurnSkillRuntime"
const AUTOLOAD_PATH := "res://addons/turn_skill_system/runtime/skill_autoload.gd"

const DOCK_SCENE_PATH := "res://addons/turn_skill_system/editor/skill_editor_dock.tscn"

var _dock: Control

func _enter_tree() -> void:
	print("[TurnSkillSystem] plugin enabled")
	_install_autoload()
	_install_dock()

func _exit_tree() -> void:
	print("[TurnSkillSystem] plugin disabled")
	_uninstall_dock()
	_remove_autoload()

func _install_autoload() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	ProjectSettings.save()

func _remove_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	remove_autoload_singleton(AUTOLOAD_NAME)
	ProjectSettings.save()

func _install_dock() -> void:
	if ResourceLoader.exists(DOCK_SCENE_PATH):
		var packed := load(DOCK_SCENE_PATH)
		_dock = packed.instantiate()
		add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

func _uninstall_dock() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null

