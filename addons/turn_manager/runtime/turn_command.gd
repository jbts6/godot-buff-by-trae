class_name TurnCommand
extends RefCounted

var kind: String = "cast_skill"
var skill_id: String
var primary_cell: Vector2i
var extra: Dictionary = {}

func _init(p_skill_id: String = "", p_primary_cell: Vector2i = Vector2i.ZERO, p_extra: Dictionary = {}) -> void:
	skill_id = p_skill_id
	primary_cell = p_primary_cell
	extra = p_extra
