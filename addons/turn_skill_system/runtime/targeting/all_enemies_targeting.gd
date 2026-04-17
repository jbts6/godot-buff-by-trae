extends RefCounted
class_name AllEnemiesTargeting

func resolve(skill: Dictionary, caster, primary_cell, grid, extra: Dictionary) -> Array[Dictionary]:
	var enemy_camp := "enemy" if String(caster.camp) == "ally" else "ally"
	var units := grid.get_units_by_camp(enemy_camp, true)
	var out: Array[Dictionary] = []
	for u in units:
		out.append({
			"unit": u,
			"unit_id": int(u.entity_id),
			"cell": Vector2i(u.cell),
			"role": "secondary",
		})
	if not out.is_empty():
		out[0]["role"] = "primary"
	return out

