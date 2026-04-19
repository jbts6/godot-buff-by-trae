extends RefCounted
class_name AuraManager

## 光环管理器（最小闭环）：
## - register_aura(owner_unit, aura_skill_id)
## - bind(event_bus, db, effects, omnibuff, grid)
## - refresh_all()：按 range 计算差集，enter/exit 执行效果
##
## 当前最小实现仅内置一个 range.rule：
## - "ally_front_row": 作用于 owner 同阵营且 cell.x == 0 的单位
## - "ally_all": 作用于 owner 同阵营全体存活单位

var _event_bus = null
var _db = null
var _effects = null
var _omnibuff = null
var _grid = null

var _auras: Array[Dictionary] = [] # [{owner_id, skill_id, skill_dict}]
var _affected: Dictionary = {}     # owner_id -> {target_id: true}

func bind(event_bus, db, effects, omnibuff, grid) -> void:
	_event_bus = event_bus
	_db = db
	_effects = effects
	_omnibuff = omnibuff
	_grid = grid


func register_aura(owner_unit, aura_skill_id: String) -> void:
	var r: Dictionary = _db.get_skill(aura_skill_id, true)
	if not bool(r.get("ok", false)):
		return
	var skill: Dictionary = r.get("skill", {})
	if String(skill.get("type", "")) != "aura":
		return
	var owner_id := int(owner_unit.entity_id)
	_auras.append({"owner_id": owner_id, "skill_id": aura_skill_id, "skill": skill})
	_affected[owner_id] = {}


func refresh_all() -> void:
	for a in _auras:
		_refresh_one(a)


func _refresh_one(a: Dictionary) -> void:
	var owner_id := int(a.get("owner_id", -1))
	var owner = _find_unit_by_id(owner_id)
	if owner == null:
		return

	var skill: Dictionary = a.get("skill", {})
	var aura: Dictionary = skill.get("aura", {})
	var range: Dictionary = aura.get("range", {})
	var rule := String(range.get("rule", ""))

	var new_targets: Dictionary = {}
	var targets: Array = []
	if rule == "ally_front_row":
		targets = _get_allies_in_front_row(owner)
	elif rule == "ally_all":
		targets = _get_allies(owner)
	else:
		# 未知规则：不生效
		targets = []

	for u in targets:
		new_targets[int(u.entity_id)] = true

	var old_targets: Dictionary = _affected.get(owner_id, {})

	# enter = new - old
	for tid in new_targets.keys():
		if old_targets.has(tid):
			continue
		var tu = _find_unit_by_id(int(tid))
		if tu == null:
			continue
		_apply_effects_list(skill, owner, tu, aura.get("on_enter", []))

	# exit = old - new
	for tid in old_targets.keys():
		if new_targets.has(tid):
			continue
		var tu2 = _find_unit_by_id(int(tid))
		if tu2 == null:
			continue
		_apply_effects_list(skill, owner, tu2, aura.get("on_exit", []))

	_affected[owner_id] = new_targets


func _apply_effects_list(skill: Dictionary, caster, target, effects_arr: Array) -> void:
	for e in effects_arr:
		var ctx := {
			"skill_id": String(skill.get("id", "")),
			"skill": skill,
			"caster": caster,
			"target": target,
			"grid": _grid,
			"event_bus": _event_bus,
			"omnibuff": _omnibuff,
			"turn_index": 0,
			"roll_key": 0,
			"rng_seed": 0,
			"damage_type": 0,
			"element": 0,
			"tags": skill.get("tags", []),
			"tags_mask": 0,
			"skill_id_int": -1,
			"a_stats": {},
			"t_stats": {},
		}
		_effects.apply_effect(e, ctx, false)


func _get_allies_in_front_row(owner_unit) -> Array:
	if _grid == null:
		return []
	var out: Array = []
	for u in _grid._units:
		if u == null:
			continue
		if u.has_method("is_dead") and bool(u.call("is_dead")):
			continue
		if String(u.camp) != String(owner_unit.camp):
			continue
		if Vector2i(u.cell).x != 0:
			continue
		out.append(u)
	return out


func _get_allies(owner_unit) -> Array:
	if _grid == null:
		return []
	var out: Array = []
	for u in _grid._units:
		if u == null:
			continue
		if u.has_method("is_dead") and bool(u.call("is_dead")):
			continue
		if String(u.camp) != String(owner_unit.camp):
			continue
		out.append(u)
	return out


func _find_unit_by_id(entity_id: int):
	if _grid == null:
		return null
	for u in _grid._units:
		if u != null and int(u.entity_id) == entity_id:
			return u
	return null
