@tool
extends EditorPlugin

func _enter_tree() -> void:
	print("[TurnManager] Plugin enabled.")

func _exit_tree() -> void:
	print("[TurnManager] Plugin disabled.")
