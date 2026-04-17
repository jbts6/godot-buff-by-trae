extends RefCounted
class_name Grid

const GRID_SIZE := 3

var _units: Array = [] # Array[Unit]

func set_units(units: Array) -> void:
	_units = units

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE

func get_unit_at(cell: Vector2i):
	for u in _units:
		if u == null:
			continue
		if Vector2i(u.cell) == cell:
			return u
	return null

func get_units_by_camp(camp: String, alive_only := true) -> Array:
	var out: Array = []
	for u in _units:
		if u == null:
			continue
		if String(u.camp) != camp:
			continue
		if alive_only and _is_dead(u):
			continue
		out.append(u)
	return out

func get_first_enemy(caster):
	var enemy_camp := "enemy" if String(caster.camp) == "ally" else "ally"
	var enemies := get_units_by_camp(enemy_camp, true)
	if enemies.is_empty():
		return null
	# 稳定排序：row asc, col asc
	enemies.sort_custom(func(a, b):
		if a.cell.x == b.cell.x:
			return a.cell.y < b.cell.y
		return a.cell.x < b.cell.x
	)
	return enemies[0]

static func _is_dead(u) -> bool:
	# demo/最小契约：优先读 u.is_dead，否则用 stats.HP <= 0
	if u.has_method("is_dead"):
		return bool(u.is_dead())
	if u.has_property("is_dead"):
		return bool(u.is_dead)
	if u.has_property("stats") and u.stats != null and u.stats.has_method("get_final"):
		# 这里无法拿到 ds.stat_id("HP")，因此仅作为扩展点
		return false
	return false

