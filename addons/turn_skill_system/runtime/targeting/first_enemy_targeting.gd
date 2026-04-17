extends RefCounted
class_name FirstEnemyTargeting

func resolve(skill: Dictionary, caster, primary_cell, grid, extra: Dictionary) -> Array[Dictionary]:
	var u = grid.get_first_enemy(caster)
	if u == null:
		return []
	return [{
		"unit": u,
		"unit_id": int(u.entity_id),
		"cell": Vector2i(u.cell),
		"role": "primary",
	}]

