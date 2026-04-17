extends RefCounted
class_name CrossTargeting

func resolve(skill: Dictionary, caster, primary_cell, grid, extra: Dictionary) -> Array[Dictionary]:
	if primary_cell == null:
		return []
	var c := Vector2i(primary_cell)
	var cells := [
		c,
		c + Vector2i(-1, 0),
		c + Vector2i(1, 0),
		c + Vector2i(0, -1),
		c + Vector2i(0, 1),
	]
	var out: Array[Dictionary] = []
	for cell in cells:
		if not grid.is_valid_cell(cell):
			continue
		var u = grid.get_unit_at(cell)
		if u == null:
			continue
		out.append({
			"unit": u,
			"unit_id": int(u.entity_id),
			"cell": cell,
			"role": "secondary",
		})
	if not out.is_empty():
		out[0]["role"] = "primary"
	return out

