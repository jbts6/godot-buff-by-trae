@tool
extends EditorPlugin

func _enter_tree() -> void:
	print("[OmniBuff] plugin enabled")

func _exit_tree() -> void:
	print("[OmniBuff] plugin disabled")

