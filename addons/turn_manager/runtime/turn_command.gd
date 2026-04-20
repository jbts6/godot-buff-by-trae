class_name TurnCommand
extends RefCounted

var kind: String = "skill" # "skill" | "item"
var id: String = ""

# 兼容旧字段名：把 skill_id 作为 id 的别名
var skill_id: String:
	get:
		return id
	set(value):
		id = String(value)
var primary_cell: Vector2i
var extra: Dictionary = {}

func _init(p_skill_id: String = "", p_primary_cell: Vector2i = Vector2i.ZERO, p_extra: Dictionary = {}) -> void:
	kind = "skill"
	id = p_skill_id
	primary_cell = p_primary_cell
	extra = p_extra


static func new_skill(p_skill_id: String, p_primary_cell: Vector2i, p_extra: Dictionary = {}) -> TurnCommand:
	return TurnCommand.new(p_skill_id, p_primary_cell, p_extra)


static func new_item(p_item_id: String, p_primary_cell: Vector2i, p_extra: Dictionary = {}) -> TurnCommand:
	var cmd = TurnCommand.new("", p_primary_cell, p_extra)
	cmd.kind = "item"
	cmd.id = p_item_id
	return cmd
