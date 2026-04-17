extends RefCounted
class_name SingleCellTargeting

func resolve(skill: Dictionary, caster, primary_cell, grid, extra: Dictionary) -> Array[Dictionary]:
	if primary_cell == null:
		return []
	var cell := Vector2i(primary_cell)
	if not grid.is_valid_cell(cell):
		return []
	var u = grid.get_unit_at(cell)
	if u == null:
		return []
	return [{
		"unit": u,
		"unit_id": int(u.entity_id),
		"cell": cell,
		"role": "primary",
	}]

